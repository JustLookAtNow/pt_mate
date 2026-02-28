import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart';

import '../../models/app_models.dart';
import '../../utils/format.dart';
import 'site_adapter.dart';
import 'api_exceptions.dart';
import '../site_config_service.dart';
import 'base_web_adapter.dart';
import 'package:dio/dio.dart';
import 'package:beautiful_soup_dart/beautiful_soup.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';
import '../logging/log_file_service.dart';

/// 参数对象，用于 Isolate 搜索解析
class ParseSearchParams {
  final String html;
  final Map<String, dynamic> searchConfig;
  final Map<String, dynamic> totalPagesConfig;
  final Map<String, String> discountMapping;
  final Map<String, String> tagMapping;
  final String baseUrl;
  final String passKey;
  final String userId;
  final int pageNumber;
  final int pageSize;

  ParseSearchParams({
    required this.html,
    required this.searchConfig,
    required this.totalPagesConfig,
    required this.discountMapping,
    required this.tagMapping,
    required this.baseUrl,
    required this.passKey,
    required this.userId,
    required this.pageNumber,
    required this.pageSize,
  });
}

/// 解析结果对象
class ParsedTorrentResult {
  final List<TorrentItem> items;
  final int totalPages;
  final List<String> logs;

  ParsedTorrentResult({
    required this.items,
    required this.totalPages,
    this.logs = const [],
  });
}

/// Helper class for Isolate usage
class _AdapterHelper with BaseWebAdapterMixin {}

/// Isolate entry point for parsing search results
Future<ParsedTorrentResult> _parseSearchResponseInIsolate(
  ParseSearchParams params,
) async {
  final soup = BeautifulSoup(params.html);
  final logs = <String>[];

  final torrents = await NexusPHPWebAdapter._staticParseTorrentList(
    soup,
    params.searchConfig,
    params.discountMapping,
    params.tagMapping,
    params.baseUrl,
    params.passKey,
    params.userId,
    logs,
  );

  final totalPages = await NexusPHPWebAdapter._staticParseTotalPages(
    soup,
    params.totalPagesConfig,
    logs,
  );

  return ParsedTorrentResult(
    items: torrents,
    totalPages: totalPages,
    logs: logs,
  );
}

/// NexusPHP Web站点适配器
/// 用于处理基于Web接口的NexusPHP站点
class NexusPHPWebAdapter extends SiteAdapter with BaseWebAdapterMixin {
  late SiteConfig _siteConfig;
  late Dio _dio;
  Map<String, String>? _discountMapping;
  Map<String, String>? _tagMapping;
  SiteConfigTemplate? _customTemplate;
  static final Logger _logger = Logger();
  static const int _maxHtmlDumpLength = 200 * 1024; // 200KB 截断

  void _logRuleAndSoup(String tag, Map<String, dynamic>? rule, dynamic soup) {
    try {
      final ruleJson = rule != null ? jsonEncode(rule) : '{}';
      String html = '';
      try {
        html = soup?.toString() ?? '';
      } catch (_) {}
      if (html.length > _maxHtmlDumpLength) {
        html = '${html.substring(0, _maxHtmlDumpLength)}\n... (truncated)';
      }
      // todo简单脱敏
      _logger.e('[$tag] rule=$ruleJson');
      // 使用 debugPrint 输出 HTML，避免 Logger 的格式化（边框等）导致难以复制
      debugPrint('HTML=$html');
      LogFileService.instance.append('[$tag] rule=$ruleJson');
      LogFileService.instance.append('HTML=$html');
    } catch (_) {
      // 忽略日志失败
    }
  }

  @override
  SiteConfig get siteConfig => _siteConfig;

  @override
  Future<void> init(SiteConfig config) async {
    final swTotal = Stopwatch()..start();
    _siteConfig = config;

    // 加载优惠类型映射配置
    final swDiscount = Stopwatch()..start();
    await _loadDiscountMapping();
    // 加载标签映射配置
    await _loadTagMapping();
    swDiscount.stop();
    if (kDebugMode) {
      _logger.d(
        'NexusPHPWebAdapter.init: 加载优惠映射耗时=${swDiscount.elapsedMilliseconds}ms',
      );
    }

    final swDio = Stopwatch()..start();
    _dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 5),
        receiveTimeout: const Duration(seconds: 10),
        sendTimeout: const Duration(seconds: 30),
      ),
    );
    _dio.options.baseUrl = _siteConfig.baseUrl;
    _dio.options.headers['User-Agent'] =
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/143.0.0.0 Safari/537.36';
    _dio.options.responseType = ResponseType.plain; // 设置为plain避免JSON解析警告
    swDio.stop();
    if (kDebugMode) {
      _logger.d(
        'NexusPHPWebAdapter.init: 创建Dio与基本配置耗时=${swDio.elapsedMilliseconds}ms',
      );
    }

    // 添加响应拦截器处理302重定向
    final swInterceptors = Stopwatch()..start();
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          // 动态添加Cookie
          if (_siteConfig.cookie != null && _siteConfig.cookie!.isNotEmpty) {
            options.headers['Cookie'] = _siteConfig.cookie;
          }
          handler.next(options);
        },
        onResponse: (response, handler) {
          // 检查是否是302重定向到登录页面
          // Dio默认会自动跟随重定向，因此最终状态码可能是200。
          // 我们需要检查最终的URI或重定向记录来判断是否跳转到了登录页。
          final isLoginRedirect =
              response.realUri.toString().contains('login') ||
              response.redirects.any(
                (r) => r.location.toString().contains('login'),
              );

          if (isLoginRedirect) {
            throw SiteAuthenticationException(
              message: 'Cookie已过期，请重新登录更新Cookie',
            );
          }

          if (response.statusCode == 302) {
            final location = response.headers.value('location');
            if (location != null && location.contains('login')) {
              throw SiteAuthenticationException(
                message: 'Cookie已过期，请重新登录更新Cookie',
              );
            }
          }
          handler.next(response);
        },
        onError: (error, handler) {
          // 检查DioException中的响应状态码
          if (error.response?.statusCode == 302) {
            final location = error.response?.headers.value('location');
            if (location != null && location.contains('login')) {
              throw SiteAuthenticationException(
                message: 'Cookie已过期，请重新登录更新Cookie',
              );
            }
          }
          handler.next(error);
        },
      ),
    );
    swInterceptors.stop();
    if (kDebugMode) {
      _logger.d(
        'NexusPHPWebAdapter.init: 添加拦截器耗时=${swInterceptors.elapsedMilliseconds}ms',
      );
    }
    swTotal.stop();
    if (kDebugMode) {
      _logger.d(
        'NexusPHPWebAdapter.init: 总耗时=${swTotal.elapsedMilliseconds}ms',
      );
    }
  }

  void setCustomTemplate(SiteConfigTemplate template) {
    _customTemplate = template;
  }

  /// 加载优惠类型映射配置
  Future<void> _loadDiscountMapping() async {
    try {
      if (_customTemplate != null) {
        _discountMapping = Map<String, String>.from(
          _customTemplate!.discountMapping,
        );
        return;
      }
      final template = await SiteConfigService.getTemplateById(
        _siteConfig.templateId,
        _siteConfig.siteType,
      );
      if (template?.discountMapping != null) {
        _discountMapping = Map<String, String>.from(template!.discountMapping);
      }
    } catch (e) {
      // 使用默认映射
      _discountMapping = {};
    }
  }

  /// 加载标签映射配置
  Future<void> _loadTagMapping() async {
    try {
      if (_customTemplate != null) {
        _tagMapping = Map<String, String>.from(_customTemplate!.tagMapping);
        return;
      }
      final template = await SiteConfigService.getTemplateById(
        _siteConfig.templateId,
        _siteConfig.siteType,
      );
      if (template?.tagMapping != null) {
        _tagMapping = Map<String, String>.from(template!.tagMapping);
      }
    } catch (e) {
      _tagMapping = {};
    }
  }

  /// 从字符串解析标签类型
  TagType? _parseTagType(String? str) {
    return _staticParseTagType(str, _tagMapping ?? {});
  }

  /// 从字符串解析标签类型（静态方法）
  static TagType? _staticParseTagType(String? str, Map<String, String> mapping) {
    if (str == null || str.isEmpty) return null;

    final enumName = mapping[str];

    if (enumName != null) {
      for (final type in TagType.values) {
        if (type.name.toLowerCase() == enumName.toLowerCase()) {
          return type;
        }
        // 也可以尝试匹配 content
        if (type.content == enumName) {
          return type;
        }
      }
    }
    return null;
  }

  /// 从字符串解析优惠类型
  DiscountType _parseDiscountType(String? str) {
    return _staticParseDiscountType(str, _discountMapping ?? {});
  }

  /// 从字符串解析优惠类型（静态方法）
  static DiscountType _staticParseDiscountType(String? str, Map<String, String> mapping) {
    if (str == null || str.isEmpty) return DiscountType.normal;

    final enumValue = mapping[str];

    if (enumValue != null) {
      for (final type in DiscountType.values) {
        if (type.value == enumValue) {
          return type;
        }
      }
    }

    return DiscountType.normal;
  }

  @override
  Future<MemberProfile> fetchMemberProfile({String? apiKey}) async {
    try {
      // 获取配置信息
      final config = await _getUserInfoConfig();
      final path = config['path'] as String? ?? 'usercp.php';

      final response = await _dio.get('/$path');
      final soup = BeautifulSoup(response.data);

      // 根据配置提取用户信息
      final userInfo = await _extractUserInfoByConfig(soup, config);

      // 提取PassKey（如果配置了）
      String? passKey = await _extractPassKeyByConfig();

      // 提取每小时魔力（如果配置了）
      double? bonusPerHour = await _extractBonusPerHourByConfig();

      // 将字符串格式的数据转换为数字
      double shareRate =
          double.tryParse(userInfo['ratio']?.replaceAll(',', '') ?? '0') ?? 0.0;
      double bonusPoints =
          double.tryParse((userInfo['bonus'] ?? '0').replaceAll(',', '')) ??
          0.0;

      // 对于bytes，由于web版本直接提供格式化字符串，这里设置为0
      // 实际使用时应该使用uploadedBytesString和downloadedBytesString
      int uploadedBytes = 0;
      int downloadedBytes = 0;

      // 更新站点配置中的临时 passKey 和 userId，便于后续下载链接生成等逻辑使用
      try {
        final uidStr = (userInfo['userId'] ?? '').toString();
        if ((passKey != null && passKey.isNotEmpty) &&
            (_siteConfig.passKey == null || _siteConfig.passKey!.isEmpty)) {
          _siteConfig = _siteConfig.copyWith(passKey: passKey);
        }
        if (uidStr.isNotEmpty &&
            (_siteConfig.userId == null || _siteConfig.userId!.isEmpty)) {
          _siteConfig = _siteConfig.copyWith(userId: uidStr);
        }
      } catch (_) {}

      return MemberProfile(
        username: userInfo['userName'] ?? '',
        bonus: bonusPoints,
        shareRate: shareRate,
        uploadedBytes: uploadedBytes,
        downloadedBytes: downloadedBytes,
        uploadedBytesString: userInfo['upload'] ?? '0 B',
        downloadedBytesString: userInfo['download'] ?? '0 B',
        userId: userInfo['userId'],
        passKey: passKey,
        bonusPerHour: bonusPerHour,
        lastAccess: null, // Web版本暂不提供该字段
      );
    } catch (e) {
      throw ApiExceptionAdapter.wrapError(e, '获取用户资料');
    }
  }

  /// 获取指定类型的配置
  /// [configType] 配置类型，如 'userInfo', 'passKey', 'search', 'categories' 等
  Future<Map<String, dynamic>> _getFinderConfig(String configType) async {
    if (_customTemplate != null && _customTemplate!.infoFinder != null) {
      final infoFinder = _customTemplate!.infoFinder!;
      if (infoFinder[configType] != null) {
        return infoFinder[configType] as Map<String, dynamic>;
      }
    }
    // 优先读取 SiteConfig.templateId 对应的配置
    if (_siteConfig.templateId != '-1') {
      try {
        final template = await SiteConfigService.getTemplateById(
          _siteConfig.templateId,
          _siteConfig.siteType,
        );
        if (template != null && template.infoFinder != null) {
          final infoFinder = template.infoFinder!;
          if (infoFinder[configType] != null) {
            return infoFinder[configType] as Map<String, dynamic>;
          }
        }
      } catch (e) {
        // 如果获取模板配置失败，继续使用默认配置
        if (kDebugMode) {
          if (kDebugMode) {
            _logger.e('获取模板配置失败: $e');
          }
        }
      }
    }

    // 没有找到模板配置或模板ID为-1，使用默认的 NexusPHPWeb 配置
    final template = await SiteConfigService.getTemplateById(
      '',
      SiteType.nexusphpweb,
    );
    if (template != null && template.infoFinder != null) {
      final infoFinder = template.infoFinder!;
      if (infoFinder[configType] != null) {
        return infoFinder[configType] as Map<String, dynamic>;
      }
    }
    return {};
  }

  /// 获取指定类型的请求配置
  /// [action] 请求动作，如 'loginPage', 'collect', 'unCollect' 或 'search.normal' 等
  Future<Map<String, dynamic>?> _getRequestConfig(String action) async {
    final templatesToTry = <SiteConfigTemplate?>[];

    // 1. 尝试自定义模板
    if (_customTemplate != null) {
      templatesToTry.add(_customTemplate);
    }

    // 2. 尝试指定的模板 ID
    if (_siteConfig.templateId != '-1' && _siteConfig.templateId.isNotEmpty) {
      try {
        final template = await SiteConfigService.getTemplateById(
          _siteConfig.templateId,
          _siteConfig.siteType,
        );
        if (template != null) {
          templatesToTry.add(template);
        }
      } catch (e) {
        if (kDebugMode) {
          _logger.e('获取模板失败: $e');
        }
      }
    }

    // 3. 始终最后尝试默认的 NexusPHPWeb 模板
    try {
      final defaultTemplate = await SiteConfigService.getTemplateById(
        '',
        SiteType.nexusphpweb,
      );
      if (defaultTemplate != null) {
        templatesToTry.add(defaultTemplate);
      }
    } catch (_) {}

    // 对每个模板尝试解析动作路径
    final parts = action.split('.');
    for (final template in templatesToTry) {
      if (template == null || template.request == null) continue;

      dynamic current = template.request;
      bool found = true;
      for (final part in parts) {
        if (current is Map && current.containsKey(part)) {
          current = current[part];
        } else {
          found = false;
          break;
        }
      }

      if (found && current is Map<String, dynamic>) {
        return current;
      }
    }

    return null;
  }

  /// 获取用户信息配置（保持向前兼容）
  Future<Map<String, dynamic>> _getUserInfoConfig() async {
    return _getFinderConfig('userInfo');
  }

  /// 根据配置提取用户信息
  Future<Map<String, String?>> _extractUserInfoByConfig(
    BeautifulSoup soup,
    Map<String, dynamic> config,
  ) async {
    final result = <String, String?>{};

    // 获取行选择器配置
    final rowsConfig = config['rows'] as Map<String, dynamic>?;
    final fieldsConfig = config['fields'] as Map<String, dynamic>?;

    if (rowsConfig == null || fieldsConfig == null) {
      throw Exception('配置格式错误：缺少 rows 或 fields 配置');
    }

    // 根据行选择器找到目标元素
    final rowSelector = rowsConfig['selector'] as String?;
    if (rowSelector == null || rowSelector.isEmpty) {
      throw Exception('配置错误：缺少行选择器');
    }

    final targetElement = findFirstElementBySelector(soup, rowSelector);
    if (targetElement == null) {
      _logRuleAndSoup('userInfo.rows.notFound', rowsConfig, soup);
      throw Exception('未找到目标元素：$rowSelector');
    }

    // 遍历字段配置，提取每个字段的值
    for (final fieldEntry in fieldsConfig.entries) {
      final fieldName = fieldEntry.key;
      final fieldConfig = fieldEntry.value as Map<String, dynamic>;

      try {
        final value = await extractFirstFieldValue(targetElement, fieldConfig);
        result[fieldName] = value;
      } catch (e) {
        // 如果某个字段提取失败，记录但继续处理其他字段
        _logRuleAndSoup(
          'userInfo.field.extractFailed.$fieldName',
          fieldConfig,
          targetElement,
        );
        result[fieldName] = null;
      }
    }

    return result;
  }

  /// 根据配置提取每小时魔力（bonusPerHour）
  Future<double?> _extractBonusPerHourByConfig() async {
    try {
      final bonusConfig = await _getFinderConfig('bonusPerHour');
      final path = bonusConfig['path'] as String? ?? 'mybonus.php';

      final response = await _dio.get('/$path');
      final soup = BeautifulSoup(response.data);

      final rowsConfig = bonusConfig['rows'] as Map<String, dynamic>?;
      final fieldsConfig = bonusConfig['fields'] as Map<String, dynamic>?;

      if (rowsConfig == null || fieldsConfig == null) {
        throw Exception('配置格式错误：缺少 rows 或 fields 配置');
      }

      final rowSelector = rowsConfig['selector'] as String?;
      if (rowSelector == null || rowSelector.isEmpty) {
        throw Exception('配置错误：缺少行选择器');
      }

      final targetElement = findFirstElementBySelector(soup, rowSelector);
      if (targetElement == null) {
        _logRuleAndSoup('bonus.rows.notFound', rowsConfig, soup);
        throw Exception('未找到目标元素：$rowSelector');
      }

      final field = fieldsConfig['bonusPerHour'] as Map<String, dynamic>?;
      if (field == null) {
        _logRuleAndSoup('bonus.field.missing', fieldsConfig, soup);
        throw Exception('配置错误：缺少 bonusPerHour 字段');
      }

      final value = await extractFirstFieldValue(targetElement, field);
      if (value == null || value.isEmpty) return null;

      final parsed = double.tryParse(value.replaceAll(',', ''));
      return parsed;
    } catch (e) {
      _logRuleAndSoup('bonus.extract.failed', null, BeautifulSoup(''));
      return null;
    }
  }

  /// 根据配置提取PassKey
  Future<String?> _extractPassKeyByConfig() async {
    try {
      // 获取PassKey配置
      final passKeyConfig = await _getFinderConfig('passKey');

      // 获取PassKey页面路径
      final path = passKeyConfig['path'] as String?;
      if (path == null || path.isEmpty) {
        throw Exception('PassKey配置中缺少path字段');
      }
      final response = await _dio.get('/$path');
      final soup = BeautifulSoup(response.data);

      // 获取行选择器配置
      final rowsConfig = passKeyConfig['rows'] as Map<String, dynamic>?;

      if (rowsConfig == null) {
        _logRuleAndSoup('passKey.rows.missing', passKeyConfig, soup);
        throw Exception('配置格式错误：缺少 rows 配置');
      }

      // 根据行选择器找到目标元素
      final rowSelector = rowsConfig['selector'] as String?;
      if (rowSelector == null || rowSelector.isEmpty) {
        throw Exception('配置错误：缺少行选择器');
      }

      final targetElement = findFirstElementBySelector(soup, rowSelector);
      if (targetElement == null) {
        _logRuleAndSoup('passKey.rows.notFound', rowsConfig, soup);
        throw Exception('未找到目标元素：$rowSelector');
      }

      // 根据配置提取PassKey
      final fields = passKeyConfig['fields'] as Map<String, dynamic>?;
      final passKeyField = fields?['passKey'] as Map<String, dynamic>?;

      if (passKeyField != null) {
        final value = await extractFirstFieldValue(
          targetElement,
          passKeyField,
        );
        if (value != null && value.isNotEmpty) {
          return value.trim();
        } else {
          _logRuleAndSoup(
            'passKey.field.extractFailed',
            passKeyField,
            targetElement,
          );
          _logRuleAndSoup('passKey.rows.info', rowsConfig, soup);

          throw Exception('提取PassKey失败：未匹配到目标元素$rowSelector');
        }
      }

      _logRuleAndSoup('passKey.field.undefined', passKeyConfig, soup);
      throw Exception('无法从配置中提取PassKey');
    } catch (e) {
      _logRuleAndSoup('passKey.extract.failed', null, BeautifulSoup(''));
      throw Exception('提取PassKey失败: $e');
    }
  }

  @override
  Future<TorrentSearchResult> searchTorrents({
    String? keyword,
    int pageNumber = 0,
    int pageSize = 100,
    int? onlyFav,
    Map<String, dynamic>? additionalParams,
  }) async {
    try {
      // 确定搜索动作类型
      String searchAction = 'search.normal';

      // 提取分类前缀信息（如果存在）
      String? categoryParam;
      if (additionalParams != null &&
          additionalParams.containsKey('category')) {
        categoryParam = additionalParams['category'] as String?;
        if (categoryParam != null && categoryParam.startsWith('special')) {
          searchAction = 'search.special';
        }
      }

      // 获取搜索请求配置
      final requestConfig = await _getRequestConfig(searchAction);
      if (requestConfig == null) {
        throw Exception('未找到搜索配置: $searchAction');
      }

      final path = requestConfig['path'] as String? ?? '/torrents.php';
      final method = requestConfig['method'] as String? ?? 'GET';
      final configParams = Map<String, dynamic>.from(
        requestConfig['params'] as Map<String, dynamic>? ?? {},
      );

      // 提取分类 ID（格式: "prefix#categoryId"）
      String categoryId = '';
      if (categoryParam != null) {
        final parts = categoryParam.split('#');
        if (parts.length == 2 && parts[1].isNotEmpty) {
          categoryId = parts[1];
        }
      }

      // 构建最终查询参数
      final queryParams = <String, dynamic>{};

      // 替换占位符并填充参数
      configParams.forEach((key, value) {
        if (value is String) {
          String val = value;
          val = val.replaceAll('{keyword}', keyword ?? '');
          val = val.replaceAll('{page}', (pageNumber - 1).toString());
          val = val.replaceAll('{pageSize}', pageSize.toString());

          // 处理 {categoryId} 占位符：无分类时移除该参数
          if (val.contains('{categoryId}')) {
            if (categoryId.isNotEmpty) {
              val = val.replaceAll('{categoryId}', categoryId);
            } else {
              return; // 没有分类 ID，不加入 queryParams
            }
          }

          // 处理 {onlyFav} 占位符
          if (val.contains('{onlyFav}')) {
            if (onlyFav == 1) {
              val = val.replaceAll('{onlyFav}', '1');
              queryParams[key] = val;
            }
            // 如果不是 1，则不加入 queryParams (即移除该参数)
          } else {
            queryParams[key] = val;
          }
          
        } else {
          queryParams[key] = value;
        }
      });

      // 添加其他额外参数
      if (additionalParams != null) {
        additionalParams.forEach((key, value) {
          if (key != 'category') {
            queryParams[key] = value;
          }
        });
      }

      // 发送请求
      final response = await _dio.request(
        path,
        queryParameters: method.toUpperCase() == 'GET' ? queryParams : null,
        data: method.toUpperCase() == 'POST' ? queryParams : null,
        options: Options(method: method.toUpperCase()),
      );

      // 准备在 Isolate 中进行解析的参数
      final searchConfig = await _getFinderConfig('search');
      final totalPagesConfig = await _getFinderConfig('totalPages');

      // 如果搜索配置为空，直接返回空结果，不启动 Isolate
      if (searchConfig.isEmpty) {
        return TorrentSearchResult(
          pageNumber: pageNumber,
          pageSize: pageSize,
          total: 0,
          totalPages: 0,
          items: [],
        );
      }

      final parseParams = ParseSearchParams(
        html: response.data.toString(),
        searchConfig: searchConfig,
        totalPagesConfig: totalPagesConfig,
        discountMapping: _discountMapping ?? {},
        tagMapping: _tagMapping ?? {},
        baseUrl: _siteConfig.baseUrl,
        passKey: _siteConfig.passKey ?? '',
        userId: _siteConfig.userId ?? '',
        pageNumber: pageNumber,
        pageSize: pageSize,
      );

      // 在 Isolate 中执行解析
      final result = await compute(_parseSearchResponseInIsolate, parseParams);

      return TorrentSearchResult(
        pageNumber: pageNumber,
        pageSize: pageSize,
        total: result.items.length * result.totalPages, // 估算值
        totalPages: result.totalPages,
        items: result.items,
      );
    } catch (e) {
      throw ApiExceptionAdapter.wrapError(e, '搜索种子');
    }
  }

  /// 下载种子文件
  ///
  /// [url] 种子文件的下载链接（相对路径或绝对路径）
  /// 返回种子文件的字节数据
  Future<List<int>> downloadTorrent(String url) async {
    try {
      // 确保URL是相对路径或完整的BaseURL路径
      String downloadUrl = url;
      if (url.startsWith('http')) {
        // 如果是完整URL，检查是否属于当前站点
        if (!url.startsWith(_siteConfig.baseUrl)) {
          // 如果不属于当前站点，直接使用Dio下载（带Cookie可能会有问题，但尝试一下）
          // 或者这里应该抛出异常？通常下载链接应该是站内的
        }
      }

      _logger.i('NexusPHPWebAdapter: Downloading torrent from $downloadUrl');

      final response = await _dio.get<List<int>>(
        downloadUrl,
        options: Options(
          responseType: ResponseType.bytes,
          followRedirects: true,
          maxRedirects: 5,
          validateStatus: (status) => status != null && status < 400,
        ),
      );

      _logger.i(
        'NexusPHPWebAdapter: Download finished. Status: ${response.statusCode}',
      );
      _logger.d('NexusPHPWebAdapter: Response headers: ${response.headers}');
      _logger.d('NexusPHPWebAdapter: Final URI: ${response.realUri}');

      if (response.realUri.toString().contains('login') ||
          response.realUri.toString().contains('verify')) {
        throw Exception(
          'Download redirected to login/verify page. Check cookies.',
        );
      }

      final contentType = response.headers.value('content-type');
      if (contentType != null &&
          !contentType.contains('bittorrent') &&
          !contentType.contains('octet-stream')) {
        _logger.w(
          'NexusPHPWebAdapter: Warning - Content-Type is $contentType, might not be a torrent file.',
        );
      }

      if (response.data != null) {
        return response.data!;
      } else {
        throw Exception('下载种子文件失败: 响应为空');
      }
    } catch (e) {
      _logger.e('下载种子文件失败: $e');
      rethrow;
    }
  }

  Future<int> parseTotalPages(BeautifulSoup soup) async {
    final config = await _getFinderConfig('totalPages');
    if (config.isEmpty) {
      return 1;
    }
    return _staticParseTotalPages(soup, config);
  }

  static Future<int> _staticParseTotalPages(
    BeautifulSoup soup,
    Map<String, dynamic> config, [
    List<String>? logs,
  ]) async {
    final helper = _AdapterHelper();
    int totalPages = 1;
    try {
      final rowsConfig = config['rows'] as Map<String, dynamic>?;
      final fieldsConfig = config['fields'] as Map<String, dynamic>?;

      if (rowsConfig == null || fieldsConfig == null) {
        return 1;
      }

      // 获取行选择器配置
      final rowSelector = rowsConfig['selector'] as String?;
      if (rowSelector == null || rowSelector.isEmpty) {
        return 1;
      }

      // 找到目标行
      final rows = helper.findElementBySelector(soup, rowSelector);
      if (rows.isEmpty) {
        return 1;
      }

      final fieldConfig = fieldsConfig['totalPages'] as Map<String, dynamic>?;
      if (fieldConfig == null) {
        return 1;
      }

      List<int> pageValues = [];
      for (final row in rows) {
        final values = await helper.extractFieldValue(row, fieldConfig);
        for (final val in values) {
          final parsed = FormatUtil.parseInt(val);
          if (parsed != null) {
            pageValues.add(parsed);
          }
        }
      }

      if (pageValues.isNotEmpty) {
        totalPages = pageValues.reduce((a, b) => a > b ? a : b);
      }
    } catch (e) {
      logs?.add('解析总页数失败: $e');
      if (logs == null) {
        // 在静态上下文中直接调用 _logger 是安全的，因为它是 static final
        _logger.e('解析总页数失败: $e');
      }
    }
    return totalPages;
  }

  Future<List<TorrentItem>> parseTorrentList(BeautifulSoup soup) async {
    // 获取搜索配置
    final searchConfig = await _getFinderConfig('search');
    // 如果没有配置，返回空列表
    if (searchConfig.isEmpty) return [];

    return _staticParseTorrentList(
      soup,
      searchConfig,
      _discountMapping ?? {},
      _tagMapping ?? {},
      _siteConfig.baseUrl,
      _siteConfig.passKey ?? '',
      _siteConfig.userId ?? '',
    );
  }

  static Future<List<TorrentItem>> _staticParseTorrentList(
    BeautifulSoup soup,
    Map<String, dynamic> searchConfig,
    Map<String, String> discountMapping,
    Map<String, String> tagMapping,
    String baseUrl,
    String passKey,
    String userId, [
    List<String>? logs,
  ]) async {
    final helper = _AdapterHelper();
    final torrents = <TorrentItem>[];

    try {
      final rowsConfig = searchConfig['rows'] as Map<String, dynamic>?;
      final fieldsConfig = searchConfig['fields'] as Map<String, dynamic>?;

      if (rowsConfig == null || fieldsConfig == null) {
        logs?.add('search.config.missing: $searchConfig');
        return torrents;
      }

      final rowSelector = rowsConfig['selector'] as String?;
      if (rowSelector == null) {
        logs?.add('search.rowSelector.missing: $rowsConfig');
        return torrents;
      }

      // 使用配置的选择器查找行
      final rows = helper.findElementBySelector(soup, rowSelector);

      for (final rowElement in rows) {
        final row = rowElement as Bs4Element;
        try {
          // 提取种子ID - 如果提取失败则跳过当前行
          final torrentIdConfig =
              fieldsConfig['torrentId'] as Map<String, dynamic>?;
          if (torrentIdConfig == null) {
            continue;
          }

          final torrentIdList = await helper.extractFieldValue(row, torrentIdConfig);
          final torrentId = torrentIdList.isNotEmpty ? torrentIdList.first : '';
          if (torrentId.isEmpty) {
            continue; // 种子ID提取失败，跳过当前行
          }

          // 提取其他字段
          final torrentNameList = await helper.extractFieldValue(
            row,
            fieldsConfig['torrentName'] as Map<String, dynamic>? ?? {},
          );
          final torrentName = torrentNameList.isNotEmpty
              ? torrentNameList.first
              : '';

          final tagList = await helper.extractFieldValue(
            row,
            fieldsConfig['tag'] as Map<String, dynamic>? ?? {},
          );

          final descriptionList = await helper.extractFieldValue(
            row,
            fieldsConfig['description'] as Map<String, dynamic>? ?? {},
          );
          final description = descriptionList.isNotEmpty
              ? descriptionList.first
              : '';

          final discountList = await helper.extractFieldValue(
            row,
            fieldsConfig['discount'] as Map<String, dynamic>? ?? {},
          );
          final discount = discountList.isNotEmpty ? discountList.first : '';

          final discountEndTimeConfig =
              fieldsConfig['discountEndTime'] as Map<String, dynamic>? ?? {};
          final discountEndTimeList = await helper.extractFieldValue(
            row,
            discountEndTimeConfig,
          );
          final discountEndTime = discountEndTimeList.isNotEmpty
              ? discountEndTimeList.first
              : '';
          final discountEndTimeTimeConfig =
              discountEndTimeConfig['time'] as Map<String, dynamic>?;

          final seedersTextList = await helper.extractFieldValue(
            row,
            fieldsConfig['seedersText'] as Map<String, dynamic>? ?? {},
          );
          final seedersText = seedersTextList.isNotEmpty
              ? seedersTextList.first
              : '';

          final leechersTextList = await helper.extractFieldValue(
            row,
            fieldsConfig['leechersText'] as Map<String, dynamic>? ?? {},
          );
          final leechersText = leechersTextList.isNotEmpty
              ? leechersTextList.first
              : '';

          final sizeTextList = await helper.extractFieldValue(
            row,
            fieldsConfig['sizeText'] as Map<String, dynamic>? ?? {},
          );
          final sizeText = sizeTextList.isNotEmpty ? sizeTextList.first : '';

          final downloadStatusTextList = await helper.extractFieldValue(
            row,
            fieldsConfig['downloadStatus'] as Map<String, dynamic>? ?? {},
          );
          final downloadUrlConfig =
              fieldsConfig['downloadUrl'] as Map<String, dynamic>? ?? {};
          var downloadUrl = '';
          if (downloadUrlConfig['value'] != null) {
            downloadUrl = downloadUrlConfig['value'] as String? ?? '';
            downloadUrl = downloadUrl.replaceAll('{torrentId}', torrentId);
            downloadUrl = downloadUrl.replaceAll(
              '{passKey}',
              passKey,
            );
            var finalBaseUrl = baseUrl;
            if (baseUrl.endsWith("/")) {
              finalBaseUrl = baseUrl.substring(
                0,
                baseUrl.length - 1,
              );
            }
            downloadUrl = downloadUrl.replaceAll('{baseUrl}', finalBaseUrl);
          }

          final downloadStatusText = downloadStatusTextList.isNotEmpty
              ? downloadStatusTextList.first
              : '';

          final coverList = await helper.extractFieldValue(
            row,
            fieldsConfig['cover'] as Map<String, dynamic>? ?? {},
          );
          final cover = coverList.isNotEmpty ? coverList.first : '';

          final createDateConfig =
              fieldsConfig['createDate'] as Map<String, dynamic>? ?? {};
          final createDateList = await helper.extractFieldValue(
            row,
            createDateConfig,
          );
          final createDate = createDateList.isNotEmpty
              ? createDateList.first
              : '';
          final createDateTimeConfig =
              createDateConfig['time'] as Map<String, dynamic>?;

          final doubanRatingList = await helper.extractFieldValue(
            row,
            fieldsConfig['doubanRating'] as Map<String, dynamic>? ?? {},
          );
          final doubanRating = doubanRatingList.isNotEmpty
              ? doubanRatingList.first
              : '';

          final imdbRatingList = await helper.extractFieldValue(
            row,
            fieldsConfig['imdbRating'] as Map<String, dynamic>? ?? {},
          );
          final imdbRating = imdbRatingList.isNotEmpty
              ? imdbRatingList.first
              : '';

          // 提取评论数
          final commentsList = await helper.extractFieldValue(
            row,
            fieldsConfig['comments'] as Map<String, dynamic>? ?? {},
          );
          final commentsText = commentsList.isNotEmpty
              ? commentsList.first
              : '0';
          final comments = FormatUtil.parseInt(commentsText) ?? 0;

          // 检查收藏状态（布尔字段）
          final collectionConfig =
              fieldsConfig['collection'] as Map<String, dynamic>?;
          bool collection = false;
          if (collectionConfig != null) {
            final collectionList = await helper.extractFieldValue(
              row,
              collectionConfig,
            );
            collection = collectionList.isNotEmpty; // 如果找不到元素说明未收藏
          }
          // 检查置顶状态（布尔字段）
          final isTopConfig = fieldsConfig['isTop'] as Map<String, dynamic>?;
          bool isTop = false;
          if (isTopConfig != null) {
            final isTopList = await helper.extractFieldValue(row, isTopConfig);
            isTop = isTopList.isNotEmpty; // 如果找不到元素说明未置顶
          }

          DownloadStatus downloadStatus = DownloadStatus.none;
          if (downloadStatusText.isNotEmpty) {
            final percentInt = FormatUtil.parseInt(downloadStatusText);
            if (percentInt != null) {
              if (percentInt == 100) {
                downloadStatus = DownloadStatus.completed;
              } else {
                downloadStatus = DownloadStatus.downloading;
              }
            }
          }

          // 解析文件大小为字节数
          int sizeInBytes = 0;
          if (sizeText.isNotEmpty) {
            final sizeMatch = RegExp(r'([\d.]+)\s*(\w+)').firstMatch(sizeText);
            if (sizeMatch != null) {
              final sizeValue = double.tryParse(sizeMatch.group(1) ?? '0') ?? 0;
              final unit = sizeMatch.group(2)?.toUpperCase() ?? 'B';

              switch (unit) {
                case 'KB':
                case 'KIB':
                  sizeInBytes = (sizeValue * 1024).round();
                  break;
                case 'MB':
                case 'MIB':
                  sizeInBytes = (sizeValue * 1024 * 1024).round();
                  break;
                case 'GB':
                case 'GIB':
                  sizeInBytes = (sizeValue * 1024 * 1024 * 1024).round();
                  break;
                case 'TB':
                case 'TIB':
                  sizeInBytes = (sizeValue * 1024 * 1024 * 1024 * 1024).round();
                  break;
                default:
                  sizeInBytes = sizeValue.round();
              }
            }
          }

          // 计算标签并清理描述
          final tags = TagType.matchTags(torrentName + description);

          if (tagList.isNotEmpty) {
            for (final tagStr in tagList) {
              final mappedTag = _staticParseTagType(tagStr, tagMapping);
              if (mappedTag != null && !tags.contains(mappedTag)) {
                tags.add(mappedTag);
              }
            }
          }

          torrents.add(
            TorrentItem(
              id: torrentId,
              name: torrentName,
              smallDescr: description.trim(),
              discount: _staticParseDiscountType(
                discount.isNotEmpty ? discount : null,
                discountMapping,
              ),
              discountEndTime: discountEndTime.isNotEmpty
                  ? Formatters.parseDateTimeCustom(
                      discountEndTime,
                      format: discountEndTimeTimeConfig?['format'] as String?,
                      zone: discountEndTimeTimeConfig?['zone'] as String?,
                    )
                  : null,
              downloadUrl: downloadUrl.isNotEmpty ? downloadUrl : null,
              seeders: FormatUtil.parseInt(seedersText) ?? 0,
              leechers: FormatUtil.parseInt(leechersText) ?? 0,
              sizeBytes: sizeInBytes,
              downloadStatus: downloadStatus,
              collection: collection,
              imageList: [], // 暂时不解析图片列表
              cover: cover,
              createdDate: Formatters.parseDateTimeCustom(
                createDate,
                format: createDateTimeConfig?['format'] as String?,
                zone: createDateTimeConfig?['zone'] as String?,
              ),
              doubanRating: doubanRating.isNotEmpty ? doubanRating : 'N/A',
              imdbRating: imdbRating.isNotEmpty ? imdbRating : 'N/A',
              isTop: isTop,
              tags: tags,
              comments: comments,
            ),
          );
        } catch (e) {
          logs?.add('search.row.parseFailed: ${fieldsConfig.toString()}');
          continue;
        }
      }
    } catch (e) {
      logs?.add('search.parse.failed: $e');
    }

    return torrents;
  }

  @override
  Future<TorrentDetail> fetchTorrentDetail(String id) async {
    // 构建种子详情页面URL
    final baseUrl = _siteConfig.baseUrl.endsWith('/')
        ? _siteConfig.baseUrl.substring(0, _siteConfig.baseUrl.length - 1)
        : _siteConfig.baseUrl;
    final detailUrl = '$baseUrl/details.php?id=$id&hit=1';

    // 如果启用了原生详情渲染，提取 DOM
    if (_siteConfig.features.nativeDetail) {
      try {
        final response = await _dio.get(
          '/details.php',
          queryParameters: {'id': id, 'hit': '1'},
        );
        final soup = BeautifulSoup(response.data);

        // 尝试通过配置获取详情选择器和内容类型
        String extractedContent = '';
        bool isBbcode = false;
        try {
          final detailConfig = await _getFinderConfig('detail');
          if (detailConfig.isNotEmpty) {
            isBbcode = detailConfig['isBbcode'] as bool? ?? false;
            final rowsConfig = detailConfig['rows'] as Map<String, dynamic>?;
            final selector = rowsConfig?['selector'] as String?;
            if (selector != null && selector.isNotEmpty) {
              final element = findFirstElementBySelector(soup, selector);
              if (element != null) {
                extractedContent = isBbcode ? element.text : element.innerHtml;
              }
            }
          }
        } catch (_) {
          // 配置不存在，使用默认选择器
        }

        // 默认 fallback 选择器（默认 HTML 模式）
        if (extractedContent.isEmpty) {
          final kdescr =
              soup.find('div', id: 'kdescr') ??
              soup.find('td', id: 'kdescr') ??
              soup.find('#kdescr');
          if (kdescr != null) {
            extractedContent = isBbcode ? kdescr.text : kdescr.innerHtml;
          }
        }

        if (extractedContent.isNotEmpty) {
          if (isBbcode) {
            return TorrentDetail(
              descr: extractedContent,
              webviewUrl: detailUrl,
            );
          } else {
            // HTML 模式：处理相对URL
            extractedContent = extractedContent.replaceAllMapped(
              RegExp(r'(src|href)="((?!https?://|//|data:|javascript:|#)[^"]+)"',
                  caseSensitive: false),
              (match) {
                final attr = match.group(1);
                final path = match.group(2)!;
                final separator = path.startsWith('/') ? '' : '/';
                return '$attr="$baseUrl$separator$path"';
              },
            );
            return TorrentDetail(
              descr: '',
              descrHtml: extractedContent,
              webviewUrl: detailUrl,
            );
          }
        }

        // 如果提取失败，fallback 到 WebView
        if (kDebugMode) {
          _logger.w('NativeDetail: 未能提取到描述内容，回退到 WebView 模式');
        }
      } catch (e) {
        // 提取失败，fallback 到 WebView
        if (kDebugMode) {
          _logger.e('NativeDetail: 提取失败，回退到 WebView: $e');
        }
      }
    }

    // WebView 模式（默认行为或 nativeDetail fallback）
    if (defaultTargetPlatform == TargetPlatform.android) {
      // 设置Cookie到baseUrl域下，HTTPOnly避免带到图片请求
      final cookieManager = CookieManager.instance();
      final baseUri = Uri.parse(_siteConfig.baseUrl);

      if (_siteConfig.cookie != null && _siteConfig.cookie!.isNotEmpty) {
        // 解析cookie字符串并设置到域下
        final cookies = _siteConfig.cookie!.split(';');
        for (final cookieStr in cookies) {
          final parts = cookieStr.trim().split('=');
          if (parts.length == 2) {
            await cookieManager.setCookie(
              url: WebUri(_siteConfig.baseUrl),
              name: parts[0].trim(),
              value: parts[1].trim(),
              domain: baseUri.host,
              isHttpOnly: true,
            );
          }
        }
      }
    }

    // 返回包含webview URL的TorrentDetail对象，让页面组件来处理嵌入式显示
    return TorrentDetail(
      descr: '', // 空描述，因为内容将通过webview显示
      webviewUrl: detailUrl, // 传递URL给页面组件
    );
  }

  @override
  Future<TorrentCommentList> fetchComments(
    String id, {
    int pageNumber = 1,
    int pageSize = 20,
  }) async {
    // NexusPHP Web 暂时不支持获取评论，返回空列表
    return TorrentCommentList(
      pageNumber: pageNumber,
      pageSize: pageSize,
      total: 0,
      totalPages: 0,
      comments: [],
    );
  }

  @override
  Future<String> genDlToken({required String id, String? url}) async {
    // 检查必要的配置参数
    if (_siteConfig.passKey == null || _siteConfig.passKey!.isEmpty) {
      throw SiteServiceException(message: '站点配置缺少passKey，无法生成下载链接');
    }
    if (_siteConfig.userId == null || _siteConfig.userId!.isEmpty) {
      throw SiteServiceException(message: '站点配置缺少userId，无法生成下载链接');
    }

    // https://www.ptskit.org/download.php?downhash={userId}.{jwt}
    final jwt = getDownLoadHash(_siteConfig.passKey!, id, _siteConfig.userId!);
    if (url != null && url.isNotEmpty) {
      return url
          .replaceAll('{jwt}', jwt)
          .replaceAll('{userId}', _siteConfig.userId!);
    }
    final baseUrl = _siteConfig.baseUrl.endsWith('/')
        ? _siteConfig.baseUrl.substring(0, _siteConfig.baseUrl.length - 1)
        : _siteConfig.baseUrl;
    return '$baseUrl/download.php?downhash=${_siteConfig.userId!}.$jwt';
  }

  /// 生成下载Hash令牌
  ///
  /// 参数:
  /// - [passkey] 站点passkey
  /// - [id] 种子ID
  /// - [userid] 用户ID
  ///
  /// 返回: JWT编码的下载令牌
  String getDownLoadHash(String passkey, String id, String userid) {
    // 生成MD5密钥: md5(passkey + 当前日期(Ymd) + userid)
    final now = DateTime.now();
    final dateStr =
        '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
    final keyString = passkey + dateStr + userid;
    final keyBytes = utf8.encode(keyString);
    final digest = md5.convert(keyBytes);
    final key = digest.toString();

    // 创建JWT payload
    final payload = {
      'id': id,
      'exp':
          (DateTime.now().millisecondsSinceEpoch / 1000).floor() +
          3600, // 1小时后过期
    };

    // 使用HS256算法生成JWT
    final jwt = JWT(payload);
    final token = jwt.sign(SecretKey(key), algorithm: JWTAlgorithm.HS256);

    return token;
  }

  @override
  Future<Map<String, dynamic>> queryHistory({
    required List<String> tids,
  }) async {
    // TODO: 实现查询下载历史
    //getusertorrentlistajax.php?userid=20148&type=seeding
    //getusertorrentlistajax.php?userid=20148&type=uploaded
    throw UnimplementedError('queryHistory not implemented');
  }

  @override
  Future<void> toggleCollection({
    required String torrentId,
    required bool make,
  }) async {
    try {
      // 从站点模板配置中获取收藏请求配置
      Map<String, dynamic>? actionConfig;
      if (!make) {
        // 取消收藏：优先使用unCollect配置，如果没有则回退到collect配置
        actionConfig = await _getRequestConfig('unCollect');
      }
      // 如果是添加收藏，或者取消收藏但没有专门的unCollect配置，则使用collect配置
      actionConfig ??= await _getRequestConfig('collect');

      if (actionConfig != null) {
        final url =
            actionConfig['path'] as String? ??
            actionConfig['url'] as String? ??
            '/bookmark.php';
        final method = actionConfig['method'] as String? ?? 'GET';
        final params = Map<String, dynamic>.from(
          actionConfig['params'] as Map<String, dynamic>? ?? {},
        );
        final headers = Map<String, String>.from(
          actionConfig['headers'] as Map<String, dynamic>? ?? {},
        );

        // 替换参数中的占位符
        final processedParams = <String, dynamic>{};
        params.forEach((key, value) {
          if (value is String && value.contains('{torrentId}')) {
            processedParams[key] = value.replaceAll('{torrentId}', torrentId);
          } else {
            processedParams[key] = value;
          }
        });

        // 准备请求选项
        final options = Options(
          method: method.toUpperCase(),
          contentType: 'application/x-www-form-urlencoded',
          headers: headers.isNotEmpty ? headers : null,
        );

        // 根据配置的方法发送请求
        Response response;
        if (method.toUpperCase() == 'POST') {
          response = await _dio.post(
            url,
            data: processedParams,
            options: options,
          );
        } else {
          response = await _dio.get(
            url,
            queryParameters: processedParams,
            options: options,
          );
        }
        debugPrint(
          'NexusPHPWebAdapter: toggleCollection response:${response.headers} ${response.data}',
        );
      } else {
        // 如果没有配置，使用默认的收藏请求
        final response = await _dio.get(
          '/bookmark.php',
          queryParameters: {'torrentid': torrentId},
        );
        debugPrint(
          'NexusPHPWebAdapter: toggleCollection (default) response:${response.headers} ${response.data}',
        );
      }
    } catch (e) {
      throw ApiExceptionAdapter.wrapError(e, '切换收藏状态');
    }
  }

  @override
  Future<bool> testConnection() async {
    // TODO: 实现测试连接
    throw UnimplementedError('testConnection not implemented');
  }

  @override
  Future<List<SearchCategoryConfig>> getSearchCategories() async {
    // 通过baseUrl匹配预设配置
    final defaultCategories =
        await SiteConfigService.getDefaultSearchCategories(_siteConfig.baseUrl);

    // 如果获取到默认分类配置，则直接返回
    if (defaultCategories.isNotEmpty) {
      return defaultCategories;
    }

    final List<SearchCategoryConfig> categories = [];
    // 默认塞个综合进来
    categories.add(
      SearchCategoryConfig(id: 'all', displayName: '综合', parameters: '{}'),
    );

    try {
      // 获取分类配置
      final categoriesConfig = await _getFinderConfig('categories');
      final path = categoriesConfig['path'] as String?;

      if (path == null || path.isEmpty) {
        throw Exception('配置错误：缺少 categories.path');
      }

      final response = await _dio.get('/$path');

      if (response.statusCode == 200) {
        final htmlContent = response.data as String;
        final soup = BeautifulSoup(htmlContent);

        // 解析HTML获取分类信息
        final parsedCategories = await _parseCategories(soup, categoriesConfig);
        categories.addAll(parsedCategories);
      }

      return categories;
    } catch (e) {
      // 发生异常时，返回默认分类
      return categories;
    }
  }

  /// 配置驱动的分类解析
  Future<List<SearchCategoryConfig>> _parseCategories(
    BeautifulSoup soup,
    Map<String, dynamic> categoriesConfig,
  ) async {
    final List<SearchCategoryConfig> categories = [];

    // 获取行选择器配置
    final rowsConfig = categoriesConfig['rows'] as Map<String, dynamic>?;
    final fieldsConfig = categoriesConfig['fields'] as Map<String, dynamic>?;

    if (rowsConfig == null || fieldsConfig == null) {
      _logRuleAndSoup('categories.config.missing', categoriesConfig, soup);
      throw Exception('配置格式错误：缺少 rows 或 fields 配置');
    }

    // 根据行选择器找到所有目标元素（支持多个批次）
    final rowSelector = rowsConfig['selector'] as String?;
    if (rowSelector == null || rowSelector.isEmpty) {
      throw Exception('配置错误：缺少行选择器');
    }

    final rowElements = findElementBySelector(soup, rowSelector);
    if (rowElements.isEmpty) {
      _logRuleAndSoup('categories.rows.notFound', rowsConfig, soup);
      throw Exception('未找到目标元素：$rowSelector');
    }

    // 获取字段配置
    final categoryIdConfig =
        fieldsConfig['categoryId'] as Map<String, dynamic>?;
    final categoryNameConfig =
        fieldsConfig['categoryName'] as Map<String, dynamic>?;

    if (categoryIdConfig == null || categoryNameConfig == null) {
      throw Exception('配置错误：缺少 categoryId 或 categoryName 字段配置');
    }

    int batchIndex = 1;

    // 遍历每个 row 元素（每个代表一个批次）
    for (final rowElement in rowElements) {
      // 提取当前 row 中的所有 categoryId
      final categoryIds = await extractFieldValue(
        rowElement,
        categoryIdConfig,
      );

      // 提取当前 row 中的所有 categoryName
      final categoryNames = await extractFieldValue(
        rowElement,
        categoryNameConfig,
      );

      // 检查是否有有效的字段提取结果
      if (categoryIds.isEmpty && categoryNames.isEmpty) {
        // 未提取到有效fields的不计数
        continue;
      }

      // 确保 categoryId 和 categoryName 数量一致
      final minLength = categoryIds.length < categoryNames.length
          ? categoryIds.length
          : categoryNames.length;

      if (minLength == 0) {
        continue; // 跳过没有有效数据的批次
      }

      // 一一对应创建分类配置
      for (int i = 0; i < minLength; i++) {
        final categoryId = categoryIds[i];
        final categoryName = categoryNames[i];

        if (categoryId.isNotEmpty && categoryName.isNotEmpty) {
          // 确定前缀
          String prefix;
          if (batchIndex == 1) {
            prefix = 'normal#';
          } else if (batchIndex == 2) {
            prefix = 'special#';
          } else {
            prefix = 'batch$batchIndex#';
          }

          categories.add(
            SearchCategoryConfig(
              id: categoryId,
              displayName: batchIndex > 1 ? 's_$categoryName' : categoryName,
              parameters: '{"category":"$prefix$categoryId"}',
            ),
          );
        }
      }

      batchIndex++;
    }

    return categories;
  }
}