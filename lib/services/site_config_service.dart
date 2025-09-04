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
}