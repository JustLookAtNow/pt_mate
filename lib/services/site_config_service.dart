import 'dart:convert';
import 'package:flutter/services.dart';
import '../models/app_models.dart';

/// 站点配置服务
/// 负责从JSON文件加载预设的站点配置
class SiteConfigService {
  static const String _configPath = 'assets/site_configs.json';

  /// 加载预设站点配置
  static Future<List<SiteConfig>> loadPresetSites() async {
    try {
      // 从assets读取JSON文件
      final String jsonString = await rootBundle.loadString(_configPath);
      final Map<String, dynamic> jsonData = json.decode(jsonString);

      // 解析预设站点列表
      final List<dynamic> presetSitesJson = jsonData['presetSites'] ?? [];

      return presetSitesJson
          .map((siteJson) => SiteConfig.fromJson(siteJson))
          .toList();
    } catch (e) {
      // 如果加载失败，返回空列表
      // Failed to load preset sites: $e
      return [];
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
      // 从assets读取JSON文件
      final String jsonString = await rootBundle.loadString(_configPath);
      final Map<String, dynamic> jsonData = json.decode(jsonString);

      final List<dynamic> presetSitesJson = jsonData['presetSites'] ?? [];

      // 通过baseUrl匹配预设站点

      // 标准化baseUrl，移除末尾的斜杠
      final normalizedBaseUrl = baseUrl.endsWith('/')
          ? baseUrl.substring(0, baseUrl.length - 1)
          : baseUrl;

      for (final siteJson in presetSitesJson) {
        final presetBaseUrl = siteJson['baseUrl'] as String?;
        if (presetBaseUrl != null) {
          final normalizedPresetUrl = presetBaseUrl.endsWith('/')
              ? presetBaseUrl.substring(0, presetBaseUrl.length - 1)
              : presetBaseUrl;
          if (normalizedPresetUrl == normalizedBaseUrl) {
            final Map<dynamic, dynamic> discountMap =
                siteJson['discountMapping'] ?? {};
            return discountMap.map((key, value) => MapEntry(key as String, value as String));
          }
        }
      }
      return {};
    } catch (e) {
      // 如果加载失败，返回空对象
      return {};
    }
  }

  /// 根据站点类型获取默认的搜索分类配置
  /// 优先匹配baseUrl，然后类型
  static Future<List<SearchCategoryConfig>> getDefaultSearchCategories(
    String siteType, {
    String? baseUrl,
  }) async {
    try {
      // 从assets读取JSON文件
      final String jsonString = await rootBundle.loadString(_configPath);
      final Map<String, dynamic> jsonData = json.decode(jsonString);

      final List<dynamic> presetSitesJson = jsonData['presetSites'] ?? [];

      // 通过baseUrl匹配预设站点
      if (baseUrl != null && baseUrl.isNotEmpty) {
        // 标准化baseUrl，移除末尾的斜杠
        final normalizedBaseUrl = baseUrl.endsWith('/')
            ? baseUrl.substring(0, baseUrl.length - 1)
            : baseUrl;

        for (final siteJson in presetSitesJson) {
          final presetBaseUrl = siteJson['baseUrl'] as String?;
          if (presetBaseUrl != null) {
            final normalizedPresetUrl = presetBaseUrl.endsWith('/')
                ? presetBaseUrl.substring(0, presetBaseUrl.length - 1)
                : presetBaseUrl;
            if (normalizedPresetUrl == normalizedBaseUrl) {
              final List<dynamic> categoriesJson =
                  siteJson['searchCategories'] ?? [];
              return categoriesJson
                  .map(
                    (categoryJson) =>
                        SearchCategoryConfig.fromJson(categoryJson),
                  )
                  .toList();
            }
          }
        }
      }

      // 如果没有匹配的id或没有提供id，直接从模板获取
      final List<dynamic> categoriesJson =
          jsonData['defaultTemplates'][siteType]['searchCategories'] ?? [];
      if (categoriesJson.isNotEmpty) {
        return categoriesJson
            .map((categoryJson) => SearchCategoryConfig.fromJson(categoryJson))
            .toList();
      }

      // 如果没有找到匹配的站点类型，返回空列表
      return [];
    } catch (e) {
      // 如果加载失败，返回空列表
      return [];
    }
  }
}
