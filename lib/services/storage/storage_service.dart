import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:logger/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/app_models.dart';
import '../downloader/downloader_config.dart';
import '../logging/log_file_service.dart';
import 'android_secure_storage_profile_resolver.dart';
import 'secure_storage_transaction.dart';
import 'storage_permission_helper.dart';

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
  static String legacyQbPasswordConflictMarker(String id) =>
      'secureStorage.migrationConflict.qbPassword.$id';
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
  static const String localDownloadLastDirectory =
      'download.localLastDirectory';
  static const String defaultDownloadToLocal = 'download.defaultToLocal';
  static const String defaultDownloadStartPaused =
      'download.defaultStartPaused';

  // 多站点API密钥存储
  static String siteApiKey(String siteId) => 'site.apiKey.$siteId';
  static String siteApiKeyFallback(String siteId) =>
      'site.apiKey.fallback.$siteId';

  // 多站点 Cookie 安全存储
  static String siteCookie(String siteId) => 'site.cookie.$siteId';
  static String siteCookieFallback(String siteId) =>
      'site.cookie.fallback.$siteId';

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
  static const String lastSiteHealthRefreshCheck =
      'app.lastSiteHealthRefreshCheck';

  // 查询条件配置已移至站点配置中，不再需要全局键

  // 网络代理设置
  static const String proxyEnabled = 'network.proxyEnabled'; // bool
  static const String proxyHost = 'network.proxyHost'; // String
  static const String proxyPort = 'network.proxyPort'; // int
  static const String proxyUsername = 'network.proxyUsername'; // String
  static const String proxyPassword = 'network.proxyPassword'; // String
  static const String proxyPasswordFallback =
      'network.proxyPassword.fallback'; // String
  static const String proxyBypassLan = 'network.proxyBypassLan'; // bool
  static const String proxyBypassRules =
      'network.proxyBypassRules'; // List<String>

  // Cookie Cloud 同步设置
  static const String cookieCloudUrl = 'cookieCloud.url';
  static const String cookieCloudUrlFallback = 'cookieCloud.url.fallback';
  static const String cookieCloudUuid = 'cookieCloud.uuid';
  static const String cookieCloudUuidFallback = 'cookieCloud.uuid.fallback';
  static const String cookieCloudPassword = 'cookieCloud.password';
  static const String cookieCloudPasswordFallback =
      'cookieCloud.password.fallback';
  static const String cookieCloudSecretsV2 = 'cookieCloud.secrets.v2';
  static const String cookieCloudSecretsV2Fallback =
      'cookieCloud.secrets.v2.fallback';
  static const String cookieCloudSecretsV2PendingCleanup =
      'cookieCloud.secrets.v2.pendingCleanup';
  static const String cookieCloudAutoSyncEnabled = 'cookieCloud.autoSync';
  static const String cookieCloudSyncIntervalMinutes =
      'cookieCloud.syncIntervalMinutes';
  static const String cookieCloudLastSyncAt = 'cookieCloud.lastSyncAt';
  static const String cookieCloudLastSyncSummary =
      'cookieCloud.lastSyncSummary';
  static const String secureFallbackConflict = 'secureStorage.fallbackConflict';
  static const String secureFallbackConflictsV1 =
      'secureStorage.fallbackConflicts.v1';
  static const String pendingSensitiveCompanionV1 =
      'secureStorage.pendingCompanionPreferences.v1';
  static const String secureStorageNamespaceInitializedV1 =
      'secureStorage.namespaceInitialized.v1';
  static const String secureStorageEncryptedEntriesExpectedV1 =
      'secureStorage.encryptedEntriesExpected.v1';
}

class CookieCloudConfig {
  final String url;
  final String uuid;
  final String password;
  final bool autoSyncEnabled;
  final int syncIntervalMinutes;
  final DateTime? lastSyncAt;
  final String lastSyncSummary;

  const CookieCloudConfig({
    this.url = '',
    this.uuid = '',
    this.password = '',
    this.autoSyncEnabled = false,
    this.syncIntervalMinutes = 360,
    this.lastSyncAt,
    this.lastSyncSummary = '',
  });

  bool get isConfigured =>
      url.trim().isNotEmpty &&
      uuid.trim().isNotEmpty &&
      password.trim().isNotEmpty;

  CookieCloudConfig copyWith({
    String? url,
    String? uuid,
    String? password,
    bool? autoSyncEnabled,
    int? syncIntervalMinutes,
    DateTime? lastSyncAt,
    String? lastSyncSummary,
  }) => CookieCloudConfig(
    url: url ?? this.url,
    uuid: uuid ?? this.uuid,
    password: password ?? this.password,
    autoSyncEnabled: autoSyncEnabled ?? this.autoSyncEnabled,
    syncIntervalMinutes: syncIntervalMinutes ?? this.syncIntervalMinutes,
    lastSyncAt: lastSyncAt ?? this.lastSyncAt,
    lastSyncSummary: lastSyncSummary ?? this.lastSyncSummary,
  );

  Map<String, dynamic> toJson() => {
    'url': url,
    'uuid': uuid,
    'password': password,
    'autoSyncEnabled': autoSyncEnabled,
    'syncIntervalMinutes': syncIntervalMinutes,
    'lastSyncAt': lastSyncAt?.toIso8601String(),
    'lastSyncSummary': lastSyncSummary,
  };

  factory CookieCloudConfig.fromJson(Map<String, dynamic> json) {
    final lastSyncAtRaw = json['lastSyncAt'] as String?;
    return CookieCloudConfig(
      url: json['url'] as String? ?? '',
      uuid: json['uuid'] as String? ?? '',
      password: json['password'] as String? ?? '',
      autoSyncEnabled: json['autoSyncEnabled'] as bool? ?? false,
      syncIntervalMinutes: json['syncIntervalMinutes'] as int? ?? 360,
      lastSyncAt: lastSyncAtRaw == null
          ? null
          : DateTime.tryParse(lastSyncAtRaw),
      lastSyncSummary: json['lastSyncSummary'] as String? ?? '',
    );
  }
}

class _CookieCloudSecrets {
  const _CookieCloudSecrets({
    required this.url,
    required this.uuid,
    required this.password,
  });

  final String url;
  final String uuid;
  final String password;

  Map<String, dynamic> toJson() => {
    'url': url,
    'uuid': uuid,
    'password': password,
  };

  factory _CookieCloudSecrets.fromJson(Map<String, dynamic> json) {
    final url = json['url'];
    final uuid = json['uuid'];
    final password = json['password'];
    if (url is! String || uuid is! String || password is! String) {
      throw const FormatException('Invalid Cookie Cloud bundle.');
    }
    return _CookieCloudSecrets(url: url, uuid: uuid, password: password);
  }
}

class _LegacyCookieCloudSecrets {
  const _LegacyCookieCloudSecrets({
    required this.secrets,
    required this.hasConflict,
  });

  final _CookieCloudSecrets secrets;
  final bool hasConflict;
}

enum SecureStorageState { unknown, ready, unavailable }

enum SecureStorageProfile {
  androidOaepGcm,
  androidPkcs1Gcm,
  androidPkcs1Cbc,
  platformDefault,
  linuxPlaintextFallback,
}

class SecureStorageStatus {
  const SecureStorageStatus({required this.state, this.failureCode});

  final SecureStorageState state;
  final String? failureCode;
}

enum SecureReadStatus { found, missing, unavailable }

class SecureReadResult<T> {
  const SecureReadResult._({
    required this.status,
    this.value,
    this.failureCode,
  });

  const SecureReadResult.found(T value)
    : this._(status: SecureReadStatus.found, value: value);

  const SecureReadResult.missing() : this._(status: SecureReadStatus.missing);

  const SecureReadResult.unavailable(String failureCode)
    : this._(status: SecureReadStatus.unavailable, failureCode: failureCode);

  final SecureReadStatus status;
  final T? value;
  final String? failureCode;
}

class SecureStorageUnavailableException implements Exception {
  const SecureStorageUnavailableException(this.code, [this.cause]);

  final String code;
  final Object? cause;

  @override
  String toString() => 'SecureStorageUnavailableException($code)';
}

class SiteConfigAtomicUpdate<T> {
  const SiteConfigAtomicUpdate({required this.configs, required this.result});

  final List<SiteConfig> configs;
  final T result;
}

class StorageService {
  StorageService._();
  static final StorageService instance = StorageService._();
  static final Logger _logger = Logger();
  static final Object _secureStoragePreflightZoneKey = Object();
  static final Object _secureStorageOperationEpochZoneKey = Object();
  static final Object _linuxPlaintextFallbackReplayZoneKey = Object();
  static const Duration _secureStorageTimeout = Duration(milliseconds: 800);
  static const Duration _secureStorageInitializationTimeout = Duration(
    seconds: 5,
  );
  static const String _sensitiveManifestKey =
      'secureStorage.transaction.sensitiveManifest.v1';
  static const String _sensitivePhysicalKeyPrefix =
      'secureStorage.sensitiveRevision.v1';
  static const String _backupRestoreCheckpointKey =
      'secureStorage.backupRestoreCheckpoint.v1';
  static const String _encryptedEntriesWitnessKey =
      '__ptmate_secure_storage_witness_v1__';
  static const String _encryptedEntriesWitnessValue =
      'ptmate-secure-storage-witness-v1';
  static const bool _secureStorageTransactionsBuildEnabled =
      bool.fromEnvironment(
        'ENABLE_SECURE_STORAGE_TRANSACTIONS',
        defaultValue: false,
      );
  static const IOSOptions _iosSecureOptions = IOSOptions(
    accessibility: KeychainAccessibility.first_unlock_this_device,
  );
  // Android 选项配置：分别对应 RSA OAEP (Modern) 与 RSA PKCS1 (Compat)
  static const AndroidOptions _androidModernSecureOptions = AndroidOptions(
    resetOnError: false,
    migrateOnAlgorithmChange: false,
    migrateWithBackup: false,
    keyCipherAlgorithm:
        KeyCipherAlgorithm.RSA_ECB_OAEPwithSHA_256andMGF1Padding,
    storageCipherAlgorithm: StorageCipherAlgorithm.AES_GCM_NoPadding,
  );
  static const AndroidOptions _androidCompatSecureOptions = AndroidOptions(
    resetOnError: false,
    migrateOnAlgorithmChange: false,
    migrateWithBackup: false,
    // ignore: deprecated_member_use
    keyCipherAlgorithm: KeyCipherAlgorithm.RSA_ECB_PKCS1Padding,
    storageCipherAlgorithm: StorageCipherAlgorithm.AES_GCM_NoPadding,
  );
  // 旧版默认格式（pre-PR#126）：PKCS1 + AES_CBC。
  static const AndroidOptions _androidLegacySecureOptions = AndroidOptions(
    resetOnError: false,
    migrateOnAlgorithmChange: false,
    migrateWithBackup: false,
    // ignore: deprecated_member_use
    keyCipherAlgorithm: KeyCipherAlgorithm.RSA_ECB_PKCS1Padding,
    // ignore: deprecated_member_use
    storageCipherAlgorithm: StorageCipherAlgorithm.AES_CBC_PKCS7Padding,
  );

  bool _hasPendingConfigUpdates = false;
  Future<void> _healthStatusesWriteQueue = Future.value();

  // 站点配置内存缓存
  List<SiteConfig>? _siteConfigsCache;
  bool _siteConfigsCacheDirty = true;
  bool _siteConfigsCacheNeedsUpdate = false;
  final Map<String, String?> _siteApiKeysCache = {};
  final Map<String, String?> _siteCookiesCache = {};
  List<SiteConfig>? get siteConfigsCache => _siteConfigsCache;
  TargetPlatform? _platformOverrideForTest;
  SecureStorageState _secureStorageState = SecureStorageState.unknown;
  String? _secureStorageFailureCode;
  bool _secureStorageUnavailableLatched = false;
  int _secureStorageOperationGeneration = 0;
  final ValueNotifier<SecureStorageStatus> _secureStorageStatusNotifier =
      ValueNotifier<SecureStorageStatus>(
        const SecureStorageStatus(state: SecureStorageState.unknown),
      );
  bool _hasLoggedSecureStorageUnavailable = false;
  bool _cookieCloudBundleCreatedThisRun = false;
  SecureStorageProfile? _secureStorageProfile;
  AndroidOptions? _androidSecureOptions;
  AndroidSecureStorageProfile? _androidProfileOverrideForTest;
  final AndroidSecureStorageProfileResolver _androidProfileResolver =
      AndroidSecureStorageProfileResolver();
  SecureStorageTransaction? _sensitiveTransaction;
  Future<void> _pendingSecureStorageCleanup = Future<void>.value();
  Future<void> _sensitiveOperationTail = Future<void>.value();
  Future<void> _siteConfigOperationTail = Future<void>.value();
  // Conflict/tombstone metadata lives in one SharedPreferences list. It must
  // have its own serial lane: sensitive revisions intentionally release their
  // commit lane before deferred plaintext cleanup, so two cleanups could
  // otherwise overwrite each other's deletion guards with stale read-modify-
  // write snapshots.
  Future<void> _fallbackMetadataOperationTail = Future<void>.value();
  bool? _secureStorageTransactionsOverrideForTest;
  ValueChanged<String>? _secureStorageAuditObserverForTest;
  Future<void> Function()? _androidSecureStorageFlushOverrideForTest;
  Future<void> Function(String fallbackKey)?
  _beforeSensitiveFallbackCleanupOverrideForTest;
  Future<void> Function(String fallbackKey)?
  _afterSensitiveFallbackCleanupMetadataReadOverrideForTest;
  bool Function(String failureCode, bool committed)?
  _preferenceMutationResultOverrideForTest;

  // 统一安全存储实例
  final FlutterSecureStorage _secure = const FlutterSecureStorage();

  Future<SharedPreferences> get _prefs async => SharedPreferences.getInstance();

  TargetPlatform get _currentPlatform =>
      _platformOverrideForTest ?? defaultTargetPlatform;

  bool get _isAndroidPlatform =>
      !kIsWeb && _currentPlatform == TargetPlatform.android;

  bool get _allowsPlaintextFallback =>
      !kIsWeb && _currentPlatform == TargetPlatform.linux;

  bool get _isPlaintextFallbackActive =>
      _allowsPlaintextFallback &&
      _secureStorageState == SecureStorageState.unavailable &&
      _secureStorageFailureCode == 'linux_keyring_unavailable';

  SecureStorageState get secureStorageState => _secureStorageState;

  SecureStorageProfile? get secureStorageProfile => _secureStorageProfile;

  ValueListenable<SecureStorageStatus> get secureStorageStatusListenable =>
      _secureStorageStatusNotifier;

  bool get isSecureStorageReady =>
      _secureStorageState == SecureStorageState.ready;

  /// 敏感数据当前是否可安全访问。Linux 保留既有 keyring 失败后的本地降级；
  /// Android/iOS 的安全存储异常则必须阻断本次运行。
  bool get canAccessSensitiveStorage =>
      isSecureStorageReady || _isPlaintextFallbackActive;

  String? get secureStorageFailureCode => _secureStorageFailureCode;

  int? get _expectedSecureStorageOperationEpoch =>
      Zone.current[_secureStorageOperationEpochZoneKey] as int?;

  /// Captures the current ready secure-storage run. Background work must keep
  /// this epoch across network waits so a failure followed by an explicit
  /// retry cannot revive an operation that started against the old run.
  int captureSecureStorageOperationEpoch() {
    final inherited = _expectedSecureStorageOperationEpoch;
    if (inherited != null) {
      requireSecureStorageOperationEpoch(inherited);
      return inherited;
    }
    if (!canAccessSensitiveStorage) {
      throw SecureStorageUnavailableException(
        _secureStorageFailureCode ?? 'secure_storage_not_ready',
      );
    }
    return _secureStorageOperationGeneration;
  }

  bool isSecureStorageOperationEpochCurrent(int epoch) =>
      canAccessSensitiveStorage && epoch == _secureStorageOperationGeneration;

  void requireSecureStorageOperationEpoch(int epoch) {
    if (!isSecureStorageOperationEpochCurrent(epoch)) {
      throw const SecureStorageUnavailableException(
        'secure_storage_operation_invalidated',
      );
    }
  }

  Future<T> runWithSecureStorageOperationEpoch<T>(
    int epoch,
    Future<T> Function() operation,
  ) {
    requireSecureStorageOperationEpoch(epoch);
    final inherited = _expectedSecureStorageOperationEpoch;
    if (inherited != null && inherited != epoch) {
      throw const SecureStorageUnavailableException(
        'secure_storage_operation_invalidated',
      );
    }
    final enteredWithPlaintextFallback = _isPlaintextFallbackActive;
    final isFallbackReplay =
        Zone.current[_linuxPlaintextFallbackReplayZoneKey] == true;
    return _runWithSecureStorageOperationEpochAfterPrecondition(
      epoch: epoch,
      operation: operation,
      enteredWithPlaintextFallback: enteredWithPlaintextFallback,
      isFallbackReplay: isFallbackReplay,
    );
  }

  Future<T> _runWithSecureStorageOperationEpochAfterPrecondition<T>({
    required int epoch,
    required Future<T> Function() operation,
    required bool enteredWithPlaintextFallback,
    required bool isFallbackReplay,
  }) async {
    Future<T> execute({required bool fallbackReplay}) => runZoned(
      operation,
      zoneValues: <Object?, Object?>{
        _secureStorageOperationEpochZoneKey: epoch,
        _linuxPlaintextFallbackReplayZoneKey: fallbackReplay,
      },
    );

    try {
      return await execute(fallbackReplay: isFallbackReplay);
    } on SecureStorageUnavailableException {
      // Linux is the one supported plaintext fallback. A transaction can
      // discover a keyring failure only after it has entered its staging
      // phase. At that point the manifest has not switched, so replaying the
      // complete high-level operation is safe: it follows the existing
      // fallback branch and never treats partial staging as a commit.
      //
      // Limit this to a single transition from healthy keyring -> fallback;
      // an already-fallback run must still surface real write/JSON errors.
      if (!enteredWithPlaintextFallback &&
          !isFallbackReplay &&
          _isPlaintextFallbackActive) {
        requireSecureStorageOperationEpoch(epoch);
        return execute(fallbackReplay: true);
      }
      rethrow;
    }
  }

  /// Runs a complete sensitive mutation or migration against one generation.
  ///
  /// Callers must keep the same zone through secure commit, verification and
  /// plaintext-fallback cleanup. Capturing only around an individual fallback
  /// delete would let an operation that began before a storage failure resume
  /// after an explicit retry and mutate the new run.
  Future<T> _runInCurrentSecureStorageOperationEpoch<T>(
    Future<T> Function() operation,
  ) {
    final inherited = _expectedSecureStorageOperationEpoch;
    if (inherited != null) {
      requireSecureStorageOperationEpoch(inherited);
      return operation();
    }
    // Do not await an already-ready initialization before capturing. Even a
    // completed Future yields one microtask, enough for a failure + explicit
    // retry to replace the generation beneath an old caller.
    if (canAccessSensitiveStorage) {
      final epoch = captureSecureStorageOperationEpoch();
      return runWithSecureStorageOperationEpoch(epoch, operation);
    }
    return _initializeAndRunInCurrentSecureStorageOperationEpoch(operation);
  }

  /// Captures one usable generation before running a caller-owned operation.
  /// Background services use this instead of awaiting initialization and then
  /// separately capturing, which would leave a retry window between them.
  Future<T> runWithCurrentSecureStorageOperation<T>(
    Future<T> Function(int epoch) operation,
  ) => _runInCurrentSecureStorageOperationEpoch(() {
    final epoch = captureSecureStorageOperationEpoch();
    return operation(epoch);
  });

  Future<T> _initializeAndRunInCurrentSecureStorageOperationEpoch<T>(
    Future<T> Function() operation,
  ) async {
    await initializeSecureStorage();
    final inherited = _expectedSecureStorageOperationEpoch;
    if (inherited != null) {
      requireSecureStorageOperationEpoch(inherited);
      return operation();
    }
    final epoch = captureSecureStorageOperationEpoch();
    return runWithSecureStorageOperationEpoch(epoch, operation);
  }

  void _requireExpectedSecureStorageOperationEpoch() {
    final expected = _expectedSecureStorageOperationEpoch;
    if (expected != null) requireSecureStorageOperationEpoch(expected);
  }

  bool _isSecureStorageOperationInvalidated(Object error) =>
      error is SecureStorageUnavailableException &&
      error.code == 'secure_storage_operation_invalidated';

  bool get _shouldShortCircuitSecureStorage => _isPlaintextFallbackActive;

  bool get _isInsideSecureStoragePreflight =>
      identical(Zone.current[_secureStoragePreflightZoneKey], this);

  bool _isLinuxKeyringFailure(Object error) {
    if (!_allowsPlaintextFallback) return false;

    if (error is PlatformException) {
      final normalizedCode = error.code.trim().toLowerCase().replaceAll(
        RegExp(r'[\s_-]'),
        '',
      );
      // flutter_secure_storage_linux reports a missing, unavailable or locked
      // Secret Service using these platform codes. KeyringLocked contains no
      // spaces, so relying on the human-readable message misses the common
      // headless/minimal-Linux case.
      if (normalizedCode == 'keyringlocked' ||
          normalizedCode == 'libsecreterror') {
        return true;
      }
    }

    final message = error.toString().toLowerCase();
    return message.contains('libsecret') ||
        message.contains('unlock the keyring') ||
        message.contains('failed to unlock the keyring');
  }

  bool _markSecureStorageAvailable(int operationGeneration) {
    if (_secureStorageUnavailableLatched ||
        operationGeneration != _secureStorageOperationGeneration) {
      return false;
    }
    _setSecureStorageStatus(SecureStorageState.ready);
    return true;
  }

  void _setSecureStorageStatus(
    SecureStorageState state, {
    String? failureCode,
  }) {
    final changed =
        _secureStorageState != state ||
        _secureStorageFailureCode != failureCode;
    _secureStorageState = state;
    _secureStorageFailureCode = failureCode;
    if (changed) {
      _secureStorageStatusNotifier.value = SecureStorageStatus(
        state: state,
        failureCode: failureCode,
      );
    }
  }

  String _failureCodeFor(Object error) {
    if (error is TimeoutException) return 'timeout';
    if (_isLinuxKeyringFailure(error)) return 'linux_keyring_unavailable';
    final categorySource = error is PlatformException
        ? '${error.code} ${error.message ?? ''}'.toLowerCase()
        : error.toString().toLowerCase();
    if (categorySource.contains('badpadding') ||
        categorySource.contains('bad_padding')) {
      return 'bad_padding';
    }
    if (categorySource.contains('aeadbadtagexception') ||
        categorySource.contains('tag mismatch') ||
        categorySource.contains('authentication_failed')) {
      return 'authentication_failed';
    }
    if (categorySource.contains('keypermanentlyinvalidated') ||
        categorySource.contains('key_permanently_invalidated')) {
      return 'key_permanently_invalidated';
    }
    if (categorySource.contains('invalidkey') ||
        categorySource.contains('invalid_key')) {
      return 'invalid_key';
    }
    if (categorySource.contains('unknown algorithm') ||
        categorySource.contains('unknown_algorithm') ||
        categorySource.contains('nosuchalgorithm') ||
        categorySource.contains('unsupported_algorithm')) {
      return 'unsupported_algorithm';
    }
    if (error is PlatformException) return 'platform_error';
    final type = error.runtimeType.toString().trim();
    return type.isEmpty ? 'unknown_error' : type.toLowerCase();
  }

  void _markSecureStorageUnavailable(
    Object error, {
    String? code,
    int? operationGeneration,
  }) {
    if (_isSecureStorageOperationInvalidated(error) ||
        code == 'secure_storage_operation_invalidated') {
      return;
    }
    // An operation started before an explicit retry/reset must not poison the
    // new run when its asynchronous platform call completes late.
    if (operationGeneration != null &&
        operationGeneration != _secureStorageOperationGeneration) {
      return;
    }
    // A healthy Linux run may discover a locked keyring while staging a
    // transaction. Keep that specific fallback state intact when the
    // transaction subsequently reports its derived staging/verification
    // error; otherwise the same operation could no longer use the approved
    // plaintext fallback on replay.
    if (_isPlaintextFallbackActive) return;
    final failureCode = code ?? _failureCodeFor(error);
    // Linux is the sole supported plaintext fallback. A keyring failure moves
    // the current run into that explicitly supported mode; it is not a new
    // run, so the operation that observed the failure must be allowed to
    // finish its verified fallback write. A later explicit retry still bumps
    // the generation and invalidates every old operation as usual.
    final preservesCurrentOperationEpoch =
        _allowsPlaintextFallback && failureCode == 'linux_keyring_unavailable';
    _secureStorageUnavailableLatched = true;
    if (!preservesCurrentOperationEpoch) {
      _secureStorageOperationGeneration++;
    }
    _setSecureStorageStatus(
      SecureStorageState.unavailable,
      failureCode: failureCode,
    );
    if (_hasLoggedSecureStorageUnavailable) {
      return;
    }
    _hasLoggedSecureStorageUnavailable = true;
    final auditLine =
        'Secure storage '
        'profile=${_secureStorageProfile?.name ?? 'unknown'}, '
        'state=${SecureStorageState.unavailable.name}, '
        'code=$_secureStorageFailureCode';
    _secureStorageAuditObserverForTest?.call(auditLine);
    if (kDebugMode) _logger.w(auditLine);
    LogFileService.instance.append(auditLine);
  }

  AndroidOptions _optionsForProfile(AndroidSecureStorageProfile profile) {
    return switch (profile) {
      AndroidSecureStorageProfile.oaepGcm ||
      AndroidSecureStorageProfile.fresh => _androidModernSecureOptions,
      AndroidSecureStorageProfile.pkcs1Gcm => _androidCompatSecureOptions,
      AndroidSecureStorageProfile.pkcs1Cbc => _androidLegacySecureOptions,
      AndroidSecureStorageProfile.inconsistent ||
      AndroidSecureStorageProfile.unsupported =>
        throw const SecureStorageUnavailableException(
          'android_secure_storage_profile_invalid',
        ),
    };
  }

  SecureStorageProfile _publicProfileForAndroid(
    AndroidSecureStorageProfile profile,
  ) {
    return switch (profile) {
      AndroidSecureStorageProfile.oaepGcm ||
      AndroidSecureStorageProfile.fresh => SecureStorageProfile.androidOaepGcm,
      AndroidSecureStorageProfile.pkcs1Gcm =>
        SecureStorageProfile.androidPkcs1Gcm,
      AndroidSecureStorageProfile.pkcs1Cbc =>
        SecureStorageProfile.androidPkcs1Cbc,
      AndroidSecureStorageProfile.inconsistent ||
      AndroidSecureStorageProfile.unsupported =>
        throw const SecureStorageUnavailableException(
          'android_secure_storage_profile_invalid',
        ),
    };
  }

  Future<void> _flushAndroidSecureStorageDurabilityBarrier() async {
    _requireExpectedSecureStorageOperationEpoch();
    if (!_isAndroidPlatform) return;
    try {
      final override = _androidSecureStorageFlushOverrideForTest;
      if (override != null) {
        await override();
        _requireExpectedSecureStorageOperationEpoch();
        return;
      }
      final result = await _androidProfileResolver.flush();
      _requireExpectedSecureStorageOperationEpoch();
      if (!result.isSuccessful) {
        throw SecureStorageUnavailableException(
          result.failureCode ?? 'secure_storage_flush_failed',
        );
      }
    } catch (error) {
      if (_isSecureStorageOperationInvalidated(error)) rethrow;
      final code = error is SecureStorageUnavailableException
          ? error.code
          : 'secure_storage_flush_failed';
      _markSecureStorageUnavailable(error, code: code);
      throw SecureStorageUnavailableException(code, error);
    }
  }

  Never _throwSecureStorageUnavailable(String code, [Object? cause]) {
    final error = SecureStorageUnavailableException(code, cause);
    if (code == 'secure_storage_operation_invalidated') throw error;
    _markSecureStorageUnavailable(error, code: code);
    throw error;
  }

  Future<T> _runSensitiveStorageOperation<T>(
    Future<T> Function() operation,
  ) async {
    final predecessor = _sensitiveOperationTail;
    final release = Completer<void>();
    _sensitiveOperationTail = release.future;
    await predecessor;
    try {
      _requireExpectedSecureStorageOperationEpoch();
      return await operation();
    } finally {
      release.complete();
    }
  }

  Future<T> _runSiteConfigOperation<T>(Future<T> Function() operation) {
    final inherited = _expectedSecureStorageOperationEpoch;
    if (inherited != null) {
      requireSecureStorageOperationEpoch(inherited);
      return _runSiteConfigOperationInCurrentEpoch(operation);
    }
    if (canAccessSensitiveStorage) {
      final epoch = captureSecureStorageOperationEpoch();
      return runWithSecureStorageOperationEpoch(
        epoch,
        () => _runSiteConfigOperationInCurrentEpoch(operation),
      );
    }
    return _runInCurrentSecureStorageOperationEpoch(
      () => _runSiteConfigOperationInCurrentEpoch(operation),
    );
  }

  Future<T> _runSiteConfigOperationInCurrentEpoch<T>(
    Future<T> Function() operation,
  ) async {
    final predecessor = _siteConfigOperationTail;
    final release = Completer<void>();
    _siteConfigOperationTail = release.future;
    await predecessor;
    try {
      _requireExpectedSecureStorageOperationEpoch();
      return await operation();
    } finally {
      release.complete();
    }
  }

  Future<T> _runFallbackMetadataOperation<T>(
    Future<T> Function(SharedPreferences prefs) operation, {
    int? expectedSecureStorageEpoch,
    bool requireSecureStorageEpoch = true,
  }) async {
    final expected =
        expectedSecureStorageEpoch ??
        _expectedSecureStorageOperationEpoch ??
        (requireSecureStorageEpoch
            ? captureSecureStorageOperationEpoch()
            : null);
    final predecessor = _fallbackMetadataOperationTail;
    final release = Completer<void>();
    _fallbackMetadataOperationTail = release.future;
    await predecessor;
    try {
      if (expected != null) requireSecureStorageOperationEpoch(expected);
      final prefs = await _prefs;
      if (expected != null) requireSecureStorageOperationEpoch(expected);
      return await operation(prefs);
    } finally {
      release.complete();
    }
  }

  Future<void> initializeSecureStorage({bool force = false}) async {
    _requireExpectedSecureStorageOperationEpoch();
    if (!force && _secureStorageState == SecureStorageState.ready) return;
    if (!force && _secureStorageState == SecureStorageState.unavailable) {
      if (_isPlaintextFallbackActive) return;
      throw SecureStorageUnavailableException(
        _secureStorageFailureCode ?? 'secure_storage_unavailable',
      );
    }

    await _runSensitiveStorageOperation(() async {
      _requireExpectedSecureStorageOperationEpoch();
      if (!force && _secureStorageState == SecureStorageState.ready) return;
      if (!force && _secureStorageState == SecureStorageState.unavailable) {
        if (_isPlaintextFallbackActive) return;
        throw SecureStorageUnavailableException(
          _secureStorageFailureCode ?? 'secure_storage_unavailable',
        );
      }
      await _initializeSecureStorageUnlocked(force: force);
    });
  }

  Future<void> _initializeSecureStorageUnlocked({required bool force}) async {
    if (force) {
      // Explicit retry starts a new generation. Any older operation that
      // completes afterwards is not allowed to unlock this run.
      _secureStorageOperationGeneration++;
      _secureStorageUnavailableLatched = false;
      _setSecureStorageStatus(SecureStorageState.unknown);
      _hasLoggedSecureStorageUnavailable = false;
    }

    try {
      if (_isAndroidPlatform) {
        AndroidSecureStorageProfile profile;
        final override = _androidProfileOverrideForTest;
        if (override != null) {
          profile = override;
        } else {
          var probe = await _androidProfileResolver.probe();
          if (!probe.isReady) {
            throw SecureStorageUnavailableException(
              probe.failureCode ?? 'android_secure_storage_profile_invalid',
            );
          }
          if (probe.profile == AndroidSecureStorageProfile.fresh) {
            final initialized = await _androidProfileResolver
                .initializeFreshOaepGcm();
            if (!initialized.isReady ||
                initialized.profile != AndroidSecureStorageProfile.oaepGcm) {
              throw SecureStorageUnavailableException(
                initialized.failureCode ??
                    'android_fresh_initialization_invalid',
              );
            }
            probe = await _androidProfileResolver.probe();
            if (!probe.isReady ||
                probe.profile != AndroidSecureStorageProfile.oaepGcm) {
              throw SecureStorageUnavailableException(
                probe.failureCode ??
                    'android_fresh_initialization_verification_failed',
              );
            }
          }
          profile = probe.profile;
        }
        _secureStorageProfile = _publicProfileForAndroid(profile);
        _androidSecureOptions = _optionsForProfile(profile);
      } else {
        _secureStorageProfile = SecureStorageProfile.platformDefault;
        _androidSecureOptions = _androidModernSecureOptions;
      }

      final operationGeneration = _secureStorageOperationGeneration;
      await _secure
          .read(
            key: '__ptmate_secure_storage_probe__',
            aOptions: _androidSecureOptions!,
            iOptions: _iosSecureOptions,
          )
          .timeout(_secureStorageInitializationTimeout);
      // flutter_secure_storage persists freshly created wrapped keys and
      // algorithm metadata with SharedPreferences.apply(). Establish a native
      // synchronous barrier before this run is allowed to observe "ready".
      await _flushAndroidSecureStorageDurabilityBarrier();
      await _ensureAndroidEncryptedEntriesWitness();
      final transaction = await _getSensitiveTransaction();
      final reconciliation = await runZoned(() async {
        final result = await transaction.reconcile(cleanupIfHealthy: false);
        if (!result.isHealthy) {
          throw const SecureStorageUnavailableException(
            'secure_transaction_requires_restore',
          );
        }
        await _recoverPendingCompanionPreferences(transaction);
        return result;
      }, zoneValues: <Object?, Object?>{_secureStoragePreflightZoneKey: this});
      if (_isAndroidPlatform) {
        final prefs = await _prefs;
        await _requirePreferenceMutation(
          mutate: () => prefs.setBool(
            StorageKeys.secureStorageNamespaceInitializedV1,
            true,
          ),
          verify: () =>
              prefs.getBool(StorageKeys.secureStorageNamespaceInitializedV1) ==
              true,
          failureCode: 'secure_storage_namespace_marker_commit_failed',
        );
      }
      // Publish ready only after profile probing, encrypted-witness verification,
      // transaction reconciliation and companion recovery have all completed.
      if (!_markSecureStorageAvailable(operationGeneration)) {
        throw SecureStorageUnavailableException(
          _secureStorageFailureCode ?? 'secure_storage_unavailable',
        );
      }
      // 活动 revision 与普通 companion 已确认完整后即可放行启动；只有确有
      // 旧密文时才调度异步清理，避免为全新/无垃圾 manifest 留下无意义任务。
      if (reconciliation.cleanup.pendingCount > 0) {
        final cleanup = _cleanupSensitiveTransactionAfterStartup(
          transaction,
          operationGeneration,
        );
        _pendingSecureStorageCleanup = Future.wait<void>([
          _pendingSecureStorageCleanup,
          cleanup,
        ]).then((_) {});
        unawaited(cleanup);
      }
    } catch (error) {
      final code = error is SecureStorageUnavailableException
          ? error.code
          : _failureCodeFor(error);
      _markSecureStorageUnavailable(error, code: code);
      if (_isPlaintextFallbackActive) {
        _secureStorageProfile = SecureStorageProfile.linuxPlaintextFallback;
        return;
      }
      throw SecureStorageUnavailableException(code, error);
    }
  }

  Future<void> _cleanupSensitiveTransactionAfterStartup(
    SecureStorageTransaction transaction,
    int operationGeneration,
  ) async {
    try {
      await runWithSecureStorageOperationEpoch(
        operationGeneration,
        transaction.cleanup,
      );
    } on SecureStorageUnavailableException catch (error) {
      // The cleanup belongs to the startup generation that scheduled it. A
      // later explicit retry starts a new generation; the old cleanup must
      // simply stop instead of executing native deletes against that new run.
      if (_isSecureStorageOperationInvalidated(error)) return;
      final code = _transactionFailureCode(error);
      _markSecureStorageUnavailable(
        error,
        code: code,
        operationGeneration: operationGeneration,
      );
    } catch (error) {
      final code = _transactionFailureCode(error);
      _markSecureStorageUnavailable(
        error,
        code: code,
        operationGeneration: operationGeneration,
      );
    }
  }

  Future<void> _ensureSecureStorageUnlocked() async {
    if (_secureStorageState == SecureStorageState.ready) return;
    if (_secureStorageState == SecureStorageState.unavailable) {
      if (_isPlaintextFallbackActive) return;
      throw SecureStorageUnavailableException(
        _secureStorageFailureCode ?? 'secure_storage_unavailable',
      );
    }
    await _initializeSecureStorageUnlocked(force: false);
  }

  Future<AndroidOptions> _getAndroidSecureOptions() async {
    await initializeSecureStorage();
    final options = _androidSecureOptions;
    if (options == null) {
      throw const SecureStorageUnavailableException(
        'secure_storage_options_unavailable',
      );
    }
    return options;
  }

  Future<SecureReadResult<String>> _secureReadResult(String key) async {
    try {
      _requireExpectedSecureStorageOperationEpoch();
    } on SecureStorageUnavailableException catch (error) {
      return SecureReadResult<String>.unavailable(error.code);
    }
    if (_shouldShortCircuitSecureStorage) {
      return SecureReadResult<String>.unavailable(
        _secureStorageFailureCode ?? 'secure_storage_unavailable',
      );
    }

    if (_isInsideSecureStoragePreflight) {
      final options = _androidSecureOptions;
      if (options == null) {
        return const SecureReadResult<String>.unavailable(
          'secure_storage_options_unavailable',
        );
      }
      try {
        final value = await _secure
            .read(key: key, aOptions: options, iOptions: _iosSecureOptions)
            .timeout(_secureStorageInitializationTimeout);
        return value == null
            ? const SecureReadResult<String>.missing()
            : SecureReadResult<String>.found(value);
      } catch (error) {
        return SecureReadResult<String>.unavailable(_failureCodeFor(error));
      }
    }

    int? operationGeneration;
    try {
      final aOptions = await _getAndroidSecureOptions();
      operationGeneration = _secureStorageOperationGeneration;
      final value = await _secure
          .read(key: key, aOptions: aOptions, iOptions: _iosSecureOptions)
          .timeout(_secureStorageTimeout);
      _requireExpectedSecureStorageOperationEpoch();
      if (!_markSecureStorageAvailable(operationGeneration)) {
        return SecureReadResult<String>.unavailable(
          _secureStorageFailureCode ?? 'secure_storage_unavailable',
        );
      }
      if (value == null) return const SecureReadResult<String>.missing();
      return SecureReadResult<String>.found(value);
    } catch (error) {
      final code = error is SecureStorageUnavailableException
          ? error.code
          : _failureCodeFor(error);
      if (_isSecureStorageOperationInvalidated(error)) {
        return SecureReadResult<String>.unavailable(code);
      }
      _markSecureStorageUnavailable(
        error,
        code: code,
        operationGeneration: operationGeneration,
      );
      return SecureReadResult<String>.unavailable(code);
    }
  }

  Future<String?> _secureRead(String key) async {
    final result = await _secureReadResult(key);
    return switch (result.status) {
      SecureReadStatus.found => result.value,
      SecureReadStatus.missing => null,
      SecureReadStatus.unavailable when _isPlaintextFallbackActive => null,
      SecureReadStatus.unavailable => throw SecureStorageUnavailableException(
        result.failureCode ?? 'secure_storage_unavailable',
      ),
    };
  }

  /// 统一安全存储写入：使用首选的加密算法
  Future<bool> _secureWrite({
    required String key,
    required String value,
  }) async {
    _requireExpectedSecureStorageOperationEpoch();
    if (_shouldShortCircuitSecureStorage) {
      return false;
    }

    int? operationGeneration;
    try {
      final aOptions = await _getAndroidSecureOptions();
      operationGeneration = _secureStorageOperationGeneration;
      await _secure
          .write(
            key: key,
            value: value,
            aOptions: aOptions,
            iOptions: _iosSecureOptions,
          )
          .timeout(_secureStorageTimeout);
      _requireExpectedSecureStorageOperationEpoch();
      if (!_markSecureStorageAvailable(operationGeneration)) {
        throw SecureStorageUnavailableException(
          _secureStorageFailureCode ?? 'secure_storage_unavailable',
        );
      }
      return true;
    } catch (error) {
      if (_isSecureStorageOperationInvalidated(error)) rethrow;
      final code = error is SecureStorageUnavailableException
          ? error.code
          : _failureCodeFor(error);
      _markSecureStorageUnavailable(
        error,
        code: code,
        operationGeneration: operationGeneration,
      );
      if (_isPlaintextFallbackActive) return false;
      throw SecureStorageUnavailableException(code, error);
    }
  }

  Future<void> _ensureAndroidEncryptedEntriesWitness() async {
    if (!_isAndroidPlatform) return;
    final prefs = await _prefs;
    final witnessExpected =
        prefs.getBool(StorageKeys.secureStorageEncryptedEntriesExpectedV1) ==
        true;
    final options = _androidSecureOptions;
    if (options == null) {
      throw const SecureStorageUnavailableException(
        'secure_storage_options_unavailable',
      );
    }

    if (!witnessExpected) {
      await _secure
          .write(
            key: _encryptedEntriesWitnessKey,
            value: _encryptedEntriesWitnessValue,
            aOptions: options,
            iOptions: _iosSecureOptions,
          )
          .timeout(_secureStorageInitializationTimeout);
    }
    final witness = await _secure
        .read(
          key: _encryptedEntriesWitnessKey,
          aOptions: options,
          iOptions: _iosSecureOptions,
        )
        .timeout(_secureStorageInitializationTimeout);
    if (witness != _encryptedEntriesWitnessValue) {
      throw SecureStorageUnavailableException(
        witnessExpected
            ? 'secure_storage_witness_missing'
            : 'secure_storage_witness_verification_failed',
      );
    }
    await _flushAndroidSecureStorageDurabilityBarrier();
    if (witnessExpected) return;
    await _requirePreferenceMutation(
      mutate: () => prefs.setBool(
        StorageKeys.secureStorageEncryptedEntriesExpectedV1,
        true,
      ),
      verify: () =>
          prefs.getBool(StorageKeys.secureStorageEncryptedEntriesExpectedV1) ==
          true,
      failureCode: 'secure_storage_witness_commit_failed',
    );
  }

  /// 统一安全存储删除：从首选的 SharedPreferences 配置中删除（由于键名相同，只需删除一次）
  Future<bool> _secureDelete({required String key}) async {
    _requireExpectedSecureStorageOperationEpoch();
    if (_shouldShortCircuitSecureStorage) {
      return false;
    }

    int? operationGeneration;
    try {
      final aOptions = await _getAndroidSecureOptions();
      operationGeneration = _secureStorageOperationGeneration;
      await _secure
          .delete(key: key, aOptions: aOptions, iOptions: _iosSecureOptions)
          .timeout(_secureStorageTimeout);
      _requireExpectedSecureStorageOperationEpoch();
      await _flushAndroidSecureStorageDurabilityBarrier();
      if (!_markSecureStorageAvailable(operationGeneration)) {
        throw SecureStorageUnavailableException(
          _secureStorageFailureCode ?? 'secure_storage_unavailable',
        );
      }
      return true;
    } catch (error) {
      if (_isSecureStorageOperationInvalidated(error)) rethrow;
      final code = error is SecureStorageUnavailableException
          ? error.code
          : _failureCodeFor(error);
      _markSecureStorageUnavailable(
        error,
        code: code,
        operationGeneration: operationGeneration,
      );
      if (_isPlaintextFallbackActive) return false;
      throw SecureStorageUnavailableException(code, error);
    }
  }

  Future<SecureStorageTransaction> _getSensitiveTransaction() async {
    final existing = _sensitiveTransaction;
    if (existing != null) return existing;

    final prefs = await _prefs;
    final transaction = SecureStorageTransaction(
      preferences: prefs,
      readSecureValue: _secureRead,
      writeSecureValue: (key, value) async {
        final wrote = await _secureWrite(key: key, value: value);
        if (!wrote) {
          throw const SecureStorageUnavailableException(
            'secure_transaction_write_unavailable',
          );
        }
      },
      deleteSecureValue: (key) async {
        final deleted = await _secureDelete(key: key);
        if (!deleted) {
          throw const SecureStorageUnavailableException(
            'secure_transaction_delete_unavailable',
          );
        }
      },
      beforeManifestBarrier: (_) =>
          _flushAndroidSecureStorageDurabilityBarrier(),
      writeManifest: (key, value) async {
        _requireExpectedSecureStorageOperationEpoch();
        final committed = await prefs.setString(key, value);
        _requireExpectedSecureStorageOperationEpoch();
        return committed;
      },
      manifestPreferenceKey: _sensitiveManifestKey,
      physicalKeyPrefix: _sensitivePhysicalKeyPrefix,
    );
    _sensitiveTransaction = transaction;
    return transaction;
  }

  String _encodePlainSiteConfigs(List<SiteConfig> configs) {
    final jsonList = configs
        .map((config) => {...config.toJson(), 'apiKey': null, 'cookie': null})
        .toList();
    return jsonEncode(jsonList);
  }

  Set<String> _loadPersistedPlainSiteIds(SharedPreferences prefs) {
    final encoded = prefs.getString(StorageKeys.siteConfigs);
    if (encoded == null) return <String>{};
    try {
      final decoded = jsonDecode(encoded);
      if (decoded is! List<dynamic>) {
        throw const FormatException('Invalid site configuration payload.');
      }
      final ids = <String>{};
      for (final value in decoded) {
        if (value is! Map<String, dynamic> ||
            value['id'] is! String ||
            (value['id'] as String).isEmpty) {
          throw const FormatException('Invalid site configuration entry.');
        }
        ids.add(value['id'] as String);
      }
      return ids;
    } catch (_) {
      throw StateError('site_config_load_failed');
    }
  }

  Future<void> _requirePreferenceMutation({
    required Future<bool> Function() mutate,
    required bool Function() verify,
    required String failureCode,
  }) async {
    try {
      _requireExpectedSecureStorageOperationEpoch();
      final mutationResult = await mutate();
      _requireExpectedSecureStorageOperationEpoch();
      final committed =
          _preferenceMutationResultOverrideForTest?.call(
            failureCode,
            mutationResult,
          ) ??
          mutationResult;
      if (!committed || !verify()) {
        throw SecureStorageUnavailableException(failureCode);
      }
    } catch (error) {
      if (_isSecureStorageOperationInvalidated(error)) rethrow;
      final exception = error is SecureStorageUnavailableException
          ? error
          : SecureStorageUnavailableException(failureCode, error);
      _markSecureStorageUnavailable(exception, code: failureCode);
      throw exception;
    }
  }

  void _validatePlainSiteConfigsPayload(String encoded) {
    final decoded = jsonDecode(encoded);
    if (decoded is! List<dynamic>) {
      throw const FormatException('Invalid plain site configuration payload.');
    }
    for (final value in decoded) {
      if (value is! Map<String, dynamic> ||
          (value['apiKey'] != null) ||
          (value['cookie'] != null)) {
        throw const FormatException(
          'Invalid plain site configuration payload.',
        );
      }
    }
  }

  String _encodeCookieCloudPreferences(CookieCloudConfig config) => jsonEncode({
    'autoSyncEnabled': config.autoSyncEnabled,
    'syncIntervalMinutes': config.syncIntervalMinutes,
    'lastSyncAt': config.lastSyncAt?.toIso8601String(),
    'lastSyncSummary': config.lastSyncSummary,
  });

  Map<String, dynamic> _validateCookieCloudPreferencesPayload(String encoded) {
    final decoded = jsonDecode(encoded);
    if (decoded is! Map<String, dynamic> ||
        decoded['autoSyncEnabled'] is! bool ||
        decoded['syncIntervalMinutes'] is! int ||
        (decoded['lastSyncAt'] != null && decoded['lastSyncAt'] is! String) ||
        decoded['lastSyncSummary'] is! String) {
      throw const FormatException('Invalid Cookie Cloud preferences payload.');
    }
    return decoded;
  }

  Map<String, dynamic> _validateBackupPreferencesPayload(String encoded) {
    final decoded = jsonDecode(encoded);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Invalid backup preferences payload.');
    }
    const allowedKeys = <String>{
      'activeSiteId',
      'downloaderConfigs',
      'defaultDownloaderId',
      'themeMode',
      'dynamicColor',
      'seedColor',
      'autoLoadImages',
      'defaultDownloadCategory',
      'defaultDownloadTags',
      'defaultDownloadSavePath',
      'proxyEnabled',
      'proxyHost',
      'proxyPort',
      'proxyUsername',
      'proxyBypassLan',
      'proxyBypassRules',
      'downloaderCategoriesCache',
      'downloaderTagsCache',
      'aggregateSearchSettings',
    };
    if (decoded.keys.any((key) => !allowedKeys.contains(key)) ||
        (decoded.containsKey('activeSiteId') &&
            decoded['activeSiteId'] is! String) ||
        (decoded.containsKey('defaultDownloaderId') &&
            decoded['defaultDownloaderId'] != null &&
            decoded['defaultDownloaderId'] is! String) ||
        (decoded.containsKey('themeMode') && decoded['themeMode'] is! String) ||
        (decoded.containsKey('dynamicColor') &&
            decoded['dynamicColor'] is! bool) ||
        (decoded.containsKey('seedColor') && decoded['seedColor'] is! int) ||
        (decoded.containsKey('autoLoadImages') &&
            decoded['autoLoadImages'] is! bool) ||
        (decoded.containsKey('defaultDownloadCategory') &&
            decoded['defaultDownloadCategory'] is! String) ||
        (decoded.containsKey('defaultDownloadSavePath') &&
            decoded['defaultDownloadSavePath'] is! String) ||
        (decoded.containsKey('proxyEnabled') &&
            decoded['proxyEnabled'] is! bool) ||
        (decoded.containsKey('proxyHost') && decoded['proxyHost'] is! String) ||
        (decoded.containsKey('proxyPort') && decoded['proxyPort'] is! int) ||
        (decoded.containsKey('proxyUsername') &&
            decoded['proxyUsername'] is! String) ||
        (decoded.containsKey('proxyBypassLan') &&
            decoded['proxyBypassLan'] is! bool)) {
      throw const FormatException('Invalid backup preferences payload.');
    }

    bool isStringList(Object? value) =>
        value is List<dynamic> && value.every((item) => item is String);
    if ((decoded.containsKey('defaultDownloadTags') &&
            !isStringList(decoded['defaultDownloadTags'])) ||
        (decoded.containsKey('proxyBypassRules') &&
            !isStringList(decoded['proxyBypassRules']))) {
      throw const FormatException('Invalid backup preferences payload.');
    }

    final downloaderConfigs = decoded['downloaderConfigs'];
    if (downloaderConfigs != null) {
      if (downloaderConfigs is! List<dynamic>) {
        throw const FormatException('Invalid backup preferences payload.');
      }
      for (final value in downloaderConfigs) {
        if (value is! Map<String, dynamic>) {
          throw const FormatException('Invalid backup preferences payload.');
        }
        final config = DownloaderConfig.fromJson(value);
        if (config.password.isNotEmpty) {
          throw const FormatException('Invalid backup preferences payload.');
        }
      }
    }

    void validateStringListMap(String key) {
      final value = decoded[key];
      if (value == null) return;
      if (value is! Map<String, dynamic> ||
          value.entries.any(
            (entry) => entry.key.isEmpty || !isStringList(entry.value),
          )) {
        throw const FormatException('Invalid backup preferences payload.');
      }
    }

    validateStringListMap('downloaderCategoriesCache');
    validateStringListMap('downloaderTagsCache');
    final aggregate = decoded['aggregateSearchSettings'];
    if (aggregate != null) {
      if (aggregate is! Map<String, dynamic>) {
        throw const FormatException('Invalid backup preferences payload.');
      }
      AggregateSearchSettings.fromJson(aggregate);
    }
    return decoded;
  }

  Future<void> _stagePendingCompanionPreferences({
    required String revision,
    String? encodedSiteConfigs,
    String? encodedCookieCloudPreferences,
    String? encodedBackupPreferences,
  }) async {
    if (encodedSiteConfigs == null &&
        encodedCookieCloudPreferences == null &&
        encodedBackupPreferences == null) {
      throw ArgumentError('A companion preference payload is required.');
    }
    if (encodedSiteConfigs != null) {
      _validatePlainSiteConfigsPayload(encodedSiteConfigs);
    }
    if (encodedCookieCloudPreferences != null) {
      _validateCookieCloudPreferencesPayload(encodedCookieCloudPreferences);
    }
    if (encodedBackupPreferences != null) {
      _validateBackupPreferencesPayload(encodedBackupPreferences);
    }
    final prefs = await _prefs;
    final encodedPending = jsonEncode({
      'version': 1,
      'revision': revision,
      'siteConfigs': encodedSiteConfigs,
      'cookieCloudPreferences': encodedCookieCloudPreferences,
      'backupPreferences': encodedBackupPreferences,
    });
    await _requirePreferenceMutation(
      mutate: () => prefs.setString(
        StorageKeys.pendingSensitiveCompanionV1,
        encodedPending,
      ),
      verify: () =>
          prefs.getString(StorageKeys.pendingSensitiveCompanionV1) ==
          encodedPending,
      failureCode: 'companion_preferences_preparation_failed',
    );
  }

  Future<void> _finalizePendingCompanionPreferences({
    required String revision,
    String? encodedSiteConfigs,
    String? encodedCookieCloudPreferences,
    String? encodedBackupPreferences,
  }) async {
    final prefs = await _prefs;
    final encodedPending = prefs.getString(
      StorageKeys.pendingSensitiveCompanionV1,
    );
    if (encodedPending == null) {
      throw const SecureStorageUnavailableException(
        'companion_preferences_pending_missing',
      );
    }
    final pending = jsonDecode(encodedPending);
    if (pending is! Map<String, dynamic> ||
        pending['version'] != 1 ||
        pending['revision'] != revision ||
        pending['siteConfigs'] != encodedSiteConfigs ||
        pending['cookieCloudPreferences'] != encodedCookieCloudPreferences ||
        pending['backupPreferences'] != encodedBackupPreferences) {
      throw const SecureStorageUnavailableException(
        'companion_preferences_pending_invalid',
      );
    }
    if (encodedSiteConfigs != null) {
      _validatePlainSiteConfigsPayload(encodedSiteConfigs);
      await _requirePreferenceMutation(
        mutate: () =>
            prefs.setString(StorageKeys.siteConfigs, encodedSiteConfigs),
        verify: () =>
            prefs.getString(StorageKeys.siteConfigs) == encodedSiteConfigs,
        failureCode: 'plain_site_config_commit_failed',
      );
      _siteConfigsCacheDirty = true;
    }
    if (encodedCookieCloudPreferences != null) {
      await _persistCookieCloudPreferenceSnapshot(
        _validateCookieCloudPreferencesPayload(encodedCookieCloudPreferences),
      );
    }
    if (encodedBackupPreferences != null) {
      await _persistBackupPreferenceSnapshot(
        _validateBackupPreferencesPayload(encodedBackupPreferences),
      );
    }
    await _requirePreferenceMutation(
      mutate: () => prefs.remove(StorageKeys.pendingSensitiveCompanionV1),
      verify: () => !prefs.containsKey(StorageKeys.pendingSensitiveCompanionV1),
      failureCode: 'companion_preferences_ack_failed',
    );
  }

  Future<void> _recoverPendingCompanionPreferences(
    SecureStorageTransaction transaction,
  ) async {
    final prefs = await _prefs;
    final encodedPending = prefs.getString(
      StorageKeys.pendingSensitiveCompanionV1,
    );
    if (encodedPending == null) return;

    try {
      final pending = jsonDecode(encodedPending);
      if (pending is! Map<String, dynamic> ||
          pending['version'] != 1 ||
          pending['revision'] is! String ||
          (pending['siteConfigs'] != null &&
              pending['siteConfigs'] is! String) ||
          (pending['cookieCloudPreferences'] != null &&
              pending['cookieCloudPreferences'] is! String) ||
          (pending['backupPreferences'] != null &&
              pending['backupPreferences'] is! String) ||
          (pending['siteConfigs'] == null &&
              pending['cookieCloudPreferences'] == null &&
              pending['backupPreferences'] == null)) {
        throw const FormatException('Invalid pending companion preferences.');
      }
      final revision = pending['revision'] as String;
      final encodedSiteConfigs = pending['siteConfigs'] as String?;
      final encodedCookieCloudPreferences =
          pending['cookieCloudPreferences'] as String?;
      final encodedBackupPreferences = pending['backupPreferences'] as String?;
      final activeRevision = await transaction.activeRevision();
      if (activeRevision != revision) {
        await _requirePreferenceMutation(
          mutate: () => prefs.remove(StorageKeys.pendingSensitiveCompanionV1),
          verify: () =>
              !prefs.containsKey(StorageKeys.pendingSensitiveCompanionV1),
          failureCode: 'companion_preferences_ack_failed',
        );
        return;
      }
      await _finalizePendingCompanionPreferences(
        revision: revision,
        encodedSiteConfigs: encodedSiteConfigs,
        encodedCookieCloudPreferences: encodedCookieCloudPreferences,
        encodedBackupPreferences: encodedBackupPreferences,
      );
    } catch (error) {
      if (error is SecureStorageUnavailableException) rethrow;
      throw SecureStorageUnavailableException(
        'companion_preferences_recovery_failed',
        error,
      );
    }
  }

  String _transactionFailureCode(Object error) {
    if (error is SecureStorageTransactionException) {
      final cause = error.cause;
      if (cause is SecureStorageUnavailableException) return cause.code;
      return 'secure_transaction_${error.stage.name}';
    }
    if (error is SecureStorageUnavailableException) return error.code;
    return 'secure_transaction_failed';
  }

  Never _throwSensitiveTransactionUnavailable(Object error) {
    final code = _transactionFailureCode(error);
    if (code == 'secure_storage_operation_invalidated') {
      throw SecureStorageUnavailableException(code, error);
    }
    _markSecureStorageUnavailable(error, code: code);
    throw SecureStorageUnavailableException(code, error);
  }

  Future<Map<String, String>> _loadLegacySensitiveValues() async {
    final prefs = await _prefs;
    final siteIds = <String>{};
    final downloaderIds = <String>{};
    final webdavIds = <String>{};

    void collectIds(String? encoded, {required bool isList}) {
      if (encoded == null || encoded.isEmpty) return;
      try {
        final decoded = jsonDecode(encoded);
        final values = isList ? decoded as List<dynamic> : <dynamic>[decoded];
        for (final value in values) {
          if (value is! Map<String, dynamic>) {
            throw const FormatException('Invalid site configuration.');
          }
          final id = value['id'];
          if (id is String && id.isNotEmpty) siteIds.add(id);
        }
      } catch (error) {
        _markSecureStorageUnavailable(
          error,
          code: 'secure_transaction_bootstrap_invalid_site_config',
        );
        throw SecureStorageUnavailableException(
          'secure_transaction_bootstrap_invalid_site_config',
          error,
        );
      }
    }

    collectIds(prefs.getString(StorageKeys.siteConfigs), isList: true);
    collectIds(prefs.getString(StorageKeys.siteConfig), isList: false);

    void collectDownloaderIds(String? encoded) {
      if (encoded == null || encoded.isEmpty) return;
      try {
        final decoded = jsonDecode(encoded) as List<dynamic>;
        for (final value in decoded) {
          if (value is! Map<String, dynamic>) {
            throw const FormatException('Invalid downloader configuration.');
          }
          final id = value['id'];
          if (id is String && id.isNotEmpty) downloaderIds.add(id);
        }
      } catch (error) {
        _markSecureStorageUnavailable(
          error,
          code: 'secure_transaction_bootstrap_invalid_downloader_config',
        );
        throw SecureStorageUnavailableException(
          'secure_transaction_bootstrap_invalid_downloader_config',
          error,
        );
      }
    }

    collectDownloaderIds(prefs.getString(StorageKeys.downloaderConfigs));
    collectDownloaderIds(prefs.getString(StorageKeys.legacyQbClientConfigs));

    void collectWebDavIds(String? encoded, {required bool isList}) {
      if (encoded == null || encoded.isEmpty) return;
      try {
        final decoded = jsonDecode(encoded);
        final values = isList ? decoded as List<dynamic> : <dynamic>[decoded];
        for (final value in values) {
          if (value is! Map<String, dynamic>) {
            throw const FormatException('Invalid WebDAV configuration.');
          }
          final id = value['id'];
          if (id is String && id.isNotEmpty) webdavIds.add(id);
        }
      } catch (error) {
        _markSecureStorageUnavailable(
          error,
          code: 'secure_transaction_bootstrap_invalid_webdav_config',
        );
        throw SecureStorageUnavailableException(
          'secure_transaction_bootstrap_invalid_webdav_config',
          error,
        );
      }
    }

    collectWebDavIds(prefs.getString('webdav_config'), isList: false);
    collectWebDavIds(prefs.getString('webdav_config_history'), isList: true);

    final values = <String, String>{};
    for (final siteId in siteIds) {
      final cookieKey = StorageKeys.siteCookie(siteId);
      final cookie = await _loadSecureWithFallback(
        key: cookieKey,
        fallbackKey: StorageKeys.siteCookieFallback(siteId),
      );
      if (cookie != null && cookie.isNotEmpty) values[cookieKey] = cookie;

      final apiKeyKey = StorageKeys.siteApiKey(siteId);
      final apiKey = await _loadSecureWithFallback(
        key: apiKeyKey,
        fallbackKey: StorageKeys.siteApiKeyFallback(siteId),
      );
      if (apiKey != null && apiKey.isNotEmpty) values[apiKeyKey] = apiKey;
    }

    for (final downloaderId in downloaderIds) {
      final passwordKey = StorageKeys.downloaderPasswordKey(downloaderId);
      final password = await _loadSecureWithFallback(
        key: passwordKey,
        fallbackKey: StorageKeys.downloaderPasswordFallbackKey(downloaderId),
      );
      if (password != null && password.isNotEmpty) {
        values[passwordKey] = password;
      }
    }

    for (final webdavId in webdavIds) {
      final passwordKey = StorageKeys.webdavPassword(webdavId);
      final password = await _loadSecureWithFallback(
        key: passwordKey,
        fallbackKey: StorageKeys.webdavPasswordFallback(webdavId),
      );
      if (password != null && password.isNotEmpty) {
        values[passwordKey] = password;
      }
    }

    final legacySiteApiKey = await _loadSecureWithFallback(
      key: StorageKeys.legacySiteApiKey,
      fallbackKey: StorageKeys.legacySiteApiKeyFallback,
    );
    if (legacySiteApiKey != null && legacySiteApiKey.isNotEmpty) {
      values[StorageKeys.legacySiteApiKey] = legacySiteApiKey;
    }

    final proxyPassword = await _loadSecureWithFallback(
      key: StorageKeys.proxyPassword,
      fallbackKey: StorageKeys.proxyPasswordFallback,
    );
    if (proxyPassword != null && proxyPassword.isNotEmpty) {
      values[StorageKeys.proxyPassword] = proxyPassword;
    }

    final cookieCloudBundle = await _loadSecureWithFallback(
      key: StorageKeys.cookieCloudSecretsV2,
      fallbackKey: StorageKeys.cookieCloudSecretsV2Fallback,
    );
    // Preserve a found-but-empty structured bundle so its normal decoder can
    // reject it as corrupt; treating it as missing could revive legacy values.
    if (cookieCloudBundle != null) {
      values[StorageKeys.cookieCloudSecretsV2] = cookieCloudBundle;
    }
    return values;
  }

  Future<SecureStorageCommitResult> _commitSensitiveMutations(
    Iterable<SecureStorageMutation> requestedMutations, {
    String? pendingPlainSiteConfigs,
    String? pendingCookieCloudPreferences,
    String? pendingBackupPreferences,
  }) async {
    return _runSensitiveStorageOperation(() async {
      await _ensureSecureStorageUnlocked();
      if (!isSecureStorageReady) {
        throw const SecureStorageUnavailableException(
          'secure_transaction_unavailable',
        );
      }
      final prefs = await _prefs;
      final requested = requestedMutations.toList(growable: false);
      final hasCompanionPreferences =
          pendingPlainSiteConfigs != null ||
          pendingCookieCloudPreferences != null ||
          pendingBackupPreferences != null;
      if (requested.isEmpty && !hasCompanionPreferences) {
        throw ArgumentError('At least one sensitive mutation is required.');
      }
      // A plaintext fallback must not be allowed to recreate an explicitly
      // deleted secret if the process dies after the manifest switch but
      // before deferred cleanup. The guard is durable before either direct
      // secure deletion or transaction commit; normal cleanup removes it.
      await _stageSensitiveDeleteFallbackGuards(requested);
      final useTransaction =
          (_secureStorageTransactionsOverrideForTest ??
              _secureStorageTransactionsBuildEnabled) ||
          prefs.containsKey(_sensitiveManifestKey);

      if (!useTransaction) {
        try {
          for (final mutation in requested) {
            if (mutation.type == SecureStorageMutationType.upsert) {
              final wrote = await _secureWrite(
                key: mutation.logicalKey,
                value: mutation.value!,
              );
              if (!wrote ||
                  await _secureRead(mutation.logicalKey) != mutation.value) {
                throw const SecureStorageUnavailableException(
                  'secure_direct_verification_failed',
                );
              }
            } else {
              final deleted = await _secureDelete(key: mutation.logicalKey);
              if (!deleted || await _secureRead(mutation.logicalKey) != null) {
                throw const SecureStorageUnavailableException(
                  'secure_direct_verification_failed',
                );
              }
            }
          }
          await _flushAndroidSecureStorageDurabilityBarrier();
          await _persistDirectCompanionPreferences(
            encodedSiteConfigs: pendingPlainSiteConfigs,
            encodedCookieCloudPreferences: pendingCookieCloudPreferences,
            encodedBackupPreferences: pendingBackupPreferences,
          );
          _requireExpectedSecureStorageOperationEpoch();
          return SecureStorageCommitResult(
            revision: 'direct',
            activeEntryCount: requested.length,
            pendingCleanupCount: 0,
          );
        } catch (error) {
          _throwSensitiveTransactionUnavailable(error);
        }
      }

      final mutationsByKey = <String, SecureStorageMutation>{};
      if (!prefs.containsKey(_sensitiveManifestKey)) {
        final legacyValues = await _loadLegacySensitiveValues();
        for (final entry in legacyValues.entries) {
          mutationsByKey[entry.key] = SecureStorageMutation.upsert(
            entry.key,
            entry.value,
          );
        }
      }
      for (final mutation in requested) {
        mutationsByKey[mutation.logicalKey] = mutation;
      }
      if (mutationsByKey.isEmpty && hasCompanionPreferences) {
        mutationsByKey[_backupRestoreCheckpointKey] =
            const SecureStorageMutation.upsert(
              _backupRestoreCheckpointKey,
              'committed',
            );
      }
      if (mutationsByKey.isEmpty) {
        throw ArgumentError('At least one sensitive mutation is required.');
      }

      try {
        final result = await (await _getSensitiveTransaction()).commit(
          mutationsByKey.values,
          beforeManifestCommit: !hasCompanionPreferences
              ? null
              : (revision) => _stagePendingCompanionPreferences(
                  revision: revision,
                  encodedSiteConfigs: pendingPlainSiteConfigs,
                  encodedCookieCloudPreferences: pendingCookieCloudPreferences,
                  encodedBackupPreferences: pendingBackupPreferences,
                ),
          afterManifestCommit: !hasCompanionPreferences
              ? null
              : (revision) => _finalizePendingCompanionPreferences(
                  revision: revision,
                  encodedSiteConfigs: pendingPlainSiteConfigs,
                  encodedCookieCloudPreferences: pendingCookieCloudPreferences,
                  encodedBackupPreferences: pendingBackupPreferences,
                ),
        );
        _requireExpectedSecureStorageOperationEpoch();
        return result;
      } catch (error) {
        _throwSensitiveTransactionUnavailable(error);
      }
    });
  }

  Future<void> _persistDirectCompanionPreferences({
    String? encodedSiteConfigs,
    String? encodedCookieCloudPreferences,
    String? encodedBackupPreferences,
  }) async {
    if (encodedSiteConfigs != null) {
      _validatePlainSiteConfigsPayload(encodedSiteConfigs);
      final prefs = await _prefs;
      await _requirePreferenceMutation(
        mutate: () =>
            prefs.setString(StorageKeys.siteConfigs, encodedSiteConfigs),
        verify: () =>
            prefs.getString(StorageKeys.siteConfigs) == encodedSiteConfigs,
        failureCode: 'plain_site_config_commit_failed',
      );
      _siteConfigsCacheDirty = true;
    }
    if (encodedCookieCloudPreferences != null) {
      await _persistCookieCloudPreferenceSnapshot(
        _validateCookieCloudPreferencesPayload(encodedCookieCloudPreferences),
      );
    }
    if (encodedBackupPreferences != null) {
      await _persistBackupPreferenceSnapshot(
        _validateBackupPreferencesPayload(encodedBackupPreferences),
      );
    }
  }

  Future<String?> _readSensitiveValue({
    required String key,
    required String fallbackKey,
  }) async {
    return _runSensitiveStorageOperation(() async {
      await _ensureSecureStorageUnlocked();
      // Linux keeps its historic plaintext fallback only after the keyring has
      // actually failed. A healthy Linux keyring must use the same revision
      // manifest path as every other platform, otherwise a process kill can
      // still leave a partially updated batch of secrets.
      if (_isPlaintextFallbackActive) {
        return _loadSecureWithFallback(key: key, fallbackKey: fallbackKey);
      }

      final prefs = await _prefs;
      if (!prefs.containsKey(_sensitiveManifestKey)) {
        return _loadSecureWithFallback(key: key, fallbackKey: fallbackKey);
      }
      try {
        return await _loadTransactionValueWithFallback(
          transaction: await _getSensitiveTransaction(),
          prefs: prefs,
          key: key,
          fallbackKey: fallbackKey,
        );
      } catch (error) {
        _throwSensitiveTransactionUnavailable(error);
      }
    });
  }

  Future<String?> _loadTransactionValueWithFallback({
    required SecureStorageTransaction transaction,
    required SharedPreferences prefs,
    required String key,
    required String fallbackKey,
  }) => _runInCurrentSecureStorageOperationEpoch(
    () => _loadTransactionValueWithFallbackInCurrentEpoch(
      transaction: transaction,
      prefs: prefs,
      key: key,
      fallbackKey: fallbackKey,
    ),
  );

  Future<String?> _loadTransactionValueWithFallbackInCurrentEpoch({
    required SecureStorageTransaction transaction,
    required SharedPreferences prefs,
    required String key,
    required String fallbackKey,
  }) async {
    final secureValue = await transaction.read(key);
    final hasFallback = prefs.containsKey(fallbackKey);
    if (secureValue != null) {
      if (hasFallback) {
        final fallbackValue = prefs.getString(fallbackKey);
        if (fallbackValue == null) {
          throw const SecureStorageUnavailableException(
            'fallback_value_invalid',
          );
        }
        if (fallbackValue == secureValue) {
          await _flushAndroidSecureStorageDurabilityBarrier();
          await _removeSensitiveFallback(fallbackKey, resolveConflict: true);
        } else {
          await _recordFallbackConflict(fallbackKey);
        }
      }
      return secureValue;
    }

    if (!hasFallback) return null;
    final fallbackValue = prefs.getString(fallbackKey);
    if (fallbackValue == null) {
      throw const SecureStorageUnavailableException('fallback_value_invalid');
    }

    // A missing active mapping is authoritative when this plaintext value was
    // already retained because of a conflict. This state can occur when the
    // process exits after a delete manifest commit but before fallback cleanup.
    // Never resurrect that stale plaintext into a new secure revision.
    if (_fallbackConflictKeys(prefs).contains(fallbackKey)) {
      return null;
    }

    await transaction.commit([
      SecureStorageMutation.upsert(key, fallbackValue),
    ]);
    if (await transaction.read(key) != fallbackValue) {
      throw const SecureStorageUnavailableException(
        'fallback_migration_verification_failed',
      );
    }
    await _removeSensitiveFallback(fallbackKey, resolveConflict: true);
    return fallbackValue;
  }

  String? _fallbackKeyForSensitiveLogicalKey(String logicalKey) {
    if (logicalKey == StorageKeys.legacySiteApiKey) {
      return StorageKeys.legacySiteApiKeyFallback;
    }
    if (logicalKey == StorageKeys.proxyPassword) {
      return StorageKeys.proxyPasswordFallback;
    }
    if (logicalKey == StorageKeys.deviceId) return StorageKeys.deviceIdFallback;
    if (logicalKey == StorageKeys.cookieCloudSecretsV2) {
      return StorageKeys.cookieCloudSecretsV2Fallback;
    }
    if (logicalKey == StorageKeys.cookieCloudUrl) {
      return StorageKeys.cookieCloudUrlFallback;
    }
    if (logicalKey == StorageKeys.cookieCloudUuid) {
      return StorageKeys.cookieCloudUuidFallback;
    }
    if (logicalKey == StorageKeys.cookieCloudPassword) {
      return StorageKeys.cookieCloudPasswordFallback;
    }

    const siteApiKeyPrefix = 'site.apiKey.';
    if (logicalKey.startsWith(siteApiKeyPrefix)) {
      final id = logicalKey.substring(siteApiKeyPrefix.length);
      return id.isEmpty ? null : StorageKeys.siteApiKeyFallback(id);
    }
    const siteCookiePrefix = 'site.cookie.';
    if (logicalKey.startsWith(siteCookiePrefix)) {
      final id = logicalKey.substring(siteCookiePrefix.length);
      return id.isEmpty ? null : StorageKeys.siteCookieFallback(id);
    }
    const downloaderPasswordPrefix = 'downloader.password.';
    if (logicalKey.startsWith(downloaderPasswordPrefix)) {
      final id = logicalKey.substring(downloaderPasswordPrefix.length);
      return id.isEmpty ? null : StorageKeys.downloaderPasswordFallbackKey(id);
    }
    const webdavPasswordPrefix = 'webdav.password.';
    if (logicalKey.startsWith(webdavPasswordPrefix)) {
      final id = logicalKey.substring(webdavPasswordPrefix.length);
      return id.isEmpty ? null : StorageKeys.webdavPasswordFallback(id);
    }
    const legacyQbPasswordPrefix = 'qb.password.';
    if (logicalKey.startsWith(legacyQbPasswordPrefix)) {
      final id = logicalKey.substring(legacyQbPasswordPrefix.length);
      return id.isEmpty ? null : StorageKeys.legacyQbPasswordFallbackKey(id);
    }
    return null;
  }

  Future<void> _stageSensitiveDeleteFallbackGuards(
    Iterable<SecureStorageMutation> mutations,
  ) async {
    final fallbackKeys = mutations
        .where((mutation) => mutation.type == SecureStorageMutationType.delete)
        .map(
          (mutation) => _fallbackKeyForSensitiveLogicalKey(mutation.logicalKey),
        )
        .whereType<String>()
        .toSet();
    if (fallbackKeys.isEmpty) return;
    await _runFallbackMetadataOperation((prefs) async {
      final guardedFallbacks = fallbackKeys.where(prefs.containsKey).toSet();
      if (guardedFallbacks.isEmpty) return;
      final conflicts = _fallbackConflictKeys(prefs)..addAll(guardedFallbacks);
      await _persistFallbackConflictKeys(prefs, conflicts);
    });
  }

  Future<void> _assertSiteManifestConsistentWithEmptyPlainConfig() async {
    final prefs = await _prefs;
    if (!prefs.containsKey(_sensitiveManifestKey)) return;
    try {
      final hasActiveSiteSecrets = await (await _getSensitiveTransaction())
          .hasActiveLogicalKeyWithPrefix(const [
            'site.cookie.',
            'site.apiKey.',
          ]);
      if (!hasActiveSiteSecrets) return;
    } catch (error) {
      _throwSensitiveTransactionUnavailable(error);
    }

    const error = SecureStorageUnavailableException(
      'secure_transaction_requires_restore',
    );
    _markSecureStorageUnavailable(error, code: error.code);
    throw error;
  }

  Set<String> _fallbackConflictKeys(SharedPreferences prefs) {
    final conflicts =
        (prefs.getStringList(StorageKeys.secureFallbackConflictsV1) ??
                const <String>[])
            .toSet();
    if (conflicts.isEmpty &&
        (prefs.getBool(StorageKeys.secureFallbackConflict) ?? false)) {
      conflicts.addAll(prefs.getKeys().where(_isPlaintextSensitivePreference));
    }
    return conflicts;
  }

  Future<void> _persistFallbackConflictKeys(
    SharedPreferences prefs,
    Set<String> conflicts,
  ) async {
    final existingConflicts = conflicts.where(prefs.containsKey).toList()
      ..sort();
    if (existingConflicts.isEmpty) {
      if (prefs.containsKey(StorageKeys.secureFallbackConflictsV1)) {
        await _requirePreferenceMutation(
          mutate: () => prefs.remove(StorageKeys.secureFallbackConflictsV1),
          verify: () =>
              !prefs.containsKey(StorageKeys.secureFallbackConflictsV1),
          failureCode: 'fallback_conflict_marker_commit_failed',
        );
      }
      if (prefs.containsKey(StorageKeys.secureFallbackConflict)) {
        await _requirePreferenceMutation(
          mutate: () => prefs.remove(StorageKeys.secureFallbackConflict),
          verify: () => !prefs.containsKey(StorageKeys.secureFallbackConflict),
          failureCode: 'fallback_conflict_marker_commit_failed',
        );
      }
      return;
    }
    await _requirePreferenceMutation(
      mutate: () => prefs.setStringList(
        StorageKeys.secureFallbackConflictsV1,
        existingConflicts,
      ),
      verify: () => _sameStringList(
        prefs.getStringList(StorageKeys.secureFallbackConflictsV1),
        existingConflicts,
      ),
      failureCode: 'fallback_conflict_marker_commit_failed',
    );
    await _requirePreferenceMutation(
      mutate: () => prefs.setBool(StorageKeys.secureFallbackConflict, true),
      verify: () => prefs.getBool(StorageKeys.secureFallbackConflict) == true,
      failureCode: 'fallback_conflict_marker_commit_failed',
    );
  }

  Future<void> _updateFallbackConflictKeys(
    void Function(Set<String> conflicts) update,
  ) => _runFallbackMetadataOperation(
    (prefs) async {
      final conflicts = _fallbackConflictKeys(prefs);
      update(conflicts);
      await _persistFallbackConflictKeys(prefs, conflicts);
    },
    // Downloader configuration normalization can run before sensitive
    // storage initialization. If it is already in a sensitive-operation zone
    // the inherited epoch is still enforced by the queue above.
    requireSecureStorageEpoch: false,
  );

  Future<void> _recordFallbackConflict(String fallbackKey) async {
    await _runFallbackMetadataOperation((prefs) async {
      final conflicts = _fallbackConflictKeys(prefs)..add(fallbackKey);
      await _persistFallbackConflictKeys(prefs, conflicts);
    });
  }

  Future<void> _clearFallbackConflictMarker(String conflictKey) async {
    await _runFallbackMetadataOperation((prefs) async {
      final conflicts = _fallbackConflictKeys(prefs)..remove(conflictKey);
      await _persistFallbackConflictKeys(prefs, conflicts);
    });
  }

  Future<void> _removeSensitiveFallback(
    String fallbackKey, {
    bool resolveConflict = false,
    int? expectedSecureStorageEpoch,
  }) async {
    final expected =
        expectedSecureStorageEpoch ??
        _expectedSecureStorageOperationEpoch ??
        captureSecureStorageOperationEpoch();
    await _beforeSensitiveFallbackCleanupOverrideForTest?.call(fallbackKey);
    await _runFallbackMetadataOperation((prefs) async {
      final conflicts = _fallbackConflictKeys(prefs);
      await _afterSensitiveFallbackCleanupMetadataReadOverrideForTest?.call(
        fallbackKey,
      );
      if (conflicts.contains(fallbackKey) && !resolveConflict) return;
      if (prefs.containsKey(fallbackKey)) {
        await _requirePreferenceMutation(
          mutate: () => prefs.remove(fallbackKey),
          verify: () => !prefs.containsKey(fallbackKey),
          failureCode: 'fallback_cleanup_failed',
        );
      }
      conflicts.remove(fallbackKey);
      await _persistFallbackConflictKeys(prefs, conflicts);
    }, expectedSecureStorageEpoch: expected);
  }

  bool _isPlaintextSensitivePreference(String key) {
    return key == StorageKeys.siteConfigs ||
        key == StorageKeys.downloaderConfigs ||
        key == StorageKeys.legacySiteApiKeyFallback ||
        key == StorageKeys.proxyPasswordFallback ||
        key == StorageKeys.deviceIdFallback ||
        key == StorageKeys.cookieCloudUrl ||
        key == StorageKeys.cookieCloudUrlFallback ||
        key == StorageKeys.cookieCloudUuid ||
        key == StorageKeys.cookieCloudUuidFallback ||
        key == StorageKeys.cookieCloudPassword ||
        key == StorageKeys.cookieCloudPasswordFallback ||
        key == StorageKeys.cookieCloudSecretsV2Fallback ||
        key.startsWith('site.apiKey.fallback.') ||
        key.startsWith('site.cookie.fallback.') ||
        key.startsWith('downloader.password.fallback.') ||
        key.startsWith('qb.password.fallback.') ||
        key.startsWith('secureStorage.migrationConflict.qbPassword.') ||
        key.startsWith('webdav.password.fallback.');
  }

  Future<void> _refreshFallbackConflictFlag() =>
      _runFallbackMetadataOperation((prefs) async {
        await _persistFallbackConflictKeys(prefs, _fallbackConflictKeys(prefs));
      }, requireSecureStorageEpoch: false);

  Future<void> _saveSecureWithFallback({
    required String key,
    required String fallbackKey,
    required String value,
  }) => _runInCurrentSecureStorageOperationEpoch(
    () => _saveSecureWithFallbackInCurrentEpoch(
      key: key,
      fallbackKey: fallbackKey,
      value: value,
    ),
  );

  Future<void> _saveSecureWithFallbackInCurrentEpoch({
    required String key,
    required String fallbackKey,
    required String value,
  }) async {
    final wrote = await _secureWrite(key: key, value: value);
    final prefs = await _prefs;
    if (wrote) {
      final verified = await _secureReadResult(key);
      if (verified.status != SecureReadStatus.found ||
          verified.value != value) {
        _throwSecureStorageUnavailable(
          'secure_storage_write_verification_failed',
        );
      }
      await _flushAndroidSecureStorageDurabilityBarrier();
      await _removeSensitiveFallback(fallbackKey);
      return;
    }
    if (!_isPlaintextFallbackActive) {
      _throwSecureStorageUnavailable('secure_storage_write_failed');
    }
    await _requirePreferenceMutation(
      mutate: () => prefs.setString(fallbackKey, value),
      verify: () => prefs.getString(fallbackKey) == value,
      failureCode: 'plaintext_fallback_commit_failed',
    );
    await _secureSharedPreferencesFile();
  }

  Future<String?> _loadSecureWithFallback({
    required String key,
    required String fallbackKey,
  }) => _runInCurrentSecureStorageOperationEpoch(
    () => _loadSecureWithFallbackInCurrentEpoch(
      key: key,
      fallbackKey: fallbackKey,
    ),
  );

  Future<String?> _loadSecureWithFallbackInCurrentEpoch({
    required String key,
    required String fallbackKey,
  }) async {
    final prefs = await _prefs;
    final secureResult = await _secureReadResult(key);
    final hasFallback = prefs.containsKey(fallbackKey);
    final fallbackValue = hasFallback ? prefs.getString(fallbackKey) : null;
    if (hasFallback && fallbackValue == null) {
      _throwSecureStorageUnavailable('fallback_value_invalid');
    }

    if (secureResult.status == SecureReadStatus.unavailable) {
      if (_isPlaintextFallbackActive) return fallbackValue;
      _throwSecureStorageUnavailable(
        secureResult.failureCode ?? 'secure_storage_unavailable',
      );
    }

    if (secureResult.status == SecureReadStatus.found) {
      final secureValue = secureResult.value!;
      if (hasFallback) {
        if (fallbackValue == secureValue) {
          await _flushAndroidSecureStorageDurabilityBarrier();
          await _removeSensitiveFallback(fallbackKey, resolveConflict: true);
        } else {
          await _recordFallbackConflict(fallbackKey);
        }
      }
      return secureValue;
    }

    if (!hasFallback) return null;
    if (_isPlaintextFallbackActive) return fallbackValue;

    // The durable deletion guard is written before an explicit direct delete.
    // A missing secure value with this marker is authoritative; migrating the
    // remaining plaintext would resurrect a secret the user just removed.
    if (_fallbackConflictKeys(prefs).contains(fallbackKey)) return null;

    await _secureWrite(key: key, value: fallbackValue!);
    final verified = await _secureReadResult(key);
    if (verified.status != SecureReadStatus.found ||
        verified.value != fallbackValue) {
      _throwSecureStorageUnavailable('fallback_migration_verification_failed');
    }
    await _flushAndroidSecureStorageDurabilityBarrier();
    await _removeSensitiveFallback(fallbackKey, resolveConflict: true);
    return fallbackValue;
  }

  Future<bool> hasSecureStorageFallbackConflict() async {
    final prefs = await _prefs;
    return _fallbackConflictKeys(prefs).isNotEmpty ||
        (prefs.getBool(StorageKeys.secureFallbackConflict) ?? false);
  }

  // 版本管理
  static const String currentVersion = '1.2.0';

  // 私有方法：保护 Linux/macOS 本地降级存储文件的权限位为 600
  Future<void> _secureSharedPreferencesFile() async {
    await secureSharedPreferencesFile();
  }

  /// 检查并执行数据迁移
  Future<void> checkAndMigrate() =>
      _runInCurrentSecureStorageOperationEpoch(_checkAndMigrateInCurrentEpoch);

  Future<void> _checkAndMigrateInCurrentEpoch() async {
    final prefs = await _prefs;
    final storedVersion = prefs.getString(StorageKeys.appVersion);

    if (storedVersion == null) {
      // 首次安装或从1.0.0升级（1.0.0版本没有版本标记）
      await _migrateFrom100To110();
      await _requirePreferenceMutation(
        mutate: () => prefs.setString(StorageKeys.appVersion, currentVersion),
        verify: () => prefs.getString(StorageKeys.appVersion) == currentVersion,
        failureCode: 'app_version_commit_failed',
      );
    } else if (storedVersion != currentVersion) {
      // 处理其他版本迁移
      if (storedVersion == '1.0.0') {
        await _migrateFrom100To110();
      } else if (storedVersion == '1.1.0') {
        await _migrateFrom110To120();
      }
      await _requirePreferenceMutation(
        mutate: () => prefs.setString(StorageKeys.appVersion, currentVersion),
        verify: () => prefs.getString(StorageKeys.appVersion) == currentVersion,
        failureCode: 'app_version_commit_failed',
      );
    }

    await _migrateKnownMobileFallbacks();

    // 【安全加固】确保 Linux/macOS 下降级存储文件的权限位为 600
    await _secureSharedPreferencesFile();
  }

  Future<void> _migrateKnownMobileFallbacks() async {
    if (kIsWeb ||
        (_currentPlatform != TargetPlatform.android &&
            _currentPlatform != TargetPlatform.iOS)) {
      return;
    }

    final prefs = await _prefs;
    final keys = prefs.getKeys();

    const siteApiPrefix = 'site.apiKey.fallback.';
    const siteCookiePrefix = 'site.cookie.fallback.';
    const downloaderPrefix = 'downloader.password.fallback.';
    const legacyQbPasswordPrefix = 'qb.password.fallback.';
    const webdavPrefix = 'webdav.password.fallback.';
    for (final fallbackKey in keys) {
      if (fallbackKey.startsWith(siteApiPrefix)) {
        final id = fallbackKey.substring(siteApiPrefix.length);
        if (id.isNotEmpty) await _loadSiteApiKey(id);
      } else if (fallbackKey.startsWith(siteCookiePrefix)) {
        final id = fallbackKey.substring(siteCookiePrefix.length);
        if (id.isNotEmpty) await _loadSiteCookie(id);
      } else if (fallbackKey.startsWith(downloaderPrefix)) {
        final id = fallbackKey.substring(downloaderPrefix.length);
        if (id.isNotEmpty) await loadDownloaderPassword(id);
      } else if (fallbackKey.startsWith(legacyQbPasswordPrefix)) {
        final id = fallbackKey.substring(legacyQbPasswordPrefix.length);
        if (id.isNotEmpty) await _migratePassword(id);
      } else if (fallbackKey.startsWith(webdavPrefix)) {
        final id = fallbackKey.substring(webdavPrefix.length);
        if (id.isNotEmpty) await loadWebDAVPassword(id);
      }
    }

    if (prefs.containsKey(StorageKeys.legacySiteApiKeyFallback)) {
      await _readSensitiveValue(
        key: StorageKeys.legacySiteApiKey,
        fallbackKey: StorageKeys.legacySiteApiKeyFallback,
      );
    }
    if (prefs.containsKey(StorageKeys.proxyPasswordFallback)) {
      await loadProxyPassword();
    }
    if (prefs.containsKey(StorageKeys.deviceIdFallback)) {
      await loadDeviceId();
    }

    await _migrateEmbeddedDownloaderPasswords();

    // 同时执行 Cookie Cloud 三旧键到单一加密 JSON 条目的两次启动迁移。
    await _loadCookieCloudSecrets();
  }

  Future<void> _migrateEmbeddedDownloaderPasswords() async {
    final prefs = await _prefs;
    final encoded = prefs.getString(StorageKeys.downloaderConfigs);
    if (encoded == null || encoded.isEmpty) return;

    List<dynamic> decoded;
    try {
      decoded = jsonDecode(encoded) as List<dynamic>;
    } catch (error) {
      _throwSecureStorageUnavailable(
        'embedded_downloader_password_config_invalid',
        error,
      );
    }

    var changed = false;
    var hasConflict = false;
    final sanitizedConfigs = <Map<String, dynamic>>[];
    for (final value in decoded) {
      if (value is! Map<String, dynamic>) {
        _throwSecureStorageUnavailable(
          'embedded_downloader_password_config_invalid',
        );
      }
      final sanitized = Map<String, dynamic>.from(value);
      final nested = value['config'];
      final nestedConfig = nested is Map<String, dynamic>
          ? Map<String, dynamic>.from(nested)
          : null;
      final nestedPassword = nestedConfig?['password'];
      final topLevelPassword = value['password'];
      final hasPasswordField =
          (nestedConfig?.containsKey('password') ?? false) ||
          value.containsKey('password');
      if ((nestedPassword != null && nestedPassword is! String) ||
          (topLevelPassword != null && topLevelPassword is! String) ||
          (nestedPassword is String &&
              nestedPassword.isNotEmpty &&
              topLevelPassword is String &&
              topLevelPassword.isNotEmpty &&
              nestedPassword != topLevelPassword)) {
        hasConflict = true;
        sanitizedConfigs.add(sanitized);
        continue;
      }
      final password = nestedPassword is String && nestedPassword.isNotEmpty
          ? nestedPassword
          : topLevelPassword is String && topLevelPassword.isNotEmpty
          ? topLevelPassword
          : null;
      if (password != null) {
        final id = value['id'];
        if (id is! String || id.isEmpty) {
          hasConflict = true;
          sanitizedConfigs.add(sanitized);
          continue;
        } else {
          final securePassword = await _readSensitiveValue(
            key: StorageKeys.downloaderPasswordKey(id),
            fallbackKey: StorageKeys.downloaderPasswordFallbackKey(id),
          );
          if (securePassword == null) {
            await saveDownloaderPassword(id, password);
            final verified = await loadDownloaderPassword(id);
            if (verified != password) {
              _throwSecureStorageUnavailable(
                'embedded_downloader_password_verification_failed',
              );
            }
          } else if (securePassword != password) {
            hasConflict = true;
            sanitizedConfigs.add(sanitized);
            continue;
          }
        }
      }
      if (hasPasswordField) {
        sanitized.remove('password');
        nestedConfig?.remove('password');
        if (nestedConfig != null) sanitized['config'] = nestedConfig;
        changed = true;
      }
      sanitizedConfigs.add(sanitized);
    }

    if (changed) {
      final sanitizedEncoded = jsonEncode(sanitizedConfigs);
      await _requirePreferenceMutation(
        mutate: () =>
            prefs.setString(StorageKeys.downloaderConfigs, sanitizedEncoded),
        verify: () =>
            prefs.getString(StorageKeys.downloaderConfigs) == sanitizedEncoded,
        failureCode: 'embedded_downloader_password_cleanup_failed',
      );
    }

    await _updateFallbackConflictKeys((conflicts) {
      if (hasConflict) {
        conflicts.add(StorageKeys.downloaderConfigs);
      } else {
        conflicts.remove(StorageKeys.downloaderConfigs);
      }
    });
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

        // 新普通配置读回确认后才删除旧来源，避免进程/平台写入失败时丢失。
        final encodedDownloaderConfigs = jsonEncode(downloaderConfigs);
        await _requirePreferenceMutation(
          mutate: () => prefs.setString(
            StorageKeys.downloaderConfigs,
            encodedDownloaderConfigs,
          ),
          verify: () =>
              prefs.getString(StorageKeys.downloaderConfigs) ==
              encodedDownloaderConfigs,
          failureCode: 'legacy_qb_config_verification_failed',
        );

        // 迁移默认下载器ID
        final defaultQbId = prefs.getString(StorageKeys.legacyDefaultQbId);
        if (defaultQbId != null) {
          await _requirePreferenceMutation(
            mutate: () =>
                prefs.setString(StorageKeys.defaultDownloaderId, defaultQbId),
            verify: () =>
                prefs.getString(StorageKeys.defaultDownloaderId) == defaultQbId,
            failureCode: 'legacy_qb_default_verification_failed',
          );
        }

        // 清理旧配置
        await _requirePreferenceMutation(
          mutate: () => prefs.remove(StorageKeys.legacyQbClientConfigs),
          verify: () => !prefs.containsKey(StorageKeys.legacyQbClientConfigs),
          failureCode: 'legacy_qb_config_cleanup_failed',
        );
        if (prefs.containsKey(StorageKeys.legacyDefaultQbId)) {
          await _requirePreferenceMutation(
            mutate: () => prefs.remove(StorageKeys.legacyDefaultQbId),
            verify: () => !prefs.containsKey(StorageKeys.legacyDefaultQbId),
            failureCode: 'legacy_qb_config_cleanup_failed',
          );
        }
      } on SecureStorageUnavailableException {
        rethrow;
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
    final prefs = await _prefs;
    final legacySecureKey = StorageKeys.legacyQbPasswordKey(clientId);
    final legacyFallbackKey = StorageKeys.legacyQbPasswordFallbackKey(clientId);
    final conflictMarker = StorageKeys.legacyQbPasswordConflictMarker(clientId);
    final oldSecure = await _secureReadResult(legacySecureKey);
    if (oldSecure.status == SecureReadStatus.unavailable) {
      _throwSecureStorageUnavailable(
        oldSecure.failureCode ?? 'secure_storage_unavailable',
      );
    }
    final hasLegacyFallback = prefs.containsKey(legacyFallbackKey);
    final oldFallback = hasLegacyFallback
        ? prefs.getString(legacyFallbackKey)
        : null;
    if (hasLegacyFallback && oldFallback == null) {
      _throwSecureStorageUnavailable('fallback_value_invalid');
    }

    final candidates = <String>{};
    if (oldSecure.status == SecureReadStatus.found) {
      candidates.add(oldSecure.value!);
    }
    if (oldFallback != null && oldFallback.isNotEmpty) {
      candidates.add(oldFallback);
    }
    if (candidates.isEmpty) {
      await _cleanupLegacyQbPasswordSources(clientId);
      return;
    }

    final target = await loadDownloaderPassword(clientId);
    final hasConflict =
        candidates.length > 1 ||
        (target != null && !candidates.contains(target));
    if (hasConflict) {
      await _runFallbackMetadataOperation((currentPrefs) async {
        final conflicts = _fallbackConflictKeys(currentPrefs);
        if (oldSecure.status == SecureReadStatus.found) {
          await _requirePreferenceMutation(
            mutate: () => currentPrefs.setBool(conflictMarker, true),
            verify: () => currentPrefs.getBool(conflictMarker) == true,
            failureCode: 'legacy_qb_conflict_marker_commit_failed',
          );
          conflicts.add(conflictMarker);
        }
        if (hasLegacyFallback) conflicts.add(legacyFallbackKey);
        await _persistFallbackConflictKeys(currentPrefs, conflicts);
      });
      return;
    }

    final candidate = candidates.single;
    if (target == null && candidate.isNotEmpty) {
      await saveDownloaderPassword(clientId, candidate);
      if (await loadDownloaderPassword(clientId) != candidate) {
        _throwSecureStorageUnavailable(
          'legacy_qb_password_verification_failed',
        );
      }
    }
    await _cleanupLegacyQbPasswordSources(clientId);
  }

  Future<void> _cleanupLegacyQbPasswordSources(String clientId) =>
      _runInCurrentSecureStorageOperationEpoch(
        () => _cleanupLegacyQbPasswordSourcesInCurrentEpoch(clientId),
      );

  Future<void> _cleanupLegacyQbPasswordSourcesInCurrentEpoch(
    String clientId,
  ) async {
    await _stageSensitiveDeleteFallbackGuards([
      SecureStorageMutation.delete(StorageKeys.legacyQbPasswordKey(clientId)),
    ]);
    await _secureDelete(key: StorageKeys.legacyQbPasswordKey(clientId));
    await _removeSensitiveFallback(
      StorageKeys.legacyQbPasswordFallbackKey(clientId),
      resolveConflict: true,
    );
    await _removeSensitiveFallback(
      StorageKeys.legacyQbPasswordConflictMarker(clientId),
      resolveConflict: true,
    );
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
  Future<void> saveSite(SiteConfig config) =>
      _runInCurrentSecureStorageOperationEpoch(
        () => _saveSiteInCurrentEpoch(config),
      );

  Future<void> _saveSiteInCurrentEpoch(SiteConfig config) async {
    final prefs = await _prefs;
    final serialized = jsonEncode({
      ...config.toJson(),
      'apiKey': null,
      'cookie': null,
    });

    if (isSecureStorageReady) {
      final cookieKey = StorageKeys.siteCookie(config.id);
      await _commitSensitiveMutations([
        (config.apiKey ?? '').isEmpty
            ? const SecureStorageMutation.delete(StorageKeys.legacySiteApiKey)
            : SecureStorageMutation.upsert(
                StorageKeys.legacySiteApiKey,
                config.apiKey!,
              ),
        (config.cookie ?? '').isEmpty
            ? SecureStorageMutation.delete(cookieKey)
            : SecureStorageMutation.upsert(cookieKey, config.cookie!),
      ]);
      await _removeSensitiveFallback(StorageKeys.legacySiteApiKeyFallback);
      await _removeSensitiveFallback(StorageKeys.siteCookieFallback(config.id));
    } else {
      await _saveSecureWithFallback(
        key: StorageKeys.legacySiteApiKey,
        fallbackKey: StorageKeys.legacySiteApiKeyFallback,
        value: config.apiKey ?? '',
      );
      await _saveSiteCookieWithoutTransaction(config.id, config.cookie ?? '');
    }

    await _requirePreferenceMutation(
      mutate: () => prefs.setString(StorageKeys.siteConfig, serialized),
      verify: () => prefs.getString(StorageKeys.siteConfig) == serialized,
      failureCode: 'plain_site_config_commit_failed',
    );
  }

  Future<SiteConfig?> loadSite() async {
    final prefs = await _prefs;
    final str = prefs.getString(StorageKeys.siteConfig);
    if (str == null) return null;
    final json = jsonDecode(str) as Map<String, dynamic>;
    final base = SiteConfig.fromJson(json);

    final apiKey = await _readSensitiveValue(
      key: StorageKeys.legacySiteApiKey,
      fallbackKey: StorageKeys.legacySiteApiKeyFallback,
    );
    final cookie = await _readSensitiveValue(
      key: StorageKeys.siteCookie(base.id),
      fallbackKey: StorageKeys.siteCookieFallback(base.id),
    );

    return base.copyWith(apiKey: apiKey, cookie: cookie);
  }

  // 多站点配置管理
  Future<void> saveSiteConfigs(
    List<SiteConfig> configs, {
    bool resolveFallbackConflicts = false,
  }) => _runSiteConfigOperation(
    () => _saveSiteConfigsUnlocked(
      configs,
      resolveFallbackConflicts: resolveFallbackConflicts,
    ),
  );

  Future<void> _saveSiteConfigsUnlocked(
    List<SiteConfig> configs, {
    required bool resolveFallbackConflicts,
  }) => _runInCurrentSecureStorageOperationEpoch(
    () => _saveSiteConfigsInCurrentEpoch(
      configs,
      resolveFallbackConflicts: resolveFallbackConflicts,
    ),
  );

  Future<void> _saveSiteConfigsInCurrentEpoch(
    List<SiteConfig> configs, {
    required bool resolveFallbackConflicts,
  }) async {
    final prefs = await _prefs;
    final encodedPlainSiteConfigs = _encodePlainSiteConfigs(configs);
    final mutations = <SecureStorageMutation>[];
    final fallbackKeys = <String>{};
    final fallbackKeysToResolve = <String>{};
    final incomingSiteIds = configs.map((config) => config.id).toSet();
    final removedSiteIds = _loadPersistedPlainSiteIds(
      prefs,
    ).difference(incomingSiteIds);
    var plainConfigsCommittedWithSensitiveRevision = false;

    if (isSecureStorageReady) {
      for (final config in configs) {
        if (config.apiKey != null) {
          final key = StorageKeys.siteApiKey(config.id);
          mutations.add(
            config.apiKey!.isEmpty
                ? SecureStorageMutation.delete(key)
                : SecureStorageMutation.upsert(key, config.apiKey!),
          );
          fallbackKeys.add(StorageKeys.siteApiKeyFallback(config.id));
        }
        if (config.cookie != null) {
          final key = StorageKeys.siteCookie(config.id);
          mutations.add(
            config.cookie!.isEmpty
                ? SecureStorageMutation.delete(key)
                : SecureStorageMutation.upsert(key, config.cookie!),
          );
          fallbackKeys.add(StorageKeys.siteCookieFallback(config.id));
        }
      }
      for (final siteId in removedSiteIds) {
        mutations
          ..add(SecureStorageMutation.delete(StorageKeys.siteApiKey(siteId)))
          ..add(SecureStorageMutation.delete(StorageKeys.siteCookie(siteId)));
        final apiFallback = StorageKeys.siteApiKeyFallback(siteId);
        final cookieFallback = StorageKeys.siteCookieFallback(siteId);
        fallbackKeys
          ..add(apiFallback)
          ..add(cookieFallback);
        fallbackKeysToResolve
          ..add(apiFallback)
          ..add(cookieFallback);
      }
      if (mutations.isNotEmpty) {
        await _commitSensitiveMutations(
          mutations,
          pendingPlainSiteConfigs: encodedPlainSiteConfigs,
        );
        plainConfigsCommittedWithSensitiveRevision = true;
        for (final fallbackKey in fallbackKeys) {
          await _removeSensitiveFallback(
            fallbackKey,
            resolveConflict:
                resolveFallbackConflicts ||
                fallbackKeysToResolve.contains(fallbackKey),
          );
        }
      }
    } else {
      // Linux 保留既有 keyring 不可用时的本地降级行为。
      for (final config in configs) {
        if (config.apiKey != null) {
          await _saveSiteApiKeyWithoutTransaction(config.id, config.apiKey);
        }
        if (config.cookie != null) {
          await _saveSiteCookieWithoutTransaction(config.id, config.cookie);
        }
      }
      for (final siteId in removedSiteIds) {
        await _deleteSiteApiKeyWithoutTransaction(siteId);
        await _deleteSiteCookieWithoutTransaction(siteId);
      }
    }

    // 所有敏感值写入并校验完成后，才提交普通站点配置。
    if (!plainConfigsCommittedWithSensitiveRevision) {
      await _persistPlainSiteConfigs(
        configs,
        encodedSiteConfigs: encodedPlainSiteConfigs,
      );
    } else {
      _updatePlainSiteConfigCache(configs);
    }
    _siteApiKeysCache.clear();
    _siteCookiesCache.clear();
    if (resolveFallbackConflicts) {
      await _clearFallbackConflictMarker(StorageKeys.siteConfigs);
    }
  }

  Future<void> _persistPlainSiteConfigs(
    List<SiteConfig> configs, {
    String? encodedSiteConfigs,
  }) async {
    final prefs = await _prefs;
    final encoded = encodedSiteConfigs ?? _encodePlainSiteConfigs(configs);
    _validatePlainSiteConfigsPayload(encoded);
    await _requirePreferenceMutation(
      mutate: () => prefs.setString(StorageKeys.siteConfigs, encoded),
      verify: () => prefs.getString(StorageKeys.siteConfigs) == encoded,
      failureCode: 'plain_site_config_commit_failed',
    );

    _updatePlainSiteConfigCache(configs);
  }

  void _updatePlainSiteConfigCache(List<SiteConfig> configs) {
    // 更新基础配置缓存（不含 apiKey 与 cookie），避免下一次再次解析 JSON
    _siteConfigsCache = configs
        .map((c) => c.copyWith(clearApiKey: true, clearCookie: true))
        .toList();
    _siteConfigsCacheDirty = false;
    _siteConfigsCacheNeedsUpdate = false;
  }

  Future<List<SiteConfig>> loadSiteConfigs({bool includeApiKeys = false}) =>
      _runSiteConfigOperation(
        () => _loadSiteConfigsUnlocked(includeApiKeys: includeApiKeys),
      );

  Future<List<SiteConfig>> _loadSiteConfigsUnlocked({
    bool includeApiKeys = false,
  }) async {
    await initializeSecureStorage();
    if (!canAccessSensitiveStorage) {
      throw SecureStorageUnavailableException(
        _secureStorageFailureCode ?? 'secure_storage_unavailable',
      );
    }
    final swTotal = Stopwatch()..start();
    try {
      final prefs = await _prefs;
      final str = prefs.getString(StorageKeys.siteConfigs);
      if (str == null) {
        await _assertSiteManifestConsistentWithEmptyPlainConfig();
        // 清空缓存并返回空
        _siteConfigsCache = null;
        _siteConfigsCacheDirty = true;
        _siteConfigsCacheNeedsUpdate = false;
        return [];
      }

      List<SiteConfig> baseConfigs;
      bool hasUpdates;
      var hasBlockingSiteConfigConflict = _fallbackConflictKeys(
        prefs,
      ).contains(StorageKeys.siteConfigs);

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
        if (jsonList.isEmpty) {
          await _assertSiteManifestConsistentWithEmptyPlainConfig();
        }
        final migratedJsonList = jsonList
            .map<dynamic>(
              (value) => value is Map<String, dynamic>
                  ? Map<String, dynamic>.from(value)
                  : value,
            )
            .toList();
        baseConfigs = <SiteConfig>[];
        hasUpdates = false;
        int idx = 0;
        var sanitizedLegacyCookie = false;
        var sawLegacyCookie = false;
        var legacyCookieConflict = false;

        for (final json in jsonList) {
          final swItem = Stopwatch()..start();
          final result = await SiteConfig.fromJsonAsync(json);
          swItem.stop();
          if (kDebugMode) {
            _logger.d(
              'StorageService.loadSiteConfigs: 第${idx + 1}个站点 fromJsonAsync 耗时=${swItem.elapsedMilliseconds}ms，templateId=${result.config.templateId}，needsUpdate=${result.needsUpdate}',
            );
          }
          var cfg = result.config;

          // 旧 JSON 中的 Cookie 只能在目标缺失/相同时迁移。目标密文与
          // 明文冲突时，以安全存储为准并保留原 JSON 等待用户显式保存。
          if (cfg.cookie != null && cfg.cookie!.isNotEmpty) {
            sawLegacyCookie = true;
            final legacyCookie = cfg.cookie!;
            var secureCookie = await _loadSiteCookie(cfg.id);
            if (secureCookie == null) {
              await _saveSiteCookie(cfg.id, legacyCookie);
              secureCookie = await _loadSiteCookie(cfg.id);
              if (secureCookie != legacyCookie) {
                _throwSecureStorageUnavailable(
                  'legacy_site_cookie_verification_failed',
                );
              }
            }
            if (secureCookie == legacyCookie) {
              final migratedJson = migratedJsonList[idx];
              if (migratedJson is! Map<String, dynamic>) {
                throw const FormatException(
                  'Invalid legacy site configuration.',
                );
              }
              migratedJson['cookie'] = null;
              sanitizedLegacyCookie = true;
            } else {
              legacyCookieConflict = true;
            }
            _siteCookiesCache[cfg.id] = secureCookie;
            cfg = cfg.copyWith(clearCookie: true);
          }

          baseConfigs.add(cfg);
          idx++;
          if (result.needsUpdate) {
            hasUpdates = true;
          }
        }

        if (sanitizedLegacyCookie) {
          final migratedEncoded = jsonEncode(migratedJsonList);
          await _requirePreferenceMutation(
            mutate: () =>
                prefs.setString(StorageKeys.siteConfigs, migratedEncoded),
            verify: () =>
                prefs.getString(StorageKeys.siteConfigs) == migratedEncoded,
            failureCode: 'legacy_site_cookie_cleanup_failed',
          );
        }
        await _updateFallbackConflictKeys((conflicts) {
          if (legacyCookieConflict) {
            conflicts.add(StorageKeys.siteConfigs);
          } else if (sawLegacyCookie ||
              conflicts.contains(StorageKeys.siteConfigs)) {
            conflicts.remove(StorageKeys.siteConfigs);
          }
        });
        hasBlockingSiteConfigConflict = legacyCookieConflict;

        // 更新缓存
        _siteConfigsCache = baseConfigs;
        _siteConfigsCacheDirty = false;
        _siteConfigsCacheNeedsUpdate = hasUpdates;
      }

      // 根据 includeApiKeys 构造返回列表：API Key 依据 includeApiKeys 决定是否加载，但 Cookie 必须总是加载
      final List<SiteConfig> configs = <SiteConfig>[];
      int idx = 0;
      for (final cfg in baseConfigs) {
        final swKey = Stopwatch()..start();

        String? cookie;
        if (_siteCookiesCache.containsKey(cfg.id)) {
          cookie = _siteCookiesCache[cfg.id];
        } else {
          cookie = await _loadSiteCookie(cfg.id);
          _siteCookiesCache[cfg.id] = cookie; // 缓存读取结果
        }

        String? apiKey;
        if (includeApiKeys) {
          if (_siteApiKeysCache.containsKey(cfg.id)) {
            apiKey = _siteApiKeysCache[cfg.id];
          } else {
            apiKey = await _loadSiteApiKey(cfg.id);
            _siteApiKeysCache[cfg.id] = apiKey; // 缓存读取结果
          }
        }

        swKey.stop();
        if (kDebugMode && includeApiKeys) {
          _logger.d(
            'StorageService.loadSiteConfigs: 第${idx + 1}个站点 加载敏感数据耗时=${swKey.elapsedMilliseconds}ms',
          );
        }

        // 如果值完全一致，则直接返回基础配置实例，维持引用等价性优化
        if (cfg.apiKey == apiKey && cfg.cookie == cookie) {
          configs.add(cfg);
        } else {
          final finalConfig = cfg.copyWith(
            apiKey: apiKey,
            cookie: cookie,
            clearApiKey: apiKey == null,
            clearCookie: cookie == null,
          );
          configs.add(finalConfig);
        }
        idx++;
      }

      // 持久化模板更新与清除明文迁移结果：仅在 includeApiKeys=true 时执行
      if (hasUpdates && includeApiKeys && !hasBlockingSiteConfigConflict) {
        final swSave = Stopwatch()..start();
        await _saveSiteConfigsUnlocked(
          configs,
          resolveFallbackConflicts: false,
        );
        swSave.stop();
        if (kDebugMode) {
          _logger.d(
            'StorageService.loadSiteConfigs: 保存更新耗时=${swSave.elapsedMilliseconds}ms',
          );
        }
      } else if (hasUpdates &&
          !includeApiKeys &&
          !hasBlockingSiteConfigConflict) {
        _hasPendingConfigUpdates = true;
        if (kDebugMode) {
          _logger.i(
            'StorageService.loadSiteConfigs: 检测到配置需要更新，但已跳过保存以避免清除API密钥和Cookie（稍后持久化）',
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
    } on SecureStorageUnavailableException {
      rethrow;
    } catch (_) {
      throw StateError('site_config_load_failed');
    }
  }

  Future<T> updateSiteConfigsAtomically<T>(
    FutureOr<SiteConfigAtomicUpdate<T>> Function(List<SiteConfig> current)
    update, {
    bool includeApiKeys = false,
    bool resolveFallbackConflicts = false,
    int? expectedSecureStorageEpoch,
  }) {
    Future<T> operation() => _runSiteConfigOperation(() async {
      final current = await _loadSiteConfigsUnlocked(
        includeApiKeys: includeApiKeys,
      );
      _requireExpectedSecureStorageOperationEpoch();
      final change = await update(List<SiteConfig>.unmodifiable(current));
      _requireExpectedSecureStorageOperationEpoch();
      await _saveSiteConfigsUnlocked(
        change.configs,
        resolveFallbackConflicts: resolveFallbackConflicts,
      );
      return change.result;
    });

    final expected = expectedSecureStorageEpoch;
    return expected == null
        ? operation()
        : runWithSecureStorageOperationEpoch(expected, operation);
  }

  Future<void> addSiteConfig(SiteConfig config) => _runSiteConfigOperation(
    () async {
      final configs = await _loadSiteConfigsUnlocked(includeApiKeys: false);
      // 仅把新增站点的敏感字段纳入本次事务。
      final preserved = configs
          .map((item) => item.copyWith(clearApiKey: true, clearCookie: true))
          .toList();
      preserved.add(config);
      await _saveSiteConfigsUnlocked(preserved, resolveFallbackConflicts: true);
    },
  );

  Future<void> updateSiteConfig(
    SiteConfig config,
  ) => _runSiteConfigOperation(() async {
    final configs = await _loadSiteConfigsUnlocked(includeApiKeys: false);
    final index = configs.indexWhere((c) => c.id == config.id);
    if (index >= 0) {
      final preserved = configs
          .map((item) => item.copyWith(clearApiKey: true, clearCookie: true))
          .toList();
      preserved[index] = config;
      await _saveSiteConfigsUnlocked(preserved, resolveFallbackConflicts: true);
    }
  });

  Future<void> deleteSiteConfig(String siteId) =>
      _runSiteConfigOperation(() => _deleteSiteConfigUnlocked(siteId));

  Future<void> _deleteSiteConfigUnlocked(String siteId) =>
      _runInCurrentSecureStorageOperationEpoch(
        () => _deleteSiteConfigInCurrentEpoch(siteId),
      );

  Future<void> _deleteSiteConfigInCurrentEpoch(String siteId) async {
    final configs = await _loadSiteConfigsUnlocked();
    configs.removeWhere((c) => c.id == siteId);
    final plainConfigs = configs
        .map((c) => c.copyWith(clearApiKey: true, clearCookie: true))
        .toList();
    final encodedPlainSiteConfigs = _encodePlainSiteConfigs(plainConfigs);
    var plainConfigsCommittedWithSensitiveRevision = false;
    if (isSecureStorageReady) {
      await _commitSensitiveMutations([
        SecureStorageMutation.delete(StorageKeys.siteApiKey(siteId)),
        SecureStorageMutation.delete(StorageKeys.siteCookie(siteId)),
      ], pendingPlainSiteConfigs: encodedPlainSiteConfigs);
      plainConfigsCommittedWithSensitiveRevision = true;
      await _removeSensitiveFallback(
        StorageKeys.siteApiKeyFallback(siteId),
        resolveConflict: true,
      );
      await _removeSensitiveFallback(
        StorageKeys.siteCookieFallback(siteId),
        resolveConflict: true,
      );
    } else {
      await _deleteSiteApiKeyWithoutTransaction(siteId);
      await _deleteSiteCookieWithoutTransaction(siteId);
    }

    // manifest 已先移除映射；普通配置随后提交，旧密文由事务层延迟清理。
    if (!plainConfigsCommittedWithSensitiveRevision) {
      await _persistPlainSiteConfigs(
        plainConfigs,
        encodedSiteConfigs: encodedPlainSiteConfigs,
      );
    } else {
      _updatePlainSiteConfigCache(plainConfigs);
    }
    _siteApiKeysCache.clear();
    _siteCookiesCache.clear();

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

  Future<SiteConfig?> getActiveSiteConfig() =>
      _runSiteConfigOperation(_getActiveSiteConfigUnlocked);

  Future<SiteConfig?> _getActiveSiteConfigUnlocked() async {
    final activeSiteId = await getActiveSiteId();
    if (activeSiteId == null) return null;

    // 加载站点配置但跳过API密钥，随后仅为活跃站点读取密钥和Cookie
    final configs = await _loadSiteConfigsUnlocked(includeApiKeys: false);
    try {
      final base = configs.firstWhere((c) => c.id == activeSiteId);
      final apiKey = await _loadSiteApiKey(activeSiteId);
      final cookie = await _loadSiteCookie(activeSiteId);
      return base.copyWith(apiKey: apiKey, cookie: cookie);
    } on SecureStorageUnavailableException {
      rethrow;
    } catch (_) {
      return null;
    }
  }

  // 私有方法：处理单个站点的Cookie安全存储与普通降级
  Future<void> _saveSiteCookie(String siteId, String? cookie) =>
      _runInCurrentSecureStorageOperationEpoch(
        () => _saveSiteCookieInCurrentEpoch(siteId, cookie),
      );

  Future<void> _saveSiteCookieInCurrentEpoch(
    String siteId,
    String? cookie,
  ) async {
    if (cookie == null) return;
    if (!isSecureStorageReady) {
      await _saveSiteCookieWithoutTransaction(siteId, cookie);
      return;
    }

    final key = StorageKeys.siteCookie(siteId);
    await _commitSensitiveMutations([
      cookie.isEmpty
          ? SecureStorageMutation.delete(key)
          : SecureStorageMutation.upsert(key, cookie),
    ]);
    await _removeSensitiveFallback(StorageKeys.siteCookieFallback(siteId));
  }

  Future<void> _saveSiteCookieWithoutTransaction(
    String siteId,
    String? cookie,
  ) async {
    if (cookie == null) return;
    if (cookie.isEmpty) {
      await _deleteSiteCookieWithoutTransaction(siteId);
      return;
    }
    await _saveSecureWithFallback(
      key: StorageKeys.siteCookie(siteId),
      fallbackKey: StorageKeys.siteCookieFallback(siteId),
      value: cookie,
    );
  }

  Future<String?> _loadSiteCookie(String siteId) async {
    return _readSensitiveValue(
      key: StorageKeys.siteCookie(siteId),
      fallbackKey: StorageKeys.siteCookieFallback(siteId),
    );
  }

  Future<void> _deleteSiteCookieWithoutTransaction(String siteId) =>
      _runInCurrentSecureStorageOperationEpoch(
        () => _deleteSiteCookieWithoutTransactionInCurrentEpoch(siteId),
      );

  Future<void> _deleteSiteCookieWithoutTransactionInCurrentEpoch(
    String siteId,
  ) async {
    await _stageSensitiveDeleteFallbackGuards([
      SecureStorageMutation.delete(StorageKeys.siteCookie(siteId)),
    ]);
    await _secureDelete(key: StorageKeys.siteCookie(siteId));
    await _removeSensitiveFallback(
      StorageKeys.siteCookieFallback(siteId),
      resolveConflict: true,
    );
  }

  Future<void> _saveSiteApiKeyWithoutTransaction(
    String siteId,
    String? apiKey,
  ) async {
    if (apiKey == null) return;
    if (apiKey.isEmpty) {
      await _deleteSiteApiKeyWithoutTransaction(siteId);
      return;
    }

    await _saveSecureWithFallback(
      key: StorageKeys.siteApiKey(siteId),
      fallbackKey: StorageKeys.siteApiKeyFallback(siteId),
      value: apiKey,
    );
  }

  Future<String?> _loadSiteApiKey(String siteId) async {
    return _readSensitiveValue(
      key: StorageKeys.siteApiKey(siteId),
      fallbackKey: StorageKeys.siteApiKeyFallback(siteId),
    );
  }

  Future<void> _deleteSiteApiKeyWithoutTransaction(String siteId) =>
      _runInCurrentSecureStorageOperationEpoch(
        () => _deleteSiteApiKeyWithoutTransactionInCurrentEpoch(siteId),
      );

  Future<void> _deleteSiteApiKeyWithoutTransactionInCurrentEpoch(
    String siteId,
  ) async {
    await _stageSensitiveDeleteFallbackGuards([
      SecureStorageMutation.delete(StorageKeys.siteApiKey(siteId)),
    ]);
    await _secureDelete(key: StorageKeys.siteApiKey(siteId));
    await _removeSensitiveFallback(
      StorageKeys.siteApiKeyFallback(siteId),
      resolveConflict: true,
    );
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

  // 网络代理设置相关：保存与读取
  Future<void> saveProxyEnabled(bool enabled) async {
    final prefs = await _prefs;
    await prefs.setBool(StorageKeys.proxyEnabled, enabled);
  }

  Future<bool> loadProxyEnabled() async {
    final prefs = await _prefs;
    return prefs.getBool(StorageKeys.proxyEnabled) ?? false;
  }

  Future<void> saveProxyHost(String host) async {
    final prefs = await _prefs;
    await prefs.setString(StorageKeys.proxyHost, host);
  }

  Future<String> loadProxyHost() async {
    final prefs = await _prefs;
    return prefs.getString(StorageKeys.proxyHost) ?? '';
  }

  Future<void> saveProxyPort(int port) async {
    final prefs = await _prefs;
    await prefs.setInt(StorageKeys.proxyPort, port);
  }

  Future<int> loadProxyPort() async {
    final prefs = await _prefs;
    return prefs.getInt(StorageKeys.proxyPort) ?? 7890;
  }

  Future<void> saveProxyUsername(String username) async {
    final prefs = await _prefs;
    await prefs.setString(StorageKeys.proxyUsername, username);
  }

  Future<String> loadProxyUsername() async {
    final prefs = await _prefs;
    return prefs.getString(StorageKeys.proxyUsername) ?? '';
  }

  Future<void> saveProxyPassword(String password) =>
      _runInCurrentSecureStorageOperationEpoch(
        () => _saveProxyPasswordInCurrentEpoch(password),
      );

  Future<void> _saveProxyPasswordInCurrentEpoch(String password) async {
    if (isSecureStorageReady) {
      await _commitSensitiveMutations([
        password.isEmpty
            ? const SecureStorageMutation.delete(StorageKeys.proxyPassword)
            : SecureStorageMutation.upsert(StorageKeys.proxyPassword, password),
      ]);
      await _removeSensitiveFallback(
        StorageKeys.proxyPasswordFallback,
        resolveConflict: true,
      );
    } else {
      await _saveSecureWithFallback(
        key: StorageKeys.proxyPassword,
        fallbackKey: StorageKeys.proxyPasswordFallback,
        value: password,
      );
    }
  }

  Future<String> loadProxyPassword() async {
    return await _readSensitiveValue(
          key: StorageKeys.proxyPassword,
          fallbackKey: StorageKeys.proxyPasswordFallback,
        ) ??
        '';
  }

  Future<void> saveProxyBypassLan(bool bypass) async {
    final prefs = await _prefs;
    await prefs.setBool(StorageKeys.proxyBypassLan, bypass);
  }

  Future<bool> loadProxyBypassLan() async {
    final prefs = await _prefs;
    return prefs.getBool(StorageKeys.proxyBypassLan) ?? true;
  }

  Future<void> saveProxyBypassRules(List<String> rules) async {
    final prefs = await _prefs;
    await prefs.setStringList(StorageKeys.proxyBypassRules, rules);
  }

  Future<List<String>> loadProxyBypassRules() async {
    final prefs = await _prefs;
    return prefs.getStringList(StorageKeys.proxyBypassRules) ?? [];
  }

  Future<void> _setCookieCloudLegacyCleanupPending(bool pending) async {
    final prefs = await _prefs;
    if (pending) {
      if (prefs.getBool(StorageKeys.cookieCloudSecretsV2PendingCleanup) ==
          true) {
        return;
      }
      await _requirePreferenceMutation(
        mutate: () =>
            prefs.setBool(StorageKeys.cookieCloudSecretsV2PendingCleanup, true),
        verify: () =>
            prefs.getBool(StorageKeys.cookieCloudSecretsV2PendingCleanup) ==
            true,
        failureCode: 'cookie_cloud_cleanup_marker_commit_failed',
      );
      return;
    }
    if (!prefs.containsKey(StorageKeys.cookieCloudSecretsV2PendingCleanup)) {
      return;
    }
    await _requirePreferenceMutation(
      mutate: () =>
          prefs.remove(StorageKeys.cookieCloudSecretsV2PendingCleanup),
      verify: () =>
          !prefs.containsKey(StorageKeys.cookieCloudSecretsV2PendingCleanup),
      failureCode: 'cookie_cloud_cleanup_marker_commit_failed',
    );
  }

  Future<void> _saveCookieCloudSecrets(
    _CookieCloudSecrets secrets, {
    bool scheduleLegacyCleanup = true,
    bool resolveLegacyConflicts = false,
    CookieCloudConfig? companionConfig,
  }) => _runInCurrentSecureStorageOperationEpoch(
    () => _saveCookieCloudSecretsInCurrentEpoch(
      secrets,
      scheduleLegacyCleanup: scheduleLegacyCleanup,
      resolveLegacyConflicts: resolveLegacyConflicts,
      companionConfig: companionConfig,
    ),
  );

  Future<void> _saveCookieCloudSecretsInCurrentEpoch(
    _CookieCloudSecrets secrets, {
    required bool scheduleLegacyCleanup,
    required bool resolveLegacyConflicts,
    required CookieCloudConfig? companionConfig,
  }) async {
    final encoded = jsonEncode(secrets.toJson());
    final encodedCompanionPreferences = companionConfig == null
        ? null
        : _encodeCookieCloudPreferences(companionConfig);
    if (isSecureStorageReady) {
      await _commitSensitiveMutations([
        SecureStorageMutation.upsert(StorageKeys.cookieCloudSecretsV2, encoded),
      ], pendingCookieCloudPreferences: encodedCompanionPreferences);
      await _removeSensitiveFallback(
        StorageKeys.cookieCloudSecretsV2Fallback,
        resolveConflict: resolveLegacyConflicts,
      );
    } else {
      await _saveSecureWithFallback(
        key: StorageKeys.cookieCloudSecretsV2,
        fallbackKey: StorageKeys.cookieCloudSecretsV2Fallback,
        value: encoded,
      );
      if (companionConfig != null) {
        await _persistCookieCloudPreferences(companionConfig);
      }
    }
    final verified = await _readSensitiveValue(
      key: StorageKeys.cookieCloudSecretsV2,
      fallbackKey: StorageKeys.cookieCloudSecretsV2Fallback,
    );
    if (verified != encoded) {
      _throwSecureStorageUnavailable('cookie_cloud_bundle_verification_failed');
    }

    await _setCookieCloudLegacyCleanupPending(scheduleLegacyCleanup);
    _cookieCloudBundleCreatedThisRun = true;
    if (resolveLegacyConflicts) {
      await _cleanupLegacyCookieCloudSecrets(resolveConflicts: true);
    }
  }

  Future<({String value, bool hasConflict})> _loadLegacyCookieCloudValue({
    required String key,
    required String fallbackKey,
  }) async {
    final prefs = await _prefs;
    final plaintextValue = prefs.getString(key);
    final fallbackValue = prefs.getString(fallbackKey);
    var secureValue = await _loadSecureWithFallback(
      key: key,
      fallbackKey: fallbackKey,
    );
    var hasConflict = false;

    if (secureValue != null) {
      if (fallbackValue != null &&
          fallbackValue.isNotEmpty &&
          fallbackValue != secureValue) {
        hasConflict = true;
      }
      if (plaintextValue != null && plaintextValue.isNotEmpty) {
        if (plaintextValue == secureValue) {
          await _removeSensitiveFallback(key, resolveConflict: true);
        } else {
          hasConflict = true;
          await _recordFallbackConflict(key);
        }
      }
    } else if (plaintextValue != null && plaintextValue.isNotEmpty) {
      await _saveSecureWithFallback(
        key: key,
        fallbackKey: fallbackKey,
        value: plaintextValue,
      );
      secureValue = await _loadSecureWithFallback(
        key: key,
        fallbackKey: fallbackKey,
      );
      if (secureValue != plaintextValue) {
        _throwSecureStorageUnavailable(
          'fallback_migration_verification_failed',
        );
      }
      await _removeSensitiveFallback(key, resolveConflict: true);
    }
    return (value: secureValue ?? '', hasConflict: hasConflict);
  }

  Future<_LegacyCookieCloudSecrets> _loadLegacyCookieCloudSecrets() async {
    final url = await _loadLegacyCookieCloudValue(
      key: StorageKeys.cookieCloudUrl,
      fallbackKey: StorageKeys.cookieCloudUrlFallback,
    );
    final uuid = await _loadLegacyCookieCloudValue(
      key: StorageKeys.cookieCloudUuid,
      fallbackKey: StorageKeys.cookieCloudUuidFallback,
    );
    final password = await _loadLegacyCookieCloudValue(
      key: StorageKeys.cookieCloudPassword,
      fallbackKey: StorageKeys.cookieCloudPasswordFallback,
    );
    return _LegacyCookieCloudSecrets(
      secrets: _CookieCloudSecrets(
        url: url.value,
        uuid: uuid.value,
        password: password.value,
      ),
      hasConflict: url.hasConflict || uuid.hasConflict || password.hasConflict,
    );
  }

  Future<void> _cleanupLegacyCookieCloudSecrets({
    bool resolveConflicts = false,
  }) => _runInCurrentSecureStorageOperationEpoch(
    () => _cleanupLegacyCookieCloudSecretsInCurrentEpoch(
      resolveConflicts: resolveConflicts,
    ),
  );

  Future<void> _cleanupLegacyCookieCloudSecretsInCurrentEpoch({
    required bool resolveConflicts,
  }) async {
    final prefs = await _prefs;
    final legacyPreferenceKeys = <String>[
      StorageKeys.cookieCloudUrl,
      StorageKeys.cookieCloudUrlFallback,
      StorageKeys.cookieCloudUuid,
      StorageKeys.cookieCloudUuidFallback,
      StorageKeys.cookieCloudPassword,
      StorageKeys.cookieCloudPasswordFallback,
    ];
    final conflicts = _fallbackConflictKeys(prefs);
    if (!resolveConflicts && legacyPreferenceKeys.any(conflicts.contains)) {
      return;
    }

    await _stageSensitiveDeleteFallbackGuards([
      const SecureStorageMutation.delete(StorageKeys.cookieCloudUrl),
      const SecureStorageMutation.delete(StorageKeys.cookieCloudUuid),
      const SecureStorageMutation.delete(StorageKeys.cookieCloudPassword),
    ]);
    await _secureDelete(key: StorageKeys.cookieCloudUrl);
    await _secureDelete(key: StorageKeys.cookieCloudUuid);
    await _secureDelete(key: StorageKeys.cookieCloudPassword);

    for (final key in legacyPreferenceKeys) {
      await _removeSensitiveFallback(key, resolveConflict: resolveConflicts);
    }
    await _setCookieCloudLegacyCleanupPending(false);
    await _refreshFallbackConflictFlag();
  }

  Future<bool> _hasLegacyCookieCloudSecrets() async {
    final prefs = await _prefs;
    if (prefs.containsKey(StorageKeys.cookieCloudUrl) ||
        prefs.containsKey(StorageKeys.cookieCloudUrlFallback) ||
        prefs.containsKey(StorageKeys.cookieCloudUuid) ||
        prefs.containsKey(StorageKeys.cookieCloudUuidFallback) ||
        prefs.containsKey(StorageKeys.cookieCloudPassword) ||
        prefs.containsKey(StorageKeys.cookieCloudPasswordFallback)) {
      return true;
    }
    return (await _secureRead(StorageKeys.cookieCloudUrl)) != null ||
        (await _secureRead(StorageKeys.cookieCloudUuid)) != null ||
        (await _secureRead(StorageKeys.cookieCloudPassword)) != null;
  }

  Future<_CookieCloudSecrets> _loadCookieCloudSecrets() =>
      _runInCurrentSecureStorageOperationEpoch(
        _loadCookieCloudSecretsInCurrentEpoch,
      );

  Future<_CookieCloudSecrets> _loadCookieCloudSecretsInCurrentEpoch() async {
    final encoded = await _readSensitiveValue(
      key: StorageKeys.cookieCloudSecretsV2,
      fallbackKey: StorageKeys.cookieCloudSecretsV2Fallback,
    );
    if (encoded != null) {
      late final _CookieCloudSecrets secrets;
      try {
        final decoded = jsonDecode(encoded);
        if (decoded is! Map<String, dynamic>) {
          throw const FormatException('Invalid Cookie Cloud bundle.');
        }
        secrets = _CookieCloudSecrets.fromJson(decoded);
      } catch (error) {
        const code = 'cookie_cloud_bundle_invalid';
        _markSecureStorageUnavailable(error, code: code);
        throw SecureStorageUnavailableException(code, error);
      }

      final prefs = await _prefs;
      var shouldCleanup =
          prefs.getBool(StorageKeys.cookieCloudSecretsV2PendingCleanup) ??
          false;
      if (!shouldCleanup &&
          !_cookieCloudBundleCreatedThisRun &&
          _fallbackConflictKeys(prefs).isEmpty) {
        shouldCleanup = await _hasLegacyCookieCloudSecrets();
      }
      if (shouldCleanup && !_cookieCloudBundleCreatedThisRun) {
        await _cleanupLegacyCookieCloudSecrets();
      }
      return secrets;
    }

    final legacy = await _loadLegacyCookieCloudSecrets();
    final secrets = legacy.secrets;
    if (secrets.url.isNotEmpty ||
        secrets.uuid.isNotEmpty ||
        secrets.password.isNotEmpty) {
      await _saveCookieCloudSecrets(
        secrets,
        scheduleLegacyCleanup: !legacy.hasConflict,
      );
    }
    return secrets;
  }

  Future<void> saveCookieCloudUrl(String url) =>
      _runInCurrentSecureStorageOperationEpoch(
        () => _saveCookieCloudUrlInCurrentEpoch(url),
      );

  Future<void> _saveCookieCloudUrlInCurrentEpoch(String url) async {
    final current = await _loadCookieCloudSecrets();
    await _saveCookieCloudSecrets(
      _CookieCloudSecrets(
        url: url,
        uuid: current.uuid,
        password: current.password,
      ),
      resolveLegacyConflicts: true,
    );
  }

  Future<String> loadCookieCloudUrl() async =>
      (await _loadCookieCloudSecrets()).url;

  Future<void> saveCookieCloudUuid(String uuid) =>
      _runInCurrentSecureStorageOperationEpoch(
        () => _saveCookieCloudUuidInCurrentEpoch(uuid),
      );

  Future<void> _saveCookieCloudUuidInCurrentEpoch(String uuid) async {
    final current = await _loadCookieCloudSecrets();
    await _saveCookieCloudSecrets(
      _CookieCloudSecrets(
        url: current.url,
        uuid: uuid,
        password: current.password,
      ),
      resolveLegacyConflicts: true,
    );
  }

  Future<String> loadCookieCloudUuid() async =>
      (await _loadCookieCloudSecrets()).uuid;

  Future<void> saveCookieCloudConfig(CookieCloudConfig config) =>
      _runInCurrentSecureStorageOperationEpoch(
        () => _saveCookieCloudConfigInCurrentEpoch(config),
      );

  Future<void> _saveCookieCloudConfigInCurrentEpoch(
    CookieCloudConfig config,
  ) async {
    await _saveCookieCloudSecrets(
      _CookieCloudSecrets(
        url: config.url.trim(),
        uuid: config.uuid.trim(),
        password: config.password,
      ),
      resolveLegacyConflicts: true,
      companionConfig: config,
    );
  }

  Future<void> _persistCookieCloudPreferences(CookieCloudConfig config) async {
    await _persistCookieCloudPreferenceSnapshot(
      _validateCookieCloudPreferencesPayload(
        _encodeCookieCloudPreferences(config),
      ),
    );
  }

  Future<void> _persistCookieCloudPreferenceSnapshot(
    Map<String, dynamic> snapshot,
  ) async {
    final prefs = await _prefs;
    final autoSyncEnabled = snapshot['autoSyncEnabled'] as bool;
    await _requirePreferenceMutation(
      mutate: () => prefs.setBool(
        StorageKeys.cookieCloudAutoSyncEnabled,
        autoSyncEnabled,
      ),
      verify: () =>
          prefs.getBool(StorageKeys.cookieCloudAutoSyncEnabled) ==
          autoSyncEnabled,
      failureCode: 'cookie_cloud_preferences_commit_failed',
    );
    final syncIntervalMinutes = snapshot['syncIntervalMinutes'] as int;
    await _requirePreferenceMutation(
      mutate: () => prefs.setInt(
        StorageKeys.cookieCloudSyncIntervalMinutes,
        syncIntervalMinutes,
      ),
      verify: () =>
          prefs.getInt(StorageKeys.cookieCloudSyncIntervalMinutes) ==
          syncIntervalMinutes,
      failureCode: 'cookie_cloud_preferences_commit_failed',
    );
    final lastSyncAt = snapshot['lastSyncAt'] as String?;
    if (lastSyncAt != null) {
      await _requirePreferenceMutation(
        mutate: () =>
            prefs.setString(StorageKeys.cookieCloudLastSyncAt, lastSyncAt),
        verify: () =>
            prefs.getString(StorageKeys.cookieCloudLastSyncAt) == lastSyncAt,
        failureCode: 'cookie_cloud_preferences_commit_failed',
      );
    } else {
      await _requirePreferenceMutation(
        mutate: () => prefs.remove(StorageKeys.cookieCloudLastSyncAt),
        verify: () => !prefs.containsKey(StorageKeys.cookieCloudLastSyncAt),
        failureCode: 'cookie_cloud_preferences_commit_failed',
      );
    }
    final lastSyncSummary = snapshot['lastSyncSummary'] as String;
    await _requirePreferenceMutation(
      mutate: () => prefs.setString(
        StorageKeys.cookieCloudLastSyncSummary,
        lastSyncSummary,
      ),
      verify: () =>
          prefs.getString(StorageKeys.cookieCloudLastSyncSummary) ==
          lastSyncSummary,
      failureCode: 'cookie_cloud_preferences_commit_failed',
    );
  }

  Future<void> _persistBackupPreferenceSnapshot(
    Map<String, dynamic> snapshot,
  ) async {
    final prefs = await _prefs;

    Future<void> persistString(String name, String key) async {
      if (!snapshot.containsKey(name)) return;
      final value = snapshot[name] as String;
      await _requirePreferenceMutation(
        mutate: () => prefs.setString(key, value),
        verify: () => prefs.getString(key) == value,
        failureCode: 'backup_preferences_commit_failed',
      );
    }

    Future<void> persistBool(String name, String key) async {
      if (!snapshot.containsKey(name)) return;
      final value = snapshot[name] as bool;
      await _requirePreferenceMutation(
        mutate: () => prefs.setBool(key, value),
        verify: () => prefs.getBool(key) == value,
        failureCode: 'backup_preferences_commit_failed',
      );
    }

    Future<void> persistInt(String name, String key) async {
      if (!snapshot.containsKey(name)) return;
      final value = snapshot[name] as int;
      await _requirePreferenceMutation(
        mutate: () => prefs.setInt(key, value),
        verify: () => prefs.getInt(key) == value,
        failureCode: 'backup_preferences_commit_failed',
      );
    }

    Future<void> persistStringList(String name, String key) async {
      if (!snapshot.containsKey(name)) return;
      final value = (snapshot[name] as List<dynamic>).cast<String>();
      await _requirePreferenceMutation(
        mutate: () => prefs.setStringList(key, value),
        verify: () => _sameStringList(prefs.getStringList(key), value),
        failureCode: 'backup_preferences_commit_failed',
      );
    }

    await persistString('activeSiteId', StorageKeys.activeSiteId);
    if (snapshot.containsKey('downloaderConfigs')) {
      final encoded = jsonEncode(snapshot['downloaderConfigs']);
      await _requirePreferenceMutation(
        mutate: () => prefs.setString(StorageKeys.downloaderConfigs, encoded),
        verify: () => prefs.getString(StorageKeys.downloaderConfigs) == encoded,
        failureCode: 'backup_preferences_commit_failed',
      );
    }
    if (snapshot.containsKey('defaultDownloaderId')) {
      final defaultDownloaderId = snapshot['defaultDownloaderId'] as String?;
      if (defaultDownloaderId == null) {
        await _requirePreferenceMutation(
          mutate: () => prefs.remove(StorageKeys.defaultDownloaderId),
          verify: () => !prefs.containsKey(StorageKeys.defaultDownloaderId),
          failureCode: 'backup_preferences_commit_failed',
        );
      } else {
        await _requirePreferenceMutation(
          mutate: () => prefs.setString(
            StorageKeys.defaultDownloaderId,
            defaultDownloaderId,
          ),
          verify: () =>
              prefs.getString(StorageKeys.defaultDownloaderId) ==
              defaultDownloaderId,
          failureCode: 'backup_preferences_commit_failed',
        );
      }
    }
    await persistString('themeMode', StorageKeys.themeMode);
    await persistBool('dynamicColor', StorageKeys.themeUseDynamic);
    await persistInt('seedColor', StorageKeys.themeSeedColor);
    await persistBool('autoLoadImages', StorageKeys.autoLoadImages);
    await persistString(
      'defaultDownloadCategory',
      StorageKeys.defaultDownloadCategory,
    );
    await persistStringList(
      'defaultDownloadTags',
      StorageKeys.defaultDownloadTags,
    );
    await persistString(
      'defaultDownloadSavePath',
      StorageKeys.defaultDownloadSavePath,
    );
    await persistBool('proxyEnabled', StorageKeys.proxyEnabled);
    await persistString('proxyHost', StorageKeys.proxyHost);
    await persistInt('proxyPort', StorageKeys.proxyPort);
    await persistString('proxyUsername', StorageKeys.proxyUsername);
    await persistBool('proxyBypassLan', StorageKeys.proxyBypassLan);
    await persistStringList('proxyBypassRules', StorageKeys.proxyBypassRules);

    Future<void> persistStringListMap(
      String name,
      String Function(String) key,
    ) async {
      final values = snapshot[name] as Map<String, dynamic>?;
      if (values == null) return;
      for (final entry in values.entries) {
        final list = (entry.value as List<dynamic>).cast<String>();
        final preferenceKey = key(entry.key);
        await _requirePreferenceMutation(
          mutate: () => prefs.setStringList(preferenceKey, list),
          verify: () =>
              _sameStringList(prefs.getStringList(preferenceKey), list),
          failureCode: 'backup_preferences_commit_failed',
        );
      }
    }

    await persistStringListMap(
      'downloaderCategoriesCache',
      StorageKeys.downloaderCategoriesKey,
    );
    await persistStringListMap(
      'downloaderTagsCache',
      StorageKeys.downloaderTagsKey,
    );
    if (snapshot.containsKey('aggregateSearchSettings')) {
      final encoded = jsonEncode(snapshot['aggregateSearchSettings']);
      await _requirePreferenceMutation(
        mutate: () =>
            prefs.setString(StorageKeys.aggregateSearchSettings, encoded),
        verify: () =>
            prefs.getString(StorageKeys.aggregateSearchSettings) == encoded,
        failureCode: 'backup_preferences_commit_failed',
      );
    }
  }

  bool _sameStringList(List<String>? actual, List<String> expected) {
    if (actual == null || actual.length != expected.length) return false;
    for (var index = 0; index < expected.length; index++) {
      if (actual[index] != expected[index]) return false;
    }
    return true;
  }

  /// 将一次备份中的全部敏感字段作为一个 revision 提交。
  ///
  /// 普通配置只会在密文逐项读回并完成 manifest 切换后写入；因此恢复进程
  /// 在提交前退出仍读取旧 revision，提交后退出则读取完整的新敏感快照。
  Future<void> restoreSensitiveBackupData({
    List<SiteConfig>? siteConfigs,
    CookieCloudConfig? cookieCloudConfig,
    Map<String, String>? downloaderPasswords,
    Set<String>? downloaderIds,
    Map<String, dynamic>? backupPreferences,
    bool hasProxyPassword = false,
    String proxyPassword = '',
    int? expectedSecureStorageEpoch,
  }) {
    Future<void> operation() => _runSiteConfigOperation(
      () => _restoreSensitiveBackupDataUnlocked(
        siteConfigs: siteConfigs,
        cookieCloudConfig: cookieCloudConfig,
        downloaderPasswords: downloaderPasswords,
        downloaderIds: downloaderIds,
        backupPreferences: backupPreferences,
        hasProxyPassword: hasProxyPassword,
        proxyPassword: proxyPassword,
      ),
    );

    final expected = expectedSecureStorageEpoch;
    return expected == null
        ? operation()
        : runWithSecureStorageOperationEpoch(expected, operation);
  }

  Future<void> _restoreSensitiveBackupDataUnlocked({
    List<SiteConfig>? siteConfigs,
    CookieCloudConfig? cookieCloudConfig,
    Map<String, String>? downloaderPasswords,
    Set<String>? downloaderIds,
    Map<String, dynamic>? backupPreferences,
    required bool hasProxyPassword,
    required String proxyPassword,
  }) => _runInCurrentSecureStorageOperationEpoch(
    () => _restoreSensitiveBackupDataInCurrentEpoch(
      siteConfigs: siteConfigs,
      cookieCloudConfig: cookieCloudConfig,
      downloaderPasswords: downloaderPasswords,
      downloaderIds: downloaderIds,
      backupPreferences: backupPreferences,
      hasProxyPassword: hasProxyPassword,
      proxyPassword: proxyPassword,
    ),
  );

  Future<void> _restoreSensitiveBackupDataInCurrentEpoch({
    List<SiteConfig>? siteConfigs,
    CookieCloudConfig? cookieCloudConfig,
    Map<String, String>? downloaderPasswords,
    Set<String>? downloaderIds,
    Map<String, dynamic>? backupPreferences,
    required bool hasProxyPassword,
    required String proxyPassword,
  }) async {
    final validatedBackupPreferences = backupPreferences == null
        ? null
        : _validateBackupPreferencesPayload(jsonEncode(backupPreferences));
    final encodedBackupPreferences = validatedBackupPreferences == null
        ? null
        : jsonEncode(validatedBackupPreferences);

    if (!isSecureStorageReady) {
      if (siteConfigs != null) {
        await _saveSiteConfigsUnlocked(
          siteConfigs
              .map(
                (config) => config.copyWith(
                  apiKey: config.apiKey ?? '',
                  cookie: config.cookie ?? '',
                ),
              )
              .toList(),
          resolveFallbackConflicts: false,
        );
      }
      if (cookieCloudConfig != null) {
        await saveCookieCloudConfig(cookieCloudConfig);
      }
      for (final id in downloaderIds ?? const <String>{}) {
        final password = downloaderPasswords?[id];
        if (password == null || password.isEmpty) {
          await deleteDownloaderPassword(id);
        } else {
          await saveDownloaderPassword(id, password);
        }
      }
      if (hasProxyPassword) await saveProxyPassword(proxyPassword);
      if (validatedBackupPreferences != null) {
        await _persistBackupPreferenceSnapshot(validatedBackupPreferences);
      }
      return;
    }

    final mutations = <String, SecureStorageMutation>{};
    final fallbackKeys = <String>{};
    final encodedPlainSiteConfigs = siteConfigs == null
        ? null
        : _encodePlainSiteConfigs(siteConfigs);
    final encodedCookieCloudPreferences = cookieCloudConfig == null
        ? null
        : _encodeCookieCloudPreferences(cookieCloudConfig);
    var plainConfigsCommittedWithSensitiveRevision = false;
    var cookieCloudPreferencesCommittedWithSensitiveRevision = false;

    if (siteConfigs != null) {
      final prefs = await _prefs;
      final existingIds = <String>{};
      final encoded = prefs.getString(StorageKeys.siteConfigs);
      if (encoded != null) {
        try {
          final decoded = jsonDecode(encoded) as List<dynamic>;
          for (final value in decoded) {
            if (value is! Map<String, dynamic>) {
              throw const FormatException('Invalid site configuration.');
            }
            final id = value['id'];
            if (id is String && id.isNotEmpty) existingIds.add(id);
          }
        } catch (error) {
          throw SecureStorageUnavailableException(
            'backup_restore_invalid_existing_site_config',
            error,
          );
        }
      }

      final restoredIds = siteConfigs.map((config) => config.id).toSet();
      for (final removedId in existingIds.difference(restoredIds)) {
        final apiKey = StorageKeys.siteApiKey(removedId);
        final cookie = StorageKeys.siteCookie(removedId);
        mutations[apiKey] = SecureStorageMutation.delete(apiKey);
        mutations[cookie] = SecureStorageMutation.delete(cookie);
        fallbackKeys.add(StorageKeys.siteApiKeyFallback(removedId));
        fallbackKeys.add(StorageKeys.siteCookieFallback(removedId));
      }

      for (final config in siteConfigs) {
        final apiKey = StorageKeys.siteApiKey(config.id);
        final cookie = StorageKeys.siteCookie(config.id);
        mutations[apiKey] = (config.apiKey ?? '').isEmpty
            ? SecureStorageMutation.delete(apiKey)
            : SecureStorageMutation.upsert(apiKey, config.apiKey!);
        mutations[cookie] = (config.cookie ?? '').isEmpty
            ? SecureStorageMutation.delete(cookie)
            : SecureStorageMutation.upsert(cookie, config.cookie!);
        fallbackKeys.add(StorageKeys.siteApiKeyFallback(config.id));
        fallbackKeys.add(StorageKeys.siteCookieFallback(config.id));
      }
    }

    if (cookieCloudConfig != null) {
      final encoded = jsonEncode(
        _CookieCloudSecrets(
          url: cookieCloudConfig.url.trim(),
          uuid: cookieCloudConfig.uuid.trim(),
          password: cookieCloudConfig.password,
        ).toJson(),
      );
      mutations[StorageKeys.cookieCloudSecretsV2] =
          SecureStorageMutation.upsert(
            StorageKeys.cookieCloudSecretsV2,
            encoded,
          );
      fallbackKeys.add(StorageKeys.cookieCloudSecretsV2Fallback);
    }

    final restoredDownloaderIds = <String>{
      ...?downloaderIds,
      ...?downloaderPasswords?.keys,
    };
    final downloaderIdsWithLegacySourcesToDelete = <String>{};
    if (downloaderIds != null) {
      final prefs = await _prefs;
      final existingIds = <String>{};
      final encoded = prefs.getString(StorageKeys.downloaderConfigs);
      if (encoded != null) {
        try {
          final decoded = jsonDecode(encoded) as List<dynamic>;
          for (final value in decoded) {
            if (value is! Map<String, dynamic>) {
              throw const FormatException('Invalid downloader configuration.');
            }
            final id = value['id'];
            if (id is String && id.isNotEmpty) existingIds.add(id);
          }
        } catch (error) {
          throw SecureStorageUnavailableException(
            'backup_restore_invalid_existing_downloader_config',
            error,
          );
        }
      }
      for (final removedId in existingIds.difference(downloaderIds)) {
        final key = StorageKeys.downloaderPasswordKey(removedId);
        mutations[key] = SecureStorageMutation.delete(key);
        fallbackKeys.add(StorageKeys.downloaderPasswordFallbackKey(removedId));
        downloaderIdsWithLegacySourcesToDelete.add(removedId);
      }
    }
    for (final id in restoredDownloaderIds) {
      final key = StorageKeys.downloaderPasswordKey(id);
      final password = downloaderPasswords?[id] ?? '';
      mutations[key] = password.isEmpty
          ? SecureStorageMutation.delete(key)
          : SecureStorageMutation.upsert(key, password);
      fallbackKeys.add(StorageKeys.downloaderPasswordFallbackKey(id));
      if (password.isEmpty) {
        downloaderIdsWithLegacySourcesToDelete.add(id);
      }
    }

    if (hasProxyPassword) {
      mutations[StorageKeys.proxyPassword] = proxyPassword.isEmpty
          ? const SecureStorageMutation.delete(StorageKeys.proxyPassword)
          : SecureStorageMutation.upsert(
              StorageKeys.proxyPassword,
              proxyPassword,
            );
      fallbackKeys.add(StorageKeys.proxyPasswordFallback);
    }

    if (mutations.isNotEmpty ||
        encodedPlainSiteConfigs != null ||
        encodedCookieCloudPreferences != null ||
        encodedBackupPreferences != null) {
      // Just like a direct downloader-password clear, remove qB sources
      // before the target revision drops a password mapping. Otherwise a
      // process exit between those two operations could migrate the legacy
      // source back on the next startup.
      for (final downloaderId in downloaderIdsWithLegacySourcesToDelete) {
        await _cleanupLegacyQbPasswordSources(downloaderId);
      }
      await _commitSensitiveMutations(
        mutations.values,
        pendingPlainSiteConfigs: encodedPlainSiteConfigs,
        pendingCookieCloudPreferences: encodedCookieCloudPreferences,
        pendingBackupPreferences: encodedBackupPreferences,
      );
      plainConfigsCommittedWithSensitiveRevision =
          encodedPlainSiteConfigs != null;
      cookieCloudPreferencesCommittedWithSensitiveRevision =
          encodedCookieCloudPreferences != null;
      for (final fallbackKey in fallbackKeys) {
        await _removeSensitiveFallback(fallbackKey, resolveConflict: true);
      }
      for (final downloaderId in restoredDownloaderIds.difference(
        downloaderIdsWithLegacySourcesToDelete,
      )) {
        await _cleanupLegacyQbPasswordSources(downloaderId);
      }
    }

    if (siteConfigs != null) {
      if (!plainConfigsCommittedWithSensitiveRevision) {
        await _persistPlainSiteConfigs(
          siteConfigs,
          encodedSiteConfigs: encodedPlainSiteConfigs,
        );
      } else {
        _updatePlainSiteConfigCache(siteConfigs);
      }
      _siteApiKeysCache.clear();
      _siteCookiesCache.clear();
      await _clearFallbackConflictMarker(StorageKeys.siteConfigs);
    }
    if (cookieCloudConfig != null) {
      await _setCookieCloudLegacyCleanupPending(true);
      _cookieCloudBundleCreatedThisRun = true;
      if (!cookieCloudPreferencesCommittedWithSensitiveRevision) {
        await _persistCookieCloudPreferences(cookieCloudConfig);
      }
    }
  }

  Future<CookieCloudConfig> loadCookieCloudConfig() async {
    final prefs = await _prefs;
    final lastSyncAtRaw = prefs.getString(StorageKeys.cookieCloudLastSyncAt);
    final secrets = await _loadCookieCloudSecrets();
    return CookieCloudConfig(
      url: secrets.url,
      uuid: secrets.uuid,
      password: secrets.password,
      autoSyncEnabled:
          prefs.getBool(StorageKeys.cookieCloudAutoSyncEnabled) ?? false,
      syncIntervalMinutes:
          prefs.getInt(StorageKeys.cookieCloudSyncIntervalMinutes) ?? 360,
      lastSyncAt: lastSyncAtRaw == null
          ? null
          : DateTime.tryParse(lastSyncAtRaw),
      lastSyncSummary:
          prefs.getString(StorageKeys.cookieCloudLastSyncSummary) ?? '',
    );
  }

  Future<void> saveCookieCloudPassword(String password) =>
      _runInCurrentSecureStorageOperationEpoch(
        () => _saveCookieCloudPasswordInCurrentEpoch(password),
      );

  Future<void> _saveCookieCloudPasswordInCurrentEpoch(String password) async {
    final current = await _loadCookieCloudSecrets();
    await _saveCookieCloudSecrets(
      _CookieCloudSecrets(
        url: current.url,
        uuid: current.uuid,
        password: password,
      ),
      resolveLegacyConflicts: true,
    );
  }

  Future<String> loadCookieCloudPassword() async =>
      (await _loadCookieCloudSecrets()).password;

  Future<void> saveCookieCloudLastSync({
    required DateTime syncedAt,
    required String summary,
    int? expectedSecureStorageEpoch,
  }) async {
    Future<void> operation() async {
      final prefs = await _prefs;
      final encodedTime = syncedAt.toIso8601String();
      await _requirePreferenceMutation(
        mutate: () =>
            prefs.setString(StorageKeys.cookieCloudLastSyncAt, encodedTime),
        verify: () =>
            prefs.getString(StorageKeys.cookieCloudLastSyncAt) == encodedTime,
        failureCode: 'cookie_cloud_last_sync_commit_failed',
      );
      await _requirePreferenceMutation(
        mutate: () =>
            prefs.setString(StorageKeys.cookieCloudLastSyncSummary, summary),
        verify: () =>
            prefs.getString(StorageKeys.cookieCloudLastSyncSummary) == summary,
        failureCode: 'cookie_cloud_last_sync_commit_failed',
      );
    }

    final expected = expectedSecureStorageEpoch;
    await (expected == null
        ? operation()
        : runWithSecureStorageOperationEpoch(expected, operation));
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

  Future<void> saveLocalDownloadLastDirectory(String? directory) async {
    final prefs = await _prefs;
    if (directory != null && directory.isNotEmpty) {
      await prefs.setString(StorageKeys.localDownloadLastDirectory, directory);
    } else {
      await prefs.remove(StorageKeys.localDownloadLastDirectory);
    }
  }

  Future<String?> loadLocalDownloadLastDirectory() async {
    final prefs = await _prefs;
    return prefs.getString(StorageKeys.localDownloadLastDirectory);
  }

  /// 保存上次选择的下载方式（true 表示下载到本地，false 表示发送到下载器）
  Future<void> saveDefaultDownloadToLocal(bool downloadToLocal) async {
    final prefs = await _prefs;
    await prefs.setBool(StorageKeys.defaultDownloadToLocal, downloadToLocal);
  }

  /// 读取上次选择的下载方式（默认发送到下载器）
  Future<bool> loadDefaultDownloadToLocal() async {
    final prefs = await _prefs;
    return prefs.getBool(StorageKeys.defaultDownloadToLocal) ?? false;
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
  Future<void> saveWebDAVPassword(String configId, String? password) =>
      _runInCurrentSecureStorageOperationEpoch(
        () => _saveWebDAVPasswordInCurrentEpoch(configId, password),
      );

  Future<void> _saveWebDAVPasswordInCurrentEpoch(
    String configId,
    String? password,
  ) async {
    final key = StorageKeys.webdavPassword(configId);
    final fallbackKey = StorageKeys.webdavPasswordFallback(configId);
    if (isSecureStorageReady) {
      await _commitSensitiveMutations([
        (password ?? '').isEmpty
            ? SecureStorageMutation.delete(key)
            : SecureStorageMutation.upsert(key, password!),
      ]);
      await _removeSensitiveFallback(fallbackKey, resolveConflict: true);
    } else if ((password ?? '').isEmpty) {
      await _stageSensitiveDeleteFallbackGuards([
        SecureStorageMutation.delete(key),
      ]);
      await _secureDelete(key: key);
      await _removeSensitiveFallback(fallbackKey, resolveConflict: true);
    } else {
      await _saveSecureWithFallback(
        key: key,
        fallbackKey: fallbackKey,
        value: password!,
      );
    }
  }

  Future<String?> loadWebDAVPassword(String configId) async {
    return _readSensitiveValue(
      key: StorageKeys.webdavPassword(configId),
      fallbackKey: StorageKeys.webdavPasswordFallback(configId),
    );
  }

  Future<void> deleteWebDAVPassword(String configId) async {
    await saveWebDAVPassword(configId, null);
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
    final jsonList = configs.map((config) {
      final json = Map<String, dynamic>.from(config.toJson());
      final nested = Map<String, dynamic>.from(
        json['config'] as Map<String, dynamic>? ?? const <String, dynamic>{},
      )..remove('password');
      json['config'] = nested;
      return json;
    }).toList();

    final encoded = jsonEncode(jsonList);
    await _requirePreferenceMutation(
      mutate: () => prefs.setString(StorageKeys.downloaderConfigs, encoded),
      verify: () => prefs.getString(StorageKeys.downloaderConfigs) == encoded,
      failureCode: 'downloader_config_commit_failed',
    );

    await _updateFallbackConflictKeys(
      (conflicts) => conflicts.remove(StorageKeys.downloaderConfigs),
    );

    if (defaultId != null) {
      await _requirePreferenceMutation(
        mutate: () =>
            prefs.setString(StorageKeys.defaultDownloaderId, defaultId),
        verify: () =>
            prefs.getString(StorageKeys.defaultDownloaderId) == defaultId,
        failureCode: 'downloader_config_commit_failed',
      );
    } else {
      if (prefs.containsKey(StorageKeys.defaultDownloaderId)) {
        await _requirePreferenceMutation(
          mutate: () => prefs.remove(StorageKeys.defaultDownloaderId),
          verify: () => !prefs.containsKey(StorageKeys.defaultDownloaderId),
          failureCode: 'downloader_config_commit_failed',
        );
      }
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
      throw StateError('downloader_config_load_failed');
    }
  }

  Future<String?> loadDefaultDownloaderId() async {
    final prefs = await _prefs;
    return prefs.getString(StorageKeys.defaultDownloaderId);
  }

  Future<void> saveDownloaderPassword(String id, String password) =>
      _runInCurrentSecureStorageOperationEpoch(
        () => _saveDownloaderPasswordInCurrentEpoch(id, password),
      );

  Future<void> _saveDownloaderPasswordInCurrentEpoch(
    String id,
    String password,
  ) async {
    final key = StorageKeys.downloaderPasswordKey(id);
    final fallbackKey = StorageKeys.downloaderPasswordFallbackKey(id);
    // A clear is a delete, not a normal update. Remove every legacy qB source
    // before removing the active target so an interruption cannot leave a
    // source that startup migration would use to recreate this password.
    if (password.isEmpty) {
      await _cleanupLegacyQbPasswordSources(id);
    }
    if (isSecureStorageReady) {
      await _commitSensitiveMutations([
        password.isEmpty
            ? SecureStorageMutation.delete(key)
            : SecureStorageMutation.upsert(key, password),
      ]);
      await _removeSensitiveFallback(fallbackKey, resolveConflict: true);
    } else {
      await _saveSecureWithFallback(
        key: key,
        fallbackKey: fallbackKey,
        value: password,
      );
    }
    if (password.isNotEmpty && isSecureStorageReady) {
      await _cleanupLegacyQbPasswordSources(id);
    }
  }

  Future<String?> loadDownloaderPassword(String id) async {
    return _readSensitiveValue(
      key: StorageKeys.downloaderPasswordKey(id),
      fallbackKey: StorageKeys.downloaderPasswordFallbackKey(id),
    );
  }

  Future<void> deleteDownloaderPassword(String id) =>
      _runInCurrentSecureStorageOperationEpoch(
        () => _deleteDownloaderPasswordInCurrentEpoch(id),
      );

  Future<void> _deleteDownloaderPasswordInCurrentEpoch(String id) async {
    final key = StorageKeys.downloaderPasswordKey(id);
    final fallbackKey = StorageKeys.downloaderPasswordFallbackKey(id);
    // Clear every legacy qB source first. If this process is interrupted after
    // the downloader manifest removes its target mapping, a surviving legacy
    // source must not be able to migrate itself back into that now-deleted
    // target on the next startup.
    await _cleanupLegacyQbPasswordSources(id);
    if (isSecureStorageReady) {
      await _commitSensitiveMutations([SecureStorageMutation.delete(key)]);
      await _removeSensitiveFallback(fallbackKey, resolveConflict: true);
    } else {
      await _stageSensitiveDeleteFallbackGuards([
        SecureStorageMutation.delete(key),
      ]);
      await _secureDelete(key: key);
      await _removeSensitiveFallback(fallbackKey, resolveConflict: true);
    }
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
  Future<void> saveDeviceId(String deviceId) =>
      _runInCurrentSecureStorageOperationEpoch(
        () => _runSensitiveStorageOperation(
          () => _saveSecureWithFallback(
            key: StorageKeys.deviceId,
            fallbackKey: StorageKeys.deviceIdFallback,
            value: deviceId,
          ),
        ),
      );

  Future<String?> loadDeviceId() => _runInCurrentSecureStorageOperationEpoch(
    () => _runSensitiveStorageOperation(
      () => _loadSecureWithFallback(
        key: StorageKeys.deviceId,
        fallbackKey: StorageKeys.deviceIdFallback,
      ),
    ),
  );

  Future<void> deleteDeviceId() => _runInCurrentSecureStorageOperationEpoch(
    () => _runSensitiveStorageOperation(_deleteDeviceIdInCurrentEpoch),
  );

  Future<void> _deleteDeviceIdInCurrentEpoch() async {
    await _stageSensitiveDeleteFallbackGuards([
      const SecureStorageMutation.delete(StorageKeys.deviceId),
    ]);
    await _secureDelete(key: StorageKeys.deviceId);
    await _removeSensitiveFallback(
      StorageKeys.deviceIdFallback,
      resolveConflict: true,
    );
  }

  @visibleForTesting
  void resetForTest() {
    _hasPendingConfigUpdates = false;
    _siteConfigsCache = null;
    _siteConfigsCacheDirty = true;
    _siteConfigsCacheNeedsUpdate = false;
    _siteApiKeysCache.clear();
    _siteCookiesCache.clear();
    _visibleTagsCache = null;
    _platformOverrideForTest = null;
    _setSecureStorageStatus(SecureStorageState.unknown);
    _secureStorageUnavailableLatched = false;
    // Invalidate any late platform completion from the previous test run.
    _secureStorageOperationGeneration++;
    _hasLoggedSecureStorageUnavailable = false;
    _cookieCloudBundleCreatedThisRun = false;
    _secureStorageProfile = null;
    _androidSecureOptions = null;
    _androidProfileOverrideForTest = AndroidSecureStorageProfile.fresh;
    _sensitiveTransaction = null;
    _secureStorageTransactionsOverrideForTest = true;
    _secureStorageAuditObserverForTest = null;
    _androidSecureStorageFlushOverrideForTest = () async {};
    _beforeSensitiveFallbackCleanupOverrideForTest = null;
    _afterSensitiveFallbackCleanupMetadataReadOverrideForTest = null;
    _preferenceMutationResultOverrideForTest = null;
    _sensitiveOperationTail = Future<void>.value();
    _siteConfigOperationTail = Future<void>.value();
    _fallbackMetadataOperationTail = Future<void>.value();
    _healthStatusesWriteQueue = Future.value();
  }

  @visibleForTesting
  Future<void> waitForPendingSecureStorageCleanup() =>
      _pendingSecureStorageCleanup;

  @visibleForTesting
  void overridePlatformForTest(TargetPlatform? platform) {
    _platformOverrideForTest = platform;
  }

  @visibleForTesting
  void overrideAndroidSecureStorageProfileForTest(
    AndroidSecureStorageProfile? profile,
  ) {
    _androidProfileOverrideForTest = profile;
    _setSecureStorageStatus(SecureStorageState.unknown);
    _androidSecureOptions = null;
  }

  @visibleForTesting
  void overrideSecureStorageTransactionsForTest(bool? enabled) {
    _secureStorageTransactionsOverrideForTest = enabled;
    _sensitiveTransaction = null;
  }

  @visibleForTesting
  void overrideSecureStorageAuditObserverForTest(
    ValueChanged<String>? observer,
  ) {
    _secureStorageAuditObserverForTest = observer;
  }

  @visibleForTesting
  void overrideAndroidSecureStorageFlushForTest(
    Future<void> Function()? flush,
  ) {
    _androidSecureStorageFlushOverrideForTest = flush;
    _sensitiveTransaction = null;
  }

  @visibleForTesting
  void overrideBeforeSensitiveFallbackCleanupForTest(
    Future<void> Function(String fallbackKey)? callback,
  ) {
    _beforeSensitiveFallbackCleanupOverrideForTest = callback;
  }

  @visibleForTesting
  void overrideAfterSensitiveFallbackCleanupMetadataReadForTest(
    Future<void> Function(String fallbackKey)? callback,
  ) {
    _afterSensitiveFallbackCleanupMetadataReadOverrideForTest = callback;
  }

  @visibleForTesting
  void overridePreferenceMutationResultForTest(
    bool Function(String failureCode, bool committed)? override,
  ) {
    _preferenceMutationResultOverrideForTest = override;
  }

  @visibleForTesting
  bool get isSecureStorageBypassedForCurrentRun =>
      _secureStorageState == SecureStorageState.unavailable;

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
    Map<String, Map<String, dynamic>> statuses, {
    int? expectedSecureStorageEpoch,
  }) async {
    Future<void> operation() async {
      final prefs = await _prefs;
      final encoded = jsonEncode(statuses);
      await _requirePreferenceMutation(
        mutate: () => prefs.setString(StorageKeys.healthStatuses, encoded),
        verify: () => prefs.getString(StorageKeys.healthStatuses) == encoded,
        failureCode: 'health_statuses_commit_failed',
      );
    }

    final expected = expectedSecureStorageEpoch;
    await (expected == null
        ? operation()
        : runWithSecureStorageOperationEpoch(expected, operation));
  }

  Future<void> mergeHealthStatuses(
    Map<String, Map<String, dynamic>> statuses, {
    bool preferNewer = true,
    int? expectedSecureStorageEpoch,
  }) {
    Future<void> merge() async {
      final current = await loadHealthStatuses();
      _requireExpectedSecureStorageOperationEpoch();
      final merged = Map<String, Map<String, dynamic>>.from(current);

      for (final entry in statuses.entries) {
        final siteId = entry.key;
        final nextStatus = entry.value;
        final currentStatus = merged[siteId];

        if (!preferNewer || currentStatus == null) {
          merged[siteId] = nextStatus;
          continue;
        }

        final currentUpdatedAt = _parseHealthStatusUpdatedAt(currentStatus);
        final nextUpdatedAt = _parseHealthStatusUpdatedAt(nextStatus);
        if (currentUpdatedAt == null ||
            nextUpdatedAt == null ||
            !currentUpdatedAt.isAfter(nextUpdatedAt)) {
          merged[siteId] = nextStatus;
        }
      }

      await saveHealthStatuses(merged);
    }

    final expected = expectedSecureStorageEpoch;
    final operation = _healthStatusesWriteQueue.then(
      (_) => expected == null
          ? merge()
          : runWithSecureStorageOperationEpoch(expected, merge),
    );
    _healthStatusesWriteQueue = operation.then<void>((_) {}, onError: (_) {});
    return operation;
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

  DateTime? _parseHealthStatusUpdatedAt(Map<String, dynamic> status) {
    final raw = status['updatedAt']?.toString();
    if (raw == null || raw.isEmpty) return null;
    try {
      return DateTime.parse(raw);
    } catch (_) {
      return null;
    }
  }

  Future<void> saveLastSiteHealthRefreshCheck(
    DateTime time, {
    int? expectedSecureStorageEpoch,
  }) async {
    Future<void> operation() async {
      final prefs = await _prefs;
      final timestamp = time.millisecondsSinceEpoch;
      await _requirePreferenceMutation(
        mutate: () =>
            prefs.setInt(StorageKeys.lastSiteHealthRefreshCheck, timestamp),
        verify: () =>
            prefs.getInt(StorageKeys.lastSiteHealthRefreshCheck) == timestamp,
        failureCode: 'health_refresh_time_commit_failed',
      );
    }

    final expected = expectedSecureStorageEpoch;
    await (expected == null
        ? operation()
        : runWithSecureStorageOperationEpoch(expected, operation));
  }

  Future<DateTime?> loadLastSiteHealthRefreshCheck() async {
    final prefs = await _prefs;
    final timestamp = prefs.getInt(StorageKeys.lastSiteHealthRefreshCheck);
    if (timestamp == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(timestamp);
  }
}
