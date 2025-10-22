import 'package:flutter/foundation.dart';

import '../../models/app_models.dart';
import 'site_adapter.dart';
import '../site_config_service.dart';
import 'package:dio/dio.dart';
import 'package:beautiful_soup_dart/beautiful_soup.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:crypto/crypto.dart';
import 'package:intl/intl.dart';
import 'dart:convert';

/// Cookie过期异常
class CookieExpiredException implements Exception {
  final String message;
  CookieExpiredException(this.message);

  @override
  String toString() => 'CookieExpiredException: $message';
}

/// NexusPHP Web站点适配器
/// 用于处理基于Web接口的NexusPHP站点
class NexusPHPWebAdapter extends SiteAdapter {
  late SiteConfig _siteConfig;
  late Dio _dio;
  Map<String, String>? _discountMapping;

  @override
  SiteConfig get siteConfig => _siteConfig;

  /// 将相对时间格式转换为绝对时间格式
  /// 例如："7时28分钟" -> "2025-08-27 21:16:48"
  String? _convertRelativeTimeToAbsolute(String? relativeTime) {
    if (relativeTime == null || relativeTime.isEmpty) {
      return null;
    }

    final now = DateTime.now();
    int totalMinutes = 0;

    // 解析月数
    final monthMatch = RegExp(r'(\d+)月').firstMatch(relativeTime);
    if (monthMatch != null) {
      final months = int.tryParse(monthMatch.group(1) ?? '0') ?? 0;
      totalMinutes += months * 30 * 24 * 60;
    }

    // 解析天数
    final dayMatch = RegExp(r'(\d+)天').firstMatch(relativeTime);
    if (dayMatch != null) {
      final days = int.tryParse(dayMatch.group(1) ?? '0') ?? 0;
      totalMinutes += days * 24 * 60;
    }

    // 解析小时数
    final hourMatch = RegExp(r'(\d+)时').firstMatch(relativeTime);
    if (hourMatch != null) {
      final hours = int.tryParse(hourMatch.group(1) ?? '0') ?? 0;
      totalMinutes += hours * 60;
    }

    // 解析分钟数
    final minuteMatch = RegExp(r'(\d+)分').firstMatch(relativeTime);
    if (minuteMatch != null) {
      final minutes = int.tryParse(minuteMatch.group(1) ?? '0') ?? 0;
      totalMinutes += minutes;
    }

    // 计算绝对时间
    final absoluteTime = now.add(Duration(minutes: totalMinutes));

    // 使用DateFormat格式化为 "yyyy-MM-dd HH:mm:ss" 格式
    final formatter = DateFormat('yyyy-MM-dd HH:mm:ss');
    return formatter.format(absoluteTime);
  }

  @override
  Future<void> init(SiteConfig config) async {
    _siteConfig = config;

    // 加载优惠类型映射配置
    await _loadDiscountMapping();

    _dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 5),
        receiveTimeout: const Duration(seconds: 10),
        sendTimeout: const Duration(seconds: 30),
      ),
    );
    _dio.options.baseUrl = _siteConfig.baseUrl;
    _dio.options.headers['User-Agent'] =
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36';
    _dio.options.responseType = ResponseType.plain; // 设置为plain避免JSON解析警告

    // 设置Cookie
    if (_siteConfig.cookie != null && _siteConfig.cookie!.isNotEmpty) {
      _dio.options.headers['Cookie'] = _siteConfig.cookie;
    }

    // 添加响应拦截器处理302重定向
    _dio.interceptors.add(
      InterceptorsWrapper(
        onResponse: (response, handler) {
          // 检查是否是302重定向到登录页面
          if (response.statusCode == 302) {
            final location = response.headers.value('location');
            if (location != null && location.contains('login')) {
              throw CookieExpiredException('Cookie已过期，请重新登录更新Cookie');
            }
          }
          handler.next(response);
        },
        onError: (error, handler) {
          // 检查DioException中的响应状态码
          if (error.response?.statusCode == 302) {
            final location = error.response?.headers.value('location');
            if (location != null && location.contains('login')) {
              throw CookieExpiredException('Cookie已过期，请重新登录更新Cookie');
            }
          }
          handler.next(error);
        },
      ),
    );
  }

  /// 加载优惠类型映射配置
  Future<void> _loadDiscountMapping() async {
    try {
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

  /// 从字符串解析优惠类型
  DiscountType _parseDiscountType(String? str) {
    if (str == null || str.isEmpty) return DiscountType.normal;

    final mapping = _discountMapping ?? {};
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

      // 将字符串格式的数据转换为数字
      double shareRate = double.tryParse(userInfo['ratio'] ?? '0') ?? 0.0;
      double bonusPoints =
          double.tryParse((userInfo['bonus'] ?? '0').replaceAll(',', '')) ??
          0.0;

      // 对于bytes，由于web版本直接提供格式化字符串，这里设置为0
      // 实际使用时应该使用uploadedBytesString和downloadedBytesString
      int uploadedBytes = 0;
      int downloadedBytes = 0;

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
      );
    } catch (e) {
      throw Exception('获取用户资料失败: $e');
    }
  }

  /// 获取指定类型的配置
  /// [configType] 配置类型，如 'userInfo', 'passKey', 'search', 'categories' 等
  Future<Map<String, dynamic>> _getFinderConfig(String configType) async {
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
          print('获取模板配置失败: $e');
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

    // 如果都没有找到，返回空配置（会导致异常）
    throw Exception('未找到 $configType 提取配置');
  }

  /// 获取用户信息配置（保持向后兼容）
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

    final targetElement = _findFirstElementBySelector(soup, rowSelector);
    if (targetElement == null) {
      throw Exception('未找到目标元素：$rowSelector');
    }

    // 遍历字段配置，提取每个字段的值
    for (final fieldEntry in fieldsConfig.entries) {
      final fieldName = fieldEntry.key;
      final fieldConfig = fieldEntry.value as Map<String, dynamic>;

      try {
        final value = await _extractFirstFieldValue(targetElement, fieldConfig);
        result[fieldName] = value;
      } catch (e) {
        // 如果某个字段提取失败，记录但继续处理其他字段
        result[fieldName] = null;
      }
    }

    return result;
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
        throw Exception('配置格式错误：缺少 rows 配置');
      }

      // 根据行选择器找到目标元素
      final rowSelector = rowsConfig['selector'] as String?;
      if (rowSelector == null || rowSelector.isEmpty) {
        throw Exception('配置错误：缺少行选择器');
      }

      final targetElement = _findFirstElementBySelector(soup, rowSelector);
      if (targetElement == null) {
        throw Exception('未找到目标元素：$rowSelector');
      }

      // 根据配置提取PassKey
      final fields = passKeyConfig['fields'] as Map<String, dynamic>?;
      final passKeyField = fields?['passKey'] as Map<String, dynamic>?;

      if (passKeyField != null) {
        final value = await _extractFirstFieldValue(
          targetElement,
          passKeyField,
        );
        if (value != null && value.isNotEmpty) {
          return value.trim();
        }
      }

      throw Exception('无法从配置中提取PassKey');
    } catch (e) {
      throw Exception('提取PassKey失败: $e');
    }
  }

  /// 根据选择器查找所有匹配的元素
  List<dynamic> _findElementBySelector(dynamic soup, String selector) {
    if (soup == null) return [];

    selector = selector.trim();
    if (selector.isEmpty) return [soup];

    // 首先处理子选择器（>），因为它可能包含其他类型的选择器
    if (selector.contains('>')) {
      final parts = selector.split('>').map((s) => s.trim()).toList();
      List<dynamic> current = [soup];

      for (final part in parts) {
        if (current.isEmpty) break;
        List<dynamic> next = [];
        for (final element in current) {
          if (part == 'next') {
            // 处理 next 关键字，获取下一个兄弟元素
            final nextSibling = element.nextSibling;
            if (nextSibling != null) {
              next.add(nextSibling);
            }
          } else {
            next.addAll(_findElementBySelector(element, part));
          }
        }
        current = next;
      }
      return current;
    }

    // 处理属性选择器
    // 1. 属性存在性选择器 tag[attr]
    final attributeExistsMatch = RegExp(
      r'^([a-zA-Z0-9_-]*)\[([a-zA-Z0-9_-]+)\]$',
    ).firstMatch(selector);
    if (attributeExistsMatch != null) {
      final tag = attributeExistsMatch.group(1)?.trim();
      final attribute = attributeExistsMatch.group(2)?.trim();

      if (attribute != null) {
        // 获取所有指定标签的元素（如果没有指定标签，则获取所有元素）
        if (tag != null && tag.isNotEmpty) {
          return soup.findAll(tag, attrs: {attribute: true});
        } else {
          return soup.findAll('*', attrs: {attribute: true});
        }
      }
    }

    // 2. 属性值选择器 tag[attr^="value"], tag[attr="value"], tag[attr~="pattern"]
    final attributeValueMatch = RegExp(
      r'^([a-zA-Z0-9_-]*)\[([a-zA-Z0-9_-]+)([\^=~])="([^"]+)"\]$',
    ).firstMatch(selector);
    if (attributeValueMatch != null) {
      final tag = attributeValueMatch.group(1)?.trim();
      final attribute = attributeValueMatch.group(2)?.trim();
      final operator = attributeValueMatch.group(3)?.trim();
      final value = attributeValueMatch.group(4)?.trim();

      if (attribute != null && operator != null && value != null) {
        // 获取所有指定标签的元素（如果没有指定标签，则获取所有元素）
        final elements = tag != null && tag.isNotEmpty
            ? soup.findAll(tag)
            : soup.findAll('*');

        final filteredElements = <dynamic>[];
        for (final element in elements) {
          final attrValue = element.attributes[attribute];
          if (attrValue != null) {
            final normalizedAttrValue = _normalizeHrefForComparison(attrValue);

            bool matches = false;
            switch (operator) {
              case '^': // 前缀匹配
                matches = normalizedAttrValue.startsWith(value);
                break;
              case '=': // 完全匹配
                matches = normalizedAttrValue == value;
                break;
              case '~': // 正则匹配
                try {
                  final regex = RegExp(value);
                  matches = regex.hasMatch(normalizedAttrValue);
                } catch (e) {
                  // 正则表达式无效，跳过
                  matches = false;
                }
                break;
            }

            if (matches) {
              filteredElements.add(element);
            }
          }
        }
        return filteredElements;
      }
    }

    // 处理单个选择器
    if (selector.contains(':nth-child')) {
      // nth-child选择器
      if (selector.contains(':nth-child(')) {
        // 带括号数字的 nth-child 选择器
        final nthChildMatch = RegExp(
          r'^([^:]*):nth-child\((\d+)\)',
        ).firstMatch(selector);
        if (nthChildMatch != null) {
          final tag = nthChildMatch.group(1)?.trim();
          final index = int.tryParse(nthChildMatch.group(2) ?? '1') ?? 1;

          // 获取直接子元素
          final children = soup.children;
          if (children.isNotEmpty && index > 0 && index <= children.length) {
            final nthChild = children[index - 1]; // nth-child是1-based索引

            // 如果指定了标签，验证第n个子元素是否匹配该标签
            if (tag != null && tag.isNotEmpty) {
              if (nthChild.name.toLowerCase() == tag.toLowerCase()) {
                return [nthChild];
              }
              // 如果第n个子元素不匹配指定标签，返回空列表
              return [];
            } else {
              // 如果没有指定标签，直接返回第n个子元素
              return [nthChild];
            }
          }
        }
      } else {
        // 不带括号的 nth-child 选择器，只取直接子元素中的指定标签
        final nthChildMatch = RegExp(
          r'^([^:]+):nth-child$',
        ).firstMatch(selector);
        if (nthChildMatch != null) {
          final tag = nthChildMatch.group(1)?.trim();
          if (tag != null && tag.isNotEmpty) {
            // 只在直接子元素中查找指定标签
            final children = soup.children;
            final matchingChildren = children
                .where((child) => child.name.toLowerCase() == tag.toLowerCase())
                .toList();
            return matchingChildren;
          }
        }
      }
    } else if (selector.contains('#')) {
      // ID选择器
      final parts = selector.split('#');
      if (parts.length == 2) {
        final tag = parts[0].isEmpty ? null : parts[0];
        final id = parts[1].split(' ').first; // 处理复合选择器
        if (tag != null) {
          return soup.findAll(tag, id: id);
        } else {
          return soup.findAll('*', id: id);
        }
      }
    } else if (selector.contains('.')) {
      // 类选择器
      final parts = selector.split('.');
      if (parts.length == 2) {
        final tag = parts[0].isEmpty ? null : parts[0];
        final className = parts[1].split(' ').first; // 处理复合选择器
        if (tag != null) {
          return soup.findAll(tag, attrs: {'class': className});
        } else {
          return soup.findAll('*', attrs: {'class': className});
        }
      }
    } else {
      // 简单标签选择器
      return soup.findAll(selector);
    }

    return [];
  }

  /// 根据选择器查找第一个匹配的元素（向后兼容）
  dynamic _findFirstElementBySelector(dynamic soup, String selector) {
    final elements = _findElementBySelector(soup, selector);
    return elements.isNotEmpty ? elements.first : null;
  }

  /// 根据字段配置提取字段值列表
  Future<List<String>> _extractFieldValue(
    dynamic element,
    Map<String, dynamic> fieldConfig,
  ) async {
    final selector = fieldConfig['selector'] as String?;
    final attribute = fieldConfig['attribute'] as String?;
    final filter = fieldConfig['filter'] as Map<String, dynamic>?;

    List<dynamic> targetElements = [element];

    // 如果有选择器，进一步定位元素
    if (selector != null && selector.isNotEmpty) {
      targetElements = _findElementBySelector(element, selector);
    }

    if (targetElements.isEmpty) {
      return [];
    }

    // 遍历所有目标元素，提取属性值
    List<String> values = [];
    for (final targetElement in targetElements) {
      if (targetElement == null) continue;

      // 根据属性类型获取值
      String? value;
      if (attribute == 'text') {
        value = targetElement.text?.trim();
      } else if (attribute == 'href') {
        value = targetElement.attributes['href'];
      } else {
        value = targetElement.attributes[attribute ?? 'text'];
      }

      // 如果有过滤器，应用过滤器
      if (filter != null && value != null) {
        value = _applyFilter(value, filter);
      }

      // 只添加非空值
      if (value != null && value.isNotEmpty) {
        values.add(value.replaceAll('\n', ' ').replaceAll(RegExp(r'\s+'), ' '));
      }
    }

    return values;
  }

  /// 根据字段配置提取第一个字段值（向后兼容）
  Future<String?> _extractFirstFieldValue(
    dynamic element,
    Map<String, dynamic> fieldConfig,
  ) async {
    final values = await _extractFieldValue(element, fieldConfig);
    return values.isNotEmpty ? values.first : null;
  }

  /// 标准化href属性用于比较
  /// 将绝对URL转换为相对路径格式，便于与配置中的路径进行比较
  String _normalizeHrefForComparison(String href) {
    if (href.startsWith('http://') || href.startsWith('https://')) {
      final uri = Uri.tryParse(href);
      if (uri != null) {
        return uri.path.substring(1) +
            (uri.query.isNotEmpty ? '?${uri.query}' : '');
      }
    }
    return href;
  }

  /// 应用过滤器
  String? _applyFilter(String value, Map<String, dynamic> filter) {
    final filterName = filter['name'] as String?;

    if (filterName == 'regexp') {
      final args = filter['args'] as String?;
      final index = filter['index'] as int? ?? 0;

      if (args != null) {
        final regex = RegExp(args);
        final match = regex.firstMatch(value);
        if (match != null && match.groupCount >= index) {
          return match.group(index); // group(0) 是整个匹配，group(1) 是第一个捕获组
        }
      }
    }

    return null;
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
      // 构建查询参数
      final queryParams = <String, dynamic>{
        'page': pageNumber - 1, // 页面从0开始
        'pageSize': pageSize,
        'incldead': 1, // 添加默认参数
      };

      // 添加关键词搜索
      if (keyword != null && keyword.isNotEmpty) {
        queryParams['search'] = keyword;
      }

      // 添加收藏筛选
      if (onlyFav != null && onlyFav == 1) {
        queryParams['inclbookmarked'] = 1;
      }

      // 确定请求路径
      String requestPath = '/torrents.php';

      // 处理分类参数
      if (additionalParams != null) {
        additionalParams.forEach((key, value) {
          if (key == 'category') {
            final categoryParam = value as String?;
            if (categoryParam != null) {
              // 解析category参数，格式为 {"category":"prefix#catid"}
              try {
                // 检查是否是special前缀
                if (categoryParam.startsWith('special')) {
                  requestPath = '/special.php';
                }
                final parts = categoryParam.split('#');
                if (parts.length == 2 && parts[1].isNotEmpty) {
                  queryParams['cat'] = parts[1];
                }
              } catch (e) {
                // 解析失败时忽略分类参数
              }
            }
          } else {
            queryParams[key] = value;
          }
        });
      }

      // 发送请求
      final response = await _dio.get(
        requestPath,
        queryParameters: queryParams,
      );
      final soup = BeautifulSoup(response.data);
      // 解析种子列表
      final torrents = await parseTorrentList(soup);

      // 解析总页数（从JavaScript变量maxpage中提取）
      int totalPages = parseTotalPages(soup);

      return TorrentSearchResult(
        pageNumber: pageNumber,
        pageSize: pageSize,
        total: torrents.length * totalPages, // 估算值
        totalPages: totalPages,
        items: torrents,
      );
    } catch (e) {
      throw Exception('搜索种子失败: $e');
    }
  }

  int parseTotalPages(BeautifulSoup soup) {
    int totalPages = 1;
    final footerDiv = soup.find('div', id: 'footer');
    if (footerDiv != null) {
      final scriptElement = footerDiv.find('script');
      if (scriptElement != null) {
        final scriptText = scriptElement.text;
        final pageMatch = RegExp(
          r'var\s+maxpage\s*=\s*(\d+);',
        ).firstMatch(scriptText);
        if (pageMatch != null) {
          totalPages = int.tryParse(pageMatch.group(1) ?? '1') ?? 1;
        }
      }
    }
    return totalPages;
  }

  Future<List<TorrentItem>> parseTorrentList(BeautifulSoup soup) async {
    final torrents = <TorrentItem>[];

    try {
      // 获取搜索配置
      final searchConfig = await _getFinderConfig('search');

      final rowsConfig = searchConfig['rows'] as Map<String, dynamic>?;
      final fieldsConfig = searchConfig['fields'] as Map<String, dynamic>?;

      if (rowsConfig == null || fieldsConfig == null) {
        debugPrint('行配置或字段配置不存在');
        return torrents;
      }

      final rowSelector = rowsConfig['selector'] as String?;
      if (rowSelector == null) {
        debugPrint('行选择器不存在');
        return torrents;
      }

      // 使用配置的选择器查找行
      final rows = _findElementBySelector(soup, rowSelector);

      for (final rowElement in rows) {
        final row = rowElement as Bs4Element;
        try {
          // 提取种子ID - 如果提取失败则跳过当前行
          final torrentIdConfig =
              fieldsConfig['torrentId'] as Map<String, dynamic>?;
          if (torrentIdConfig == null) {
            continue;
          }

          final torrentIdList = await _extractFieldValue(row, torrentIdConfig);
          final torrentId = torrentIdList.isNotEmpty ? torrentIdList.first : '';
          if (torrentId.isEmpty) {
            continue; // 种子ID提取失败，跳过当前行
          }

          // 提取其他字段
          final torrentNameList = await _extractFieldValue(
            row,
            fieldsConfig['torrentName'] as Map<String, dynamic>? ?? {},
          );
          final torrentName = torrentNameList.isNotEmpty
              ? torrentNameList.first
              : '';

          final descriptionList = await _extractFieldValue(
            row,
            fieldsConfig['description'] as Map<String, dynamic>? ?? {},
          );
          final description = descriptionList.isNotEmpty
              ? descriptionList.first
              : '';

          final discountList = await _extractFieldValue(
            row,
            fieldsConfig['discount'] as Map<String, dynamic>? ?? {},
          );
          final discount = discountList.isNotEmpty ? discountList.first : '';

          final discountEndTimeList = await _extractFieldValue(
            row,
            fieldsConfig['discountEndTime'] as Map<String, dynamic>? ?? {},
          );
          final discountEndTime = discountEndTimeList.isNotEmpty
              ? discountEndTimeList.first
              : '';

          final seedersTextList = await _extractFieldValue(
            row,
            fieldsConfig['seedersText'] as Map<String, dynamic>? ?? {},
          );
          final seedersText = seedersTextList.isNotEmpty
              ? seedersTextList.first
              : '';

          final leechersTextList = await _extractFieldValue(
            row,
            fieldsConfig['leechersText'] as Map<String, dynamic>? ?? {},
          );
          final leechersText = leechersTextList.isNotEmpty
              ? leechersTextList.first
              : '';

          final sizeTextList = await _extractFieldValue(
            row,
            fieldsConfig['sizeText'] as Map<String, dynamic>? ?? {},
          );
          final sizeText = sizeTextList.isNotEmpty ? sizeTextList.first : '';

          final downloadStatusTextList = await _extractFieldValue(
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
              _siteConfig.passKey!,
            );
            var baseUrl = _siteConfig.baseUrl;
            if (_siteConfig.baseUrl.endsWith("/")) {
              baseUrl = _siteConfig.baseUrl.substring(
                0,
                _siteConfig.baseUrl.length - 1,
              );
            }
            downloadUrl = downloadUrl.replaceAll('{baseUrl}', baseUrl);
          }

          final downloadStatusText = downloadStatusTextList.isNotEmpty
              ? downloadStatusTextList.first
              : '';

          final coverList = await _extractFieldValue(
            row,
            fieldsConfig['cover'] as Map<String, dynamic>? ?? {},
          );
          final cover = coverList.isNotEmpty ? coverList.first : '';

          final createDateList = await _extractFieldValue(
            row,
            fieldsConfig['createData'] as Map<String, dynamic>? ?? {},
          );
          final createDate = createDateList.isNotEmpty
              ? createDateList.first
              : '';

          final doubanRatingList = await _extractFieldValue(
            row,
            fieldsConfig['doubanRating'] as Map<String, dynamic>? ?? {},
          );
          final doubanRating = doubanRatingList.isNotEmpty
              ? doubanRatingList.first
              : '';

          final imdbRatingList = await _extractFieldValue(
            row,
            fieldsConfig['imdbRating'] as Map<String, dynamic>? ?? {},
          );
          final imdbRating = imdbRatingList.isNotEmpty
              ? imdbRatingList.first
              : '';

          // 检查收藏状态（布尔字段）
          final collectionConfig =
              fieldsConfig['collection'] as Map<String, dynamic>?;
          bool collection = false;
          if (collectionConfig != null) {
            final collectionList = await _extractFieldValue(
              row,
              collectionConfig,
            );
            collection = collectionList.isNotEmpty; // 如果找不到元素说明未收藏
          }

          // 解析下载状态
          DownloadStatus downloadStatus = DownloadStatus.none;
          if (downloadStatusText.isNotEmpty) {
            final percentInt = int.tryParse(downloadStatusText);
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
                  sizeInBytes = (sizeValue * 1024).round();
                  break;
                case 'MB':
                  sizeInBytes = (sizeValue * 1024 * 1024).round();
                  break;
                case 'GB':
                  sizeInBytes = (sizeValue * 1024 * 1024 * 1024).round();
                  break;
                case 'TB':
                  sizeInBytes = (sizeValue * 1024 * 1024 * 1024 * 1024).round();
                  break;
                default:
                  sizeInBytes = sizeValue.round();
              }
            }
          }

          // 清理文本字段
          final cleanedDescription = description
              .replaceAll(torrentName, '')
              .replaceAll(RegExp(r'剩余时间：\d+.*?\d+[分钟|时]'), '')
              .trim();

          torrents.add(
            TorrentItem(
              id: torrentId,
              name: torrentName,
              smallDescr: cleanedDescription,
              discount: _parseDiscountType(
                discount.isNotEmpty ? discount : null,
              ),
              discountEndTime: discountEndTime.isNotEmpty
                  ? discountEndTime
                  : null,
              downloadUrl: downloadUrl.isNotEmpty ? downloadUrl : null,
              seeders: int.tryParse(seedersText) ?? 0,
              leechers: int.tryParse(leechersText) ?? 0,
              sizeBytes: sizeInBytes,
              downloadStatus: downloadStatus,
              collection: collection,
              imageList: [], // 暂时不解析图片列表
              cover: cover,
              createdDate: createDate,
              doubanRating: doubanRating.isNotEmpty ? doubanRating : 'N/A',
              imdbRating: imdbRating.isNotEmpty ? imdbRating : 'N/A',
            ),
          );
        } catch (e) {
          debugPrint('解析种子行失败: $e');
          continue;
        }
      }
    } catch (e) {
      debugPrint('获取搜索配置失败: $e');
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
  Future<String> genDlToken({required String id}) async {
    // 检查必要的配置参数
    if (_siteConfig.passKey == null || _siteConfig.passKey!.isEmpty) {
      throw Exception('站点配置缺少passKey，无法生成下载链接');
    }
    if (_siteConfig.userId == null || _siteConfig.userId!.isEmpty) {
      throw Exception('站点配置缺少userId，无法生成下载链接');
    }

    // https://www.ptskit.org/download.php?downhash={userId}.{jwt}
    final jwt = getDownLoadHash(_siteConfig.passKey!, id, _siteConfig.userId!);
    return '${_siteConfig.baseUrl}download.php?downhash=${_siteConfig.userId!}.$jwt';
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
      final template = await SiteConfigService.getTemplateById(
        _siteConfig.templateId,
        _siteConfig.siteType,
      );

      final collectConfig =
          template?.request?['collect'] as Map<String, dynamic>?;

      if (collectConfig != null) {
        final url =
            collectConfig['path'] as String? ??
            collectConfig['url'] as String? ??
            '/bookmark.php';
        final method = collectConfig['method'] as String? ?? 'GET';
        final params = Map<String, dynamic>.from(
          collectConfig['params'] as Map<String, dynamic>? ?? {},
        );
        final headers = Map<String, String>.from(
          collectConfig['headers'] as Map<String, dynamic>? ?? {},
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
          headers: headers.isNotEmpty ? headers : null,
        );

        // 根据配置的方法发送请求
        if (method.toUpperCase() == 'POST') {
          await _dio.post(url, data: processedParams, options: options);
        } else {
          await _dio.get(
            url,
            queryParameters: processedParams,
            options: options,
          );
        }
      } else {
        // 如果没有配置，使用默认的收藏请求
        await _dio.get(
          '/bookmark.php',
          queryParameters: {'torrentid': torrentId},
        );
      }
    } catch (e) {
      throw Exception('切换收藏状态失败: $e');
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
      throw Exception('配置格式错误：缺少 rows 或 fields 配置');
    }

    // 根据行选择器找到所有目标元素（支持多个批次）
    final rowSelector = rowsConfig['selector'] as String?;
    if (rowSelector == null || rowSelector.isEmpty) {
      throw Exception('配置错误：缺少行选择器');
    }

    final rowElements = _findElementBySelector(soup, rowSelector);
    if (rowElements.isEmpty) {
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
      final categoryIds = await _extractFieldValue(
        rowElement,
        categoryIdConfig,
      );

      // 提取当前 row 中的所有 categoryName
      final categoryNames = await _extractFieldValue(
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
