import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/app_models.dart';

class StorageKeys {
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

  static const String siteApiKey = 'site.apiKey';
  // 非安全存储的降级 Key（例如 Linux 桌面端 keyring 被锁定时）
  static const String siteApiKeyFallback = 'site.apiKey.fallback';

  // 主题相关
  static const String themeMode = 'theme.mode'; // system | light | dark
  static const String themeUseDynamic = 'theme.useDynamic'; // bool
  static const String themeSeedColor = 'theme.seedColor'; // int (ARGB)
  
  // 图片设置
  static const String autoLoadImages = 'images.autoLoad'; // bool
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
        await _secure.write(key: StorageKeys.siteApiKey, value: config.apiKey);
        // 清理降级存储
        await prefs.remove(StorageKeys.siteApiKeyFallback);
      } catch (_) {
        // 当桌面环境的 keyring 被锁定或不可用时，降级到本地存储，避免崩溃
        await prefs.setString(StorageKeys.siteApiKeyFallback, config.apiKey!);
      }
    } else {
      try {
        await _secure.delete(key: StorageKeys.siteApiKey);
      } catch (_) {
        // 同步清理降级存储
        await prefs.remove(StorageKeys.siteApiKeyFallback);
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
      apiKey = await _secure.read(key: StorageKeys.siteApiKey);
    } catch (_) {
      // 读取失败时，从降级存储取值
      apiKey = prefs.getString(StorageKeys.siteApiKeyFallback);
    }
    // 若安全存储读取到的值为空或为 null，则继续尝试降级存储
    if (apiKey == null || apiKey.isEmpty) {
      final fallback = prefs.getString(StorageKeys.siteApiKeyFallback);
      if (fallback != null && fallback.isNotEmpty) {
        apiKey = fallback;
      }
    }

    return base.copyWith(apiKey: apiKey);
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
}
