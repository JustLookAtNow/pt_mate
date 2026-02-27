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

// -----------------------------------------------------------------------------
// Helper Classes and Functions for Isolate Logic
// -----------------------------------------------------------------------------

/// Isolate 搜索解析参数对象
class ParseSearchParams {
  final String html;
  final Map<String, dynamic> searchConfig;
  final Map<String, dynamic>? totalPagesConfig;
  final Map<String, String> tagMapping;
  final Map<String, String> discountMapping;
  final String baseUrl;
  final String passKey;
  final int pageNumber;
  final int pageSize;

  ParseSearchParams({
    required this.html,
    required this.searchConfig,
    this.totalPagesConfig,
    required this.tagMapping,
    required this.discountMapping,
    required this.baseUrl,
    required this.passKey,
    required this.pageNumber,
    required this.pageSize,
  });
}

/// 适配器解析器助手类，混入 BaseWebAdapterMixin 以在 Isolate 中使用
class _AdapterParser with BaseWebAdapterMixin {
  /// 单例模式，避免重复实例化
  static final _AdapterParser instance = _AdapterParser();
}

/// 解析标签类型的静态帮助方法
TagType? _parseTagTypeStatic(String? str, Map<String, String> tagMapping) {
  if (str == null || str.isEmpty) return null;

  final enumName = tagMapping[str];

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

/// 解析优惠类型的静态帮助方法
DiscountType _parseDiscountTypeStatic(
    String? str, Map<String, String> discountMapping) {
  if (str == null || str.isEmpty) return DiscountType.normal;

  final enumValue = discountMapping[str];

  if (enumValue != null) {
    for (final type in DiscountType.values) {
      if (type.value == enumValue) {
        return type;
      }
    }
  }

  return DiscountType.normal;
}

/// 在 Isolate 中运行的搜索结果解析函数
Future<TorrentSearchResult> parseSearchResultInIsolate(
    ParseSearchParams params) async {
  final soup = BeautifulSoup(params.html);
  final parser = _AdapterParser.instance;

  // 1. 解析种子列表
  final torrents = <TorrentItem>[];

  try {
    final searchConfig = params.searchConfig;
    final rowsConfig = searchConfig['rows'] as Map<String, dynamic>?;
    final fieldsConfig = searchConfig['fields'] as Map<String, dynamic>?;

    if (rowsConfig != null &&
        fieldsConfig != null &&
        rowsConfig['selector'] != null) {
      final rowSelector = rowsConfig['selector'] as String;
      // 使用配置的选择器查找行
      final rows = parser.findElementBySelector(soup, rowSelector);

      for (final rowElement in rows) {
        final row = rowElement as Bs4Element;
        try {
          // 提取种子ID - 如果提取失败则跳过当前行
          final torrentIdConfig =
              fieldsConfig['torrentId'] as Map<String, dynamic>?;
          if (torrentIdConfig == null) {
            continue;
          }

          final torrentIdList = await parser.extractFieldValue(
              row, torrentIdConfig);
          final torrentId = torrentIdList.isNotEmpty ? torrentIdList.first : '';
          if (torrentId.isEmpty) {
            continue; // 种子ID提取失败，跳过当前行
          }

          // 提取其他字段
          final torrentNameList = await parser.extractFieldValue(
            row,
            fieldsConfig['torrentName'] as Map<String, dynamic>? ?? {},
          );
          final torrentName = torrentNameList.isNotEmpty
              ? torrentNameList.first
              : '';

          final tagList = await parser.extractFieldValue(
            row,
            fieldsConfig['tag'] as Map<String, dynamic>? ?? {},
          );

          final descriptionList = await parser.extractFieldValue(
            row,
            fieldsConfig['description'] as Map<String, dynamic>? ?? {},
          );
          final description = descriptionList.isNotEmpty
              ? descriptionList.first
              : '';

          final discountList = await parser.extractFieldValue(
            row,
            fieldsConfig['discount'] as Map<String, dynamic>? ?? {},
          );
          final discount = discountList.isNotEmpty ? discountList.first : '';

          final discountEndTimeConfig =
              fieldsConfig['discountEndTime'] as Map<String, dynamic>? ?? {};
          final discountEndTimeList = await parser.extractFieldValue(
            row,
            discountEndTimeConfig,
          );
          final discountEndTime = discountEndTimeList.isNotEmpty
              ? discountEndTimeList.first
              : '';
          final discountEndTimeTimeConfig =
              discountEndTimeConfig['time'] as Map<String, dynamic>?;

          final seedersTextList = await parser.extractFieldValue(
            row,
            fieldsConfig['seedersText'] as Map<String, dynamic>? ?? {},
          );
          final seedersText = seedersTextList.isNotEmpty
              ? seedersTextList.first
              : '';

          final leechersTextList = await parser.extractFieldValue(
            row,
            fieldsConfig['leechersText'] as Map<String, dynamic>? ?? {},
          );
          final leechersText = leechersTextList.isNotEmpty
              ? leechersTextList.first
              : '';

          final sizeTextList = await parser.extractFieldValue(
            row,
            fieldsConfig['sizeText'] as Map<String, dynamic>? ?? {},
          );
          final sizeText = sizeTextList.isNotEmpty ? sizeTextList.first : '';

          final downloadStatusTextList = await parser.extractFieldValue(
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
              params.passKey,
            );
            var baseUrl = params.baseUrl;
            if (params.baseUrl.endsWith("/")) {
              baseUrl = params.baseUrl.substring(
                0,
                params.baseUrl.length - 1,
              );
            }
            downloadUrl = downloadUrl.replaceAll('{baseUrl}', baseUrl);
          }

          final downloadStatusText = downloadStatusTextList.isNotEmpty
              ? downloadStatusTextList.first
              : '';

          final coverList = await parser.extractFieldValue(
            row,
            fieldsConfig['cover'] as Map<String, dynamic>? ?? {},
          );
          final cover = coverList.isNotEmpty ? coverList.first : '';

          final createDateConfig =
              fieldsConfig['createDate'] as Map<String, dynamic>? ?? {};
          final createDateList = await parser.extractFieldValue(
            row,
            createDateConfig,
          );
          final createDate = createDateList.isNotEmpty
              ? createDateList.first
              : '';
          final createDateTimeConfig =
              createDateConfig['time'] as Map<String, dynamic>?;

          final doubanRatingList = await parser.extractFieldValue(
            row,
            fieldsConfig['doubanRating'] as Map<String, dynamic>? ?? {},
          );
          final doubanRating = doubanRatingList.isNotEmpty
              ? doubanRatingList.first
              : '';

          final imdbRatingList = await parser.extractFieldValue(
            row,
            fieldsConfig['imdbRating'] as Map<String, dynamic>? ?? {},
          );
          final imdbRating = imdbRatingList.isNotEmpty
              ? imdbRatingList.first
              : '';

          // 提取评论数
          final commentsList = await parser.extractFieldValue(
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
            final collectionList = await parser.extractFieldValue(
              row,
              collectionConfig,
            );
            collection = collectionList.isNotEmpty; // 如果找不到元素说明未收藏
          }
          // 检查置顶状态（布尔字段）
          final isTopConfig = fieldsConfig['isTop'] as Map<String, dynamic>?;
          bool isTop = false;
          if (isTopConfig != null) {
            final isTopList = await parser.extractFieldValue(row, isTopConfig);
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
              final mappedTag = _parseTagTypeStatic(tagStr, params.tagMapping);
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
              discount: _parseDiscountTypeStatic(
                discount.isNotEmpty ? discount : null,
                params.discountMapping,
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
          // Isolate中不能使用Logger，使用debugPrint
          debugPrint('NexusPHPWebAdapter Isolate: Row parse failed - $e');
          continue;
        }
      }
    }
  } catch (e) {
    debugPrint('NexusPHPWebAdapter Isolate: Search parse failed - $e');
  }

  // 2. 解析总页数
  int totalPages = 1;
  try {
    final config = params.totalPagesConfig;
    if (config != null && config.isNotEmpty) {
      final rowsConfig = config['rows'] as Map<String, dynamic>?;
      final fieldsConfig = config['fields'] as Map<String, dynamic>?;

      if (rowsConfig != null && fieldsConfig != null) {
        final rowSelector = rowsConfig['selector'] as String?;
        if (rowSelector != null && rowSelector.isNotEmpty) {
          final rows = parser.findElementBySelector(soup, rowSelector);
          if (rows.isNotEmpty) {
            final fieldConfig =
                fieldsConfig['totalPages'] as Map<String, dynamic>?;
            if (fieldConfig != null) {
              List<int> pageValues = [];
              for (final row in rows) {
                final values = await parser.extractFieldValue(row, fieldConfig);
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
            }
          }
        }
      }
    }
  } catch (e) {
    debugPrint('NexusPHPWebAdapter Isolate: Total pages parse failed - $e');
  }

  return TorrentSearchResult(
    pageNumber: params.pageNumber,
    pageSize: params.pageSize,
    total: torrents.length * totalPages, // 估算值
    totalPages: totalPages,
    items: torrents,
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
    return _parseTagTypeStatic(str, _tagMapping ?? {});
  }

  /// 从字符串解析优惠类型
  DiscountType _parseDiscountType(String? str) {
    return _parseDiscountTypeStatic(str, _discountMapping ?? {});
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

      // 使用 Isolate 处理解析
      final searchConfig = await _getFinderConfig('search');
      final totalPagesConfig = await _getFinderConfig('totalPages');

      final params = ParseSearchParams(
        html: response.data as String,
        searchConfig: searchConfig,
        totalPagesConfig: totalPagesConfig,
        tagMapping: _tagMapping ?? {},
        discountMapping: _discountMapping ?? {},
        baseUrl: _siteConfig.baseUrl,
        passKey: _siteConfig.passKey ?? '',
        pageNumber: pageNumber,
        pageSize: pageSize,
      );

      return await compute(parseSearchResultInIsolate, params);

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
    // 保持实例方法用于兼容性或测试
    int totalPages = 1;
    try {
      // 获取配置
      final config = await _getFinderConfig('totalPages');
      if (config.isEmpty) {
        return 1;
      }

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
      final rows = findElementBySelector(soup, rowSelector);
      if (rows.isEmpty) {
        return 1;
      }

      final fieldConfig = fieldsConfig['totalPages'] as Map<String, dynamic>?;
      if (fieldConfig == null) {
        return 1;
      }

      List<int> pageValues = [];
      for (final row in rows) {
        final values = await extractFieldValue(row, fieldConfig);
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
      _logger.e('解析总页数失败: $e');
    }
    return totalPages;
  }

  Future<List<TorrentItem>> parseTorrentList(BeautifulSoup soup) async {
    // 这个实例方法仍然保留，但我们可以重构它以使用 Isolate 逻辑，
    // 或者仅仅用于测试/backward compatibility。
    // 为了通过基准测试，我们可以在这里直接调用 `parseSearchResultInIsolate` 的内部逻辑（非isolate方式），
    // 也就是构造 ParseSearchParams 然后直接调用（但这需要 soup 已经存在，而 isolate 函数接收 html 字符串）。
    // 所以，我们可以把核心逻辑抽取出来，或者保留此处的逻辑作为同步版本。

    // 为了避免重复维护代码，最佳做法是将核心解析逻辑抽取出来。
    // 但是 `parseSearchResultInIsolate` 包含了 soup 创建。
    // 我们可以创建一个 `_parseTorrentListImpl` 函数接受 soup 和 config。

    final torrents = <TorrentItem>[];

    try {
      // 获取搜索配置
      final searchConfig = await _getFinderConfig('search');

      // 直接调用核心解析逻辑，避免重复代码
      // 注意：这里仍然是在主线程运行
      // 为了复用 isolate 中的代码，我们需要构造参数

      // 由于 isolate 函数是 top-level 且自包含的，我们很难直接复用它的内部部分而不暴露更多细节。
      // 鉴于 `parseTorrentList` 是公开 API，我们可以选择：
      // 1. 保持原样（代码重复，但风险低）
      // 2. 将 Isolate 函数内部逻辑抽取为另一个 top-level 函数（接受 Soup 和 Configs），然后 Isolate 函数和此函数都调用它。

      // 让我们选择方案 2：抽取核心逻辑。
      // 下面我将定义 `_parseTorrentListFromSoup`。

      return await _parseTorrentListFromSoup(
        soup,
        searchConfig,
        _tagMapping ?? {},
        _discountMapping ?? {},
        _siteConfig.baseUrl,
        _siteConfig.passKey ?? ''
      );

    } catch (e) {
      _logRuleAndSoup('search.parse.failed', null, soup);
    }

    return torrents;
  }

  /// 内部静态/实例方法，用于从 Soup 解析列表，可被 Main Thread 或 Isolate 调用
  /// 这里为了方便，我们写一个静态的辅助函数
  static Future<List<TorrentItem>> _parseTorrentListFromSoup(
    BeautifulSoup soup,
    Map<String, dynamic> searchConfig,
    Map<String, String> tagMapping,
    Map<String, String> discountMapping,
    String baseUrl,
    String passKey,
  ) async {
    final parser = _AdapterParser.instance;
    final torrents = <TorrentItem>[];

    final rowsConfig = searchConfig['rows'] as Map<String, dynamic>?;
    final fieldsConfig = searchConfig['fields'] as Map<String, dynamic>?;

    if (rowsConfig == null || fieldsConfig == null) {
      return torrents;
    }

    final rowSelector = rowsConfig['selector'] as String?;
    if (rowSelector == null) {
      return torrents;
    }

    // 使用配置的选择器查找行
    final rows = parser.findElementBySelector(soup, rowSelector);

    for (final rowElement in rows) {
      final row = rowElement as Bs4Element;
      try {
        // 提取种子ID - 如果提取失败则跳过当前行
        final torrentIdConfig =
            fieldsConfig['torrentId'] as Map<String, dynamic>?;
        if (torrentIdConfig == null) {
          continue;
        }

        final torrentIdList = await parser.extractFieldValue(row, torrentIdConfig);
        final torrentId = torrentIdList.isNotEmpty ? torrentIdList.first : '';
        if (torrentId.isEmpty) {
          continue; // 种子ID提取失败，跳过当前行
        }

        // 提取其他字段
        final torrentNameList = await parser.extractFieldValue(
          row,
          fieldsConfig['torrentName'] as Map<String, dynamic>? ?? {},
        );
        final torrentName = torrentNameList.isNotEmpty
            ? torrentNameList.first
            : '';

        final tagList = await parser.extractFieldValue(
          row,
          fieldsConfig['tag'] as Map<String, dynamic>? ?? {},
        );

        final descriptionList = await parser.extractFieldValue(
          row,
          fieldsConfig['description'] as Map<String, dynamic>? ?? {},
        );
        final description = descriptionList.isNotEmpty
            ? descriptionList.first
            : '';

        final discountList = await parser.extractFieldValue(
          row,
          fieldsConfig['discount'] as Map<String, dynamic>? ?? {},
        );
        final discount = discountList.isNotEmpty ? discountList.first : '';

        final discountEndTimeConfig =
            fieldsConfig['discountEndTime'] as Map<String, dynamic>? ?? {};
        final discountEndTimeList = await parser.extractFieldValue(
          row,
          discountEndTimeConfig,
        );
        final discountEndTime = discountEndTimeList.isNotEmpty
            ? discountEndTimeList.first
            : '';
        final discountEndTimeTimeConfig =
            discountEndTimeConfig['time'] as Map<String, dynamic>?;

        final seedersTextList = await parser.extractFieldValue(
          row,
          fieldsConfig['seedersText'] as Map<String, dynamic>? ?? {},
        );
        final seedersText = seedersTextList.isNotEmpty
            ? seedersTextList.first
            : '';

        final leechersTextList = await parser.extractFieldValue(
          row,
          fieldsConfig['leechersText'] as Map<String, dynamic>? ?? {},
        );
        final leechersText = leechersTextList.isNotEmpty
            ? leechersTextList.first
            : '';

        final sizeTextList = await parser.extractFieldValue(
          row,
          fieldsConfig['sizeText'] as Map<String, dynamic>? ?? {},
        );
        final sizeText = sizeTextList.isNotEmpty ? sizeTextList.first : '';

        final downloadStatusTextList = await parser.extractFieldValue(
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

        final coverList = await parser.extractFieldValue(
          row,
          fieldsConfig['cover'] as Map<String, dynamic>? ?? {},
        );
        final cover = coverList.isNotEmpty ? coverList.first : '';

        final createDateConfig =
            fieldsConfig['createDate'] as Map<String, dynamic>? ?? {};
        final createDateList = await parser.extractFieldValue(
          row,
          createDateConfig,
        );
        final createDate = createDateList.isNotEmpty
            ? createDateList.first
            : '';
        final createDateTimeConfig =
            createDateConfig['time'] as Map<String, dynamic>?;

        final doubanRatingList = await parser.extractFieldValue(
          row,
          fieldsConfig['doubanRating'] as Map<String, dynamic>? ?? {},
        );
        final doubanRating = doubanRatingList.isNotEmpty
            ? doubanRatingList.first
            : '';

        final imdbRatingList = await parser.extractFieldValue(
          row,
          fieldsConfig['imdbRating'] as Map<String, dynamic>? ?? {},
        );
        final imdbRating = imdbRatingList.isNotEmpty
            ? imdbRatingList.first
            : '';

        // 提取评论数
        final commentsList = await parser.extractFieldValue(
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
          final collectionList = await parser.extractFieldValue(
            row,
            collectionConfig,
          );
          collection = collectionList.isNotEmpty; // 如果找不到元素说明未收藏
        }
        // 检查置顶状态（布尔字段）
        final isTopConfig = fieldsConfig['isTop'] as Map<String, dynamic>?;
        bool isTop = false;
        if (isTopConfig != null) {
          final isTopList = await parser.extractFieldValue(row, isTopConfig);
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
            final mappedTag = _parseTagTypeStatic(tagStr, tagMapping);
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
            discount: _parseDiscountTypeStatic(
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
        // _logRuleAndSoup('search.row.parseFailed', fieldsConfig, row);
        continue;
      }
    }

    return torrents;
  }
}
