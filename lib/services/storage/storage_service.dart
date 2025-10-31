import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/app_models.dart';
import '../downloader/downloader_config.dart';

class StorageKeys {
  // 应用版本管理
  static const String appVersion = 'app.version'; // 存储应用数据版本
  
  // 多站点配置
  static const String siteConfigs = 'app.sites'; // 存储所有站点配置
  static const String activeSiteId = 'app.activeSiteId'; // 当前活跃站点ID
  
  // 兼容性：旧的单站点配置（用于迁移）
  static const String siteConfig = 'app.site';
  
  // 兼容性：旧的qBittorrent配置（用于迁移）
  static const String legacyQbClientConfigs = 'qb.clients';
  static const String legacyDefaultQbId = 'qb.defaultId';
  static String legacyQbPasswordKey(String id) => 'qb.password.$id';
  static String legacyQbPasswordFallbackKey(String id) => 'qb.password.fallback.$id';
  static String legacyQbCategoriesKey(String id) => 'qb.categories.$id';
  static String legacyQbTagsKey(String id) => 'qb.tags.$id';
  
  // 新的下载器配置
  static const String downloaderConfigs = 'downloader.configs';
  static const String defaultDownloaderId = 'downloader.defaultId';
  static String downloaderPasswordKey(String id) => 'downloader.password.$id';
  static String downloaderPasswordFallbackKey(String id) => 'downloader.password.fallback.$id';
  static String downloaderCategoriesKey(String id) => 'downloader.categories.$id';
  static String downloaderTagsKey(String id) => 'downloader.tags.$id';
  static String downloaderPathsKey(String id) => 'downloader.paths.$id';
  
  // 默认下载设置
  static const String defaultDownloadCategory = 'download.defaultCategory';
  static const String defaultDownloadTags = 'download.defaultTags';
  static const String defaultDownloadSavePath = 'download.defaultSavePath';
  static const String defaultDownloadStartPaused = 'download.defaultStartPaused';

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

  // 版本管理
  static const String currentVersion = '1.2.0';
  
  /// 检查并执行数据迁移
  Future<void> checkAndMigrate() async {
    final prefs = await _prefs;
    final storedVersion = prefs.getString(StorageKeys.appVersion);
    
    if (storedVersion == null) {
      // 首次安装或从1.0.0升级（1.0.0版本没有版本标记）
      await _migrateFrom100To110();
      await prefs.setString(StorageKeys.appVersion, currentVersion);
    } else if (storedVersion != currentVersion) {
      // 处理其他版本迁移
      if (storedVersion == '1.0.0') {
        await _migrateFrom100To110();
      } else if (storedVersion == '1.1.0') {
        await _migrateFrom110To120();
      }
      await prefs.setString(StorageKeys.appVersion, currentVersion);
    }
  }
  
  /// 从1.0.0迁移到1.1.0
  Future<void> _migrateFrom100To110() async {
    final prefs = await _prefs;
    
    // 迁移qBittorrent配置到下载器配置
    final qbConfigsStr = prefs.getString(StorageKeys.legacyQbClientConfigs);
    if (qbConfigsStr != null) {
      try {
        final qbConfigs = (jsonDecode(qbConfigsStr) as List).cast<Map<String, dynamic>>();
        final downloaderConfigs = <Map<String, dynamic>>[];
        
        for (final qbConfig in qbConfigs) {
          // 转换为新的下载器配置格式
          final downloaderConfig = {
            'id': qbConfig['id'] ?? '',
            'name': qbConfig['name'] ?? '',
            'type': 'qbittorrent',
            'config': {
              'host': qbConfig['host'] ?? '',
              'port': qbConfig['port'] ?? 8080,
              'username': qbConfig['username'] ?? '',
              'useLocalRelay': qbConfig['useLocalRelay'] ?? false,
              'version': qbConfig['version'] ?? '',
            },
          };
          downloaderConfigs.add(downloaderConfig);
          
          // 迁移密码
          final clientId = qbConfig['id'] as String?;
          if (clientId != null && clientId.isNotEmpty) {
            await _migratePassword(clientId);
            await _migrateCategories(clientId);
            await _migrateTags(clientId);
          }
        }
        
        // 保存新的下载器配置
        await prefs.setString(StorageKeys.downloaderConfigs, jsonEncode(downloaderConfigs));
        
        // 迁移默认下载器ID
        final defaultQbId = prefs.getString(StorageKeys.legacyDefaultQbId);
        if (defaultQbId != null) {
          await prefs.setString(StorageKeys.defaultDownloaderId, defaultQbId);
        }
        
        // 清理旧配置
        await prefs.remove(StorageKeys.legacyQbClientConfigs);
        await prefs.remove(StorageKeys.legacyDefaultQbId);
        
      } catch (e) {
         // 迁移失败时记录错误，但不阻塞应用启动
         if (kDebugMode) {
           print('数据迁移失败: $e');
         }
       }
    }
  }
  
  /// 迁移密码
  Future<void> _migratePassword(String clientId) async {
    try {
      // 尝试从安全存储读取旧密码
      final oldPassword = await _secure.read(key: StorageKeys.legacyQbPasswordKey(clientId));
      if (oldPassword != null && oldPassword.isNotEmpty) {
        await _secure.write(key: StorageKeys.downloaderPasswordKey(clientId), value: oldPassword);
        await _secure.delete(key: StorageKeys.legacyQbPasswordKey(clientId));
        return;
      }
    } catch (_) {
      // 安全存储读取失败，尝试从降级存储读取
    }
    
    try {
      // 尝试从降级存储读取旧密码
      final prefs = await _prefs;
      final oldPassword = prefs.getString(StorageKeys.legacyQbPasswordFallbackKey(clientId));
      if (oldPassword != null && oldPassword.isNotEmpty) {
        await saveDownloaderPassword(clientId, oldPassword);
        await prefs.remove(StorageKeys.legacyQbPasswordFallbackKey(clientId));
      }
    } catch (_) {
      // 降级存储读取失败，忽略
    }
  }
  
  /// 迁移分类缓存
  Future<void> _migrateCategories(String clientId) async {
    try {
      final prefs = await _prefs;
      final oldCategories = prefs.getString(StorageKeys.legacyQbCategoriesKey(clientId));
      if (oldCategories != null) {
        await prefs.setString(StorageKeys.downloaderCategoriesKey(clientId), oldCategories);
        await prefs.remove(StorageKeys.legacyQbCategoriesKey(clientId));
      }
    } catch (_) {
      // 迁移失败，忽略
    }
  }
  
  /// 迁移标签缓存
  Future<void> _migrateTags(String clientId) async {
    try {
      final prefs = await _prefs;
      final oldTags = prefs.getString(StorageKeys.legacyQbTagsKey(clientId));
      if (oldTags != null) {
        await prefs.setString(StorageKeys.downloaderTagsKey(clientId), oldTags);
        await prefs.remove(StorageKeys.legacyQbTagsKey(clientId));
      }
    } catch (_) {
      // 迁移失败，忽略
    }
  }

  /// 从1.1.0迁移到1.2.0
  Future<void> _migrateFrom110To120() async {
    // 1.2.0版本主要添加了多URL模板支持
    // 由于SiteConfig.fromJson已经具备向后兼容性，
    // 现有的站点配置可以无缝使用新的多URL模板系统
    // 这里不需要特殊的数据迁移逻辑
    try {
      if (kDebugMode) {
        print('数据迁移: 1.1.0 -> 1.2.0 (多URL模板支持)');
      }
    } catch (e) {
      // 迁移失败时记录错误，但不阻塞应用启动
      if (kDebugMode) {
        print('数据迁移失败: $e');
      }
    }
  }

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
      bool hasUpdates = false;
      
      for (final json in list) {
        final result = await SiteConfig.fromJsonAsync(json);
        final apiKey = await _loadSiteApiKey(result.config.id);
        final finalConfig = result.config.copyWith(apiKey: apiKey);
        configs.add(finalConfig);
        
        // 如果templateId被更新了，标记需要重新保存
        if (result.needsUpdate) {
          hasUpdates = true;
        }
      }
      
      // 如果有配置被更新，重新保存到持久化存储
      if (hasUpdates) {
        await saveSiteConfigs(configs);
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

  /// 保存“添加后暂停”默认设置
  Future<void> saveDefaultDownloadStartPaused(bool startPaused) async {
    final prefs = await _prefs;
    await prefs.setBool(StorageKeys.defaultDownloadStartPaused, startPaused);
  }

  /// 读取“添加后暂停”默认设置（默认 false）
  Future<bool> loadDefaultDownloadStartPaused() async {
    final prefs = await _prefs;
    return prefs.getBool(StorageKeys.defaultDownloadStartPaused) ?? false;
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

  // 新的下载器配置管理方法
  Future<void> saveDownloaderConfigs(List<DownloaderConfig> configs, {String? defaultId}) async {
    final prefs = await _prefs;
    final jsonList = configs.map((config) => config.toJson()).toList();
    
    await prefs.setString(StorageKeys.downloaderConfigs, jsonEncode(jsonList));
    
    if (defaultId != null) {
      await prefs.setString(StorageKeys.defaultDownloaderId, defaultId);
    } else {
      await prefs.remove(StorageKeys.defaultDownloaderId);
    }
  }

  Future<List<Map<String, dynamic>>> loadDownloaderConfigs() async {
    final prefs = await _prefs;
    final str = prefs.getString(StorageKeys.downloaderConfigs);
    if (str == null) return [];
    
    try {
      final list = (jsonDecode(str) as List).cast<Map<String, dynamic>>();
      return list;
    } catch (_) {
      return [];
    }
  }

  Future<String?> loadDefaultDownloaderId() async {
    final prefs = await _prefs;
    return prefs.getString(StorageKeys.defaultDownloaderId);
  }

  Future<void> saveDownloaderPassword(String id, String password) async {
    try {
      await _secure.write(key: StorageKeys.downloaderPasswordKey(id), value: password);
      // 清理可能存在的降级存储
      final prefs = await _prefs;
      await prefs.remove(StorageKeys.downloaderPasswordFallbackKey(id));
    } catch (_) {
      // 在 Linux 桌面端等环境，可能出现 keyring 未解锁；降级写入本地存储，避免功能中断
      final prefs = await _prefs;
      await prefs.setString(StorageKeys.downloaderPasswordFallbackKey(id), password);
    }
  }

  Future<String?> loadDownloaderPassword(String id) async {
    try {
      final password = await _secure.read(key: StorageKeys.downloaderPasswordKey(id));
      if (password != null && password.isNotEmpty) return password;
    } catch (_) {
      // 读取失败时，从降级存储取值
    }
    
    // 若安全存储读取到的值为空或为 null，则继续尝试降级存储
    final prefs = await _prefs;
    final fallback = prefs.getString(StorageKeys.downloaderPasswordFallbackKey(id));
    if (fallback != null && fallback.isNotEmpty) {
      return fallback;
    }
    
    return null;
  }

  Future<void> deleteDownloaderPassword(String id) async {
    try {
      await _secure.delete(key: StorageKeys.downloaderPasswordKey(id));
    } catch (_) {
      // ignore
    }
    final prefs = await _prefs;
    await prefs.remove(StorageKeys.downloaderPasswordFallbackKey(id));
  }

  // 下载器分类与标签的本地缓存
  Future<void> saveDownloaderCategories(String id, List<String> categories) async {
    final prefs = await _prefs;
    await prefs.setStringList(StorageKeys.downloaderCategoriesKey(id), categories);
  }

  Future<List<String>> loadDownloaderCategories(String id) async {
    final prefs = await _prefs;
    return prefs.getStringList(StorageKeys.downloaderCategoriesKey(id)) ?? <String>[];
  }

  Future<void> saveDownloaderTags(String id, List<String> tags) async {
    final prefs = await _prefs;
    await prefs.setStringList(StorageKeys.downloaderTagsKey(id), tags);
  }

  Future<List<String>> loadDownloaderTags(String id) async {
    final prefs = await _prefs;
    return prefs.getStringList(StorageKeys.downloaderTagsKey(id)) ?? <String>[];
  }

  Future<void> saveDownloaderPaths(String id, List<String> paths) async {
    final prefs = await _prefs;
    await prefs.setStringList(StorageKeys.downloaderPathsKey(id), paths);
  }

  Future<List<String>> loadDownloaderPaths(String id) async {
    final prefs = await _prefs;
    return prefs.getStringList(StorageKeys.downloaderPathsKey(id)) ?? <String>[];
  }
}
