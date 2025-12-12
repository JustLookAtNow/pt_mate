import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart';
import 'package:flutter/services.dart';
import '../models/app_models.dart';

/// 站点配置服务
/// 负责从JSON文件加载预设的站点配置
class SiteConfigService {
  static const String _configPath = 'assets/site_configs.json';
  static const String _sitesManifestPath = 'assets/sites_manifest.json';
  static const String _sitesBasePath = 'assets/sites/';

  /// 预设站点模板列表缓存
  static List<SiteConfigTemplate>? _presetTemplatesCache;

  /// URL到模板ID的映射缓存
  static Map<String, String>? _urlToTemplateIdMapping;

  /// 模板缓存：按模板ID和站点类型缓存已解析的模板，避免重复IO与合并
  static final Map<String, SiteConfigTemplate?> _templateCache = {};
  static final Logger _logger = Logger();

  /// 默认模板配置缓存
  static Map<String, dynamic>? _defaultTemplatesCache;

  /// 获取所有可用的预设站点文件列表
  static Future<List<String>> _getPresetSiteFiles() async {
    try {
      final swManifest = Stopwatch()..start();
      // 从清单文件读取站点列表
      final String manifestString = await rootBundle.loadString(
        _sitesManifestPath,
      );
      final Map<String, dynamic> manifest = json.decode(manifestString);

      final List<dynamic> siteFiles = manifest['sites'] ?? [];
      swManifest.stop();
      if (kDebugMode) {
        _logger.d('SiteConfigService._getPresetSiteFiles: 清单加载耗时=${swManifest.elapsedMilliseconds}ms');
      }
      return siteFiles
          .map((file) => '$_sitesBasePath$file')
          .cast<String>()
          .toList();
    } catch (e) {
      // 如果清单文件读取失败，返回空列表
      // Failed to load sites manifest: $e
      return [];
    }
  }

  /// 加载预设站点模板配置
  static Future<List<SiteConfigTemplate>> loadPresetSiteTemplates() async {
    // 如果缓存存在，直接返回缓存的数据
    if (_presetTemplatesCache != null) {
      return _presetTemplatesCache!;
    }

    final swTotal = Stopwatch()..start();
    final List<SiteConfigTemplate> presetTemplates = [];
    final Map<String, String> urlMapping = {};

    // 动态获取站点文件列表
    final swList = Stopwatch()..start();
    final presetSiteFiles = await _getPresetSiteFiles();
    swList.stop();
    if (kDebugMode) {
      _logger.d('SiteConfigService.loadPresetSiteTemplates: 站点清单获取耗时=${swList.elapsedMilliseconds}ms, 文件数=${presetSiteFiles.length}');
    }

    for (final filePath in presetSiteFiles) {
      try {
        final swFile = Stopwatch()..start();
        // 从assets读取每个站点的JSON文件
        final String jsonString = await rootBundle.loadString(filePath);
        final Map<String, dynamic> siteJson = json.decode(jsonString);

        final siteTemplate = SiteConfigTemplate.fromJson(siteJson);
        presetTemplates.add(siteTemplate);

        // 构建URL映射缓存
        final templateId = siteTemplate.id;
        for (final url in siteTemplate.baseUrls) {
          final normalizedUrl = url.endsWith('/')
              ? url.substring(0, url.length - 1)
              : url;
          urlMapping[normalizedUrl] = templateId;
        }
        swFile.stop();
        if (kDebugMode) {
          _logger.d('SiteConfigService.loadPresetSiteTemplates: 解析模板 $filePath 耗时=${swFile.elapsedMilliseconds}ms');
        }
      } catch (e) {
        // 如果某个文件加载失败，跳过该文件继续加载其他文件
        // Failed to load preset site template from $filePath: $e
        continue;
      }
    }

    // 缓存预设站点模板列表和URL映射
    _presetTemplatesCache = presetTemplates;
    _urlToTemplateIdMapping = urlMapping;
    swTotal.stop();
    if (kDebugMode) {
      _logger.d('SiteConfigService.loadPresetSiteTemplates: 加载模板数量=${presetTemplates.length}, 总耗时=${swTotal.elapsedMilliseconds}ms');
    }
    
    return presetTemplates;
  }

  /// 加载预设站点配置（向前兼容方法）
  /// 将模板转换为SiteConfig实例，使用主要URL
  static Future<List<SiteConfig>> loadPresetSites() async {
    final List<SiteConfig> presetSites = [];
    final templates = await loadPresetSiteTemplates();

    for (final template in templates) {
      try {
        final siteConfig = template.toSiteConfig();
        presetSites.add(siteConfig);
      } catch (e) {
        // 如果转换失败，跳过该模板
        continue;
      }
    }

    return presetSites;
  }

  /// 根据模板ID获取站点模板
  static Future<SiteConfigTemplate?> getTemplateById(
    String templateId,
    SiteType siteType,
  ) async {
    final swTotal = Stopwatch()..start();
    // 先查缓存，命中直接返回
    final String cacheKey = '$templateId|${siteType.id}';
    if (_templateCache.containsKey(cacheKey)) {
      swTotal.stop();
      if (kDebugMode) {
        _logger.d('SiteConfigService.getTemplateById: 命中缓存($cacheKey), 耗时=${swTotal.elapsedMilliseconds}ms');
      }
      return _templateCache[cacheKey];
    }

    SiteConfigTemplate? result;

    if (templateId.isNotEmpty && templateId != "-1") {
      final templates = await loadPresetSiteTemplates();
      try {
        final swSearch = Stopwatch()..start();
        final template = templates.firstWhere(
          (template) => template.id == templateId,
        );
        swSearch.stop();
        if (kDebugMode) {
          _logger.d('SiteConfigService.getTemplateById: 搜索模板ID=$templateId 耗时=${swSearch.elapsedMilliseconds}ms');
        }

        // 如果模板没有 infoFinder 或 request 配置，尝试从默认模板中获取
        if ((template.infoFinder == null ||
                template.request == null ||
                template.request == null ||
                template.discountMapping.isEmpty ||
                template.tagMapping.isEmpty) &&
            template.siteType != SiteType.mteam) {
          final swDefault = Stopwatch()..start();
          final defaultTemplate = await _getDefaultTemplateConfig(siteType);
          swDefault.stop();
          if (kDebugMode) {
            _logger.d('SiteConfigService.getTemplateById: 加载默认模板(${siteType.id})耗时=${swDefault.elapsedMilliseconds}ms');
          }
          if (defaultTemplate != null) {
            Map<String, dynamic>? infoFinder = template.infoFinder;
            Map<String, dynamic>? request = template.request;
            Map<String, String>? discountMapping = Map<String, String>.from(
              defaultTemplate['discountMapping'] as Map<String, dynamic>? ?? {},
            );
            Map<String, String>? tagMapping = Map<String, String>.from(
              defaultTemplate['tagMapping'] as Map<String, dynamic>? ?? {},
            );

            // 如果模板没有 infoFinder 配置，从默认模板中获取
            if (infoFinder == null && defaultTemplate['infoFinder'] != null) {
              infoFinder =
                  defaultTemplate['infoFinder'] as Map<String, dynamic>;
            }

            // 如果模板没有 request 配置，从默认模板中获取
            if (request == null && defaultTemplate['request'] != null) {
              request = defaultTemplate['request'] as Map<String, dynamic>;
            }
            if (template.discountMapping.isNotEmpty) {
              discountMapping.addAll(template.discountMapping);
            }
            if (template.tagMapping.isNotEmpty) {
              tagMapping.addAll(template.tagMapping);
            }
            // 如果有任何配置需要合并，返回新的模板

            result = template.copyWith(
              infoFinder: infoFinder,
              request: request,
              discountMapping: discountMapping,
              tagMapping: tagMapping,
            );
          } else {
            result = template;
          }
        } else {
          result = template;
        }
      } catch (e) {
        if (kDebugMode) {
          _logger.e('Failed to find template with ID $templateId: $e');
        }
      }
    }

    if (result == null) {
      // 如果没有找到对应的模板，尝试返回默认模板配置
      final swDefault2 = Stopwatch()..start();
      final defaultTemplate = await _getDefaultTemplateConfig(siteType);
      swDefault2.stop();
      if (kDebugMode) {
        _logger.d('SiteConfigService.getTemplateById: 备用默认模板(${siteType.id})加载耗时=${swDefault2.elapsedMilliseconds}ms');
      }
      if (defaultTemplate != null) {
        // 将默认模板配置转换为 SiteConfigTemplate
        result = _convertDefaultTemplateToSiteConfigTemplate(
          templateId,
          defaultTemplate,
        );
      }
    }

    // 写入缓存（包括null结果，避免重复IO）
    _templateCache[cacheKey] = result;
    if (swTotal.isRunning) {
      swTotal.stop();
    }
    if (kDebugMode) {
      _logger.d('SiteConfigService.getTemplateById: 模板ID=$templateId, 站点类型=${siteType.id}, 总耗时=${swTotal.elapsedMilliseconds}ms');
    }
    return result;
  }

  /// 将默认模板配置转换为 SiteConfigTemplate
  static SiteConfigTemplate? _convertDefaultTemplateToSiteConfigTemplate(
    String templateId,
    Map<String, dynamic> defaultTemplate,
  ) {
    try {
      // 解析搜索分类配置
      List<SearchCategoryConfig> categories = [];
      if (defaultTemplate['searchCategories'] != null) {
        final list = (defaultTemplate['searchCategories'] as List)
            .cast<Map<String, dynamic>>();
        categories = list.map(SearchCategoryConfig.fromJson).toList();
      }

      // 解析功能配置
      SiteFeatures features = SiteFeatures.mteamDefault;
      if (defaultTemplate['features'] != null) {
        features = SiteFeatures.fromJson(
          defaultTemplate['features'] as Map<String, dynamic>,
        );
      }

      // 解析优惠映射配置
      Map<String, String> discountMapping = {};
      if (defaultTemplate['discountMapping'] != null) {
        discountMapping = Map<String, String>.from(
          defaultTemplate['discountMapping'] as Map<String, dynamic>,
        );
      }

      // 解析标签映射配置
      Map<String, String> tagMapping = {};
      if (defaultTemplate['tagMapping'] != null) {
        tagMapping = Map<String, String>.from(
          defaultTemplate['tagMapping'] as Map<String, dynamic>,
        );
      }

      // 解析 infoFinder 配置
      Map<String, dynamic>? infoFinder;
      if (defaultTemplate['infoFinder'] != null) {
        infoFinder = Map<String, dynamic>.from(
          defaultTemplate['infoFinder'] as Map<String, dynamic>,
        );
      }

      // 解析 request 配置
      Map<String, dynamic>? request;
      if (defaultTemplate['request'] != null) {
        request = Map<String, dynamic>.from(
          defaultTemplate['request'] as Map<String, dynamic>,
        );
      }

      // 确定站点类型
      SiteType siteType = SiteType.values.firstWhere(
        (type) => type.id == templateId,
        orElse: () => SiteType.mteam,
      );

      return SiteConfigTemplate(
        id: templateId,
        name: defaultTemplate['name'] as String? ?? templateId,
        baseUrls: [defaultTemplate['baseUrl'] as String? ?? 'https://'],
        siteType: siteType,
        searchCategories: categories,
        features: features,
        discountMapping: discountMapping,
        tagMapping: tagMapping,
        infoFinder: infoFinder,
        request: request,
      );
    } catch (e) {
      return null;
    }
  }

  /// 根据站点类型获取默认模板配置（私有方法）
  static Future<Map<String, dynamic>?> _getDefaultTemplateConfig(
    SiteType siteType,
  ) async {
    try {
      final swTotal = Stopwatch()..start();
      // 如果缓存不存在，先加载默认模板配置
      if (_defaultTemplatesCache == null) {
        final swLoad = Stopwatch()..start();
        // 从assets读取JSON文件
        final String jsonString = await rootBundle.loadString(_configPath);
        final Map<String, dynamic> jsonData = json.decode(jsonString);

        // 缓存默认模板配置
        _defaultTemplatesCache = jsonData['defaultTemplates'] as Map<String, dynamic>?;
        swLoad.stop();
        if (kDebugMode) {
          _logger.d('SiteConfigService._getDefaultTemplateConfig: 首次加载默认模板耗时=${swLoad.elapsedMilliseconds}ms');
        }
      }

      // 从缓存中获取默认模板配置
      if (_defaultTemplatesCache != null && _defaultTemplatesCache!.containsKey(siteType.id)) {
        swTotal.stop();
        if (kDebugMode) {
          _logger.d('SiteConfigService._getDefaultTemplateConfig: 命中 ${siteType.id}, 总耗时=${swTotal.elapsedMilliseconds}ms');
        }
        return _defaultTemplatesCache![siteType.id] as Map<String, dynamic>;
      }

      swTotal.stop();
      if (kDebugMode) {
        _logger.d('SiteConfigService._getDefaultTemplateConfig: 未找到 ${siteType.id}, 总耗时=${swTotal.elapsedMilliseconds}ms');
      }
      return null;
    } catch (e) {
      // 如果加载失败，返回null
      if (kDebugMode) {
        _logger.e('SiteConfigService._getDefaultTemplateConfig: 加载失败 ${siteType.id}, 错误=$e');
      }
      return null;
    }
  }

  /// 获取默认的站点功能配置
  static SiteFeatures getDefaultFeatures() {
    return SiteFeatures.mteamDefault;
  }

  // 获取默认的优惠映射配置
  static Future<Map<String, String>> getDiscountMapping(String baseUrl) async {
    try {
      final swTotal = Stopwatch()..start();
      // 标准化baseUrl，移除末尾的斜杠
      final normalizedBaseUrl = baseUrl.endsWith('/')
          ? baseUrl.substring(0, baseUrl.length - 1)
          : baseUrl;

      // 使用新的模板加载方法
      final templates = await loadPresetSiteTemplates();

      // 遍历所有模板，查找匹配的baseUrl
      for (final template in templates) {
        // 检查是否有匹配的URL
        final normalizedUrls = template.baseUrls
            .map(
              (url) =>
                  url.endsWith('/') ? url.substring(0, url.length - 1) : url,
            )
            .toList();

        if (normalizedUrls.contains(normalizedBaseUrl)) {
          // 找到匹配的站点，返回discountMapping
          swTotal.stop();
          if (kDebugMode) {
            _logger.d('SiteConfigService.getDiscountMapping: 命中 $normalizedBaseUrl, 模板=${template.id}, 耗时=${swTotal.elapsedMilliseconds}ms');
          }
          return template.discountMapping;
        }
      }

      // 如果没有找到匹配的站点，返回空映射
      swTotal.stop();
      if (kDebugMode) {
        _logger.d('SiteConfigService.getDiscountMapping: 未命中 $normalizedBaseUrl, 耗时=${swTotal.elapsedMilliseconds}ms');
      }
      return {};
    } catch (e) {
      // 如果加载失败，返回空对象
      if (kDebugMode) {
        _logger.e('SiteConfigService.getDiscountMapping: 加载失败 baseUrl=$baseUrl, 错误=$e');
      }
      return {};
    }
  }

  // 获取默认的搜索分类配置
  static Future<List<SearchCategoryConfig>> getDefaultSearchCategories(
    String baseUrl,
  ) async {
    try {
      final swTotal = Stopwatch()..start();
      // 标准化baseUrl，移除末尾的斜杠
      final normalizedBaseUrl = baseUrl.endsWith('/')
          ? baseUrl.substring(0, baseUrl.length - 1)
          : baseUrl;

      // 使用新的模板加载方法
      final templates = await loadPresetSiteTemplates();

      // 遍历所有模板，查找匹配的baseUrl
      for (final template in templates) {
        // 检查是否有匹配的URL
        final normalizedUrls = template.baseUrls
            .map(
              (url) =>
                  url.endsWith('/') ? url.substring(0, url.length - 1) : url,
            )
            .toList();

        if (normalizedUrls.contains(normalizedBaseUrl)) {
          // 找到匹配的站点，返回searchCategories
           swTotal.stop();
           if (kDebugMode) {
             _logger.d('SiteConfigService.getDefaultSearchCategories: 命中 $normalizedBaseUrl, 模板=${template.id}, 耗时=${swTotal.elapsedMilliseconds}ms');
           }
          return template.searchCategories;
        }
      }

      // 如果没有找到匹配的站点，返回空列表
      swTotal.stop();
      if (kDebugMode) {
        _logger.d('SiteConfigService.getDefaultSearchCategories: 未命中 $normalizedBaseUrl, 耗时=${swTotal.elapsedMilliseconds}ms');
      }
      return [];
    } catch (e) {
      // 如果加载失败，返回空列表
      if (kDebugMode) {
        _logger.e('SiteConfigService.getDefaultSearchCategories: 加载失败 baseUrl=$baseUrl, 错误=$e');
      }
      return [];
    }
  }

  /// 获取URL到模板ID的映射
  /// 如果缓存为空，会先加载预设站点模板来构建缓存
  static Future<Map<String, String>> getUrlToTemplateIdMapping() async {
    final swTotal = Stopwatch()..start();
    if (_urlToTemplateIdMapping == null) {
      // 如果缓存为空，先加载预设站点模板来构建缓存
      await loadPresetSiteTemplates();
    }
    swTotal.stop();
    if (kDebugMode) {
      _logger.d('SiteConfigService.getUrlToTemplateIdMapping: 映射数量=${_urlToTemplateIdMapping?.length ?? 0}, 总耗时=${swTotal.elapsedMilliseconds}ms');
    }
    return _urlToTemplateIdMapping ?? {};
  }

  /// 清空所有缓存（例如切换环境或资产更新后）
  static void clearAllCache() {
    _presetTemplatesCache = null;
    _urlToTemplateIdMapping = null;
    _defaultTemplatesCache = null;
    _templateCache.clear();
  }

  /// 清空模板缓存（向前兼容方法）
  static void clearTemplateCache() {
    clearAllCache();
  }
}
