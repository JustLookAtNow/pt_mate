import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../models/app_models.dart';

/// 站点配置服务
/// 负责从JSON文件加载预设的站点配置
class SiteConfigService {
  static const String _configPath = 'assets/site_configs.json';
  static const String _sitesManifestPath = 'assets/sites_manifest.json';
  static const String _sitesBasePath = 'assets/sites/';

  /// URL到模板ID的映射缓存
  static Map<String, String>? _urlToTemplateIdMapping;

  /// 模板缓存：按模板ID和站点类型缓存已解析的模板，避免重复IO与合并
  static final Map<String, SiteConfigTemplate?> _templateCache = {};

  /// 获取所有可用的预设站点文件列表
  static Future<List<String>> _getPresetSiteFiles() async {
    try {
      // 从清单文件读取站点列表
      final String manifestString = await rootBundle.loadString(
        _sitesManifestPath,
      );
      final Map<String, dynamic> manifest = json.decode(manifestString);

      final List<dynamic> siteFiles = manifest['sites'] ?? [];
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
    final List<SiteConfigTemplate> presetTemplates = [];
    final Map<String, String> urlMapping = {};

    // 动态获取站点文件列表
    final presetSiteFiles = await _getPresetSiteFiles();

    for (final filePath in presetSiteFiles) {
      try {
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
      } catch (e) {
        // 如果某个文件加载失败，跳过该文件继续加载其他文件
        // Failed to load preset site template from $filePath: $e
        continue;
      }
    }

    // 缓存URL映射
    _urlToTemplateIdMapping = urlMapping;
    return presetTemplates;
  }

  /// 加载预设站点配置（向后兼容方法）
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
    // 先查缓存，命中直接返回
    final String cacheKey = '$templateId|${siteType.id}';
    if (_templateCache.containsKey(cacheKey)) {
      return _templateCache[cacheKey];
    }

    SiteConfigTemplate? result;

    if (templateId.isNotEmpty && templateId != "-1") {
      final templates = await loadPresetSiteTemplates();
      try {
        final template = templates.firstWhere(
          (template) => template.id == templateId,
        );

        // 如果模板没有 infoFinder 或 request 配置，尝试从默认模板中获取
        if ((template.infoFinder == null ||
                template.request == null ||
                template.discountMapping.isEmpty) &&
            template.siteType != SiteType.mteam) {
          final defaultTemplate = await _getDefaultTemplateConfig(siteType);
          if (defaultTemplate != null) {
            Map<String, dynamic>? infoFinder = template.infoFinder;
            Map<String, dynamic>? request = template.request;
            Map<String, String>? discountMapping = Map<String, String>.from(
              defaultTemplate['discountMapping'] as Map<String, dynamic>,
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
            // 如果有任何配置需要合并，返回新的模板

            result = template.copyWith(
              infoFinder: infoFinder,
              request: request,
              discountMapping: discountMapping,
            );
          } else {
            result = template;
          }
        } else {
          result = template;
        }
      } catch (e) {
        if (kDebugMode) {
          print('Failed to find template with ID $templateId: $e');
        }
      }
    }

    if (result == null) {
      // 如果没有找到对应的模板，尝试返回默认模板配置
      final defaultTemplate = await _getDefaultTemplateConfig(siteType);
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
      // 从assets读取JSON文件
      final String jsonString = await rootBundle.loadString(_configPath);
      final Map<String, dynamic> jsonData = json.decode(jsonString);

      // 获取默认模板配置
      final Map<String, dynamic>? templates = jsonData['defaultTemplates'];
      if (templates != null && templates.containsKey(siteType.id)) {
        return templates[siteType.id] as Map<String, dynamic>;
      }

      return null;
    } catch (e) {
      // 如果加载失败，返回null
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
          return template.discountMapping;
        }
      }

      // 如果没有找到匹配的站点，返回空映射
      return {};
    } catch (e) {
      // 如果加载失败，返回空对象
      return {};
    }
  }

  // 获取默认的搜索分类配置
  static Future<List<SearchCategoryConfig>> getDefaultSearchCategories(
    String baseUrl,
  ) async {
    try {
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
          return template.searchCategories;
        }
      }

      // 如果没有找到匹配的站点，返回空列表
      return [];
    } catch (e) {
      // 如果加载失败，返回空列表
      return [];
    }
  }

  /// 获取URL到模板ID的映射
  /// 如果缓存为空，会先加载预设站点模板来构建缓存
  static Future<Map<String, String>> getUrlToTemplateIdMapping() async {
    if (_urlToTemplateIdMapping == null) {
      // 如果缓存为空，先加载预设站点模板来构建缓存
      await loadPresetSiteTemplates();
    }
    return _urlToTemplateIdMapping ?? {};
  }

  /// 清空模板缓存（例如切换环境或资产更新后）
  static void clearTemplateCache() {
    _templateCache.clear();
  }
}
