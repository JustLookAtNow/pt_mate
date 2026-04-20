import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:logger/logger.dart';
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
  static String legacyQbPasswordFallbackKey(String id) =>
      'qb.password.fallback.$id';
  static String legacyQbCategoriesKey(String id) => 'qb.categories.$id';
  static String legacyQbTagsKey(String id) => 'qb.tags.$id';

  // 新的下载器配置
  static const String downloaderConfigs = 'downloader.configs';
  static const String defaultDownloaderId = 'downloader.defaultId';
  static String downloaderPasswordKey(String id) => 'downloader.password.$id';
  static String downloaderPasswordFallbackKey(String id) =>
      'downloader.password.fallback.$id';
  static String downloaderCategoriesKey(String id) =>
      'downloader.categories.$id';
  static String downloaderTagsKey(String id) => 'downloader.tags.$id';
  static String downloaderPathsKey(String id) => 'downloader.paths.$id';

  // 默认下载设置
  static const String defaultDownloadCategory = 'download.defaultCategory';
  static const String defaultDownloadTags = 'download.defaultTags';
  static const String defaultDownloadSavePath = 'download.defaultSavePath';
  static const String defaultDownloadStartPaused =
      'download.defaultStartPaused';

  // 多站点API密钥存储
  static String siteApiKey(String siteId) => 'site.apiKey.$siteId';
  static String siteApiKeyFallback(String siteId) =>
      'site.apiKey.fallback.$siteId';

  // 兼容性：旧的API密钥存储
  static const String legacySiteApiKey = 'site.apiKey';
  // 非安全存储的降级 Key（例如 Linux 桌面端 keyring 被锁定时）
  static const String legacySiteApiKeyFallback = 'site.apiKey.fallback';

  // WebDAV密码安全存储
  static String webdavPassword(String configId) => 'webdav.password.$configId';
  static String webdavPasswordFallback(String configId) =>
      'webdav.password.fallback.$configId';

  // 设备ID（与历史 DeviceIdService 使用的 key 保持一致）
  static const String deviceId = 'device_id';
  // 非安全存储的降级 Key（例如 Linux 桌面端 keyring 被锁定时）
  static const String deviceIdFallback = 'device_id.fallback';

  // 主题相关
  static const String themeMode = 'theme.mode'; // system | light | dark
  static const String themeUseDynamic = 'theme.useDynamic'; // bool
  static const String themeSeedColor = 'theme.seedColor'; // int (ARGB)

  // 图片设置
  static const String autoLoadImages = 'images.autoLoad'; // bool
  static const String showCoverImages = 'images.showCover'; // bool
  // 日志设置
  static const String logToFileEnabled = 'logging.toFile'; // bool
  // 标签显示设置
  static const String visibleTags = 'ui.visibleTags'; // List<String>

  // 聚合搜索设置
  static const String aggregateSearchSettings = 'aggregateSearch.settings';

  // 健康检查结果缓存（站点ID -> 状态JSON）
  static const String healthStatuses = 'app.healthStatuses';

  // 查询条件配置已移至站点配置中，不再需要全局键
}

enum _SecureStorageAvailability { unknown, available, unavailable }

class StorageService {
  StorageService._();
  static final StorageService instance = StorageService._();
  static final Logger _logger = Logger();
  static const Duration _secureStorageTimeout = Duration(milliseconds: 800);
  static const IOSOptions _iosSecureOptions = IOSOptions(
    accessibility: KeychainAccessibility.first_unlock_this_device,
  );
  // Android 选项配置：分别对应 RSA OAEP (Modern) 与 RSA PKCS1 (Compat)
  static const AndroidOptions _androidModernSecureOptions = AndroidOptions(
    resetOnError: false,
    migrateOnAlgorithmChange: false,
    keyCipherAlgorithm:
        KeyCipherAlgorithm.RSA_ECB_OAEPwithSHA_256andMGF1Padding,
    storageCipherAlgorithm: StorageCipherAlgorithm.AES_GCM_NoPadding,
  );
  static const AndroidOptions _androidCompatSecureOptions = AndroidOptions(
    resetOnError: false,
    migrateOnAlgorithmChange: false,
    keyCipherAlgorithm: KeyCipherAlgorithm.RSA_ECB_PKCS1Padding,
    storageCipherAlgorithm: StorageCipherAlgorithm.AES_GCM_NoPadding,
  );
  // 旧版默认格式（pre-PR#126）：PKCS1 + AES_CBC，与 const AndroidOptions() 的库默认值一致
  static const AndroidOptions _androidLegacySecureOptions = AndroidOptions(
    resetOnError: false,
    migrateOnAlgorithmChange: false,
    keyCipherAlgorithm: KeyCipherAlgorithm.RSA_ECB_PKCS1Padding,
    storageCipherAlgorithm: StorageCipherAlgorithm.AES_CBC_PKCS7Padding,
  );

  bool _hasPendingConfigUpdates = false;

  // 站点配置内存缓存
  List<SiteConfig>? _siteConfigsCache;
  bool _siteConfigsCacheDirty = true;
  bool _siteConfigsCacheNeedsUpdate = false;
  final Map<String, String?> _siteApiKeysCache = {};
  List<SiteConfig>? get siteConfigsCache => _siteConfigsCache;
  TargetPlatform? _platformOverrideForTest;
  _SecureStorageAvailability _secureStorageAvailability =
      _SecureStorageAvailability.unknown;
  bool _hasLoggedSecureStorageUnavailable = false;

  // 统一安全存储实例
  final FlutterSecureStorage _secure = const FlutterSecureStorage();

  // Android 选项序列缓存，用于根据 API 版本动态调整首选算法
  List<AndroidOptions>? _cachedAndroidOptionsSequence;

  Future<List<AndroidOptions>> _getAndroidOptionsSequence() async {
    if (_cachedAndroidOptionsSequence != null) {
      return _cachedAndroidOptionsSequence!;
    }
    if (!_isAndroidPlatform) {
      _cachedAndroidOptionsSequence = [const AndroidOptions()];
      return _cachedAndroidOptionsSequence!;
    }

    // 既然有报告称 Android 13 (API 33) 使用 OAEP 也会在重启后丢失数据，
    // 我们统一首选最稳定的 PKCS1 (Compat) 进行写入。
    // OAEP (Modern) 仅放在序列中用于尝试读取现有数据。
    _cachedAndroidOptionsSequence = [
      _androidCompatSecureOptions,  // 当前首选 (PKCS1+AES_GCM)
      _androidLegacySecureOptions,  // 旧版默认格式 (PKCS1+AES_CBC)，pre-PR#126 数据
      _androidModernSecureOptions,  // 历史回退 (OAEP+AES_GCM)
      const AndroidOptions(),       // 兜底默认
    ];
    return _cachedAndroidOptionsSequence!;
  }

  Future<SharedPreferences> get _prefs async => SharedPreferences.getInstance();

  TargetPlatform get _currentPlatform =>
      _platformOverrideForTest ?? defaultTargetPlatform;

  bool get _isAndroidPlatform =>
      !kIsWeb && _currentPlatform == TargetPlatform.android;

  bool get _shouldShortCircuitSecureStorage =>
      !kIsWeb &&
      _currentPlatform == TargetPlatform.linux &&
      _secureStorageAvailability == _SecureStorageAvailability.unavailable;

  bool _isSecureStorageFailure(Object error) {
    final message = error.toString().toLowerCase();
    return message.contains('libsecret') ||
        message.contains('unlock the keyring') ||
        message.contains('failed to unlock the keyring');
  }

  void _markSecureStorageAvailable() {
    if (kIsWeb || _currentPlatform != TargetPlatform.linux) {
      return;
    }
    if (_secureStorageAvailability == _SecureStorageAvailability.unknown) {
      _secureStorageAvailability = _SecureStorageAvailability.available;
    }
  }

  void _markSecureStorageUnavailable(Object error) {
    if (kIsWeb || _currentPlatform != TargetPlatform.linux) {
      return;
    }
    _secureStorageAvailability = _SecureStorageAvailability.unavailable;
    if (_hasLoggedSecureStorageUnavailable) {
      return;
    }
    _hasLoggedSecureStorageUnavailable = true;
    if (kDebugMode) {
      _logger.w('StorageService: Linux keyring 不可用，本次运行改用本地降级存储。error=$error');
    }
  }

  void _logSecureStorageError({
    required String operation,
    required String key,
    required Object error,
  }) {
    if (!kDebugMode) {
      return;
    }
    _logger.w(
      'StorageService: secure storage $operation failed, '
      'platform=$_currentPlatform, key=$key, error=$error',
    );
  }

  /// 统一安全存储读取：支持按序列尝试不同的加密算法（主要针对 Android 兼容性）
  Future<String?> _secureRead(String key) async {
    if (_shouldShortCircuitSecureStorage) {
      return null;
    }

    final sequence = await _getAndroidOptionsSequence();
    Object? lastError;

    for (final aOptions in sequence) {
      try {
        final value = await _secure
            .read(key: key, aOptions: aOptions, iOptions: _iosSecureOptions)
            .timeout(_secureStorageTimeout);

        if (value != null) {
          _markSecureStorageAvailable();
          // 如果使用了回退算法（非首选）读取成功，则触发静默迁移
          if (_isAndroidPlatform && aOptions != sequence.first) {
            await _secureWrite(key: key, value: value);
          }
          return value;
        }
        // null 仅代表在当前算法空间中不存在，继续尝试其他算法
      } catch (e) {
        lastError = e;
        if (_isSecureStorageFailure(e)) {
          _markSecureStorageUnavailable(e);
          return null;
        }
        // 解密失败通常意味着算法不匹配，继续尝试下一个选项
      }
      // 如果不是安卓平台，或者只有一个选项，则无需循环
      if (!_isAndroidPlatform) break;
    }

    if (lastError != null && kDebugMode && !_isAndroidPlatform) {
      _logSecureStorageError(operation: 'read', key: key, error: lastError);
    }
    return null;
  }

  /// 统一安全存储写入：使用首选的加密算法
  Future<bool> _secureWrite({
    required String key,
    required String value,
  }) async {
    if (_shouldShortCircuitSecureStorage) {
      return false;
    }

    final sequence = await _getAndroidOptionsSequence();
    final aOptions = sequence.first;

    try {
      await _secure
          .write(
            key: key,
            value: value,
            aOptions: aOptions,
            iOptions: _iosSecureOptions,
          )
          .timeout(_secureStorageTimeout);
      _markSecureStorageAvailable();
      return true;
    } catch (e) {
      if (_isSecureStorageFailure(e)) {
        _markSecureStorageUnavailable(e);
      } else {
        _logSecureStorageError(operation: 'write', key: key, error: e);
      }
      return false;
    }
  }

  /// 统一安全存储删除：从首选的 SharedPreferences 配置中删除（由于键名相同，只需删除一次）
  Future<bool> _secureDelete({required String key}) async {
    if (_shouldShortCircuitSecureStorage) {
      return false;
    }

    final sequence = await _getAndroidOptionsSequence();
    try {
      await _secure
          .delete(
            key: key,
            aOptions: sequence.first,
            iOptions: _iosSecureOptions,
          )
          .timeout(_secureStorageTimeout);
      _markSecureStorageAvailable();
      return true;
    } catch (e) {
      if (_isSecureStorageFailure(e)) {
        _markSecureStorageUnavailable(e);
      } else {
        _logSecureStorageError(operation: 'delete', key: key, error: e);
      }
      return false;
    }
  }

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
        final qbConfigs = (jsonDecode(qbConfigsStr) as List)
            .cast<Map<String, dynamic>>();
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
        await prefs.setString(
          StorageKeys.downloaderConfigs,
          jsonEncode(downloaderConfigs),
        );

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
          _logger.e('数据迁移失败: $e');
        }
      }
    }
  }

  /// 迁移密码
  Future<void> _migratePassword(String clientId) async {
    // 尝试从安全存储读取旧密码
    final oldPassword = await _secureRead(
      StorageKeys.legacyQbPasswordKey(clientId),
    );
    if (oldPassword != null && oldPassword.isNotEmpty) {
      await saveDownloaderPassword(clientId, oldPassword);
      await _secureDelete(key: StorageKeys.legacyQbPasswordKey(clientId));
      return;
    }

    try {
      // 尝试从降级存储读取旧密码
      final prefs = await _prefs;
      final oldPassword = prefs.getString(
        StorageKeys.legacyQbPasswordFallbackKey(clientId),
      );
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
      final oldCategories = prefs.getString(
        StorageKeys.legacyQbCategoriesKey(clientId),
      );
      if (oldCategories != null) {
        await prefs.setString(
          StorageKeys.downloaderCategoriesKey(clientId),
          oldCategories,
        );
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
    // 由于SiteConfig.fromJson已经具备向前兼容性，
    // 现有的站点配置可以无缝使用新的多URL模板系统
    // 这里不需要特殊的数据迁移逻辑
    try {
      if (kDebugMode) {
        _logger.i('数据迁移: 1.1.0 -> 1.2.0 (多URL模板支持)');
      }
    } catch (e) {
      // 迁移失败时记录错误，但不阻塞应用启动
      if (kDebugMode) {
        _logger.e('数据迁移失败: $e');
      }
    }
  }

  // Site config
  Future<void> saveSite(SiteConfig config) async {
    final prefs = await _prefs;
    await prefs.setString(StorageKeys.siteConfig, jsonEncode(config.toJson()));
    // secure parts
    if ((config.apiKey ?? '').isNotEmpty) {
      final wrote = await _secureWrite(
        key: StorageKeys.legacySiteApiKey,
        value: config.apiKey!,
      );
      if (wrote) {
        // 清理降级存储
        await prefs.remove(StorageKeys.legacySiteApiKeyFallback);
      } else {
        // 当桌面环境的 keyring 被锁定或不可用时，降级到本地存储，避免崩溃
        await prefs.setString(
          StorageKeys.legacySiteApiKeyFallback,
          config.apiKey!,
        );
      }
    } else {
      await _secureDelete(key: StorageKeys.legacySiteApiKey);
      // 同步清理降级存储
      await prefs.remove(StorageKeys.legacySiteApiKeyFallback);
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
      apiKey = await _secureRead(StorageKeys.legacySiteApiKey);
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
    final jsonList = configs
        .map(
          (config) => {
            ...config.toJson(),
            'apiKey': null, // API密钥单独存储
          },
        )
        .toList();
    await prefs.setString(StorageKeys.siteConfigs, jsonEncode(jsonList));

    // 保存每个站点的API密钥
    for (final config in configs) {
      // 仅当传入的 apiKey 非空时才更新安全存储；
      // 为 null 表示“不修改当前存储的密钥”，避免误删其他站点的密钥。
      if (config.apiKey != null) {
        await _saveSiteApiKey(config.id, config.apiKey);
        // 更新内存中的 apiKey 缓存
        _siteApiKeysCache[config.id] = config.apiKey;
      }
    }

    // 更新基础配置缓存（不含 apiKey），避免下一次再次解析 JSON
    _siteConfigsCache = configs.map((c) => c.copyWith(apiKey: null)).toList();
    _siteConfigsCacheDirty = false;
    _siteConfigsCacheNeedsUpdate = false;
  }

  Future<List<SiteConfig>> loadSiteConfigs({
    bool includeApiKeys = false,
  }) async {
    final swTotal = Stopwatch()..start();
    try {
      final prefs = await _prefs;
      final str = prefs.getString(StorageKeys.siteConfigs);
      if (str == null) {
        // 清空缓存并返回空
        _siteConfigsCache = null;
        _siteConfigsCacheDirty = true;
        _siteConfigsCacheNeedsUpdate = false;
        return [];
      }

      List<SiteConfig> baseConfigs;
      bool hasUpdates;

      if (_siteConfigsCache != null && !_siteConfigsCacheDirty) {
        // 使用缓存的基础配置与更新标记
        baseConfigs = _siteConfigsCache!;
        hasUpdates = _siteConfigsCacheNeedsUpdate;
        if (kDebugMode) {
          _logger.d(
            'StorageService.loadSiteConfigs: 使用内存缓存，includeApiKeys=$includeApiKeys',
          );
        }
      } else {
        // 重新解析 JSON
        final List<dynamic> jsonList = jsonDecode(str);
        baseConfigs = <SiteConfig>[];
        hasUpdates = false;
        int idx = 0;

        for (final json in jsonList) {
          final swItem = Stopwatch()..start();
          final result = await SiteConfig.fromJsonAsync(json);
          swItem.stop();
          if (kDebugMode) {
            _logger.d(
              'StorageService.loadSiteConfigs: 第${idx + 1}个站点 fromJsonAsync 耗时=${swItem.elapsedMilliseconds}ms，templateId=${result.config.templateId}，needsUpdate=${result.needsUpdate}',
            );
          }
          baseConfigs.add(result.config);
          idx++;
          if (result.needsUpdate) {
            hasUpdates = true;
          }
        }

        // 更新缓存
        _siteConfigsCache = baseConfigs;
        _siteConfigsCacheDirty = false;
        _siteConfigsCacheNeedsUpdate = hasUpdates;
      }

      // 根据 includeApiKeys 构造返回列表
      final List<SiteConfig> configs = <SiteConfig>[];
      int idx = 0;
      for (final cfg in baseConfigs) {
        SiteConfig finalConfig;
        if (includeApiKeys) {
          final swKey = Stopwatch()..start();
          String? apiKey;
          if (_siteApiKeysCache.containsKey(cfg.id)) {
            apiKey = _siteApiKeysCache[cfg.id];
          } else {
            apiKey = await _loadSiteApiKey(cfg.id);
            _siteApiKeysCache[cfg.id] = apiKey; // 缓存读取结果（可为 null）
          }
          swKey.stop();
          if (kDebugMode) {
            _logger.d(
              'StorageService.loadSiteConfigs: 第${idx + 1}个站点 加载API密钥耗时=${swKey.elapsedMilliseconds}ms',
            );
          }
          finalConfig = cfg.copyWith(apiKey: apiKey);
        } else {
          finalConfig = cfg;
        }
        configs.add(finalConfig);
        idx++;
      }

      // 持久化模板更新：仅在 includeApiKeys=true 时执行
      if (hasUpdates && includeApiKeys) {
        final swSave = Stopwatch()..start();
        await saveSiteConfigs(configs);
        swSave.stop();
        if (kDebugMode) {
          _logger.d(
            'StorageService.loadSiteConfigs: 保存更新耗时=${swSave.elapsedMilliseconds}ms',
          );
        }
      } else if (hasUpdates && !includeApiKeys) {
        _hasPendingConfigUpdates = true;
        if (kDebugMode) {
          _logger.i(
            'StorageService.loadSiteConfigs: 检测到配置需要更新，但已跳过保存以避免清除API密钥（稍后持久化）',
          );
        }
      }

      swTotal.stop();
      if (kDebugMode) {
        _logger.d(
          'StorageService.loadSiteConfigs: 总耗时=${swTotal.elapsedMilliseconds}ms',
        );
      }

      return configs;
    } catch (_) {
      return [];
    }
  }

  Future<void> addSiteConfig(SiteConfig config) async {
    final configs = await loadSiteConfigs(includeApiKeys: false);
    // 新增时，避免触碰其他站点密钥；仅处理当前新增站点的密钥
    configs.add(config.copyWith(apiKey: null));
    await saveSiteConfigs(configs);
    // 单独保存新增站点密钥（若提供）
    if (config.apiKey != null) {
      await _saveSiteApiKey(config.id, config.apiKey);
      _siteApiKeysCache[config.id] = config.apiKey; // 更新缓存
    }
  }

  Future<void> updateSiteConfig(SiteConfig config) async {
    final configs = await loadSiteConfigs(includeApiKeys: false);
    final index = configs.indexWhere((c) => c.id == config.id);
    if (index >= 0) {
      // 更新列表时，将其他站点的 apiKey 保持为 null，避免被 saveSiteConfigs 误操作
      configs[index] = config.copyWith(apiKey: null);
      await saveSiteConfigs(configs);
      // 单独更新当前站点密钥（如果提供）
      if (config.apiKey != null) {
        await _saveSiteApiKey(config.id, config.apiKey);
        _siteApiKeysCache[config.id] = config.apiKey; // 更新缓存
      }
    }
  }

  Future<void> deleteSiteConfig(String siteId) async {
    final configs = await loadSiteConfigs();
    configs.removeWhere((c) => c.id == siteId);
    // 删除站点后保存其余站点配置，但不传递 apiKey（保持为 null），
    // 以避免在未加载密钥的场景下误删其他站点的密钥。
    await saveSiteConfigs(
      configs.map((c) => c.copyWith(apiKey: null)).toList(),
    );
    await _deleteSiteApiKey(siteId);
    _siteApiKeysCache.remove(siteId); // 移除缓存中的 apiKey

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

    // 加载站点配置但跳过API密钥，随后仅为活跃站点读取密钥
    final configs = await loadSiteConfigs(includeApiKeys: false);
    try {
      final base = configs.firstWhere((c) => c.id == activeSiteId);
      final apiKey = await _loadSiteApiKey(activeSiteId);
      return base.copyWith(apiKey: apiKey);
    } catch (_) {
      return null;
    }
  }

  // 私有方法：处理单个站点的API密钥
  Future<void> _saveSiteApiKey(String siteId, String? apiKey) async {
    // 为 null：不触碰现有密钥（用于避免在未加载密钥的情况下误删）
    if (apiKey == null) {
      return;
    }
    // 为空字符串：明确删除该站点密钥（用户清空字段）
    if (apiKey.isEmpty) {
      await _deleteSiteApiKey(siteId);
      return;
    }

    final wrote = await _secureWrite(
      key: StorageKeys.siteApiKey(siteId),
      value: apiKey,
    );
    if (wrote) {
      // 清理降级存储
      final prefs = await _prefs;
      await prefs.remove(StorageKeys.siteApiKeyFallback(siteId));
    } else {
      // 降级到本地存储
      final prefs = await _prefs;
      await prefs.setString(StorageKeys.siteApiKeyFallback(siteId), apiKey);
    }
  }

  Future<String?> _loadSiteApiKey(String siteId) async {
    try {
      final apiKey = await _secureRead(StorageKeys.siteApiKey(siteId));
      if (apiKey != null && apiKey.isNotEmpty) return apiKey;
    } catch (_) {
      // ignore and try fallback
    }

    final prefs = await _prefs;
    return prefs.getString(StorageKeys.siteApiKeyFallback(siteId));
  }

  Future<void> _deleteSiteApiKey(String siteId) async {
    await _secureDelete(key: StorageKeys.siteApiKey(siteId));

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

  // 封面图片显示设置
  Future<void> saveShowCoverImages(bool show) async {
    final prefs = await _prefs;
    await prefs.setBool(StorageKeys.showCoverImages, show);
  }

  Future<bool> loadShowCoverImages() async {
    final prefs = await _prefs;
    return prefs.getBool(StorageKeys.showCoverImages) ?? true; // 默认自动显示
  }

  Future<void> saveLogToFileEnabled(bool enabled) async {
    final prefs = await _prefs;
    await prefs.setBool(StorageKeys.logToFileEnabled, enabled);
  }

  Future<bool> loadLogToFileEnabled() async {
    final prefs = await _prefs;
    return prefs.getBool(StorageKeys.logToFileEnabled) ?? false;
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

    final wrote = await _secureWrite(
      key: StorageKeys.webdavPassword(configId),
      value: password,
    );
    if (wrote) {
      // 清理降级存储
      final prefs = await _prefs;
      await prefs.remove(StorageKeys.webdavPasswordFallback(configId));
    } else {
      // 当桌面环境的 keyring 被锁定或不可用时，降级到本地存储，避免崩溃
      final prefs = await _prefs;
      await prefs.setString(
        StorageKeys.webdavPasswordFallback(configId),
        password,
      );
    }
  }

  Future<String?> loadWebDAVPassword(String configId) async {
    try {
      final password = await _secureRead(StorageKeys.webdavPassword(configId));
      if (password != null && password.isNotEmpty) return password;
    } catch (_) {
      // 读取失败时，从降级存储取值
    }

    // 若安全存储读取到的值为空或为 null，则继续尝试降级存储
    final prefs = await _prefs;
    final fallback = prefs.getString(
      StorageKeys.webdavPasswordFallback(configId),
    );
    if (fallback != null && fallback.isNotEmpty) {
      return fallback;
    }

    return null;
  }

  Future<void> deleteWebDAVPassword(String configId) async {
    await _secureDelete(key: StorageKeys.webdavPassword(configId));

    final prefs = await _prefs;
    await prefs.remove(StorageKeys.webdavPasswordFallback(configId));
  }

  // 聚合搜索设置相关
  Future<void> saveAggregateSearchSettings(
    AggregateSearchSettings settings,
  ) async {
    final prefs = await _prefs;
    await prefs.setString(
      StorageKeys.aggregateSearchSettings,
      jsonEncode(settings.toJson()),
    );
  }

  Future<AggregateSearchSettings> loadAggregateSearchSettings() async {
    final prefs = await _prefs;
    final str = prefs.getString(StorageKeys.aggregateSearchSettings);
    if (str == null) {
      // 返回默认设置，包含一个"全部站点"的默认配置
      final allSites = await loadSiteConfigs(includeApiKeys: false);
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
      final allSites = await loadSiteConfigs(includeApiKeys: false);
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
  Future<void> saveDownloaderConfigs(
    List<DownloaderConfig> configs, {
    String? defaultId,
  }) async {
    final prefs = await _prefs;
    final jsonList = configs.map((config) => config.toJson()).toList();

    await prefs.setString(StorageKeys.downloaderConfigs, jsonEncode(jsonList));

    if (defaultId != null) {
      await prefs.setString(StorageKeys.defaultDownloaderId, defaultId);
    } else {
      await prefs.remove(StorageKeys.defaultDownloaderId);
    }
  }

  // 标签显示设置
  List<String>? _visibleTagsCache;
  List<String> get visibleTags => _visibleTagsCache ?? [];

  Future<void> saveVisibleTags(List<String> tags) async {
    final prefs = await _prefs;
    await prefs.setStringList(StorageKeys.visibleTags, tags);
    _visibleTagsCache = tags;
  }

  Future<void> loadVisibleTags() async {
    final prefs = await _prefs;
    _visibleTagsCache = prefs.getStringList(StorageKeys.visibleTags);
    // 如果没有保存过设置，默认显示所有标签
    _visibleTagsCache ??= TagType.values.map((e) => e.name).toList();
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
    final wrote = await _secureWrite(
      key: StorageKeys.downloaderPasswordKey(id),
      value: password,
    );
    if (wrote) {
      // 清理可能存在的降级存储
      final prefs = await _prefs;
      await prefs.remove(StorageKeys.downloaderPasswordFallbackKey(id));
    } else {
      // 在 Linux 桌面端等环境，可能出现 keyring 未解锁；降级写入本地存储，避免功能中断
      final prefs = await _prefs;
      await prefs.setString(
        StorageKeys.downloaderPasswordFallbackKey(id),
        password,
      );
    }
  }

  Future<String?> loadDownloaderPassword(String id) async {
    try {
      final password = await _secureRead(StorageKeys.downloaderPasswordKey(id));
      if (password != null && password.isNotEmpty) return password;
    } catch (_) {
      // 读取失败时，从降级存储取值
    }

    // 若安全存储读取到的值为空或为 null，则继续尝试降级存储
    final prefs = await _prefs;
    final fallback = prefs.getString(
      StorageKeys.downloaderPasswordFallbackKey(id),
    );
    if (fallback != null && fallback.isNotEmpty) {
      return fallback;
    }

    return null;
  }

  Future<void> deleteDownloaderPassword(String id) async {
    await _secureDelete(key: StorageKeys.downloaderPasswordKey(id));
    final prefs = await _prefs;
    await prefs.remove(StorageKeys.downloaderPasswordFallbackKey(id));
  }

  // 下载器分类与标签的本地缓存
  Future<void> saveDownloaderCategories(
    String id,
    List<String> categories,
  ) async {
    final prefs = await _prefs;
    await prefs.setStringList(
      StorageKeys.downloaderCategoriesKey(id),
      categories,
    );
  }

  Future<List<String>> loadDownloaderCategories(String id) async {
    final prefs = await _prefs;
    return prefs.getStringList(StorageKeys.downloaderCategoriesKey(id)) ??
        <String>[];
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
    return prefs.getStringList(StorageKeys.downloaderPathsKey(id)) ??
        <String>[];
  }

  // 设备ID统一读写删除（使用安全存储，支持旧存储兼容与自动迁移；在桌面环境等不可用时降级到本地存储）
  Future<void> saveDeviceId(String deviceId) async {
    final wrote = await _secureWrite(
      key: StorageKeys.deviceId,
      value: deviceId,
    );
    if (wrote) {
      // 清理降级存储
      final prefs = await _prefs;
      await prefs.remove(StorageKeys.deviceIdFallback);
    } else {
      // 降级到本地存储，避免因 keyring 未解锁导致崩溃
      final prefs = await _prefs;
      await prefs.setString(StorageKeys.deviceIdFallback, deviceId);
    }
  }

  Future<String?> loadDeviceId() async {
    try {
      final id = await _secureRead(StorageKeys.deviceId);
      if (id != null && id.isNotEmpty) return id;
    } catch (_) {
      // 忽略错误，尝试降级存储
    }
    final prefs = await _prefs;
    final fallback = prefs.getString(StorageKeys.deviceIdFallback);
    if (fallback != null && fallback.isNotEmpty) {
      return fallback;
    }
    return null;
  }

  Future<void> deleteDeviceId() async {
    await _secureDelete(key: StorageKeys.deviceId);

    final prefs = await _prefs;
    await prefs.remove(StorageKeys.deviceIdFallback);
  }

  @visibleForTesting
  void resetForTest() {
    _hasPendingConfigUpdates = false;
    _siteConfigsCache = null;
    _siteConfigsCacheDirty = true;
    _siteConfigsCacheNeedsUpdate = false;
    _siteApiKeysCache.clear();
    _visibleTagsCache = null;
    _platformOverrideForTest = null;
    _secureStorageAvailability = _SecureStorageAvailability.unknown;
    _hasLoggedSecureStorageUnavailable = false;
  }

  @visibleForTesting
  void overridePlatformForTest(TargetPlatform? platform) {
    _platformOverrideForTest = platform;
  }

  @visibleForTesting
  bool get isSecureStorageBypassedForCurrentRun =>
      _secureStorageAvailability == _SecureStorageAvailability.unavailable;

  /// 如果有待处理的配置更新，则执行持久化
  Future<void> persistPendingConfigUpdates() async {
    if (_hasPendingConfigUpdates) {
      if (kDebugMode) {
        _logger.i('StorageService: 开始持久化待处理的站点配置更新...');
      }
      // 通过全量加载（包含API密钥）来触发保存逻辑
      await loadSiteConfigs(includeApiKeys: true);
      _hasPendingConfigUpdates = false;
      if (kDebugMode) {
        _logger.i('StorageService: 待处理的站点配置更新已持久化。');
      }
    }
  }

  // 健康检查结果缓存：保存与读取
  Future<void> saveHealthStatuses(
    Map<String, Map<String, dynamic>> statuses,
  ) async {
    final prefs = await _prefs;
    try {
      await prefs.setString(StorageKeys.healthStatuses, jsonEncode(statuses));
    } catch (_) {
      // ignore parse/store errors
    }
  }

  Future<Map<String, Map<String, dynamic>>> loadHealthStatuses() async {
    final prefs = await _prefs;
    final str = prefs.getString(StorageKeys.healthStatuses);
    if (str == null) return <String, Map<String, dynamic>>{};
    try {
      final decoded = jsonDecode(str);
      if (decoded is Map) {
        // 强制转换为 Map<String, Map<String, dynamic>>
        return decoded.map((key, value) {
          final k = key.toString();
          final v = (value is Map)
              ? value.cast<String, dynamic>()
              : <String, dynamic>{};
          return MapEntry(k, v);
        });
      }
    } catch (_) {
      // ignore decode errors
    }
    return <String, Map<String, dynamic>>{};
  }
}
