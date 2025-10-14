import 'dart:convert';
import 'package:flutter/services.dart';
import '../models/app_models.dart';

/// 站点配置服务
/// 负责从JSON文件加载预设的站点配置
class SiteConfigService {
  static const String _configPath = 'assets/site_configs.json';
  static const String _sitesManifestPath = 'assets/sites/sites_manifest.json';
  static const String _sitesBasePath = 'assets/sites/';

  /// 获取所有可用的预设站点文件列表
  static Future<List<String>> _getPresetSiteFiles() async {
    try {
      // 从清单文件读取站点列表
      final String manifestString = await rootBundle.loadString(_sitesManifestPath);
      final Map<String, dynamic> manifest = json.decode(manifestString);
      
      final List<dynamic> siteFiles = manifest['sites'] ?? [];
      return siteFiles.map((file) => '$_sitesBasePath$file').cast<String>().toList();
    } catch (e) {
      // 如果清单文件读取失败，返回空列表
      // Failed to load sites manifest: $e
      return [];
    }
  }

  /// 加载预设站点模板配置
  static Future<List<SiteConfigTemplate>> loadPresetSiteTemplates() async {
    final List<SiteConfigTemplate> presetTemplates = [];
    
    // 动态获取站点文件列表
    final presetSiteFiles = await _getPresetSiteFiles();
    
    for (final filePath in presetSiteFiles) {
      try {
        // 从assets读取每个站点的JSON文件
        final String jsonString = await rootBundle.loadString(filePath);
        final Map<String, dynamic> siteJson = json.decode(jsonString);
        
        final siteTemplate = SiteConfigTemplate.fromJson(siteJson);
        presetTemplates.add(siteTemplate);
      } catch (e) {
        // 如果某个文件加载失败，跳过该文件继续加载其他文件
        // Failed to load preset site template from $filePath: $e
        continue;
      }
    }
    
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
  static Future<SiteConfigTemplate?> getTemplateById(String templateId) async {
    final templates = await loadPresetSiteTemplates();
    try {
      return templates.firstWhere((template) => template.id == templateId);
    } catch (e) {
      return null;
    }
  }

  /// 获取默认的站点功能配置
  static SiteFeatures getDefaultFeatures() {
    return SiteFeatures.mteamDefault;
  }

  /// 根据站点类型获取默认模板配置
  static Future<Map<String, dynamic>?> getDefaultTemplate(
    String siteType,
  ) async {
    try {
      // 从assets读取JSON文件
      final String jsonString = await rootBundle.loadString(_configPath);
      final Map<String, dynamic> jsonData = json.decode(jsonString);

      // 获取默认模板配置
      final Map<String, dynamic>? templates = jsonData['defaultTemplates'];
      if (templates != null && templates.containsKey(siteType)) {
        return templates[siteType] as Map<String, dynamic>;
      }

      return null;
    } catch (e) {
      // 如果加载失败，返回null
      return null;
    }
  }

  // 获取默认的优惠映射配置
  static Future<Map<String, String>> getDiscountMapping(
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
        final normalizedUrls = template.baseUrls.map((url) => 
          url.endsWith('/') ? url.substring(0, url.length - 1) : url
        ).toList();
        
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
        final normalizedUrls = template.baseUrls.map((url) => 
          url.endsWith('/') ? url.substring(0, url.length - 1) : url
        ).toList();
        
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
}
