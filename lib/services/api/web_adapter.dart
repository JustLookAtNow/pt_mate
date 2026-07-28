import 'dart:convert';

import 'package:beautiful_soup_dart/beautiful_soup.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:logger/logger.dart';

import '../../models/app_models.dart';
import '../site_config_service.dart';
import 'api_exceptions.dart';
import 'html_extractor.dart';
import 'site_adapter.dart';

/// 配置不完整或不适用于通用 Web 适配器时抛出的异常。
///
/// 这类错误不回退到 NexusPHPWeb 默认规则，避免将另一个站点的规则误用到
/// 配置驱动的 Web 站点。
class WebAdapterConfigurationException extends SiteServiceException {
  WebAdapterConfigurationException(String message) : super(message: message);
}

/// 通用 Web 适配器可复用的 Cookie 请求、占位符与 URL 工具。
///
/// NexusPHPWeb 等旧适配器可以逐步复用此核心；这里不包含任何站点专属
/// 路径、Passkey 或 Gazelle API 假设。
class WebAdapterCore {
  WebAdapterCore._();

  static const _defaultUserAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
      'AppleWebKit/537.36 (KHTML, like Gecko) '
      'Chrome/143.0.0.0 Safari/537.36';

  static Dio createCookieDio(SiteConfig config) {
    final dio = Dio(
      BaseOptions(
        baseUrl: config.baseUrl,
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 15),
        sendTimeout: const Duration(seconds: 30),
        responseType: ResponseType.plain,
        headers: {'User-Agent': _defaultUserAgent},
      ),
    );

    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          final cookie = config.cookie;
          if (cookie != null && cookie.isNotEmpty) {
            options.headers['Cookie'] = cookie;
          }
          handler.next(options);
        },
        onResponse: (response, handler) {
          if (_isAuthenticationRedirect(
            realUri: response.realUri,
            redirects: response.redirects,
            statusCode: response.statusCode,
            location: response.headers.value('location'),
          )) {
            handler.reject(
              DioException(
                requestOptions: response.requestOptions,
                response: response,
                type: DioExceptionType.badResponse,
                error: SiteAuthenticationException(
                  statusCode: response.statusCode,
                  message: 'Cookie已过期，请重新登录更新Cookie',
                ),
              ),
            );
            return;
          }
          handler.next(response);
        },
        onError: (error, handler) {
          final response = error.response;
          if (_isAuthenticationRedirect(
            realUri: response?.realUri,
            redirects: response?.redirects ?? const [],
            statusCode: response?.statusCode,
            location: response?.headers.value('location'),
          )) {
            handler.reject(
              DioException(
                requestOptions: error.requestOptions,
                response: response,
                type: error.type,
                error: SiteAuthenticationException(
                  statusCode: response?.statusCode,
                  message: 'Cookie已过期，请重新登录更新Cookie',
                ),
              ),
            );
            return;
          }
          handler.next(error);
        },
      ),
    );

    return dio;
  }

  static bool _isAuthenticationRedirect({
    Uri? realUri,
    List<RedirectRecord> redirects = const [],
    int? statusCode,
    String? location,
  }) {
    if (statusCode == 401 || statusCode == 403) return true;

    bool isLoginPath(String? value) {
      if (value == null || value.isEmpty) return false;
      final normalized = value.toLowerCase();
      return normalized.contains('/login') ||
          normalized.contains('login.php') ||
          normalized.contains('takelogin') ||
          normalized.contains('/verify') ||
          normalized.contains('verify.php');
    }

    if (isLoginPath(realUri?.toString()) || isLoginPath(location)) {
      return true;
    }
    return redirects.any(
      (redirect) => isLoginPath(redirect.location.toString()),
    );
  }

  /// 将 `{name}` 占位符替换为上下文中的字符串值；没有值时替换为空字符串。
  static String replacePlaceholders(
    String source,
    Map<String, dynamic> variables,
  ) {
    return source.replaceAllMapped(RegExp(r'\{([A-Za-z0-9_]+)\}'), (match) {
      final value = variables[match.group(1)];
      return value == null ? '' : value.toString();
    });
  }

  /// 深度替换请求参数中的占位符，保持列表和嵌套 Map 的原始类型。
  static dynamic replacePlaceholdersDeep(
    dynamic value,
    Map<String, dynamic> variables,
  ) {
    if (value is String) return replacePlaceholders(value, variables);
    if (value is List) {
      return value
          .map((entry) => replacePlaceholdersDeep(entry, variables))
          .toList();
    }
    if (value is Map) {
      return value.map(
        (key, entry) =>
            MapEntry(key.toString(), replacePlaceholdersDeep(entry, variables)),
      );
    }
    return value;
  }

  /// 只接受并返回绝对 HTTP(S) URL。
  ///
  /// 相对 URL、根路径 URL 与 protocol-relative URL 都会以 [baseUrl] 解析；
  /// javascript/data 等非 HTTP 链接会返回 null，防止把它们交给 WebView 或下载器。
  static String? resolveHttpUrl(String? value, String baseUrl) {
    if (value == null) return null;
    final raw = value.trim();
    if (raw.isEmpty) return null;

    final base = Uri.tryParse(baseUrl);
    if (base == null || !base.hasScheme || base.host.isEmpty) return null;

    Uri? resolved;
    if (raw.startsWith('//')) {
      resolved = Uri.tryParse('${base.scheme}:$raw');
    } else {
      final candidate = Uri.tryParse(raw);
      resolved = candidate?.hasScheme == true ? candidate : base.resolve(raw);
    }
    if (resolved == null ||
        (resolved.scheme != 'http' && resolved.scheme != 'https') ||
        resolved.host.isEmpty) {
      return null;
    }
    return resolved.toString();
  }

  /// Android WebView 不会自动读取 Dio 请求头中的 Cookie，需要显式同步。
  static Future<void> syncCookiesToWebView(SiteConfig config) async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    final cookieHeader = config.cookie;
    if (cookieHeader == null || cookieHeader.isEmpty) return;

    final baseUri = Uri.tryParse(config.baseUrl);
    if (baseUri == null || baseUri.host.isEmpty) return;

    final manager = CookieManager.instance();
    for (final segment in cookieHeader.split(';')) {
      final separator = segment.indexOf('=');
      if (separator <= 0) continue;
      final name = segment.substring(0, separator).trim();
      final value = segment.substring(separator + 1).trim();
      if (name.isEmpty) continue;
      await manager.setCookie(
        url: WebUri(config.baseUrl),
        name: name,
        value: value,
        domain: baseUri.host,
        isHttpOnly: true,
      );
    }
  }
}

/// 纯 HTML 搜索解析结果，便于无网络单测和后台 Isolate 复用。
class WebSearchParseResult {
  final List<TorrentItem> items;
  final int totalPages;

  /// 进入字段解析的候选种子行数量，不包含 Gazelle 分组标题行。
  final int candidateItemRows;

  const WebSearchParseResult({
    required this.items,
    required this.totalPages,
    required this.candidateItemRows,
  });
}

class _WebSearchItems {
  final List<TorrentItem> items;
  final int candidateItemRows;

  const _WebSearchItems({required this.items, required this.candidateItemRows});
}

/// 通用 Web 适配器的安全诊断阶段。
enum WebAdapterDiagnosticStage { request, searchParse }

/// 不含认证数据、参数值、完整 URL 或 HTML 正文的 Web 解析诊断事件。
///
/// [diagnosticSink] 仅适合调试或测试收集聚合统计；生产调用方不传入时，
/// 不会改变适配器的行为。
class WebAdapterDiagnostic {
  final WebAdapterDiagnosticStage stage;
  final String? method;
  final String? path;
  final List<String> parameterKeys;
  final int? statusCode;
  final int? responseBytes;
  final String? outcome;
  final String? parser;
  final int? candidateItemRows;
  final int? parsedItems;
  final int? totalPages;

  const WebAdapterDiagnostic({
    required this.stage,
    this.method,
    this.path,
    this.parameterKeys = const [],
    this.statusCode,
    this.responseBytes,
    this.outcome,
    this.parser,
    this.candidateItemRows,
    this.parsedItems,
    this.totalPages,
  });

  /// 可安全写入调试日志的单行摘要。
  String toSafeLogLine() {
    switch (stage) {
      case WebAdapterDiagnosticStage.request:
        return 'WebAdapter request: '
            'method=${method ?? '-'} '
            'path=${path ?? '-'} '
            'paramKeys=[${parameterKeys.join(',')}] '
            'status=${statusCode ?? '-'} '
            'responseBytes=${responseBytes ?? 0} '
            'outcome=${outcome ?? '-'}';
      case WebAdapterDiagnosticStage.searchParse:
        return 'WebAdapter search parse: '
            'parser=${parser ?? 'flatTable'} '
            'candidateRows=${candidateItemRows ?? 0} '
            'parsedItems=${parsedItems ?? 0} '
            'totalPages=${totalPages ?? 1}';
    }
  }
}

/// 以站点 JSON 模板驱动的搜索列表解析器。
class WebSearchParser {
  WebSearchParser._();

  static WebSearchParseResult parse({
    required String html,
    required Map<String, dynamic> searchConfig,
    required String baseUrl,
    Map<String, String> discountMapping = const {},
    Map<String, String> tagMapping = const {},
  }) {
    final soup = BeautifulSoup(html);
    final parser = (searchConfig['parser'] as String? ?? 'flatTable')
        .trim()
        .toLowerCase();
    final parsedItems = switch (parser) {
      'flattable' || '' => _parseFlatTable(
        soup,
        searchConfig,
        baseUrl,
        discountMapping,
        tagMapping,
      ),
      'gazellegrouped' => _parseGazelleGrouped(
        soup,
        searchConfig,
        baseUrl,
        discountMapping,
        tagMapping,
      ),
      _ => throw WebAdapterConfigurationException(
        '不支持的 Web 搜索解析器: ${searchConfig['parser']}',
      ),
    };

    return WebSearchParseResult(
      items: parsedItems.items,
      totalPages: _parseTotalPages(soup, searchConfig),
      candidateItemRows: parsedItems.candidateItemRows,
    );
  }

  static _WebSearchItems _parseFlatTable(
    BeautifulSoup soup,
    Map<String, dynamic> config,
    String baseUrl,
    Map<String, String> discountMapping,
    Map<String, String> tagMapping,
  ) {
    final rows = _findRows(soup, config, required: true);
    final fields = _map(config['fields']);
    if (fields.isEmpty) {
      throw WebAdapterConfigurationException(
        'flatTable 缺少 infoFinder.search.fields 配置',
      );
    }

    final items = <TorrentItem>[];
    for (final row in rows) {
      final values = _extractValues(row, fields);
      final item = _buildTorrentItem(
        values,
        fields,
        baseUrl,
        discountMapping,
        tagMapping,
      );
      if (item != null) items.add(item);
    }
    return _WebSearchItems(items: items, candidateItemRows: rows.length);
  }

  static _WebSearchItems _parseGazelleGrouped(
    BeautifulSoup soup,
    Map<String, dynamic> config,
    String baseUrl,
    Map<String, String> discountMapping,
    Map<String, String> tagMapping,
  ) {
    final rows = _findRows(soup, config, required: true);
    final groupRows = _findConfiguredRows(
      soup,
      config,
      'groupRows',
      'groupRow',
    );
    final torrentRows = _findConfiguredRows(
      soup,
      config,
      'torrentRows',
      'torrentRow',
    );

    final groupFields = _map(config['groupFields']);
    final commonFields = _map(config['fields']);
    final childFields = _map(config['childFields']);
    final standaloneFields = _map(config['standaloneFields']);
    if (commonFields.isEmpty &&
        childFields.isEmpty &&
        standaloneFields.isEmpty) {
      throw WebAdapterConfigurationException(
        'gazelleGrouped 缺少 infoFinder.search.fields、childFields 或 standaloneFields 配置',
      );
    }

    final childOffset = _asInt(config['childColumnOffset']) ?? 0;
    var currentGroup = <String, String>{};
    final items = <TorrentItem>[];
    var candidateItemRows = 0;

    for (final row in rows) {
      if (_containsRow(groupRows, row) || _hasClass(row, 'group_redline')) {
        currentGroup = _extractValues(row, groupFields);
        continue;
      }

      final isChild = _hasClass(row, 'group_torrent_redline');
      final isStandalone =
          _hasClass(row, 'torrent_redline') || _hasClass(row, 'torrent');
      final isConfiguredTorrent = _containsRow(torrentRows, row);
      if (!isChild && !isStandalone && !isConfiguredTorrent) continue;
      candidateItemRows++;

      final rowFields = <String, dynamic>{...commonFields};
      if (isChild) {
        // 子行缺少父组占用的前置单元格；fields 与 childFields 都按完整行
        // 列号书写，因此统一按 childColumnOffset 修正。
        rowFields.addAll(childFields);
      } else if (isStandalone) {
        rowFields.addAll(standaloneFields);
      }
      final normalizedFields = isChild && childOffset > 0
          ? _shiftColumnFields(rowFields, childOffset)
          : rowFields;
      final rowValues = _extractValues(row, normalizedFields);
      final inherited = isChild ? currentGroup : const <String, String>{};
      final values = _mergeNonEmpty(inherited, rowValues);
      final item = _buildTorrentItem(
        values,
        normalizedFields,
        baseUrl,
        discountMapping,
        tagMapping,
      );
      if (item != null) items.add(item);
    }
    return _WebSearchItems(items: items, candidateItemRows: candidateItemRows);
  }

  static List<dynamic> _findRows(
    BeautifulSoup soup,
    Map<String, dynamic> config, {
    required bool required,
  }) {
    final rows = _map(config['rows']);
    final selector = rows['selector'] as String?;
    if (selector == null || selector.trim().isEmpty) {
      if (required) {
        throw WebAdapterConfigurationException(
          'Web 搜索解析缺少 infoFinder.search.rows.selector 配置',
        );
      }
      return const [];
    }
    return HtmlExtractor().findRows(soup, selector);
  }

  static List<dynamic> _findConfiguredRows(
    BeautifulSoup soup,
    Map<String, dynamic> config,
    String firstKey,
    String alternateKey,
  ) {
    final rowConfig = _map(config[firstKey]).isNotEmpty
        ? _map(config[firstKey])
        : _map(config[alternateKey]);
    final selector = rowConfig['selector'] as String?;
    if (selector == null || selector.trim().isEmpty) return const [];
    return HtmlExtractor().findRows(soup, selector);
  }

  static bool _containsRow(List<dynamic> rows, dynamic row) {
    return rows.any(
      (candidate) => identical(candidate, row) || candidate == row,
    );
  }

  static bool _hasClass(dynamic row, String className) {
    final raw = row?.attributes?['class'];
    if (raw == null) return false;
    if (raw is Iterable) {
      return raw.map((item) => item.toString()).contains(className);
    }
    return raw
        .toString()
        .split(RegExp(r'[\s,\[\]]+'))
        .where((item) => item.isNotEmpty)
        .contains(className);
  }

  static Map<String, String> _extractValues(
    dynamic row,
    Map<String, dynamic> rawFields,
  ) {
    final normalizedRawFields = _normalizePositionalSelectors(rawFields);
    final fields = HtmlExtractor.parseFieldConfigs(normalizedRawFields);
    final results = HtmlExtractor().extractRowResultsSync(row, fields);
    final values = <String, String>{};
    for (final entry in results.entries) {
      final value = entry.value.first.string;
      if (value != null && value.isNotEmpty) values[entry.key] = value;
    }

    // 对组标题等文本字段可声明 stripSelectors/excludeSelectors，在提取文本前
    // 去掉优惠标签、评论链接等展示元素，避免它们污染种子名称。
    for (final entry in normalizedRawFields.entries) {
      final rawField = _map(entry.value);
      final stripped = _extractStrippedTextValues(row, rawField);
      if (stripped.isNotEmpty) values[entry.key] = stripped.first;
    }

    // value 模板在基础字段提取之后再计算，使 {torrentId} 等可引用同一行字段。
    for (final entry in fields.entries) {
      if (!entry.value.hasValue) continue;
      final templateVariables = <String, dynamic>{...values};
      final value = WebAdapterCore.replacePlaceholders(
        entry.value.value!,
        templateVariables,
      );
      if (value.isNotEmpty) values[entry.key] = value;
    }

    // join 计算字段用于组合来自同一行的多个已提取字段，例如
    // { "torrentName": { "join": ["title", "artist"],
    //   "separator": " - " } }。空字段会被忽略，避免生成尾随分隔符。
    for (final entry in normalizedRawFields.entries) {
      final rawField = _map(entry.value);
      final joinedFieldNames = _stringList(rawField['join']);
      if (joinedFieldNames.isEmpty) continue;

      // 没有 selector 的计算字段默认会提取整行文本；join 必须覆盖该中间值。
      values.remove(entry.key);
      final joinedValues = joinedFieldNames
          .map((fieldName) => values[fieldName]?.trim())
          .whereType<String>()
          .where((value) => value.isNotEmpty)
          .toList();
      if (joinedValues.isEmpty) continue;
      final separator = rawField['separator'] as String? ?? '';
      values[entry.key] = joinedValues.join(separator);
    }
    return values;
  }

  /// `beautiful_soup_dart` 的 CSS 查询在行元素上无法可靠处理
  /// `@@td:nth-child(n)`；将这类位置选择器交给 BaseWeb 的手工选择器，
  /// 同时保留其余 `@@` CSS 规则（例如 href* 匹配）。
  static Map<String, dynamic> _normalizePositionalSelectors(
    Map<String, dynamic> fields,
  ) {
    return fields.map((key, rawValue) {
      if (rawValue is! Map) return MapEntry(key, rawValue);
      final field = _map(rawValue);
      final selector = field['selector'];
      if (selector is String &&
          RegExp(r'^@@(?:td|th):nth-child\(\d+\)').hasMatch(selector)) {
        field['selector'] = selector.substring(2);
      }
      return MapEntry(key, field);
    });
  }

  static List<String> _extractStrippedTextValues(
    dynamic row,
    Map<String, dynamic> rawField,
  ) {
    final selectors = _stringList(
      rawField['stripSelectors'] ?? rawField['excludeSelectors'],
    );
    if (selectors.isEmpty || rawField['attribute'] != 'text') return const [];

    final selector = rawField['selector'] as String?;
    final targets = selector == null || selector.isEmpty
        ? <dynamic>[row]
        : HtmlExtractor().findElementBySelector(row, selector);
    final cleanedConfig = FieldConfig.fromJson({
      'attribute': 'text',
      if (rawField['filter'] != null) 'filter': rawField['filter'],
      if (rawField['defaultValue'] != null)
        'defaultValue': rawField['defaultValue'],
    });
    final values = <String>[];
    for (final target in targets) {
      final html = target?.outerHtml;
      if (html is! String || html.isEmpty) continue;
      final clonedSoup = BeautifulSoup(html);
      final rootName = target?.name?.toString();
      final root = rootName == null || rootName.isEmpty
          ? clonedSoup
          : (clonedSoup.find(rootName) ?? clonedSoup);
      for (final stripSelector in selectors) {
        final elements = HtmlExtractor()
            .findElementBySelector(root, stripSelector)
            .toList();
        for (final element in elements) {
          element.decompose();
        }
      }
      final value = HtmlExtractor()
          .extractFieldSync(root, cleanedConfig)
          .string;
      if (value != null && value.isNotEmpty) values.add(value);
    }
    return values;
  }

  static Map<String, String> _mergeNonEmpty(
    Map<String, String> inherited,
    Map<String, String> values,
  ) {
    final merged = <String, String>{...inherited};
    values.forEach((key, value) {
      if (value.isNotEmpty) merged[key] = value;
    });
    return merged;
  }

  static Map<String, dynamic> _shiftColumnFields(
    Map<String, dynamic> fields,
    int offset,
  ) {
    return fields.map((key, rawValue) {
      if (rawValue is! Map) return MapEntry(key, rawValue);
      final field = _map(rawValue);
      final selector = field['selector'];
      if (selector is String) {
        field['selector'] = selector.replaceAllMapped(
          RegExp(r'\b(td|th):nth-child\((\d+)\)'),
          (match) {
            final index = int.parse(match.group(2)!);
            return '${match.group(1)}:nth-child(${index > offset ? index - offset : 1})';
          },
        );
      }
      return MapEntry(key, field);
    });
  }

  static TorrentItem? _buildTorrentItem(
    Map<String, String> values,
    Map<String, dynamic> rawFields,
    String baseUrl,
    Map<String, String> discountMapping,
    Map<String, String> tagMapping,
  ) {
    var torrentId = _first(values, const ['torrentId', 'id']);
    final rawDetailUrl = _first(values, const ['detailUrl', 'url']);
    final rawDownloadUrl = _first(values, const ['downloadUrl', 'link']);
    torrentId ??=
        _torrentIdFromUrl(rawDownloadUrl) ?? _torrentIdFromUrl(rawDetailUrl);
    if (torrentId == null || torrentId.isEmpty) return null;

    final detailUrl = WebAdapterCore.resolveHttpUrl(rawDetailUrl, baseUrl);
    final downloadUrl = WebAdapterCore.resolveHttpUrl(rawDownloadUrl, baseUrl);
    final name = _first(values, const ['torrentName', 'name', 'title']) ?? '';
    final description =
        _first(values, const [
          'description',
          'smallDescr',
          'subtitle',
          'category',
        ]) ??
        '';
    final sizeText = _first(values, const ['sizeText', 'size']) ?? '';
    final discountRaw = _first(values, const [
      'discount',
      'freeleech',
      'isFreeleech',
    ]);
    final discount = _parseDiscount(discountRaw, discountMapping);
    final createDate = _parseDate(
      values['createDate'],
      rawFields['createDate'],
    );
    final discountEnd = _parseDate(
      values['discountEndTime'],
      rawFields['discountEndTime'],
    );
    final tagValues = values['tag']?.split(',') ?? const <String>[];

    return TorrentItem(
      id: torrentId,
      name: name,
      smallDescr: description,
      discount: discount,
      discountEndTime: discountEnd,
      downloadUrl: downloadUrl,
      detailUrl: detailUrl,
      description: values['description'],
      seeders: _asInt(_first(values, const ['seedersText', 'seeders'])) ?? 0,
      leechers: _asInt(_first(values, const ['leechersText', 'leechers'])) ?? 0,
      sizeBytes: TypedConverter.parseSizeToBytes(sizeText),
      createdDate: createDate ?? DateTime.now(),
      imageList: const [],
      cover: WebAdapterCore.resolveHttpUrl(values['cover'], baseUrl) ?? '',
      downloadStatus: TypedConverter.parseDownloadStatus(
        values['downloadStatus'],
      ),
      collection: _asBool(values['collection']),
      doubanRating: values['doubanRating'] ?? 'N/A',
      imdbRating: values['imdbRating'] ?? 'N/A',
      isTop: _asBool(values['isTop']),
      tags: TypedConverter.parseTags(name, description, tagValues, tagMapping),
      comments: _asInt(values['comments']) ?? 0,
    );
  }

  static String? _first(Map<String, String> values, List<String> keys) {
    for (final key in keys) {
      final value = values[key];
      if (value != null && value.isNotEmpty) return value;
    }
    return null;
  }

  static String? _torrentIdFromUrl(String? url) {
    if (url == null || url.isEmpty) return null;
    final uri = Uri.tryParse(url);
    final fromQuery =
        uri?.queryParameters['torrentid'] ?? uri?.queryParameters['id'];
    if (fromQuery != null && fromQuery.isNotEmpty) return fromQuery;
    final match = RegExp(r'[?&](?:torrentid|id)=(\d+)').firstMatch(url);
    return match?.group(1);
  }

  static DiscountType _parseDiscount(String? raw, Map<String, String> mapping) {
    if (raw == null || raw.isEmpty) return DiscountType.normal;
    final mapped = TypedConverter.parseDiscount(raw, mapping);
    if (mapped != DiscountType.normal) return mapped;
    final normalized = raw.toLowerCase();
    if (normalized == 'true' ||
        normalized == '1' ||
        normalized.contains('free')) {
      return DiscountType.free;
    }
    return DiscountType.normal;
  }

  static DateTime? _parseDate(String? raw, dynamic rawField) {
    if (raw == null || raw.isEmpty) return null;
    final field = _map(rawField);
    final time = _map(field['time']);
    return ExtractedValue.fromString(raw).parseDateTime(
      format: time['format'] as String?,
      zone: time['zone'] as String?,
      fieldName: 'createdDate',
    );
  }

  static bool _asBool(String? value) {
    if (value == null || value.isEmpty) return false;
    return value.toLowerCase() != 'false' && value != '0';
  }

  static int? _asInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    return ExtractedValue.fromString(value.toString()).intValue;
  }

  static int _parseTotalPages(BeautifulSoup soup, Map<String, dynamic> config) {
    final totalConfig = _map(config['totalPages']);
    if (totalConfig.isEmpty) return 1;
    final rowsConfig = _map(totalConfig['rows']);
    final selector = rowsConfig['selector'] as String?;
    final fields = _map(totalConfig['fields']);
    final field = HtmlExtractor.parseFieldConfigs(fields)['totalPages'];
    if (selector == null || field == null) return 1;
    final values = HtmlExtractor()
        .findRows(soup, selector)
        .map((row) => HtmlExtractor().extractFieldSync(row, field).intValue)
        .whereType<int>();
    if (values.isEmpty) return 1;
    return values.reduce((a, b) => a > b ? a : b);
  }

  static Map<String, dynamic> _map(dynamic value) {
    if (value is! Map) return <String, dynamic>{};
    return value.map((key, entry) => MapEntry(key.toString(), entry));
  }

  static List<String> _stringList(dynamic value) {
    if (value is String) return value.isEmpty ? const [] : [value];
    if (value is! List) return const [];
    return value.whereType<String>().where((item) => item.isNotEmpty).toList();
  }
}

/// 仅通过内置 Web 模板工作的通用 Cookie/HTML 站点适配器。
class WebAdapter extends SiteAdapter {
  WebAdapter({Dio? dio, this.diagnosticSink}) : _providedDio = dio;

  static final Logger _logger = Logger();

  final Dio? _providedDio;
  final void Function(WebAdapterDiagnostic diagnostic)? diagnosticSink;
  late SiteConfig _siteConfig;
  late Dio _dio;
  SiteConfigTemplate? _customTemplate;
  SiteConfigTemplate? _template;

  @override
  SiteConfig get siteConfig => _siteConfig;

  @override
  Future<void> init(SiteConfig config) async {
    if (config.siteType != SiteType.web) {
      throw WebAdapterConfigurationException(
        'WebAdapter 仅支持 SiteType.web，当前为 ${config.siteType.id}',
      );
    }
    _siteConfig = config;
    _dio = _providedDio ?? WebAdapterCore.createCookieDio(config);
  }

  /// 供无文件模板的调试与单测使用；生产站点仍从内置 assets 模板读取。
  void setCustomTemplate(SiteConfigTemplate template) {
    if (template.siteType != SiteType.web) {
      throw WebAdapterConfigurationException('通用 Web 适配器只能使用 SiteType.web 模板');
    }
    _customTemplate = template;
    _template = null;
  }

  Future<SiteConfigTemplate> _getTemplate() async {
    final custom = _customTemplate;
    if (custom != null) return custom;
    final cached = _template;
    if (cached != null) return cached;

    final template = await SiteConfigService.getTemplateById(
      _siteConfig.templateId,
      SiteType.web,
    );
    if (template == null || template.siteType != SiteType.web) {
      throw WebAdapterConfigurationException(
        '未找到 Web 模板: ${_siteConfig.templateId}。通用 Web 不会回退到 NexusPHPWeb 规则。',
      );
    }
    _template = template;
    return template;
  }

  Future<Map<String, dynamic>> _getInfoFinder(String key) async {
    final infoFinder = (await _getTemplate()).infoFinder;
    final value = infoFinder?[key];
    if (value is! Map) {
      throw WebAdapterConfigurationException('Web 模板缺少 infoFinder.$key 配置');
    }
    return value.map((mapKey, entry) => MapEntry(mapKey.toString(), entry));
  }

  Future<Map<String, dynamic>> _getRequest(String key) async {
    final request = (await _getTemplate()).request;
    final value = request?[key];
    if (value is! Map) {
      throw WebAdapterConfigurationException('Web 模板缺少 request.$key 配置');
    }
    return value.map((mapKey, entry) => MapEntry(mapKey.toString(), entry));
  }

  Future<Response<dynamic>> _request(
    Map<String, dynamic> config,
    Map<String, dynamic> variables,
  ) async {
    final pathTemplate = (config['path'] ?? config['url']) as String?;
    if (pathTemplate == null || pathTemplate.isEmpty) {
      throw WebAdapterConfigurationException('Web 请求配置缺少 path');
    }
    final method = (config['method'] as String? ?? 'GET').toUpperCase();
    final path = WebAdapterCore.replacePlaceholders(pathTemplate, variables);
    final rawParams = config['params'] ?? config['queryParameters'];
    final params = _replaceParams(rawParams, variables);
    final headers = _stringMap(config['headers']);
    try {
      final response = await _dio.request<dynamic>(
        path,
        queryParameters: method == 'GET' ? params : null,
        data: method == 'GET' ? null : params,
        options: Options(
          method: method,
          headers: headers.isEmpty ? null : headers,
        ),
      );
      _logRequestDiagnostics(
        method: method,
        path: path,
        params: params,
        statusCode: response.statusCode,
        responseBytes: _responseByteLength(response.data),
      );
      return response;
    } on DioException catch (error) {
      // 诊断信息刻意不包含 Cookie、请求参数值、URL query 或响应正文。
      _logRequestDiagnostics(
        method: method,
        path: path,
        params: params,
        statusCode: error.response?.statusCode,
        responseBytes: 0,
        errorType: error.type.name,
      );
      rethrow;
    }
  }

  void _logRequestDiagnostics({
    required String method,
    required String path,
    required Map<String, dynamic> params,
    required int? statusCode,
    required int responseBytes,
    String? errorType,
  }) {
    final parameterKeys = params.keys.map((key) => key.toString()).toList()
      ..sort();
    _emitDiagnostic(
      WebAdapterDiagnostic(
        stage: WebAdapterDiagnosticStage.request,
        method: method,
        path: _safeDiagnosticPath(path),
        parameterKeys: parameterKeys,
        statusCode: statusCode,
        responseBytes: responseBytes,
        outcome: errorType == null ? 'ok' : 'error:$errorType',
      ),
    );
  }

  void _logSearchParseDiagnostics(
    Map<String, dynamic> searchConfig,
    WebSearchParseResult parsed,
  ) {
    final parser = (searchConfig['parser'] as String? ?? 'flatTable').trim();
    _emitDiagnostic(
      WebAdapterDiagnostic(
        stage: WebAdapterDiagnosticStage.searchParse,
        parser: parser,
        candidateItemRows: parsed.candidateItemRows,
        parsedItems: parsed.items.length,
        totalPages: parsed.totalPages,
      ),
    );
  }

  void _emitDiagnostic(WebAdapterDiagnostic diagnostic) {
    try {
      diagnosticSink?.call(diagnostic);
    } catch (_) {
      // 诊断回调不能影响实际请求或解析流程。
    }
    if (kDebugMode) _logger.d(diagnostic.toSafeLogLine());
  }

  static String _safeDiagnosticPath(String path) {
    final uri = Uri.tryParse(path);
    final parsedPath = uri?.path;
    if (parsedPath != null && parsedPath.isNotEmpty) return parsedPath;
    final withoutQuery = path.split(RegExp(r'[?#]')).first.trim();
    return withoutQuery.isEmpty ? '/' : withoutQuery;
  }

  static int _responseByteLength(dynamic data) {
    if (data == null) return 0;
    if (data is List<int>) return data.length;
    return utf8.encode(data.toString()).length;
  }

  Map<String, dynamic> _replaceParams(
    dynamic rawParams,
    Map<String, dynamic> variables,
  ) {
    if (rawParams is! Map) return <String, dynamic>{};
    final result = <String, dynamic>{};
    rawParams.forEach((key, rawValue) {
      if (rawValue is String &&
          rawValue.contains('{categoryId}') &&
          (variables['categoryId']?.toString().isEmpty ?? true)) {
        return;
      }
      result[key.toString()] = WebAdapterCore.replacePlaceholdersDeep(
        rawValue,
        variables,
      );
    });
    return result;
  }

  @override
  Future<MemberProfile> fetchMemberProfile({String? apiKey}) async {
    try {
      final config = await _getInfoFinder('userInfo');
      final rawSteps = config['steps'];
      final steps = rawSteps is List
          ? rawSteps.whereType<Map>().map(_dynamicMap).toList()
          : <Map<String, dynamic>>[_dynamicMap(config)];
      if (steps.isEmpty) {
        throw WebAdapterConfigurationException(
          'infoFinder.userInfo.steps 不能为空',
        );
      }

      final values = <String, String>{
        'baseUrl': _siteConfig.baseUrl,
        if (_siteConfig.userId != null) 'userId': _siteConfig.userId!,
        if (_siteConfig.passKey != null) 'passKey': _siteConfig.passKey!,
        if (_siteConfig.authKey != null) 'authKey': _siteConfig.authKey!,
      };
      for (final step in steps) {
        final response = await _request(step, values);
        final extracted = _extractProfileValues(
          BeautifulSoup(response.data?.toString() ?? ''),
          step,
        );
        extracted.forEach((key, value) {
          if (value.isNotEmpty) values[key] = value;
        });
      }

      final passKey = values['passKey'];
      final authKey = values['authKey'];
      final userId = values['userId'];
      _siteConfig = _siteConfig.copyWith(
        userId: userId,
        passKey: passKey,
        authKey: authKey,
      );
      final upload = _profileValue(values, const ['upload', 'uploaded']);
      final download = _profileValue(values, const ['download', 'downloaded']);
      return MemberProfile(
        username: _profileValue(values, const ['userName', 'username', 'name']),
        bonus: _asDouble(_profileValue(values, const ['bonus', 'bonusPoints'])),
        shareRate: _asDouble(
          _profileValue(values, const ['ratio', 'shareRate']),
        ),
        uploadedBytes: TypedConverter.parseSizeToBytes(upload),
        downloadedBytes: TypedConverter.parseSizeToBytes(download),
        uploadedBytesString: upload.isEmpty ? '0 B' : upload,
        downloadedBytesString: download.isEmpty ? '0 B' : download,
        userId: userId,
        passKey: passKey,
        authKey: authKey,
        bonusPerHour: _optionalDouble(values['bonusPerHour']),
        seedingSizeBytes: TypedConverter.parseSizeToBytes(
          values['seedingSize'],
        ),
      );
    } catch (error) {
      throw ApiExceptionAdapter.wrapError(error, '获取用户资料');
    }
  }

  Map<String, String> _extractProfileValues(
    BeautifulSoup soup,
    Map<String, dynamic> config,
  ) {
    final fields = _dynamicMap(config['fields']);
    if (fields.isEmpty) {
      throw WebAdapterConfigurationException('用户资料步骤缺少 fields 配置');
    }
    final rows = _dynamicMap(config['rows']);
    final selector = rows['selector'] as String?;
    final element = selector == null || selector.isEmpty
        ? soup
        : HtmlExtractor().findFirst(soup, selector);
    if (element == null) {
      throw WebAdapterConfigurationException(
        '用户资料步骤未找到 rows.selector: $selector',
      );
    }
    final values = WebSearchParser._extractValues(element, fields);
    final requiredFields = HtmlExtractor.parseFieldConfigs(fields).entries
        .where((entry) => entry.value.required)
        .map((entry) => entry.key)
        .where((key) => values[key]?.isNotEmpty != true)
        .toList();
    if (requiredFields.isNotEmpty) {
      throw SiteAuthenticationException(
        message: 'Cookie已过期，请重新登录更新Cookie',
        detail: '用户资料页面缺少必填字段: ${requiredFields.join(', ')}',
      );
    }
    return values;
  }

  @override
  Future<TorrentSearchResult> searchTorrents({
    String? keyword,
    int pageNumber = 1,
    int pageSize = 30,
    int? onlyFav,
    Map<String, dynamic>? additionalParams,
  }) async {
    try {
      final request = await _getRequest('search');
      final searchConfig = await _getInfoFinder('search');
      final additions = Map<String, dynamic>.from(additionalParams ?? const {});
      final category = additions['category'];
      String categoryId = '';
      if (category is String) {
        final split = category.split('#');
        categoryId = split.length > 1 ? split.last : category;
        if (split.length > 1) additions.remove('category');
      }
      categoryId = categoryId.isNotEmpty
          ? categoryId
          : additions['filter_cat']?.toString() ?? '';
      final variables = <String, dynamic>{
        'baseUrl': _siteConfig.baseUrl,
        'keyword': keyword?.trim() ?? '',
        'page': pageNumber,
        'pageSize': pageSize,
        'onlyFav': onlyFav ?? '',
        'categoryId': categoryId,
        if (_siteConfig.userId != null) 'userId': _siteConfig.userId!,
        if (_siteConfig.passKey != null) 'passKey': _siteConfig.passKey!,
        if (_siteConfig.authKey != null) 'authKey': _siteConfig.authKey!,
      };
      final requestWithAdditions = Map<String, dynamic>.from(request);
      final paramsKey = request.containsKey('queryParameters')
          ? 'queryParameters'
          : 'params';
      final requestParams = _dynamicMap(request[paramsKey]);
      requestParams.addAll(additions);
      requestWithAdditions[paramsKey] = requestParams;
      final response = await _request(requestWithAdditions, variables);
      final parsed = WebSearchParser.parse(
        html: response.data?.toString() ?? '',
        searchConfig: searchConfig,
        baseUrl: _siteConfig.baseUrl,
        discountMapping: (await _getTemplate()).discountMapping,
        tagMapping: (await _getTemplate()).tagMapping,
      );
      _logSearchParseDiagnostics(searchConfig, parsed);
      return TorrentSearchResult(
        pageNumber: pageNumber,
        pageSize: pageSize,
        total: parsed.items.length * parsed.totalPages,
        totalPages: parsed.totalPages,
        items: parsed.items,
      );
    } catch (error) {
      throw ApiExceptionAdapter.wrapError(error, '搜索种子');
    }
  }

  @override
  Future<TorrentDetail> fetchTorrentDetail(
    String id, {
    String? description,
    String? detailUrl,
  }) async {
    String? url = WebAdapterCore.resolveHttpUrl(detailUrl, _siteConfig.baseUrl);
    if (url == null) {
      final template = await _getTemplate();
      final request = _dynamicMap(template.request?['detail']);
      final path = request['path'] ?? request['url'];
      if (path is String && path.isNotEmpty) {
        final relative = WebAdapterCore.replacePlaceholders(path, {
          'torrentId': id,
          'id': id,
          'baseUrl': _siteConfig.baseUrl,
        });
        url = WebAdapterCore.resolveHttpUrl(relative, _siteConfig.baseUrl);
      }
    }
    if (url == null) {
      throw WebAdapterConfigurationException(
        'Web 种子详情缺少 detailUrl，且模板未提供 request.detail.path',
      );
    }
    await WebAdapterCore.syncCookiesToWebView(_siteConfig);
    return TorrentDetail(descr: '', descrHtml: description, webviewUrl: url);
  }

  @override
  Future<String> genDlToken({required String id, String? url}) async {
    final direct = WebAdapterCore.resolveHttpUrl(url, _siteConfig.baseUrl);
    if (direct != null) return direct;

    final template = await _getTemplate();
    final request = _dynamicMap(template.request?['download']);
    final path = request['path'] ?? request['url'];
    if (path is String && path.isNotEmpty) {
      final relative = WebAdapterCore.replacePlaceholders(path, {
        'torrentId': id,
        'id': id,
        'baseUrl': _siteConfig.baseUrl,
      });
      final generated = WebAdapterCore.resolveHttpUrl(
        relative,
        _siteConfig.baseUrl,
      );
      if (generated != null) return generated;
    }
    throw WebAdapterConfigurationException(
      'Web 种子下载缺少列表 downloadUrl，且模板未提供 request.download.path',
    );
  }

  @override
  Future<TorrentCommentList> fetchComments(
    String id, {
    int pageNumber = 1,
    int pageSize = 20,
  }) async {
    return TorrentCommentList(
      pageNumber: pageNumber,
      pageSize: pageSize,
      total: 0,
      totalPages: 0,
      comments: const [],
    );
  }

  @override
  Future<Map<String, dynamic>> queryHistory({
    required List<String> tids,
  }) async => const {};

  @override
  Future<void> toggleCollection({
    required String torrentId,
    required bool make,
  }) {
    throw UnsupportedError('通用 Web 站点暂不支持收藏操作');
  }

  @override
  Future<bool> testConnection() async {
    try {
      await fetchMemberProfile();
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<List<SearchCategoryConfig>> getSearchCategories() async {
    if (_siteConfig.searchCategories.isNotEmpty) {
      return _siteConfig.searchCategories;
    }
    return (await _getTemplate()).searchCategories;
  }

  static Map<String, dynamic> _dynamicMap(dynamic value) {
    if (value is! Map) return <String, dynamic>{};
    return value.map((key, entry) => MapEntry(key.toString(), entry));
  }

  static Map<String, String> _stringMap(dynamic value) {
    if (value is! Map) return <String, String>{};
    return value.map(
      (key, entry) => MapEntry(key.toString(), entry.toString()),
    );
  }

  static String _profileValue(Map<String, String> values, List<String> keys) {
    for (final key in keys) {
      final value = values[key];
      if (value != null && value.isNotEmpty) return value;
    }
    return '';
  }

  static double _asDouble(String value) =>
      double.tryParse(value.replaceAll(',', '')) ?? 0;

  static double? _optionalDouble(String? value) {
    if (value == null || value.isEmpty) return null;
    return _asDouble(value);
  }
}
