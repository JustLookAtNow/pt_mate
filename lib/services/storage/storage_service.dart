import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/app_models.dart';

class StorageKeys {
  // 多站点配置
  static const String siteConfigs = 'app.sites'; // 存储所有站点配置
  static const String activeSiteId = 'app.activeSiteId'; // 当前活跃站点ID
  
  // 兼容性：旧的单站点配置（用于迁移）
  static const String siteConfig = 'app.site';
  
  static const String qbClients = 'qb.clients';
  static const String qbDefaultId = 'qb.defaultId';
  static String qbPasswordKey(String id) => 'qb.password.$id';
  static String qbPasswordFallbackKey(String id) => 'qb.password.fallback.$id';
  // 新增：分类与标签缓存 key
  static String qbCategoriesKey(String id) => 'qb.categories.$id';
  static String qbTagsKey(String id) => 'qb.tags.$id';
  
  // 默认下载设置
  static const String defaultDownloadCategory = 'download.defaultCategory';
  static const String defaultDownloadTags = 'download.defaultTags';
  static const String defaultDownloadSavePath = 'download.defaultSavePath';

  // 多站点API密钥存储
  static String siteApiKey(String siteId) => 'site.apiKey.$siteId';
  static String siteApiKeyFallback(String siteId) => 'site.apiKey.fallback.$siteId';
  
  // 兼容性：旧的API密钥存储
  static const String legacySiteApiKey = 'site.apiKey';
  // 非安全存储的降级 Key（例如 Linux 桌面端 keyring 被锁定时）
  static const String legacySiteApiKeyFallback = 'site.apiKey.fallback';

  // WebDAV密码安全存储
  static String webdavPassword(String configId) => 'webdav.password.$configId';
  static String webdavPasswordFallback(String configId) => 'webdav.password.fallback.$configId';

  // 主题相关
  static const String themeMode = 'theme.mode'; // system | light | dark
  static const String themeUseDynamic = 'theme.useDynamic'; // bool
  static const String themeSeedColor = 'theme.seedColor'; // int (ARGB)
  
  // 图片设置
  static const String autoLoadImages = 'images.autoLoad'; // bool
  
  // 聚合搜索设置
  static const String aggregateSearchSettings = 'aggregateSearch.settings';
  
  // 查询条件配置已移至站点配置中，不再需要全局键
}

class StorageService {
  StorageService._();
  static final StorageService instance = StorageService._();

  final FlutterSecureStorage _secure = const FlutterSecureStorage();

  Future<SharedPreferences> get _prefs async => SharedPreferences.getInstance();

  // Site config
  Future<void> saveSite(SiteConfig config) async {
    final prefs = await _prefs;
    await prefs.setString(StorageKeys.siteConfig, jsonEncode(config.toJson()));
    // secure parts
    if ((config.apiKey ?? '').isNotEmpty) {
      try {
        await _secure.write(key: StorageKeys.legacySiteApiKey, value: config.apiKey);
        // 清理降级存储
        await prefs.remove(StorageKeys.legacySiteApiKeyFallback);
      } catch (_) {
        // 当桌面环境的 keyring 被锁定或不可用时，降级到本地存储，避免崩溃
        await prefs.setString(StorageKeys.legacySiteApiKeyFallback, config.apiKey!);
      }
    } else {
      try {
        await _secure.delete(key: StorageKeys.legacySiteApiKey);
      } catch (_) {
        // 同步清理降级存储
        await prefs.remove(StorageKeys.legacySiteApiKeyFallback);
      }
    }
  }

  Future<SiteConfig?> loadSite() async {
    final prefs = await _prefs;
    final str = prefs.getString(StorageKeys.siteConfig);
    if (str == null) return null;
    final json = jsonDecode(str) as Map<String, dynamic>;
    final base = SiteConfig.fromJson(json);

    String? apiKey;
    try {
      apiKey = await _secure.read(key: StorageKeys.legacySiteApiKey);
    } catch (_) {
      // 读取失败时，从降级存储取值
      apiKey = prefs.getString(StorageKeys.legacySiteApiKeyFallback);
    }
    // 若安全存储读取到的值为空或为 null，则继续尝试降级存储
    if (apiKey == null || apiKey.isEmpty) {
      final fallback = prefs.getString(StorageKeys.legacySiteApiKeyFallback);
      if (fallback != null && fallback.isNotEmpty) {
        apiKey = fallback;
      }
    }

    return base.copyWith(apiKey: apiKey);
  }

  // 多站点配置管理
  Future<void> saveSiteConfigs(List<SiteConfig> configs) async {
    final prefs = await _prefs;
    final jsonList = configs.map((config) => {
      ...config.toJson(),
      'apiKey': null, // API密钥单独存储
    }).toList();
    await prefs.setString(StorageKeys.siteConfigs, jsonEncode(jsonList));
    
    // 保存每个站点的API密钥
    for (final config in configs) {
      await _saveSiteApiKey(config.id, config.apiKey);
    }
  }

  Future<List<SiteConfig>> loadSiteConfigs() async {
    final prefs = await _prefs;
    final str = prefs.getString(StorageKeys.siteConfigs);
    if (str == null) {
      // 尝试从旧的单站点配置迁移
      final legacySite = await loadSite();
      if (legacySite != null) {
        // 为旧配置生成ID并迁移
        final migratedSite = legacySite.copyWith(
          id: 'migrated-${DateTime.now().millisecondsSinceEpoch}',
        );
        await saveSiteConfigs([migratedSite]);
        await setActiveSiteId(migratedSite.id);
        return [migratedSite];
      }
      return [];
    }
    
    try {
      final list = (jsonDecode(str) as List).cast<Map<String, dynamic>>();
      final configs = <SiteConfig>[];
      
      for (final json in list) {
        final baseConfig = SiteConfig.fromJson(json);
        final apiKey = await _loadSiteApiKey(baseConfig.id);
        configs.add(baseConfig.copyWith(apiKey: apiKey));
      }
      
      return configs;
    } catch (_) {
      return [];
    }
  }

  Future<void> addSiteConfig(SiteConfig config) async {
    final configs = await loadSiteConfigs();
    configs.add(config);
    await saveSiteConfigs(configs);
  }

  Future<void> updateSiteConfig(SiteConfig config) async {
    final configs = await loadSiteConfigs();
    final index = configs.indexWhere((c) => c.id == config.id);
    if (index >= 0) {
      configs[index] = config;
      await saveSiteConfigs(configs);
    }
  }

  Future<void> deleteSiteConfig(String siteId) async {
    final configs = await loadSiteConfigs();
    configs.removeWhere((c) => c.id == siteId);
    await saveSiteConfigs(configs);
    await _deleteSiteApiKey(siteId);
    
    // 如果删除的是当前活跃站点，清除活跃站点设置
    final activeSiteId = await getActiveSiteId();
    if (activeSiteId == siteId) {
      await setActiveSiteId(null);
    }
  }

  Future<void> setActiveSiteId(String? siteId) async {
    final prefs = await _prefs;
    if (siteId != null) {
      await prefs.setString(StorageKeys.activeSiteId, siteId);
    } else {
      await prefs.remove(StorageKeys.activeSiteId);
    }
  }

  Future<String?> getActiveSiteId() async {
    final prefs = await _prefs;
    return prefs.getString(StorageKeys.activeSiteId);
  }

  Future<SiteConfig?> getActiveSiteConfig() async {
    final activeSiteId = await getActiveSiteId();
    if (activeSiteId == null) return null;
    
    final configs = await loadSiteConfigs();
    try {
      return configs.firstWhere((c) => c.id == activeSiteId);
    } catch (_) {
      return null;
    }
  }

  // 私有方法：处理单个站点的API密钥
  Future<void> _saveSiteApiKey(String siteId, String? apiKey) async {
    if (apiKey == null || apiKey.isEmpty) {
      await _deleteSiteApiKey(siteId);
      return;
    }
    
    try {
      await _secure.write(key: StorageKeys.siteApiKey(siteId), value: apiKey);
      // 清理降级存储
      final prefs = await _prefs;
      await prefs.remove(StorageKeys.siteApiKeyFallback(siteId));
    } catch (_) {
      // 降级到本地存储
      final prefs = await _prefs;
      await prefs.setString(StorageKeys.siteApiKeyFallback(siteId), apiKey);
    }
  }

  Future<String?> _loadSiteApiKey(String siteId) async {
    try {
      final apiKey = await _secure.read(key: StorageKeys.siteApiKey(siteId));
      if (apiKey != null && apiKey.isNotEmpty) return apiKey;
    } catch (_) {
      // ignore and try fallback
    }
    
    final prefs = await _prefs;
    return prefs.getString(StorageKeys.siteApiKeyFallback(siteId));
  }

  Future<void> _deleteSiteApiKey(String siteId) async {
    try {
      await _secure.delete(key: StorageKeys.siteApiKey(siteId));
    } catch (_) {
      // ignore
    }
    
    final prefs = await _prefs;
    await prefs.remove(StorageKeys.siteApiKeyFallback(siteId));
  }

  // qBittorrent clients
  Future<void> saveQbClients(List<QbClientConfig> clients, {String? defaultId}) async {
    final prefs = await _prefs;
    await prefs.setString(StorageKeys.qbClients, jsonEncode(clients.map((e) => e.toJson()).toList()));
    if (defaultId != null) {
      await prefs.setString(StorageKeys.qbDefaultId, defaultId);
    } else {
      // 允许将默认下载器清空
      await prefs.remove(StorageKeys.qbDefaultId);
    }
    // passwords should be saved separately when creating/editing single client
  }

  Future<List<QbClientConfig>> loadQbClients() async {
    final prefs = await _prefs;
    final str = prefs.getString(StorageKeys.qbClients);
    if (str == null) return [];
    final list = (jsonDecode(str) as List).cast<Map<String, dynamic>>();
    return list.map(QbClientConfig.fromJson).toList();
  }

  Future<void> saveQbPassword(String id, String password) async {
    try {
      await _secure.write(key: StorageKeys.qbPasswordKey(id), value: password);
      // 清理可能存在的降级存储
      final prefs = await _prefs;
      await prefs.remove(StorageKeys.qbPasswordFallbackKey(id));
    } catch (_) {
      // 在 Linux 桌面端等环境，可能出现 keyring 未解锁；降级写入本地存储，避免功能中断
      final prefs = await _prefs;
      await prefs.setString(StorageKeys.qbPasswordFallbackKey(id), password);
    }
  }

  Future<String?> loadQbPassword(String id) async {
    try {
      final v = await _secure.read(key: StorageKeys.qbPasswordKey(id));
      if (v != null && v.isNotEmpty) return v;
    } catch (_) {
      // ignore and try fallback
    }
    final prefs = await _prefs;
    return prefs.getString(StorageKeys.qbPasswordFallbackKey(id));
  }

  Future<void> deleteQbPassword(String id) async {
    try {
      await _secure.delete(key: StorageKeys.qbPasswordKey(id));
    } catch (_) {
      // ignore
    }
    final prefs = await _prefs;
    await prefs.remove(StorageKeys.qbPasswordFallbackKey(id));
  }

  // 新增：分类与标签的本地缓存
  Future<void> saveQbCategories(String id, List<String> categories) async {
    final prefs = await _prefs;
    await prefs.setStringList(StorageKeys.qbCategoriesKey(id), categories);
  }

  Future<List<String>> loadQbCategories(String id) async {
    final prefs = await _prefs;
    return prefs.getStringList(StorageKeys.qbCategoriesKey(id)) ?? <String>[];
  }

  Future<void> saveQbTags(String id, List<String> tags) async {
    final prefs = await _prefs;
    await prefs.setStringList(StorageKeys.qbTagsKey(id), tags);
  }

  Future<List<String>> loadQbTags(String id) async {
    final prefs = await _prefs;
    return prefs.getStringList(StorageKeys.qbTagsKey(id)) ?? <String>[];
  }

  Future<String?> loadDefaultQbId() async {
    final prefs = await _prefs;
    return prefs.getString(StorageKeys.qbDefaultId);
  }

  // 主题相关：保存与读取
  Future<void> saveThemeMode(String mode) async {
    final prefs = await _prefs;
    await prefs.setString(StorageKeys.themeMode, mode);
  }

  Future<String?> loadThemeMode() async {
    final prefs = await _prefs;
    return prefs.getString(StorageKeys.themeMode);
  }

  Future<void> saveUseDynamicColor(bool useDynamic) async {
    final prefs = await _prefs;
    await prefs.setBool(StorageKeys.themeUseDynamic, useDynamic);
  }

  Future<bool?> loadUseDynamicColor() async {
    final prefs = await _prefs;
    return prefs.getBool(StorageKeys.themeUseDynamic);
  }

  Future<void> saveSeedColor(int argb) async {
    final prefs = await _prefs;
    await prefs.setInt(StorageKeys.themeSeedColor, argb);
  }

  Future<int?> loadSeedColor() async {
    final prefs = await _prefs;
    return prefs.getInt(StorageKeys.themeSeedColor);
  }

  // 图片设置相关：保存与读取
  Future<void> saveAutoLoadImages(bool autoLoad) async {
    final prefs = await _prefs;
    await prefs.setBool(StorageKeys.autoLoadImages, autoLoad);
  }

  Future<bool> loadAutoLoadImages() async {
    final prefs = await _prefs;
    return prefs.getBool(StorageKeys.autoLoadImages) ?? true; // 默认自动加载
  }

  // 默认下载设置相关
  Future<void> saveDefaultDownloadCategory(String? category) async {
    final prefs = await _prefs;
    if (category != null && category.isNotEmpty) {
      await prefs.setString(StorageKeys.defaultDownloadCategory, category);
    } else {
      await prefs.remove(StorageKeys.defaultDownloadCategory);
    }
  }

  Future<String?> loadDefaultDownloadCategory() async {
    final prefs = await _prefs;
    return prefs.getString(StorageKeys.defaultDownloadCategory);
  }

  Future<void> saveDefaultDownloadTags(List<String> tags) async {
    final prefs = await _prefs;
    if (tags.isNotEmpty) {
      await prefs.setStringList(StorageKeys.defaultDownloadTags, tags);
    } else {
      await prefs.remove(StorageKeys.defaultDownloadTags);
    }
  }

  Future<List<String>> loadDefaultDownloadTags() async {
    final prefs = await _prefs;
    return prefs.getStringList(StorageKeys.defaultDownloadTags) ?? <String>[];
  }

  Future<void> saveDefaultDownloadSavePath(String? savePath) async {
    final prefs = await _prefs;
    if (savePath != null && savePath.isNotEmpty) {
      await prefs.setString(StorageKeys.defaultDownloadSavePath, savePath);
    } else {
      await prefs.remove(StorageKeys.defaultDownloadSavePath);
    }
  }

  Future<String?> loadDefaultDownloadSavePath() async {
    final prefs = await _prefs;
    return prefs.getString(StorageKeys.defaultDownloadSavePath);
  }

  // WebDAV密码安全存储方法
  Future<void> saveWebDAVPassword(String configId, String? password) async {
    if (password == null || password.isEmpty) {
      await deleteWebDAVPassword(configId);
      return;
    }
    
    try {
      await _secure.write(key: StorageKeys.webdavPassword(configId), value: password);
      // 清理降级存储
      final prefs = await _prefs;
      await prefs.remove(StorageKeys.webdavPasswordFallback(configId));
    } catch (_) {
      // 当桌面环境的 keyring 被锁定或不可用时，降级到本地存储，避免崩溃
      final prefs = await _prefs;
      await prefs.setString(StorageKeys.webdavPasswordFallback(configId), password);
    }
  }

  Future<String?> loadWebDAVPassword(String configId) async {
    try {
      final password = await _secure.read(key: StorageKeys.webdavPassword(configId));
      if (password != null && password.isNotEmpty) return password;
    } catch (_) {
      // 读取失败时，从降级存储取值
    }
    
    // 若安全存储读取到的值为空或为 null，则继续尝试降级存储
    final prefs = await _prefs;
    final fallback = prefs.getString(StorageKeys.webdavPasswordFallback(configId));
    if (fallback != null && fallback.isNotEmpty) {
      return fallback;
    }
    
    return null;
  }

  Future<void> deleteWebDAVPassword(String configId) async {
    try {
      await _secure.delete(key: StorageKeys.webdavPassword(configId));
    } catch (_) {
      // ignore
    }
    
    final prefs = await _prefs;
    await prefs.remove(StorageKeys.webdavPasswordFallback(configId));
  }

  // 聚合搜索设置相关
  Future<void> saveAggregateSearchSettings(AggregateSearchSettings settings) async {
    final prefs = await _prefs;
    await prefs.setString(StorageKeys.aggregateSearchSettings, jsonEncode(settings.toJson()));
  }

  Future<AggregateSearchSettings> loadAggregateSearchSettings() async {
    final prefs = await _prefs;
    final str = prefs.getString(StorageKeys.aggregateSearchSettings);
    if (str == null) {
      // 返回默认设置，包含一个"全部站点"的默认配置
      final allSites = await loadSiteConfigs();
      final defaultConfig = AggregateSearchConfig.createDefaultConfig(
        allSites.map((site) => site.id).toList(),
      );
      return AggregateSearchSettings(
        searchConfigs: [defaultConfig],
        searchThreads: 3,
      );
    }
    
    try {
      final json = jsonDecode(str) as Map<String, dynamic>;
      return AggregateSearchSettings.fromJson(json);
    } catch (_) {
      // 解析失败时返回默认设置
      final allSites = await loadSiteConfigs();
      final defaultConfig = AggregateSearchConfig.createDefaultConfig(
        allSites.map((site) => site.id).toList(),
      );
      return AggregateSearchSettings(
        searchConfigs: [defaultConfig],
        searchThreads: 3,
      );
    }
  }
}
