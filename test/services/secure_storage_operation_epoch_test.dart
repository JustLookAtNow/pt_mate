import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pt_mate/models/app_models.dart';
import 'package:pt_mate/services/network/cookie_cloud_auto_sync_service.dart';
import 'package:pt_mate/services/network/cookie_cloud_service.dart';
import 'package:pt_mate/services/storage/storage_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const secureStorageChannel = MethodChannel(
    'plugins.it_nomads.com/flutter_secure_storage',
  );
  final storage = StorageService.instance;
  late Map<String, String> secureValues;
  late bool failNextSecureRead;

  Future<Object?> secureStorageHandler(MethodCall call) async {
    final arguments = call.arguments as Map<dynamic, dynamic>?;
    final key = arguments?['key'] as String?;
    switch (call.method) {
      case 'write':
        secureValues[key!] = arguments!['value'] as String;
        return null;
      case 'read':
        if (failNextSecureRead) {
          failNextSecureRead = false;
          throw PlatformException(
            code: 'invalid_key',
            message: 'InvalidKeyException',
          );
        }
        return secureValues[key];
      case 'delete':
        secureValues.remove(key);
        return null;
      case 'containsKey':
        return secureValues.containsKey(key);
      case 'readAll':
        return Map<String, String>.from(secureValues);
      default:
        return null;
    }
  }

  Matcher invalidatedOperation() =>
      isA<SecureStorageUnavailableException>().having(
        (error) => error.code,
        'code',
        'secure_storage_operation_invalidated',
      );

  Future<void> initializeReadyStorage() async {
    await storage.initializeSecureStorage();
    // 使用实际存在的密文触发后续读取失败，避免“缺失键”直接从 manifest
    // 返回 null 而不经过平台安全存储。
    await storage.saveDeviceId('epoch-test-device');
  }

  Future<void> failStorageThenRetry() async {
    failNextSecureRead = true;
    await expectLater(
      storage.loadDeviceId(),
      throwsA(isA<SecureStorageUnavailableException>()),
    );
    expect(storage.secureStorageState, SecureStorageState.unavailable);

    await storage.initializeSecureStorage(force: true);
    expect(storage.secureStorageState, SecureStorageState.ready);
  }

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    storage.resetForTest();
    storage.overridePlatformForTest(TargetPlatform.iOS);
    secureValues = <String, String>{};
    failNextSecureRead = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorageChannel, secureStorageHandler);
  });

  tearDown(() async {
    await storage.waitForPendingSecureStorageCleanup();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorageChannel, null);
    storage.resetForTest();
  });

  test('安全存储失败并强制恢复后旧 epoch 永久失效', () async {
    await initializeReadyStorage();
    final oldEpoch = storage.captureSecureStorageOperationEpoch();

    expect(storage.isSecureStorageOperationEpochCurrent(oldEpoch), isTrue);
    storage.requireSecureStorageOperationEpoch(oldEpoch);

    await failStorageThenRetry();

    expect(storage.isSecureStorageOperationEpochCurrent(oldEpoch), isFalse);
    expect(
      () => storage.requireSecureStorageOperationEpoch(oldEpoch),
      throwsA(invalidatedOperation()),
    );
    final currentEpoch = storage.captureSecureStorageOperationEpoch();
    expect(currentEpoch, isNot(oldEpoch));
    expect(storage.isSecureStorageOperationEpochCurrent(currentEpoch), isTrue);
  });

  test('旧运行提交后暂停在 fallback 清理时不会跨 retry 删除明文', () async {
    const downloaderId = 'epoch-fallback-cleanup';
    final fallbackKey = StorageKeys.downloaderPasswordFallbackKey(downloaderId);
    await initializeReadyStorage();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(fallbackKey, 'legacy-plaintext-password');

    final cleanupEntered = Completer<void>();
    final releaseCleanup = Completer<void>();
    var paused = false;
    storage.overrideBeforeSensitiveFallbackCleanupForTest((key) async {
      if (key != fallbackKey || paused) return;
      paused = true;
      cleanupEntered.complete();
      await releaseCleanup.future;
    });

    final staleSave = storage.saveDownloaderPassword(
      downloaderId,
      'new-secure-password',
    );
    await cleanupEntered.future;

    // 此时本次保存的密文事务已提交且其串行锁已释放；模拟另一个操作
    // 发现不可用、用户点“重试”成功，然后旧保存恢复执行。
    await failStorageThenRetry();
    releaseCleanup.complete();

    await expectLater(staleSave, throwsA(invalidatedOperation()));
    expect(prefs.getString(fallbackKey), 'legacy-plaintext-password');
    expect(
      await storage.loadDownloaderPassword(downloaderId),
      'new-secure-password',
    );
    expect(storage.secureStorageState, SecureStorageState.ready);
  });

  test('排队中的 Cookie Cloud 站点提交不会跨 epoch 写入', () async {
    const original = SiteConfig(
      id: 'epoch-cookie-site',
      name: 'Original Site',
      baseUrl: 'https://epoch-cookie.example',
      cookie: 'cookie-old',
      siteType: SiteType.nexusphpweb,
    );
    await storage.saveSiteConfigs(const <SiteConfig>[original]);
    await storage.saveDeviceId('epoch-test-device');
    final oldEpoch = storage.captureSecureStorageOperationEpoch();
    final updateEntered = Completer<void>();
    final releaseUpdate = Completer<void>();

    final staleUpdate = storage.updateSiteConfigsAtomically<bool>((
      current,
    ) async {
      updateEntered.complete();
      await releaseUpdate.future;
      return SiteConfigAtomicUpdate<bool>(
        configs: <SiteConfig>[
          current.single.copyWith(name: 'Stale Site', cookie: 'cookie-stale'),
        ],
        result: true,
      );
    }, expectedSecureStorageEpoch: oldEpoch);

    await updateEntered.future;
    await failStorageThenRetry();
    releaseUpdate.complete();

    await expectLater(staleUpdate, throwsA(invalidatedOperation()));
    final current = await storage.loadSiteConfigs(includeApiKeys: true);
    expect(current, hasLength(1));
    expect(current.single.name, 'Original Site');
    expect(current.single.cookie, 'cookie-old');
    expect(storage.secureStorageState, SecureStorageState.ready);
  });

  test('站点队列中等待的备份恢复不会跨 epoch 提交', () async {
    const original = SiteConfig(
      id: 'epoch-backup-original',
      name: 'Original Site',
      baseUrl: 'https://epoch-backup-old.example',
      cookie: 'cookie-old',
      siteType: SiteType.nexusphpweb,
    );
    const restored = SiteConfig(
      id: 'epoch-backup-restored',
      name: 'Restored Site',
      baseUrl: 'https://epoch-backup-new.example',
      cookie: 'cookie-from-backup',
      siteType: SiteType.nexusphpweb,
    );
    await storage.saveSiteConfigs(const <SiteConfig>[original]);
    await storage.saveThemeMode('light');
    await storage.saveDeviceId('epoch-test-device');
    final oldEpoch = storage.captureSecureStorageOperationEpoch();

    final blockerEntered = Completer<void>();
    final releaseBlocker = Completer<void>();
    final blocker = storage.updateSiteConfigsAtomically<bool>((_) async {
      blockerEntered.complete();
      await releaseBlocker.future;
      throw StateError('release site-config queue');
    });
    final blockerExpectation = expectLater(blocker, throwsA(isA<StateError>()));
    await blockerEntered.future;

    final staleRestore = storage.restoreSensitiveBackupData(
      siteConfigs: const <SiteConfig>[restored],
      backupPreferences: const <String, dynamic>{'themeMode': 'dark'},
      expectedSecureStorageEpoch: oldEpoch,
    );
    await failStorageThenRetry();
    releaseBlocker.complete();

    await blockerExpectation;
    await expectLater(staleRestore, throwsA(invalidatedOperation()));
    final current = await storage.loadSiteConfigs(includeApiKeys: true);
    expect(current.map((site) => site.id), <String>['epoch-backup-original']);
    expect(current.single.cookie, 'cookie-old');
    expect(await storage.loadThemeMode(), 'light');
    expect(storage.secureStorageState, SecureStorageState.ready);
  });

  test('旧 Cookie Cloud 后台任务不能覆盖新运行的同步摘要', () async {
    final originalSyncAt = DateTime.utc(2026, 7, 21, 8);
    await initializeReadyStorage();
    await storage.saveCookieCloudLastSync(
      syncedAt: originalSyncAt,
      summary: 'current-run-summary',
    );
    final oldEpoch = storage.captureSecureStorageOperationEpoch();
    final releaseBackgroundTask = Completer<void>();

    final staleTask = (() async {
      await releaseBackgroundTask.future;
      await storage.saveCookieCloudLastSync(
        syncedAt: DateTime.utc(2026, 7, 21, 9),
        summary: 'stale-run-summary',
        expectedSecureStorageEpoch: oldEpoch,
      );
    })();

    await failStorageThenRetry();
    releaseBackgroundTask.complete();
    await expectLater(staleTask, throwsA(invalidatedOperation()));

    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getString(StorageKeys.cookieCloudLastSyncAt),
      originalSyncAt.toIso8601String(),
    );
    expect(
      prefs.getString(StorageKeys.cookieCloudLastSyncSummary),
      'current-run-summary',
    );
    expect(storage.secureStorageState, SecureStorageState.ready);
  });

  test('Cookie Cloud 网络等待跨 epoch 后不会应用远端 Cookie', () async {
    const original = SiteConfig(
      id: 'epoch-auto-sync-site',
      name: 'Auto Sync Site',
      baseUrl: 'https://epoch-auto-sync.example/',
      cookie: 'cookie-old',
      siteType: SiteType.nexusphpweb,
    );
    await storage.saveSiteConfigs(const <SiteConfig>[original]);
    await storage.saveCookieCloudConfig(
      const CookieCloudConfig(
        url: 'https://cookie-cloud.example',
        uuid: 'epoch-auto-sync-uuid',
        password: 'epoch-auto-sync-password',
        autoSyncEnabled: true,
        lastSyncSummary: 'current-run-summary',
      ),
    );
    await storage.saveDeviceId('epoch-test-device');

    final requestStarted = Completer<void>();
    final releaseResponse = Completer<void>();
    final dio = Dio();
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          requestStarted.complete();
          await releaseResponse.future;
          handler.resolve(
            Response<Map<String, dynamic>>(
              requestOptions: options,
              statusCode: 200,
              data: const <String, dynamic>{
                'epoch-auto-sync.example': 'cookie-from-stale-run',
              },
            ),
          );
        },
      ),
    );
    final autoSync = CookieCloudAutoSyncService.forTest(
      storage: storage,
      cookieCloudService: CookieCloudService(dio: dio, storage: storage),
    );

    final staleSync = autoSync.syncIfNeeded(force: true);
    await requestStarted.future.timeout(const Duration(seconds: 2));
    await failStorageThenRetry();
    releaseResponse.complete();
    await staleSync.timeout(const Duration(seconds: 2));

    final current = await storage.loadSiteConfigs(includeApiKeys: true);
    expect(current.single.cookie, 'cookie-old');
    final config = await storage.loadCookieCloudConfig();
    expect(config.lastSyncAt, isNull);
    expect(config.lastSyncSummary, 'current-run-summary');
    expect(storage.secureStorageState, SecureStorageState.ready);
    dio.close(force: true);
  });

  test('旧健康刷新任务不能提交状态或最后刷新时间', () async {
    final originalCheck = DateTime.utc(2026, 7, 20, 7);
    const originalStatuses = <String, Map<String, dynamic>>{
      'epoch-health-site': <String, dynamic>{
        'ok': true,
        'message': 'current-run-status',
        'updatedAt': '2026-07-20T07:00:00.000Z',
      },
    };
    const staleStatuses = <String, Map<String, dynamic>>{
      'epoch-health-site': <String, dynamic>{
        'ok': false,
        'message': 'stale-run-status',
        'updatedAt': '2026-07-20T08:00:00.000Z',
      },
    };
    await initializeReadyStorage();
    await storage.saveHealthStatuses(originalStatuses);
    await storage.saveLastSiteHealthRefreshCheck(originalCheck);
    final oldEpoch = storage.captureSecureStorageOperationEpoch();
    final releaseBackgroundTasks = Completer<void>();

    final staleMerge = (() async {
      await releaseBackgroundTasks.future;
      await storage.mergeHealthStatuses(
        staleStatuses,
        expectedSecureStorageEpoch: oldEpoch,
      );
    })();
    final staleCheck = (() async {
      await releaseBackgroundTasks.future;
      await storage.saveLastSiteHealthRefreshCheck(
        DateTime.utc(2026, 7, 20, 8),
        expectedSecureStorageEpoch: oldEpoch,
      );
    })();

    await failStorageThenRetry();
    // Both stale tasks resume from the same completer. Register both failure
    // expectations before releasing it so one synchronous epoch rejection
    // cannot be reported as unhandled while the other expectation is awaited.
    final staleMergeExpectation = expectLater(
      staleMerge,
      throwsA(invalidatedOperation()),
    );
    final staleCheckExpectation = expectLater(
      staleCheck,
      throwsA(invalidatedOperation()),
    );
    releaseBackgroundTasks.complete();

    await Future.wait<void>([staleMergeExpectation, staleCheckExpectation]);
    expect(await storage.loadHealthStatuses(), originalStatuses);
    expect(
      (await storage.loadLastSiteHealthRefreshCheck())?.millisecondsSinceEpoch,
      originalCheck.millisecondsSinceEpoch,
    );
    expect(storage.secureStorageState, SecureStorageState.ready);
  });
}
