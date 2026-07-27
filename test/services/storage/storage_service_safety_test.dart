import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pt_mate/models/app_models.dart';
import 'package:pt_mate/services/downloader/downloader_config.dart';
import 'package:pt_mate/services/storage/android_secure_storage_profile_resolver.dart';
import 'package:pt_mate/services/storage/secure_storage_transaction.dart';
import 'package:pt_mate/services/storage/storage_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const secureStorageChannel = MethodChannel(
    'plugins.it_nomads.com/flutter_secure_storage',
  );
  const secureStorageProfileChannel = MethodChannel(
    'pt_mate/secure_storage_profile',
  );
  const manifestKey = 'secureStorage.transaction.sensitiveManifest.v1';

  late StorageService storage;
  late Map<String, String> secureValues;
  late bool failWrites;
  late int writesBeforeFailure;
  late bool corruptSecondReadAfterWrite;
  late Map<String, int> readsAfterWrite;

  Future<Object?> statefulHandler(MethodCall call) async {
    final arguments = call.arguments as Map<dynamic, dynamic>?;
    final key = arguments?['key'] as String?;
    switch (call.method) {
      case 'write':
        if (failWrites && writesBeforeFailure-- <= 0) {
          throw PlatformException(
            code: 'bad_padding',
            message: 'BadPaddingException',
          );
        }
        secureValues[key!] = arguments!['value'] as String;
        readsAfterWrite[key] = 0;
        return null;
      case 'read':
        final value = secureValues[key];
        if (key != null && value != null) {
          final readCount = (readsAfterWrite[key] ?? 0) + 1;
          readsAfterWrite[key] = readCount;
          if (corruptSecondReadAfterWrite && readCount >= 2) {
            return '$value-corrupt-readback';
          }
        }
        return value;
      case 'delete':
        secureValues.remove(key);
        readsAfterWrite.remove(key);
        return null;
      case 'readAll':
        return Map<String, String>.from(secureValues);
      default:
        return null;
    }
  }

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    storage = StorageService.instance;
    storage.resetForTest();
    secureValues = <String, String>{};
    failWrites = false;
    writesBeforeFailure = 0;
    corruptSecondReadAfterWrite = false;
    readsAfterWrite = <String, int>{};
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorageChannel, statefulHandler);
  });

  tearDown(() async {
    await storage.waitForPendingSecureStorageCleanup();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorageChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorageProfileChannel, null);
  });

  test('全新 Android 先原子初始化 OAEP/GCM marker 再读取安全存储', () async {
    storage.overridePlatformForTest(TargetPlatform.android);
    storage.overrideAndroidSecureStorageProfileForTest(null);
    final calls = <String>[];
    var probeCount = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorageProfileChannel, (call) async {
          calls.add(call.method);
          if (call.method == 'initializeFreshAndroidSecureStorage') {
            return <String, Object?>{
              'status': 'ready',
              'profile': 'oaepGcm',
              'keyCipher': 'RSA_ECB_OAEPwithSHA_256andMGF1Padding',
              'storageCipher': 'AES_GCM_NoPadding',
              'hasEncryptedEntries': false,
              'hasWrappedKeys': false,
              'failureCode': null,
            };
          }
          expect(call.method, 'probeAndroidSecureStorage');
          probeCount++;
          if (probeCount == 1) {
            return <String, Object?>{
              'status': 'fresh',
              'profile': 'fresh',
              'keyCipher': null,
              'storageCipher': null,
              'hasEncryptedEntries': false,
              'hasWrappedKeys': false,
              'failureCode': null,
            };
          }
          return <String, Object?>{
            'status': 'ready',
            'profile': 'oaepGcm',
            'keyCipher': 'RSA_ECB_OAEPwithSHA_256andMGF1Padding',
            'storageCipher': 'AES_GCM_NoPadding',
            'hasEncryptedEntries': false,
            'hasWrappedKeys': false,
            'failureCode': null,
          };
        });

    await storage.initializeSecureStorage();

    expect(calls, <String>[
      'probeAndroidSecureStorage',
      'initializeFreshAndroidSecureStorage',
      'probeAndroidSecureStorage',
    ]);
    expect(storage.secureStorageProfile, SecureStorageProfile.androidOaepGcm);
    expect(storage.secureStorageState, SecureStorageState.ready);
  });

  test('Android 初始化会先写入并验证持久化密文见证', () async {
    storage.overridePlatformForTest(TargetPlatform.android);
    storage.overrideAndroidSecureStorageProfileForTest(
      AndroidSecureStorageProfile.oaepGcm,
    );
    storage.overrideSecureStorageTransactionsForTest(false);

    await storage.initializeSecureStorage();
    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getBool(StorageKeys.secureStorageEncryptedEntriesExpectedV1),
      isTrue,
    );
    expect(
      secureValues['__ptmate_secure_storage_witness_v1__'],
      'ptmate-secure-storage-witness-v1',
    );

    await storage.saveDeviceId('device-id');
    await storage.deleteDeviceId();

    expect(secureValues, <String, String>{
      '__ptmate_secure_storage_witness_v1__':
          'ptmate-secure-storage-witness-v1',
    });

    // 删除最后一个用户敏感值后，冷启动仍必须通过见证校验。
    storage.resetForTest();
    storage.overridePlatformForTest(TargetPlatform.android);
    storage.overrideAndroidSecureStorageProfileForTest(
      AndroidSecureStorageProfile.oaepGcm,
    );
    storage.overrideSecureStorageTransactionsForTest(false);
    await storage.initializeSecureStorage();

    expect(
      prefs.getBool(StorageKeys.secureStorageEncryptedEntriesExpectedV1),
      isTrue,
    );
    expect(storage.secureStorageState, SecureStorageState.ready);
  });

  test('Android 见证标记存在但加密见证丢失时阻断启动', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      StorageKeys.secureStorageEncryptedEntriesExpectedV1: true,
    });
    storage.overridePlatformForTest(TargetPlatform.android);
    storage.overrideAndroidSecureStorageProfileForTest(
      AndroidSecureStorageProfile.oaepGcm,
    );

    await expectLater(
      storage.initializeSecureStorage(),
      throwsA(
        isA<SecureStorageUnavailableException>().having(
          (error) => error.code,
          'code',
          'secure_storage_witness_missing',
        ),
      ),
    );

    expect(storage.secureStorageState, SecureStorageState.unavailable);
  });

  test('全新 Android 初始化结果不是 OAEP/GCM 时不读取任何密文', () async {
    storage.overridePlatformForTest(TargetPlatform.android);
    storage.overrideAndroidSecureStorageProfileForTest(null);
    var secureCalls = 0;
    var probeCount = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorageChannel, (_) async {
          secureCalls++;
          return null;
        });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorageProfileChannel, (call) async {
          if (call.method == 'probeAndroidSecureStorage') {
            probeCount++;
            return <String, Object?>{
              'status': 'fresh',
              'profile': 'fresh',
              'keyCipher': null,
              'storageCipher': null,
              'hasEncryptedEntries': false,
              'hasWrappedKeys': false,
              'failureCode': null,
            };
          }
          return <String, Object?>{
            'status': 'ready',
            'profile': 'pkcs1Gcm',
            'keyCipher': 'RSA_ECB_PKCS1Padding',
            'storageCipher': 'AES_GCM_NoPadding',
            'hasEncryptedEntries': false,
            'hasWrappedKeys': false,
            'failureCode': null,
          };
        });

    await expectLater(
      storage.initializeSecureStorage(),
      throwsA(
        isA<SecureStorageUnavailableException>().having(
          (error) => error.code,
          'code',
          'android_fresh_initialization_invalid',
        ),
      ),
    );

    expect(probeCount, 1);
    expect(secureCalls, 0);
    expect(storage.secureStorageState, SecureStorageState.unavailable);
  });

  test('解密异常不会把已有站点配置转换为空列表', () async {
    final prefs = await SharedPreferences.getInstance();
    final original = jsonEncode([
      const SiteConfig(
        id: 'site-a',
        name: 'Site A',
        baseUrl: 'https://a.example.com',
      ).toJson(),
    ]);
    await prefs.setString(StorageKeys.siteConfigs, original);
    var readCount = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorageChannel, (call) async {
          if (call.method == 'read' && readCount++ > 0) {
            throw PlatformException(
              code: 'invalid_key',
              message: 'InvalidKeyException',
            );
          }
          return null;
        });

    await expectLater(
      storage.loadSiteConfigs(),
      throwsA(isA<SecureStorageUnavailableException>()),
    );

    expect(prefs.getString(StorageKeys.siteConfigs), original);
    expect(storage.secureStorageState, SecureStorageState.unavailable);
  });

  test('敏感写入失败不写移动端 fallback 且不覆盖普通站点 JSON', () async {
    final prefs = await SharedPreferences.getInstance();
    const original = '[{"id":"old-site"}]';
    await prefs.setString(StorageKeys.siteConfigs, original);
    failWrites = true;

    await expectLater(
      storage.saveSiteConfigs([
        const SiteConfig(
          id: 'new-site',
          name: 'New Site',
          baseUrl: 'https://new.example.com',
          cookie: 'cookie-new',
          apiKey: 'api-new',
        ),
      ]),
      throwsA(isA<SecureStorageUnavailableException>()),
    );

    expect(prefs.getString(StorageKeys.siteConfigs), original);
    expect(
      prefs.containsKey(StorageKeys.siteCookieFallback('new-site')),
      isFalse,
    );
    expect(
      prefs.containsKey(StorageKeys.siteApiKeyFallback('new-site')),
      isFalse,
    );
  });

  test('第一阶段默认路径不创建 revision manifest', () async {
    storage.overrideSecureStorageTransactionsForTest(false);

    await storage.saveSiteConfigs(const [
      SiteConfig(
        id: 'phase-one-site',
        name: 'Phase One',
        baseUrl: 'https://phase-one.example.com',
        cookie: 'phase-one-cookie',
        apiKey: 'phase-one-api-key',
      ),
    ]);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.containsKey(manifestKey), isFalse);
    expect(
      secureValues[StorageKeys.siteCookie('phase-one-site')],
      'phase-one-cookie',
    );
    expect(
      secureValues[StorageKeys.siteApiKey('phase-one-site')],
      'phase-one-api-key',
    );
    final plain =
        jsonDecode(prefs.getString(StorageKeys.siteConfigs)!) as List<dynamic>;
    final plainSite = plain.single as Map<String, dynamic>;
    expect(plainSite['cookie'], isNull);
    expect(plainSite['apiKey'], isNull);
  });

  test('Linux keyring 可用时第二阶段也提交完整 revision manifest', () async {
    storage.overridePlatformForTest(TargetPlatform.linux);
    storage.overrideSecureStorageTransactionsForTest(true);

    await storage.saveSiteConfigs(const [
      SiteConfig(
        id: 'linux-transaction-site',
        name: 'Linux Transaction Site',
        baseUrl: 'https://linux-transaction.example.com',
        cookie: 'linux-cookie',
        apiKey: 'linux-api-key',
      ),
    ]);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.containsKey(manifestKey), isTrue);
    final manifest =
        jsonDecode(prefs.getString(manifestKey)!) as Map<String, dynamic>;
    final entries = manifest['entries'] as Map<String, dynamic>;
    expect(
      entries.containsKey(StorageKeys.siteCookie('linux-transaction-site')),
      isTrue,
    );
    expect(
      entries.containsKey(StorageKeys.siteApiKey('linux-transaction-site')),
      isTrue,
    );

    storage.resetForTest();
    storage.overridePlatformForTest(TargetPlatform.linux);
    storage.overrideSecureStorageTransactionsForTest(true);
    await storage.initializeSecureStorage();
    final reloaded = await storage.loadSiteConfigs(includeApiKeys: true);
    expect(reloaded.single.cookie, 'linux-cookie');
    expect(reloaded.single.apiKey, 'linux-api-key');
  });

  test('安全存储超时进入 unavailable 而不是 missing', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorageChannel, (call) async {
          if (call.method == 'read') {
            // 初始化探测允许 5 秒，确保平台调用确实越过该上限。
            await Future<void>.delayed(const Duration(seconds: 6));
          }
          return null;
        });

    await expectLater(
      storage.initializeSecureStorage(),
      throwsA(
        isA<SecureStorageUnavailableException>().having(
          (error) => error.code,
          'code',
          'timeout',
        ),
      ),
    );
    expect(storage.secureStorageState, SecureStorageState.unavailable);
  });

  test('敏感读取串行化，后续失败仍锁定 unavailable 状态', () async {
    await storage.initializeSecureStorage();
    final firstReadStarted = Completer<void>();
    final releaseFirstRead = Completer<void>();
    var deviceReadCount = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorageChannel, (call) async {
          final arguments = call.arguments as Map<dynamic, dynamic>?;
          if (call.method == 'read' &&
              arguments?['key'] == StorageKeys.deviceId) {
            deviceReadCount++;
            if (deviceReadCount == 1) {
              firstReadStarted.complete();
              await releaseFirstRead.future;
              return 'stale-success';
            }
            throw PlatformException(
              code: 'invalid_key',
              message: 'InvalidKeyException',
            );
          }
          return statefulHandler(call);
        });

    final oldRead = storage.loadDeviceId();
    await firstReadStarted.future;
    var secondReadCompleted = false;
    final secondRead = storage.loadDeviceId().whenComplete(
      () => secondReadCompleted = true,
    );
    // Device ID fallback migration and deletion share the sensitive lane.
    // The later read must not overtake the old read while it still owns the
    // secure-storage operation.
    await Future<void>.delayed(Duration.zero);
    expect(secondReadCompleted, isFalse);
    releaseFirstRead.complete();
    expect(await oldRead, 'stale-success');
    await expectLater(
      secondRead,
      throwsA(isA<SecureStorageUnavailableException>()),
    );

    expect(storage.secureStorageState, SecureStorageState.unavailable);
    expect(storage.canAccessSensitiveStorage, isFalse);
  });

  test('unavailable 后的敏感写入与删除不再调用原生存储', () async {
    var secureCalls = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorageChannel, (call) async {
          secureCalls++;
          if (call.method == 'read') {
            throw PlatformException(
              code: 'invalid_key',
              message: 'InvalidKeyException',
            );
          }
          return null;
        });
    await expectLater(
      storage.initializeSecureStorage(),
      throwsA(isA<SecureStorageUnavailableException>()),
    );
    secureCalls = 0;

    final blockedOperations = <Future<void> Function()>[
      () => storage.saveProxyPassword('proxy-secret'),
      () => storage.saveWebDAVPassword('webdav-a', 'webdav-secret'),
      () => storage.saveDownloaderPassword('downloader-a', 'client-secret'),
      () => storage.deleteDownloaderPassword('downloader-a'),
      () => storage.saveSiteConfigs(const [
        SiteConfig(
          id: 'site-a',
          name: 'Site A',
          baseUrl: 'https://a.example.com',
          apiKey: 'api-secret',
          cookie: 'cookie-secret',
        ),
      ]),
      () => storage.saveCookieCloudConfig(
        const CookieCloudConfig(
          url: 'https://cloud.example.com',
          uuid: 'uuid-secret',
          password: 'password-secret',
        ),
      ),
    ];
    for (final operation in blockedOperations) {
      await expectLater(
        operation(),
        throwsA(isA<SecureStorageUnavailableException>()),
      );
    }

    final prefs = await SharedPreferences.getInstance();
    expect(secureCalls, 0);
    expect(prefs.containsKey(StorageKeys.siteConfigs), isFalse);
    expect(prefs.getKeys().where((key) => key.contains('.fallback')), isEmpty);
  });

  for (final testCase in <({String platformCode, String message, String code})>[
    (
      platformCode: 'bad_padding',
      message: 'BadPaddingException secret-value',
      code: 'bad_padding',
    ),
    (
      platformCode: 'invalid_key',
      message: 'InvalidKeyException site-id',
      code: 'invalid_key',
    ),
    (
      platformCode: 'unknown_algorithm',
      message: 'NoSuchAlgorithmException key-name',
      code: 'unsupported_algorithm',
    ),
  ]) {
    test('原生异常归一为固定类别 ${testCase.code}', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(secureStorageChannel, (call) async {
            if (call.method == 'read') {
              throw PlatformException(
                code: testCase.platformCode,
                message: testCase.message,
              );
            }
            return null;
          });

      await expectLater(
        storage.initializeSecureStorage(),
        throwsA(
          isA<SecureStorageUnavailableException>().having(
            (error) => error.code,
            'code',
            testCase.code,
          ),
        ),
      );
      expect(storage.secureStorageFailureCode, testCase.code);
    });
  }

  test('安全存储审计日志不会包含异常中的键名、站点或敏感 canary', () async {
    const siteCanary = 'site-canary-do-not-log';
    const keyCanary = 'site.cookie.logical-key-canary';
    const secretCanary = 'cookie-secret-canary';
    final auditLines = <String>[];
    storage.overrideSecureStorageAuditObserverForTest(auditLines.add);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorageChannel, (call) async {
          if (call.method == 'read') {
            throw PlatformException(
              code: 'storage_failure',
              message: '$siteCanary $keyCanary $secretCanary',
            );
          }
          return null;
        });

    await expectLater(
      storage.initializeSecureStorage(),
      throwsA(isA<SecureStorageUnavailableException>()),
    );

    expect(auditLines, hasLength(1));
    final line = auditLines.single;
    expect(line, contains('profile='));
    expect(line, contains('state=unavailable'));
    expect(line, contains('code=platform_error'));
    expect(line, isNot(contains(siteCanary)));
    expect(line, isNot(contains(keyCanary)));
    expect(line, isNot(contains(secretCanary)));
  });

  test('不一致算法 profile 在读取任何密文前即阻断', () async {
    var secureCalls = 0;
    storage.overrideAndroidSecureStorageProfileForTest(
      AndroidSecureStorageProfile.inconsistent,
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorageChannel, (_) async {
          secureCalls++;
          return null;
        });

    await expectLater(
      storage.initializeSecureStorage(),
      throwsA(
        isA<SecureStorageUnavailableException>().having(
          (error) => error.code,
          'code',
          'android_secure_storage_profile_invalid',
        ),
      ),
    );
    expect(secureCalls, 0);
  });

  test('manifest 存在但活动密文缺失时要求恢复', () async {
    SharedPreferences.setMockInitialValues({
      manifestKey: jsonEncode({
        'version': 1,
        'revision': 'revision-a',
        'entries': {'site.cookie.site-a': 'missing-physical-value'},
        'garbage': <String>[],
      }),
    });

    await expectLater(
      storage.initializeSecureStorage(),
      throwsA(
        isA<SecureStorageUnavailableException>().having(
          (error) => error.code,
          'code',
          'secure_transaction_requires_restore',
        ),
      ),
    );
  });

  test('事务预检完成前不对外发布 ready 且外部读取继续排队', () async {
    const activePhysicalKey = 'active-physical-during-preflight';
    SharedPreferences.setMockInitialValues({
      manifestKey: jsonEncode({
        'version': 1,
        'revision': 'revision-preflight',
        'entries': {StorageKeys.proxyPassword: activePhysicalKey},
        'garbage': <String>[],
      }),
    });
    secureValues[activePhysicalKey] = 'active-password';
    storage.overridePlatformForTest(TargetPlatform.iOS);

    final reconcileStarted = Completer<void>();
    final releaseReconcile = Completer<void>();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorageChannel, (call) async {
          final arguments = call.arguments as Map<dynamic, dynamic>?;
          if (call.method == 'read' && arguments?['key'] == activePhysicalKey) {
            if (!reconcileStarted.isCompleted) reconcileStarted.complete();
            await releaseReconcile.future;
          }
          return statefulHandler(call);
        });

    final initialization = storage.initializeSecureStorage();
    await reconcileStarted.future;

    expect(storage.secureStorageState, SecureStorageState.unknown);
    expect(storage.canAccessSensitiveStorage, isFalse);

    var externalReadCompleted = false;
    final externalRead = storage.loadDeviceId().then((value) {
      externalReadCompleted = true;
      return value;
    });
    await pumpEventQueue(times: 10);
    expect(externalReadCompleted, isFalse);

    releaseReconcile.complete();
    await initialization;
    expect(storage.secureStorageState, SecureStorageState.ready);
    expect(await externalRead, isNull);
    expect(externalReadCompleted, isTrue);
  });

  test('manifest 仍有站点密文但普通站点配置缺失时要求恢复', () async {
    const site = SiteConfig(
      id: 'site-with-orphaned-secret',
      name: 'Site',
      baseUrl: 'https://site.example.com',
      cookie: 'cookie-value',
      apiKey: 'api-value',
    );
    await storage.saveSiteConfigs([site]);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(StorageKeys.siteConfigs);
    await storage.waitForPendingSecureStorageCleanup();
    storage.resetForTest();

    await expectLater(
      storage.loadSiteConfigs(includeApiKeys: true),
      throwsA(
        isA<SecureStorageUnavailableException>().having(
          (error) => error.code,
          'code',
          'secure_transaction_requires_restore',
        ),
      ),
    );
    expect(storage.secureStorageState, SecureStorageState.unavailable);
  });

  test('Linux 非 keyring 错误不会创建明文 fallback', () async {
    storage.overridePlatformForTest(TargetPlatform.linux);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorageChannel, (call) async {
          if (call.method == 'read') {
            throw PlatformException(
              code: 'invalid_key',
              message: 'InvalidKeyException',
            );
          }
          return null;
        });

    await expectLater(
      storage.saveDownloaderPassword('downloader-a', 'secret'),
      throwsA(isA<SecureStorageUnavailableException>()),
    );
    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.containsKey(
        StorageKeys.downloaderPasswordFallbackKey('downloader-a'),
      ),
      isFalse,
    );
    expect(storage.canAccessSensitiveStorage, isFalse);
  });

  test('Linux keyring 不可用时仍可删除既有明文 fallback', () async {
    const downloaderId = 'linux-delete-downloader';
    const webdavId = 'linux-delete-webdav';
    SharedPreferences.setMockInitialValues(<String, Object>{
      StorageKeys.downloaderPasswordFallbackKey(downloaderId):
          'downloader-password',
      StorageKeys.webdavPasswordFallback(webdavId): 'webdav-password',
      StorageKeys.deviceIdFallback: 'device-id',
    });
    storage.overridePlatformForTest(TargetPlatform.linux);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorageChannel, (call) async {
          if (call.method == 'read') {
            throw PlatformException(
              code: 'keyring_locked',
              message: 'Failed to unlock the keyring',
            );
          }
          return null;
        });

    await storage.initializeSecureStorage();
    expect(storage.canAccessSensitiveStorage, isTrue);
    expect(storage.isSecureStorageReady, isFalse);

    await storage.deleteDownloaderPassword(downloaderId);
    await storage.deleteWebDAVPassword(webdavId);
    await storage.deleteDeviceId();

    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.containsKey(
        StorageKeys.downloaderPasswordFallbackKey(downloaderId),
      ),
      isFalse,
    );
    expect(
      prefs.containsKey(StorageKeys.webdavPasswordFallback(webdavId)),
      isFalse,
    );
    expect(prefs.containsKey(StorageKeys.deviceIdFallback), isFalse);
  });

  test('移动端已有 fallback 在安全值缺失时写入并读回后删除', () async {
    SharedPreferences.setMockInitialValues({
      StorageKeys.proxyPasswordFallback: 'fallback-password',
    });

    expect(await storage.loadProxyPassword(), 'fallback-password');

    final prefs = await SharedPreferences.getInstance();
    expect(secureValues[StorageKeys.proxyPassword], 'fallback-password');
    expect(prefs.containsKey(StorageKeys.proxyPasswordFallback), isFalse);
  });

  test('移动端 secure 与 fallback 冲突时以 secure 为准并保留警告', () async {
    SharedPreferences.setMockInitialValues({
      StorageKeys.proxyPasswordFallback: 'fallback-password',
    });
    secureValues[StorageKeys.proxyPassword] = 'secure-password';

    expect(await storage.loadProxyPassword(), 'secure-password');

    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getString(StorageKeys.proxyPasswordFallback),
      'fallback-password',
    );
    expect(await storage.hasSecureStorageFallbackConflict(), isTrue);
  });

  test('安全存储中已找到的空字符串不会被 fallback 覆盖', () async {
    SharedPreferences.setMockInitialValues({
      StorageKeys.proxyPasswordFallback: 'stale-password',
    });
    secureValues[StorageKeys.proxyPassword] = '';

    expect(await storage.loadProxyPassword(), '');

    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getString(StorageKeys.proxyPasswordFallback),
      'stale-password',
    );
    expect(await storage.hasSecureStorageFallbackConflict(), isTrue);
  });

  test('manifest 已存在时会迁移未映射 fallback 并删除明文', () async {
    const downloaderId = 'transaction-fallback-missing';
    final fallbackKey = StorageKeys.downloaderPasswordFallbackKey(downloaderId);
    await storage.saveProxyPassword('proxy-password');
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(fallbackKey, 'fallback-password');
    await storage.waitForPendingSecureStorageCleanup();
    storage.resetForTest();

    expect(
      await storage.loadDownloaderPassword(downloaderId),
      'fallback-password',
    );
    expect(prefs.containsKey(fallbackKey), isFalse);
    expect(await storage.hasSecureStorageFallbackConflict(), isFalse);
  });

  test('manifest 已存在时遗留的异值 fallback 会保留并告警', () async {
    const downloaderId = 'transaction-fallback-conflict';
    final fallbackKey = StorageKeys.downloaderPasswordFallbackKey(downloaderId);
    await storage.saveDownloaderPassword(downloaderId, 'secure-password');
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(fallbackKey, 'stale-password');
    await storage.waitForPendingSecureStorageCleanup();
    storage.resetForTest();

    expect(
      await storage.loadDownloaderPassword(downloaderId),
      'secure-password',
    );
    expect(prefs.getString(fallbackKey), 'stale-password');
    expect(await storage.hasSecureStorageFallbackConflict(), isTrue);

    await storage.saveDownloaderPassword(downloaderId, 'confirmed-password');
    expect(prefs.containsKey(fallbackKey), isFalse);
    expect(await storage.hasSecureStorageFallbackConflict(), isFalse);
  });

  test('Android 落盘屏障失败时 fallback 事务不切换 manifest', () async {
    const downloaderId = 'flush-failure-fallback';
    final fallbackKey = StorageKeys.downloaderPasswordFallbackKey(downloaderId);
    await storage.saveProxyPassword('proxy-password');
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(fallbackKey, 'fallback-password');

    await storage.waitForPendingSecureStorageCleanup();
    // 首次事务会把不存在的旧逻辑键列入幂等垃圾清单；先在正常屏障下
    // 完成该清理，确保下面只注入“新 revision 提交前”的屏障失败。
    storage.resetForTest();
    await storage.initializeSecureStorage();
    await storage.waitForPendingSecureStorageCleanup();
    final oldManifest = prefs.getString(manifestKey)!;
    storage.resetForTest();
    storage.overrideAndroidSecureStorageFlushForTest(() async {
      throw const SecureStorageUnavailableException(
        'secure_storage_flush_commit_failed',
      );
    });

    await expectLater(
      storage.loadDownloaderPassword(downloaderId),
      throwsA(
        isA<SecureStorageUnavailableException>().having(
          (error) => error.code,
          'code',
          'secure_storage_flush_commit_failed',
        ),
      ),
    );

    expect(prefs.getString(manifestKey), oldManifest);
    expect(prefs.getString(fallbackKey), 'fallback-password');
    expect(storage.secureStorageState, SecureStorageState.unavailable);
  });

  test('站点 API Key fallback 迁移后读回并删除明文', () async {
    const siteId = 'site-api-fallback';
    final fallbackKey = StorageKeys.siteApiKeyFallback(siteId);
    final secureKey = StorageKeys.siteApiKey(siteId);
    SharedPreferences.setMockInitialValues({
      StorageKeys.siteConfigs: jsonEncode([
        const SiteConfig(
          id: siteId,
          name: 'API Site',
          baseUrl: 'https://api.example.com',
        ).toJson(),
      ]),
      fallbackKey: 'fallback-api-key',
    });

    final loaded = await storage.loadSiteConfigs(includeApiKeys: true);

    final prefs = await SharedPreferences.getInstance();
    expect(loaded.single.apiKey, 'fallback-api-key');
    expect(secureValues[secureKey], 'fallback-api-key');
    expect(prefs.containsKey(fallbackKey), isFalse);
  });

  test('下载器 fallback 冲突保留到明确重存', () async {
    const downloaderId = 'downloader-conflict';
    final fallbackKey = StorageKeys.downloaderPasswordFallbackKey(downloaderId);
    final secureKey = StorageKeys.downloaderPasswordKey(downloaderId);
    SharedPreferences.setMockInitialValues({fallbackKey: 'stale-password'});
    secureValues[secureKey] = 'secure-password';

    expect(
      await storage.loadDownloaderPassword(downloaderId),
      'secure-password',
    );
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(fallbackKey), 'stale-password');
    expect(await storage.hasSecureStorageFallbackConflict(), isTrue);

    await storage.saveDownloaderPassword(downloaderId, 'confirmed-password');
    expect(
      await storage.loadDownloaderPassword(downloaderId),
      'confirmed-password',
    );
    expect(prefs.containsKey(fallbackKey), isFalse);
    expect(await storage.hasSecureStorageFallbackConflict(), isFalse);
  });

  test('移动端旧下载器内嵌密码写入安全存储并读回后清除明文', () async {
    const downloaderId = 'embedded-downloader';
    SharedPreferences.setMockInitialValues({
      StorageKeys.appVersion: StorageService.currentVersion,
      StorageKeys.downloaderConfigs: jsonEncode([
        {
          'id': downloaderId,
          'name': 'Embedded',
          'type': 'qbittorrent',
          'config': {
            'host': 'downloader.example.com',
            'port': 8080,
            'username': 'user',
            'password': 'embedded-password',
          },
        },
      ]),
    });

    await storage.checkAndMigrate();

    final prefs = await SharedPreferences.getInstance();
    final stored =
        (jsonDecode(prefs.getString(StorageKeys.downloaderConfigs)!)
            as List<dynamic>);
    final config = stored.single as Map<String, dynamic>;
    expect(
      (config['config'] as Map<String, dynamic>).containsKey('password'),
      isFalse,
    );
    expect(
      await storage.loadDownloaderPassword(downloaderId),
      'embedded-password',
    );
    expect(await storage.hasSecureStorageFallbackConflict(), isFalse);
  });

  test('移动端旧下载器内嵌密码冲突保留到用户重新保存', () async {
    const downloaderId = 'embedded-conflict';
    SharedPreferences.setMockInitialValues({
      StorageKeys.appVersion: StorageService.currentVersion,
      StorageKeys.downloaderConfigs: jsonEncode([
        {
          'id': downloaderId,
          'name': 'Embedded Conflict',
          'type': 'qbittorrent',
          'config': {
            'host': 'downloader.example.com',
            'port': 8080,
            'username': 'user',
            'password': 'stale-password',
          },
        },
      ]),
    });
    secureValues[StorageKeys.downloaderPasswordKey(downloaderId)] =
        'secure-password';

    await storage.checkAndMigrate();

    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getString(StorageKeys.downloaderConfigs),
      contains('stale-password'),
    );
    expect(await storage.hasSecureStorageFallbackConflict(), isTrue);

    await storage.saveDownloaderConfigs(const [
      QbittorrentConfig(
        id: downloaderId,
        name: 'Embedded Conflict',
        host: 'downloader.example.com',
        port: 8080,
        username: 'user',
        password: 'stale-password',
      ),
    ]);
    expect(
      prefs.getString(StorageKeys.downloaderConfigs),
      isNot(contains('stale-password')),
    );
    expect(
      await storage.loadDownloaderPassword(downloaderId),
      'secure-password',
    );
    expect(await storage.hasSecureStorageFallbackConflict(), isFalse);
  });

  test('旧 qB 明文 fallback 成功迁移到下载器安全密码', () async {
    const downloaderId = 'legacy-qb';
    final fallbackKey = StorageKeys.legacyQbPasswordFallbackKey(downloaderId);
    SharedPreferences.setMockInitialValues({
      StorageKeys.appVersion: StorageService.currentVersion,
      fallbackKey: 'legacy-qb-password',
    });

    await storage.checkAndMigrate();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.containsKey(fallbackKey), isFalse);
    expect(
      await storage.loadDownloaderPassword(downloaderId),
      'legacy-qb-password',
    );
  });

  test('旧 qB 密码与新目标冲突时保留两者直到明确重存', () async {
    const downloaderId = 'legacy-qb-conflict';
    final legacySecureKey = StorageKeys.legacyQbPasswordKey(downloaderId);
    final legacyFallbackKey = StorageKeys.legacyQbPasswordFallbackKey(
      downloaderId,
    );
    await storage.saveDownloaderPassword(downloaderId, 'current-password');
    secureValues[legacySecureKey] = 'legacy-secure-password';
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(legacyFallbackKey, 'legacy-fallback-password');
    await prefs.setString(
      StorageKeys.appVersion,
      StorageService.currentVersion,
    );

    await storage.checkAndMigrate();

    expect(
      await storage.loadDownloaderPassword(downloaderId),
      'current-password',
    );
    expect(secureValues[legacySecureKey], 'legacy-secure-password');
    expect(prefs.getString(legacyFallbackKey), 'legacy-fallback-password');
    expect(await storage.hasSecureStorageFallbackConflict(), isTrue);

    await storage.saveDownloaderPassword(downloaderId, 'confirmed-password');
    expect(secureValues.containsKey(legacySecureKey), isFalse);
    expect(prefs.containsKey(legacyFallbackKey), isFalse);
    expect(await storage.hasSecureStorageFallbackConflict(), isFalse);
  });

  test('旧 qB 安全值已找到为空时不会被非空 fallback 覆盖', () async {
    const downloaderId = 'legacy-qb-empty-secure';
    final legacySecureKey = StorageKeys.legacyQbPasswordKey(downloaderId);
    final legacyFallbackKey = StorageKeys.legacyQbPasswordFallbackKey(
      downloaderId,
    );
    secureValues[legacySecureKey] = '';
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(legacyFallbackKey, 'plaintext-stale');
    await prefs.setString(
      StorageKeys.appVersion,
      StorageService.currentVersion,
    );

    await storage.checkAndMigrate();

    expect(await storage.loadDownloaderPassword(downloaderId), isNull);
    expect(secureValues[legacySecureKey], '');
    expect(prefs.getString(legacyFallbackKey), 'plaintext-stale');
    expect(await storage.hasSecureStorageFallbackConflict(), isTrue);
  });

  test('旧 qB 密码迁移失败时不删除旧配置、fallback 或版本号', () async {
    const downloaderId = 'legacy-qb-failure';
    final fallbackKey = StorageKeys.legacyQbPasswordFallbackKey(downloaderId);
    final legacyConfigs = jsonEncode([
      {
        'id': downloaderId,
        'name': 'Legacy qB',
        'host': 'qb.example.com',
        'port': 8080,
        'username': 'user',
      },
    ]);
    SharedPreferences.setMockInitialValues({
      StorageKeys.appVersion: '1.0.0',
      StorageKeys.legacyQbClientConfigs: legacyConfigs,
      fallbackKey: 'legacy-qb-password',
    });
    failWrites = true;

    await expectLater(
      storage.checkAndMigrate(),
      throwsA(isA<SecureStorageUnavailableException>()),
    );

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(StorageKeys.appVersion), '1.0.0');
    expect(prefs.getString(StorageKeys.legacyQbClientConfigs), legacyConfigs);
    expect(prefs.getString(fallbackKey), 'legacy-qb-password');
    expect(prefs.containsKey(StorageKeys.downloaderConfigs), isFalse);
  });

  test('WebDAV fallback 读回迁移，冲突则保留到用户重新保存', () async {
    const configId = 'webdav-a';
    final fallbackKey = StorageKeys.webdavPasswordFallback(configId);
    final secureKey = StorageKeys.webdavPassword(configId);
    SharedPreferences.setMockInitialValues({fallbackKey: 'fallback-password'});

    expect(await storage.loadWebDAVPassword(configId), 'fallback-password');
    var prefs = await SharedPreferences.getInstance();
    expect(secureValues[secureKey], 'fallback-password');
    expect(prefs.containsKey(fallbackKey), isFalse);

    await storage.waitForPendingSecureStorageCleanup();
    storage.resetForTest();
    secureValues[secureKey] = 'secure-password';
    SharedPreferences.setMockInitialValues({fallbackKey: 'stale-password'});
    expect(await storage.loadWebDAVPassword(configId), 'secure-password');
    prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(fallbackKey), 'stale-password');
    expect(await storage.hasSecureStorageFallbackConflict(), isTrue);

    await storage.saveWebDAVPassword(configId, 'confirmed-password');
    expect(await storage.loadWebDAVPassword(configId), 'confirmed-password');
    expect(prefs.containsKey(fallbackKey), isFalse);
    expect(await storage.hasSecureStorageFallbackConflict(), isFalse);
  });

  test('自动站点保存不会清理逐键 fallback 冲突', () async {
    const siteId = 'site-conflict';
    final fallbackKey = StorageKeys.siteCookieFallback(siteId);
    final secureKey = StorageKeys.siteCookie(siteId);
    final plainSite = const SiteConfig(
      id: siteId,
      name: 'Conflict Site',
      baseUrl: 'https://conflict.example.com',
    ).toJson();
    SharedPreferences.setMockInitialValues({
      StorageKeys.siteConfigs: jsonEncode([plainSite]),
      fallbackKey: 'stale-cookie',
    });
    secureValues[secureKey] = 'secure-cookie';

    final loaded = await storage.loadSiteConfigs();
    expect(loaded.single.cookie, 'secure-cookie');
    await storage.saveSiteConfigs(loaded);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(fallbackKey), 'stale-cookie');
    expect(await storage.hasSecureStorageFallbackConflict(), isTrue);

    await storage.updateSiteConfig(
      loaded.single.copyWith(cookie: 'confirmed-cookie'),
    );
    expect(prefs.containsKey(fallbackKey), isFalse);
    expect(await storage.hasSecureStorageFallbackConflict(), isFalse);
  });

  test('旧站点 JSON Cookie 冲突时不覆盖密文且不自动清理明文', () async {
    const siteId = 'embedded-site-cookie-conflict';
    final legacyJson = const SiteConfig(
      id: siteId,
      name: 'Legacy Cookie Site',
      baseUrl: 'https://legacy-cookie.example.com',
      cookie: 'plaintext-cookie-secret',
    ).toJson();
    SharedPreferences.setMockInitialValues({
      StorageKeys.siteConfigs: jsonEncode([legacyJson]),
    });
    secureValues[StorageKeys.siteCookie(siteId)] = 'secure-cookie';

    final loaded = await storage.loadSiteConfigs(includeApiKeys: true);

    final prefs = await SharedPreferences.getInstance();
    expect(loaded.single.cookie, 'secure-cookie');
    expect(
      prefs.getString(StorageKeys.siteConfigs),
      contains('plaintext-cookie-secret'),
    );
    expect(secureValues[StorageKeys.siteCookie(siteId)], 'secure-cookie');
    expect(await storage.hasSecureStorageFallbackConflict(), isTrue);

    await storage.updateSiteConfig(
      loaded.single.copyWith(cookie: 'confirmed-cookie'),
    );
    expect(
      prefs.getString(StorageKeys.siteConfigs),
      isNot(contains('plaintext-cookie-secret')),
    );
    expect(
      await storage.loadSiteConfigs().then((sites) => sites.single.cookie),
      'confirmed-cookie',
    );
    expect(await storage.hasSecureStorageFallbackConflict(), isFalse);
  });

  test('旧站点 JSON Cookie 目标缺失时先验证密文再清除明文', () async {
    const siteId = 'embedded-site-cookie-migration';
    final legacyJson = const SiteConfig(
      id: siteId,
      name: 'Legacy Cookie Site',
      baseUrl: 'https://legacy-cookie.example.com',
      cookie: 'plaintext-cookie-secret',
    ).toJson();
    SharedPreferences.setMockInitialValues({
      StorageKeys.siteConfigs: jsonEncode([legacyJson]),
    });

    final loaded = await storage.loadSiteConfigs(includeApiKeys: true);

    final prefs = await SharedPreferences.getInstance();
    expect(loaded.single.cookie, 'plaintext-cookie-secret');
    expect(
      prefs.getString(StorageKeys.siteConfigs),
      isNot(contains('plaintext-cookie-secret')),
    );
    expect(
      await storage.loadSiteConfigs().then((sites) => sites.single.cookie),
      'plaintext-cookie-secret',
    );
    expect(await storage.hasSecureStorageFallbackConflict(), isFalse);
  });

  test('Cookie Cloud 迁移为单条 JSON 并在下一次启动清理旧三键', () async {
    secureValues.addAll({
      StorageKeys.cookieCloudUrl: 'https://cloud.example.com',
      StorageKeys.cookieCloudUuid: 'uuid-a',
      StorageKeys.cookieCloudPassword: 'password-a',
    });

    final firstLoad = await storage.loadCookieCloudConfig();
    expect(firstLoad.url, 'https://cloud.example.com');
    expect(firstLoad.uuid, 'uuid-a');
    expect(firstLoad.password, 'password-a');

    final prefs = await SharedPreferences.getInstance();
    final manifest =
        jsonDecode(prefs.getString(manifestKey)!) as Map<String, dynamic>;
    final entries = manifest['entries'] as Map<String, dynamic>;
    final bundlePhysicalKey =
        entries[StorageKeys.cookieCloudSecretsV2] as String;
    final bundle =
        jsonDecode(secureValues[bundlePhysicalKey]!) as Map<String, dynamic>;
    expect(bundle.keys.toSet(), {'url', 'uuid', 'password'});
    expect(secureValues.containsKey(StorageKeys.cookieCloudUrl), isTrue);

    await storage.waitForPendingSecureStorageCleanup();
    storage.resetForTest();
    final secondLoad = await storage.loadCookieCloudConfig();
    expect(secondLoad.password, 'password-a');
    expect(secureValues.containsKey(StorageKeys.cookieCloudUrl), isFalse);
    expect(secureValues.containsKey(StorageKeys.cookieCloudUuid), isFalse);
    expect(secureValues.containsKey(StorageKeys.cookieCloudPassword), isFalse);
    expect(
      prefs.containsKey(StorageKeys.cookieCloudSecretsV2PendingCleanup),
      isFalse,
    );
  });

  test('Cookie Cloud 明文密码冲突保留，明确重存后才清理', () async {
    SharedPreferences.setMockInitialValues({
      StorageKeys.cookieCloudPassword: 'plaintext-password',
    });
    secureValues.addAll({
      StorageKeys.cookieCloudUrl: 'https://cloud.example.com',
      StorageKeys.cookieCloudUuid: 'uuid-a',
      StorageKeys.cookieCloudPassword: 'secure-password',
    });

    final migrated = await storage.loadCookieCloudConfig();
    expect(migrated.password, 'secure-password');
    var prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getString(StorageKeys.cookieCloudPassword),
      'plaintext-password',
    );
    expect(await storage.hasSecureStorageFallbackConflict(), isTrue);

    await storage.waitForPendingSecureStorageCleanup();
    storage.resetForTest();
    final secondLoad = await storage.loadCookieCloudConfig();
    expect(secondLoad.password, 'secure-password');
    expect(prefs.containsKey(StorageKeys.cookieCloudPassword), isTrue);

    await storage.saveCookieCloudConfig(secondLoad);
    prefs = await SharedPreferences.getInstance();
    expect(prefs.containsKey(StorageKeys.cookieCloudPassword), isFalse);
    expect(await storage.hasSecureStorageFallbackConflict(), isFalse);
  });

  test('Cookie Cloud 旧安全值已找到为空时不采用旧明文', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      StorageKeys.cookieCloudUrl,
      'https://plaintext-stale.example.com',
    );
    secureValues.addAll({
      StorageKeys.cookieCloudUrl: '',
      StorageKeys.cookieCloudUuid: 'uuid-secure',
      StorageKeys.cookieCloudPassword: 'password-secure',
    });

    final migrated = await storage.loadCookieCloudConfig();

    expect(migrated.url, isEmpty);
    expect(migrated.uuid, 'uuid-secure');
    expect(migrated.password, 'password-secure');
    expect(
      prefs.getString(StorageKeys.cookieCloudUrl),
      'https://plaintext-stale.example.com',
    );
    expect(await storage.hasSecureStorageFallbackConflict(), isTrue);
  });

  test('Cookie Cloud v2 已找到为空时判为损坏而不回退旧三键', () async {
    secureValues[StorageKeys.cookieCloudSecretsV2] = '';
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      StorageKeys.cookieCloudUrl,
      'https://plaintext-stale.example.com',
    );
    // 先触发另一敏感值的首次事务，确保 bootstrap 也不会把 found-empty
    // bundle 当作 missing 而从 manifest 中丢掉。
    await storage.saveProxyPassword('proxy-password');
    final manifestBeforeLoad =
        jsonDecode(prefs.getString(manifestKey)!) as Map<String, dynamic>;
    final manifestEntries =
        manifestBeforeLoad['entries'] as Map<String, dynamic>;
    final bundlePhysicalKey =
        manifestEntries[StorageKeys.cookieCloudSecretsV2] as String;
    expect(secureValues[bundlePhysicalKey], '');

    await expectLater(
      storage.loadCookieCloudConfig(),
      throwsA(
        isA<SecureStorageUnavailableException>().having(
          (error) => error.code,
          'code',
          'cookie_cloud_bundle_invalid',
        ),
      ),
    );

    expect(storage.secureStorageState, SecureStorageState.unavailable);
    expect(secureValues[StorageKeys.cookieCloudSecretsV2], '');
    expect(
      prefs.getString(StorageKeys.cookieCloudUrl),
      'https://plaintext-stale.example.com',
    );
  });

  test('Cookie Cloud v2 缺字段时进入 unavailable 且不清理旧键', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      manifestKey,
      jsonEncode({
        'version': 1,
        'revision': 'revision-invalid-bundle',
        'entries': {
          StorageKeys.cookieCloudSecretsV2: 'physical-invalid-bundle',
        },
        'garbage': <String>[],
      }),
    );
    await prefs.setString(StorageKeys.cookieCloudPassword, 'legacy-password');
    secureValues['physical-invalid-bundle'] = '{}';

    await expectLater(
      storage.loadCookieCloudConfig(),
      throwsA(
        isA<SecureStorageUnavailableException>().having(
          (error) => error.code,
          'code',
          'cookie_cloud_bundle_invalid',
        ),
      ),
    );
    expect(prefs.getString(StorageKeys.cookieCloudPassword), 'legacy-password');
    expect(storage.secureStorageState, SecureStorageState.unavailable);
  });

  test('Cookie Cloud 提交后读回不一致会粘滞 unavailable', () async {
    corruptSecondReadAfterWrite = true;

    await expectLater(
      storage.saveCookieCloudConfig(
        const CookieCloudConfig(
          url: 'https://cookie-cloud.example.com',
          uuid: 'cookie-cloud-uuid',
          password: 'cookie-cloud-password',
        ),
      ),
      throwsA(
        isA<SecureStorageUnavailableException>().having(
          (error) => error.code,
          'code',
          'cookie_cloud_bundle_verification_failed',
        ),
      ),
    );

    expect(storage.secureStorageState, SecureStorageState.unavailable);
    expect(storage.canAccessSensitiveStorage, isFalse);
  });

  test('manifest 已提交后强杀，重启先完成普通站点 JSON 再清理旧版', () async {
    const oldConfig = SiteConfig(
      id: 'site-a',
      name: 'Old Site',
      baseUrl: 'https://a.example.com',
      cookie: 'cookie-old',
      apiKey: 'api-old',
    );
    const newConfig = SiteConfig(
      id: 'site-a',
      name: 'New Site',
      baseUrl: 'https://a.example.com',
      cookie: 'cookie-new',
      apiKey: 'api-new',
    );
    await storage.saveSiteConfigs([oldConfig]);
    final prefs = await SharedPreferences.getInstance();
    final oldPlain = prefs.getString(StorageKeys.siteConfigs)!;
    await storage.saveSiteConfigs([newConfig]);
    final newPlain = prefs.getString(StorageKeys.siteConfigs)!;
    final manifest =
        jsonDecode(prefs.getString(manifestKey)!) as Map<String, dynamic>;
    final revision = manifest['revision'] as String;
    final garbageBefore = List<String>.from(
      manifest['garbage'] as List<dynamic>,
    );
    expect(garbageBefore, isNotEmpty);

    // 模拟 manifest 已落盘、普通 JSON 尚未提交时进程直接退出。
    await prefs.setString(StorageKeys.siteConfigs, oldPlain);
    await prefs.setString(
      StorageKeys.pendingSensitiveCompanionV1,
      jsonEncode({'version': 1, 'revision': revision, 'siteConfigs': newPlain}),
    );
    await storage.waitForPendingSecureStorageCleanup();
    storage.resetForTest();

    await storage.initializeSecureStorage();
    expect(prefs.getString(StorageKeys.siteConfigs), newPlain);
    expect(prefs.containsKey(StorageKeys.pendingSensitiveCompanionV1), isFalse);
    await pumpEventQueue(times: 20);
    for (final oldPhysicalKey in garbageBefore) {
      expect(secureValues.containsKey(oldPhysicalKey), isFalse);
    }
    final restored = await storage.loadSiteConfigs(includeApiKeys: true);
    expect(restored.single.name, 'New Site');
    expect(restored.single.cookie, 'cookie-new');
    expect(restored.single.apiKey, 'api-new');
  });

  test('启动不等待旧密文清理且旧代失败不能污染显式重试', () async {
    const activePhysicalKey = 'active-physical-key';
    const stalePhysicalKey = 'stale-physical-key';
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      manifestKey,
      jsonEncode({
        'version': 1,
        'revision': 'revision-active',
        'entries': {StorageKeys.proxyPassword: activePhysicalKey},
        'garbage': [stalePhysicalKey],
      }),
    );
    secureValues[activePhysicalKey] = 'active-password';
    secureValues[stalePhysicalKey] = 'stale-password';
    final deleteStarted = Completer<void>();
    final releaseFirstDelete = Completer<void>();
    final retryProbeStarted = Completer<void>();
    var probeReads = 0;
    var staleDeleteAttempts = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorageChannel, (call) async {
          final arguments = call.arguments as Map<dynamic, dynamic>?;
          final key = arguments?['key'] as String?;
          switch (call.method) {
            case 'read':
              if (key == '__ptmate_secure_storage_probe__') {
                probeReads++;
                if (probeReads == 2 && !retryProbeStarted.isCompleted) {
                  retryProbeStarted.complete();
                }
              }
              return secureValues[key];
            case 'delete':
              if (key == stalePhysicalKey) {
                staleDeleteAttempts++;
                if (staleDeleteAttempts == 1) {
                  deleteStarted.complete();
                  await releaseFirstDelete.future;
                  throw PlatformException(code: 'invalid_key');
                }
              }
              secureValues.remove(key);
              return null;
            case 'write':
              secureValues[key!] = arguments!['value'] as String;
              return null;
            default:
              return null;
          }
        });

    await storage.initializeSecureStorage();
    await deleteStarted.future;
    expect(storage.secureStorageState, SecureStorageState.ready);

    final retry = storage.initializeSecureStorage(force: true);
    await retryProbeStarted.future;
    releaseFirstDelete.complete();
    await retry;
    await storage.waitForPendingSecureStorageCleanup();

    expect(storage.secureStorageState, SecureStorageState.ready);
    expect(secureValues[activePhysicalKey], 'active-password');
    expect(secureValues.containsKey(stalePhysicalKey), isFalse);
    expect(staleDeleteAttempts, 2);
  });

  test('Cookie Cloud manifest 提交后强杀会在重启补齐普通偏好', () async {
    const oldConfig = CookieCloudConfig(
      url: 'https://old.example.com',
      uuid: 'uuid-old',
      password: 'password-old',
      autoSyncEnabled: false,
      syncIntervalMinutes: 360,
      lastSyncSummary: 'old-summary',
    );
    final newSyncAt = DateTime.utc(2026, 7, 20, 12);
    final newConfig = CookieCloudConfig(
      url: 'https://new.example.com',
      uuid: 'uuid-new',
      password: 'password-new',
      autoSyncEnabled: true,
      syncIntervalMinutes: 45,
      lastSyncAt: newSyncAt,
      lastSyncSummary: 'new-summary',
    );
    await storage.saveCookieCloudConfig(oldConfig);
    await storage.saveCookieCloudConfig(newConfig);

    final prefs = await SharedPreferences.getInstance();
    final manifest =
        jsonDecode(prefs.getString(manifestKey)!) as Map<String, dynamic>;
    final revision = manifest['revision'] as String;
    final encodedPreferences = jsonEncode({
      'autoSyncEnabled': true,
      'syncIntervalMinutes': 45,
      'lastSyncAt': newSyncAt.toIso8601String(),
      'lastSyncSummary': 'new-summary',
    });

    // 模拟 manifest 已提交而普通偏好仍为旧值时强杀。
    await prefs.setBool(StorageKeys.cookieCloudAutoSyncEnabled, false);
    await prefs.setInt(StorageKeys.cookieCloudSyncIntervalMinutes, 360);
    await prefs.remove(StorageKeys.cookieCloudLastSyncAt);
    await prefs.setString(
      StorageKeys.cookieCloudLastSyncSummary,
      'old-summary',
    );
    await prefs.setString(
      StorageKeys.pendingSensitiveCompanionV1,
      jsonEncode({
        'version': 1,
        'revision': revision,
        'cookieCloudPreferences': encodedPreferences,
      }),
    );
    await storage.waitForPendingSecureStorageCleanup();
    storage.resetForTest();

    await storage.initializeSecureStorage();
    final restored = await storage.loadCookieCloudConfig();
    expect(restored.url, 'https://new.example.com');
    expect(restored.password, 'password-new');
    expect(restored.autoSyncEnabled, isTrue);
    expect(restored.syncIntervalMinutes, 45);
    expect(restored.lastSyncAt, newSyncAt);
    expect(restored.lastSyncSummary, 'new-summary');
    expect(prefs.containsKey(StorageKeys.pendingSensitiveCompanionV1), isFalse);
  });

  test('备份 manifest 提交后强杀会在重启补齐完整普通偏好快照', () async {
    const oldSnapshot = <String, dynamic>{
      'themeMode': 'light',
      'dynamicColor': false,
      'proxyHost': 'old.proxy.example.com',
      'downloaderConfigs': <Map<String, dynamic>>[],
      'defaultDownloaderId': null,
      'downloaderCategoriesCache': <String, dynamic>{
        'downloader-a': <String>['old-category'],
      },
    };
    const newSnapshot = <String, dynamic>{
      'themeMode': 'dark',
      'dynamicColor': true,
      'proxyHost': 'new.proxy.example.com',
      'downloaderConfigs': <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 'downloader-a',
          'name': 'Downloader A',
          'type': 'qbittorrent',
          'config': <String, dynamic>{
            'host': 'downloader.example.com',
            'port': 8080,
            'username': 'user',
          },
        },
      ],
      'defaultDownloaderId': 'downloader-a',
      'downloaderCategoriesCache': <String, dynamic>{
        'downloader-a': <String>['new-category'],
      },
    };
    await storage.restoreSensitiveBackupData(backupPreferences: oldSnapshot);
    final prefs = await SharedPreferences.getInstance();
    await storage.restoreSensitiveBackupData(backupPreferences: newSnapshot);
    final manifest =
        jsonDecode(prefs.getString(manifestKey)!) as Map<String, dynamic>;
    final revision = manifest['revision'] as String;

    // 模拟 manifest 已提交，但普通偏好只保留旧快照时进程退出。
    await prefs.setString(StorageKeys.themeMode, 'light');
    await prefs.setBool(StorageKeys.themeUseDynamic, false);
    await prefs.setString(StorageKeys.proxyHost, 'old.proxy.example.com');
    await prefs.setString(StorageKeys.downloaderConfigs, '[]');
    await prefs.remove(StorageKeys.defaultDownloaderId);
    await prefs.setStringList(
      StorageKeys.downloaderCategoriesKey('downloader-a'),
      const <String>['old-category'],
    );
    await prefs.setString(
      StorageKeys.pendingSensitiveCompanionV1,
      jsonEncode({
        'version': 1,
        'revision': revision,
        'backupPreferences': jsonEncode(newSnapshot),
      }),
    );
    await storage.waitForPendingSecureStorageCleanup();
    storage.resetForTest();

    await storage.initializeSecureStorage();

    expect(prefs.getString(StorageKeys.themeMode), 'dark');
    expect(prefs.getBool(StorageKeys.themeUseDynamic), isTrue);
    expect(prefs.getString(StorageKeys.proxyHost), 'new.proxy.example.com');
    expect(
      prefs.getString(StorageKeys.downloaderConfigs),
      contains('downloader-a'),
    );
    expect(prefs.getString(StorageKeys.defaultDownloaderId), 'downloader-a');
    expect(
      prefs.getStringList(StorageKeys.downloaderCategoriesKey('downloader-a')),
      const <String>['new-category'],
    );
    expect(prefs.containsKey(StorageKeys.pendingSensitiveCompanionV1), isFalse);
  });

  test('备份敏感快照暂存失败后重启只能读到完整旧版本', () async {
    await storage.restoreSensitiveBackupData(
      siteConfigs: const [
        SiteConfig(
          id: 'site-a',
          name: 'Site A',
          baseUrl: 'https://a.example.com',
          cookie: 'cookie-old',
          apiKey: 'api-old',
        ),
      ],
      cookieCloudConfig: const CookieCloudConfig(
        url: 'https://old.example.com',
        uuid: 'uuid-old',
        password: 'password-old',
      ),
      downloaderPasswords: const {'downloader-a': 'downloader-old'},
      downloaderIds: const {'downloader-a'},
      hasProxyPassword: true,
      proxyPassword: 'proxy-old',
    );
    final prefs = await SharedPreferences.getInstance();
    final oldPlainSites = prefs.getString(StorageKeys.siteConfigs);

    failWrites = true;
    writesBeforeFailure = 1;
    await expectLater(
      storage.restoreSensitiveBackupData(
        siteConfigs: const [
          SiteConfig(
            id: 'site-a',
            name: 'Site A New',
            baseUrl: 'https://a.example.com',
            cookie: 'cookie-new',
            apiKey: 'api-new',
          ),
        ],
        cookieCloudConfig: const CookieCloudConfig(
          url: 'https://new.example.com',
          uuid: 'uuid-new',
          password: 'password-new',
        ),
        downloaderPasswords: const {'downloader-a': 'downloader-new'},
        downloaderIds: const {'downloader-a'},
        hasProxyPassword: true,
        proxyPassword: 'proxy-new',
      ),
      throwsA(isA<SecureStorageUnavailableException>()),
    );
    expect(prefs.getString(StorageKeys.siteConfigs), oldPlainSites);

    failWrites = false;
    await storage.waitForPendingSecureStorageCleanup();
    storage.resetForTest();
    final sites = await storage.loadSiteConfigs(includeApiKeys: true);
    final cookieCloud = await storage.loadCookieCloudConfig();
    expect(sites.single.cookie, 'cookie-old');
    expect(sites.single.apiKey, 'api-old');
    expect(cookieCloud.password, 'password-old');
    expect(
      await storage.loadDownloaderPassword('downloader-a'),
      'downloader-old',
    );
    expect(await storage.loadProxyPassword(), 'proxy-old');
  });

  test('companion 暂存提交返回 false 时不切换 manifest', () async {
    const oldConfig = SiteConfig(
      id: 'site-a',
      name: 'Old Site',
      baseUrl: 'https://a.example.com',
      cookie: 'cookie-old',
      apiKey: 'api-old',
    );
    const newConfig = SiteConfig(
      id: 'site-a',
      name: 'New Site',
      baseUrl: 'https://a.example.com',
      cookie: 'cookie-new',
      apiKey: 'api-new',
    );
    await storage.saveSiteConfigs(const [oldConfig]);
    await storage.waitForPendingSecureStorageCleanup();
    final prefs = await SharedPreferences.getInstance();
    final oldManifest = prefs.getString(manifestKey);
    final oldPlainSites = prefs.getString(StorageKeys.siteConfigs);
    storage.overridePreferenceMutationResultForTest((failureCode, committed) {
      if (failureCode == 'companion_preferences_preparation_failed') {
        return false;
      }
      return committed;
    });

    await expectLater(
      storage.saveSiteConfigs(const [newConfig]),
      throwsA(
        isA<SecureStorageUnavailableException>().having(
          (error) => error.code,
          'code',
          'companion_preferences_preparation_failed',
        ),
      ),
    );

    expect(prefs.getString(manifestKey), oldManifest);
    expect(prefs.getString(StorageKeys.siteConfigs), oldPlainSites);
    expect(prefs.containsKey(StorageKeys.pendingSensitiveCompanionV1), isTrue);
    expect(storage.secureStorageState, SecureStorageState.unavailable);
  });

  test('manifest 切换后普通偏好提交返回 false 时保留 pending 供重启恢复', () async {
    const oldConfig = SiteConfig(
      id: 'site-a',
      name: 'Old Site',
      baseUrl: 'https://a.example.com',
      cookie: 'cookie-old',
      apiKey: 'api-old',
    );
    const newConfig = SiteConfig(
      id: 'site-a',
      name: 'New Site',
      baseUrl: 'https://a.example.com',
      cookie: 'cookie-new',
      apiKey: 'api-new',
    );
    await storage.saveSiteConfigs(const [oldConfig]);
    await storage.waitForPendingSecureStorageCleanup();
    final prefs = await SharedPreferences.getInstance();
    final oldManifest = prefs.getString(manifestKey);
    final oldPlainSites = prefs.getString(StorageKeys.siteConfigs)!;
    storage.overridePreferenceMutationResultForTest((failureCode, committed) {
      if (failureCode == 'plain_site_config_commit_failed') return false;
      return committed;
    });

    await expectLater(
      storage.saveSiteConfigs(const [newConfig]),
      throwsA(
        isA<SecureStorageUnavailableException>().having(
          (error) => error.code,
          'code',
          'plain_site_config_commit_failed',
        ),
      ),
    );

    expect(prefs.getString(manifestKey), isNot(oldManifest));
    expect(prefs.containsKey(StorageKeys.pendingSensitiveCompanionV1), isTrue);
    expect(storage.secureStorageState, SecureStorageState.unavailable);

    // 模拟底层返回 false 时：manifest 与 pending 已落盘，但普通 JSON 仍是旧值。
    await prefs.setString(StorageKeys.siteConfigs, oldPlainSites);
    storage.resetForTest();
    await storage.initializeSecureStorage();

    final recovered = await storage.loadSiteConfigs(includeApiKeys: true);
    expect(recovered.single.name, 'New Site');
    expect(recovered.single.cookie, 'cookie-new');
    expect(recovered.single.apiKey, 'api-new');
    expect(prefs.containsKey(StorageKeys.pendingSensitiveCompanionV1), isFalse);
    expect(storage.secureStorageState, SecureStorageState.ready);
  });

  test('fallback 删除提交返回 false 时锁定并保留已提交的新密文', () async {
    const downloaderId = 'fallback-remove-false';
    final fallbackKey = StorageKeys.downloaderPasswordFallbackKey(downloaderId);
    await storage.saveProxyPassword('proxy-password');
    await storage.waitForPendingSecureStorageCleanup();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(fallbackKey, 'fallback-password');
    storage.overridePreferenceMutationResultForTest((failureCode, committed) {
      if (failureCode == 'fallback_cleanup_failed') return false;
      return committed;
    });

    await expectLater(
      storage.loadDownloaderPassword(downloaderId),
      throwsA(
        isA<SecureStorageUnavailableException>().having(
          (error) => error.code,
          'code',
          'fallback_cleanup_failed',
        ),
      ),
    );
    expect(storage.secureStorageState, SecureStorageState.unavailable);

    // 模拟删除未落盘；重启后读取相同密文并再次安全清理 fallback。
    await prefs.setString(fallbackKey, 'fallback-password');
    storage.resetForTest();
    expect(
      await storage.loadDownloaderPassword(downloaderId),
      'fallback-password',
    );
    expect(prefs.containsKey(fallbackKey), isFalse);
    expect(storage.secureStorageState, SecureStorageState.ready);
  });

  test('companion 已暂存但 manifest 未切换时丢弃 pending 并保留旧偏好', () async {
    const activePhysicalKey = 'active-proxy-password';
    const oldManifest = <String, dynamic>{
      'version': 1,
      'revision': 'revision-old',
      'entries': <String, dynamic>{
        StorageKeys.proxyPassword: activePhysicalKey,
      },
      'garbage': <String>[],
    };
    const pendingSnapshot = <String, dynamic>{
      'themeMode': 'dark',
      'dynamicColor': true,
    };
    final prefs = await SharedPreferences.getInstance();
    final encodedOldManifest = jsonEncode(oldManifest);
    await prefs.setString(manifestKey, encodedOldManifest);
    await prefs.setString(StorageKeys.themeMode, 'light');
    await prefs.setBool(StorageKeys.themeUseDynamic, false);
    await prefs.setString(
      StorageKeys.pendingSensitiveCompanionV1,
      jsonEncode({
        'version': 1,
        'revision': 'revision-not-committed',
        'backupPreferences': jsonEncode(pendingSnapshot),
      }),
    );
    secureValues[activePhysicalKey] = 'proxy-old';

    await storage.waitForPendingSecureStorageCleanup();
    storage.resetForTest();
    await storage.initializeSecureStorage();

    expect(prefs.getString(manifestKey), encodedOldManifest);
    expect(await storage.loadProxyPassword(), 'proxy-old');
    expect(prefs.getString(StorageKeys.themeMode), 'light');
    expect(prefs.getBool(StorageKeys.themeUseDynamic), isFalse);
    expect(prefs.containsKey(StorageKeys.pendingSensitiveCompanionV1), isFalse);
  });

  test('manifest 已切换但普通偏好仅部分写入时重启重放完整新版', () async {
    const oldSnapshot = <String, dynamic>{
      'themeMode': 'light',
      'dynamicColor': false,
      'autoLoadImages': false,
      'proxyHost': 'old.proxy.example.com',
      'proxyPort': 8080,
      'defaultDownloadTags': <String>['old-tag'],
    };
    const newSnapshot = <String, dynamic>{
      'themeMode': 'dark',
      'dynamicColor': true,
      'autoLoadImages': true,
      'proxyHost': 'new.proxy.example.com',
      'proxyPort': 8443,
      'defaultDownloadTags': <String>['new-tag-a', 'new-tag-b'],
    };
    await storage.restoreSensitiveBackupData(backupPreferences: oldSnapshot);
    final prefs = await SharedPreferences.getInstance();
    await storage.restoreSensitiveBackupData(backupPreferences: newSnapshot);
    final manifest =
        jsonDecode(prefs.getString(manifestKey)!) as Map<String, dynamic>;
    final revision = manifest['revision'] as String;

    // 模拟逐项提交普通偏好时，前半已是新值，后半仍是旧值就强杀。
    expect(prefs.getString(StorageKeys.themeMode), 'dark');
    expect(prefs.getBool(StorageKeys.autoLoadImages), isTrue);
    expect(prefs.getString(StorageKeys.proxyHost), 'new.proxy.example.com');
    await prefs.setBool(StorageKeys.themeUseDynamic, false);
    await prefs.setInt(StorageKeys.proxyPort, 8080);
    await prefs.setStringList(StorageKeys.defaultDownloadTags, const <String>[
      'old-tag',
    ]);
    await prefs.setString(
      StorageKeys.pendingSensitiveCompanionV1,
      jsonEncode({
        'version': 1,
        'revision': revision,
        'backupPreferences': jsonEncode(newSnapshot),
      }),
    );

    await storage.waitForPendingSecureStorageCleanup();
    storage.resetForTest();
    await storage.initializeSecureStorage();

    expect(prefs.getString(StorageKeys.themeMode), 'dark');
    expect(prefs.getBool(StorageKeys.themeUseDynamic), isTrue);
    expect(prefs.getBool(StorageKeys.autoLoadImages), isTrue);
    expect(prefs.getString(StorageKeys.proxyHost), 'new.proxy.example.com');
    expect(prefs.getInt(StorageKeys.proxyPort), 8443);
    expect(prefs.getStringList(StorageKeys.defaultDownloadTags), const <String>[
      'new-tag-a',
      'new-tag-b',
    ]);
    expect(prefs.containsKey(StorageKeys.pendingSensitiveCompanionV1), isFalse);
  });

  test('普通偏好已完整但 pending ack 尚存时重启幂等确认并移除', () async {
    const snapshot = <String, dynamic>{
      'themeMode': 'dark',
      'dynamicColor': true,
      'proxyHost': 'new.proxy.example.com',
      'proxyPort': 8443,
    };
    await storage.restoreSensitiveBackupData(backupPreferences: snapshot);
    final prefs = await SharedPreferences.getInstance();
    final encodedManifest = prefs.getString(manifestKey)!;
    final manifest = jsonDecode(encodedManifest) as Map<String, dynamic>;
    final revision = manifest['revision'] as String;
    expect(prefs.getString(StorageKeys.themeMode), 'dark');
    expect(prefs.getBool(StorageKeys.themeUseDynamic), isTrue);
    expect(prefs.getString(StorageKeys.proxyHost), 'new.proxy.example.com');
    expect(prefs.getInt(StorageKeys.proxyPort), 8443);

    // 模拟全部普通偏好已写完，但删除 pending ack 前进程退出。
    await prefs.setString(
      StorageKeys.pendingSensitiveCompanionV1,
      jsonEncode({
        'version': 1,
        'revision': revision,
        'backupPreferences': jsonEncode(snapshot),
      }),
    );

    await storage.waitForPendingSecureStorageCleanup();
    storage.resetForTest();
    await storage.initializeSecureStorage();

    expect(prefs.getString(manifestKey), encodedManifest);
    expect(prefs.getString(StorageKeys.themeMode), 'dark');
    expect(prefs.getBool(StorageKeys.themeUseDynamic), isTrue);
    expect(prefs.getString(StorageKeys.proxyHost), 'new.proxy.example.com');
    expect(prefs.getInt(StorageKeys.proxyPort), 8443);
    expect(prefs.containsKey(StorageKeys.pendingSensitiveCompanionV1), isFalse);
  });

  test('已有 manifest 时即使构建开关关闭也继续事务写入', () async {
    await storage.saveProxyPassword('proxy-old');
    final prefs = await SharedPreferences.getInstance();
    final oldManifest = prefs.getString(manifestKey)!;

    await storage.waitForPendingSecureStorageCleanup();
    storage.resetForTest();
    storage.overrideSecureStorageTransactionsForTest(false);
    await storage.saveProxyPassword('proxy-new');

    final newManifest = prefs.getString(manifestKey)!;
    expect(newManifest, isNot(oldManifest));
    final decoded = jsonDecode(newManifest) as Map<String, dynamic>;
    final entries = decoded['entries'] as Map<String, dynamic>;
    final physicalKey = entries[StorageKeys.proxyPassword] as String;
    expect(physicalKey, startsWith('secureStorage.sensitiveRevision.v1.'));
    expect(secureValues[physicalKey], 'proxy-new');
    expect(secureValues.containsKey(StorageKeys.proxyPassword), isFalse);
    expect(await storage.loadProxyPassword(), 'proxy-new');
  });

  test('批量清空站点先移除全部敏感映射再提交空列表', () async {
    await storage.saveSiteConfigs(const [
      SiteConfig(
        id: 'site-to-clear',
        name: 'Site To Clear',
        baseUrl: 'https://clear.example.com',
        cookie: 'cookie-to-clear',
        apiKey: 'api-to-clear',
      ),
    ]);
    await storage.saveSiteConfigs(const <SiteConfig>[]);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(StorageKeys.siteConfigs), '[]');
    final manifest =
        jsonDecode(prefs.getString(manifestKey)!) as Map<String, dynamic>;
    final entries = manifest['entries'] as Map<String, dynamic>;
    expect(
      entries.keys.where(
        (key) =>
            key.startsWith('site.cookie.') || key.startsWith('site.apiKey.'),
      ),
      isEmpty,
    );

    await storage.waitForPendingSecureStorageCleanup();
    storage.resetForTest();
    await storage.initializeSecureStorage();
    expect(await storage.loadSiteConfigs(includeApiKeys: true), isEmpty);
    expect(storage.secureStorageState, SecureStorageState.ready);
  });

  test('事务删除提交后强杀不会由未标记 fallback 复活下载器密码', () async {
    const downloaderId = 'delete-transaction-tombstone';
    final fallbackKey = StorageKeys.downloaderPasswordFallbackKey(downloaderId);
    await storage.saveDownloaderPassword(downloaderId, 'secure-password');
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(fallbackKey, 'plaintext-password');
    expect(await storage.hasSecureStorageFallbackConflict(), isFalse);

    final cleanupEntered = Completer<void>();
    final releaseCleanup = Completer<void>();
    storage.overrideBeforeSensitiveFallbackCleanupForTest((key) async {
      if (key != fallbackKey || cleanupEntered.isCompleted) return;
      cleanupEntered.complete();
      await releaseCleanup.future;
    });
    final deletion = storage.deleteDownloaderPassword(downloaderId);
    await cleanupEntered.future;

    // 删除 guard 在 manifest 切换前落盘；模拟强杀后重新启动。
    expect(await storage.hasSecureStorageFallbackConflict(), isTrue);
    storage.resetForTest();
    await storage.initializeSecureStorage();
    expect(await storage.loadDownloaderPassword(downloaderId), isNull);
    expect(prefs.getString(fallbackKey), 'plaintext-password');
    expect(await storage.hasSecureStorageFallbackConflict(), isTrue);

    releaseCleanup.complete();
    await expectLater(
      deletion,
      throwsA(
        isA<SecureStorageUnavailableException>().having(
          (error) => error.code,
          'code',
          'secure_storage_operation_invalidated',
        ),
      ),
    );
  });

  test('阶段一 direct 删除提交后强杀不会由 fallback 复活密码', () async {
    const downloaderId = 'delete-direct-tombstone';
    final fallbackKey = StorageKeys.downloaderPasswordFallbackKey(downloaderId);
    storage.overrideSecureStorageTransactionsForTest(false);
    await storage.saveDownloaderPassword(downloaderId, 'secure-password');
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(fallbackKey, 'plaintext-password');

    final cleanupEntered = Completer<void>();
    final releaseCleanup = Completer<void>();
    storage.overrideBeforeSensitiveFallbackCleanupForTest((key) async {
      if (key != fallbackKey || cleanupEntered.isCompleted) return;
      cleanupEntered.complete();
      await releaseCleanup.future;
    });
    final deletion = storage.deleteDownloaderPassword(downloaderId);
    await cleanupEntered.future;

    storage.resetForTest();
    storage.overrideSecureStorageTransactionsForTest(false);
    await storage.initializeSecureStorage();
    expect(await storage.loadDownloaderPassword(downloaderId), isNull);
    expect(prefs.getString(fallbackKey), 'plaintext-password');
    expect(await storage.hasSecureStorageFallbackConflict(), isTrue);

    releaseCleanup.complete();
    await expectLater(
      deletion,
      throwsA(
        isA<SecureStorageUnavailableException>().having(
          (error) => error.code,
          'code',
          'secure_storage_operation_invalidated',
        ),
      ),
    );
  });

  test('Device ID raw delete 提交后强杀不会由 fallback 复活', () async {
    await storage.saveDeviceId('secure-device-id');
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(StorageKeys.deviceIdFallback, 'plaintext-device-id');

    final cleanupEntered = Completer<void>();
    final releaseCleanup = Completer<void>();
    storage.overrideBeforeSensitiveFallbackCleanupForTest((key) async {
      if (key != StorageKeys.deviceIdFallback || cleanupEntered.isCompleted) {
        return;
      }
      cleanupEntered.complete();
      await releaseCleanup.future;
    });
    final deletion = storage.deleteDeviceId();
    await cleanupEntered.future;

    storage.resetForTest();
    await storage.initializeSecureStorage();
    expect(await storage.loadDeviceId(), isNull);
    expect(
      prefs.getString(StorageKeys.deviceIdFallback),
      'plaintext-device-id',
    );
    expect(await storage.hasSecureStorageFallbackConflict(), isTrue);

    releaseCleanup.complete();
    await expectLater(
      deletion,
      throwsA(
        isA<SecureStorageUnavailableException>().having(
          (error) => error.code,
          'code',
          'secure_storage_operation_invalidated',
        ),
      ),
    );
  });

  test('删除下载器会先清理旧 qB 来源，重启迁移不得复活目标密码', () async {
    const downloaderId = 'delete-legacy-qb-before-target';
    final targetFallback = StorageKeys.downloaderPasswordFallbackKey(
      downloaderId,
    );
    final legacySecure = StorageKeys.legacyQbPasswordKey(downloaderId);
    await storage.saveDownloaderPassword(downloaderId, 'target-password');
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(targetFallback, 'target-plaintext');
    secureValues[legacySecure] = 'legacy-qb-password';
    await prefs.setString(
      StorageKeys.legacyQbClientConfigs,
      jsonEncode(<Map<String, Object>>[
        <String, Object>{
          'id': downloaderId,
          'name': 'Legacy qB',
          'host': 'https://qb.example.com',
          'port': 8080,
        },
      ]),
    );
    await prefs.setString(StorageKeys.appVersion, '1.0.0');

    final cleanupEntered = Completer<void>();
    final releaseCleanup = Completer<void>();
    storage.overrideBeforeSensitiveFallbackCleanupForTest((key) async {
      if (key != targetFallback || cleanupEntered.isCompleted) return;
      cleanupEntered.complete();
      await releaseCleanup.future;
    });
    final deletion = storage.deleteDownloaderPassword(downloaderId);
    await cleanupEntered.future;
    expect(secureValues.containsKey(legacySecure), isFalse);

    storage.resetForTest();
    await storage.initializeSecureStorage();
    await storage.checkAndMigrate();
    expect(await storage.loadDownloaderPassword(downloaderId), isNull);

    releaseCleanup.complete();
    await expectLater(
      deletion,
      throwsA(
        isA<SecureStorageUnavailableException>().having(
          (error) => error.code,
          'code',
          'secure_storage_operation_invalidated',
        ),
      ),
    );
  });

  test('保存空下载器密码会先清理旧 qB 来源，强杀后不得复活', () async {
    const downloaderId = 'clear-legacy-qb-before-target';
    final targetFallback = StorageKeys.downloaderPasswordFallbackKey(
      downloaderId,
    );
    final legacySecure = StorageKeys.legacyQbPasswordKey(downloaderId);
    await storage.saveDownloaderPassword(downloaderId, 'target-password');
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(targetFallback, 'target-plaintext');
    secureValues[legacySecure] = 'legacy-qb-password';
    await prefs.setString(
      StorageKeys.legacyQbClientConfigs,
      jsonEncode(<Map<String, Object>>[
        <String, Object>{
          'id': downloaderId,
          'name': 'Legacy qB',
          'host': 'https://qb.example.com',
          'port': 8080,
        },
      ]),
    );
    await prefs.setString(StorageKeys.appVersion, '1.0.0');

    final cleanupEntered = Completer<void>();
    final releaseCleanup = Completer<void>();
    storage.overrideBeforeSensitiveFallbackCleanupForTest((key) async {
      if (key != targetFallback || cleanupEntered.isCompleted) return;
      cleanupEntered.complete();
      await releaseCleanup.future;
    });
    final clear = storage.saveDownloaderPassword(downloaderId, '');
    await cleanupEntered.future;
    expect(secureValues.containsKey(legacySecure), isFalse);

    storage.resetForTest();
    await storage.initializeSecureStorage();
    await storage.checkAndMigrate();
    expect(await storage.loadDownloaderPassword(downloaderId), isNull);

    releaseCleanup.complete();
    await expectLater(
      clear,
      throwsA(
        isA<SecureStorageUnavailableException>().having(
          (error) => error.code,
          'code',
          'secure_storage_operation_invalidated',
        ),
      ),
    );
  });

  test('备份恢复清空下载器密码会先清理旧 qB 来源，强杀后不得复活', () async {
    const downloaderId = 'restore-clear-legacy-qb-before-target';
    final targetFallback = StorageKeys.downloaderPasswordFallbackKey(
      downloaderId,
    );
    final legacySecure = StorageKeys.legacyQbPasswordKey(downloaderId);
    await storage.saveDownloaderPassword(downloaderId, 'target-password');
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(targetFallback, 'target-plaintext');
    secureValues[legacySecure] = 'legacy-qb-password';
    await prefs.setString(
      StorageKeys.legacyQbClientConfigs,
      jsonEncode(<Map<String, Object>>[
        <String, Object>{
          'id': downloaderId,
          'name': 'Legacy qB',
          'host': 'https://qb.example.com',
          'port': 8080,
        },
      ]),
    );
    await prefs.setString(StorageKeys.appVersion, '1.0.0');

    final cleanupEntered = Completer<void>();
    final releaseCleanup = Completer<void>();
    storage.overrideBeforeSensitiveFallbackCleanupForTest((key) async {
      if (key != targetFallback || cleanupEntered.isCompleted) return;
      cleanupEntered.complete();
      await releaseCleanup.future;
    });
    final restore = storage.restoreSensitiveBackupData(
      downloaderIds: const <String>{downloaderId},
      downloaderPasswords: const <String, String>{downloaderId: ''},
    );
    await cleanupEntered.future;
    expect(secureValues.containsKey(legacySecure), isFalse);

    storage.resetForTest();
    await storage.initializeSecureStorage();
    await storage.checkAndMigrate();
    expect(await storage.loadDownloaderPassword(downloaderId), isNull);

    releaseCleanup.complete();
    await expectLater(
      restore,
      throwsA(
        isA<SecureStorageUnavailableException>().having(
          (error) => error.code,
          'code',
          'secure_storage_operation_invalidated',
        ),
      ),
    );
  });

  test('Device ID fallback 迁移与删除串行，不能在删除后复活', () async {
    await storage.initializeSecureStorage();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(StorageKeys.deviceIdFallback, 'legacy-device-id');

    final migrationWriteStarted = Completer<void>();
    final releaseMigrationWrite = Completer<void>();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorageChannel, (call) async {
          final arguments = call.arguments as Map<dynamic, dynamic>?;
          if (call.method == 'write' &&
              arguments?['key'] == StorageKeys.deviceId &&
              !migrationWriteStarted.isCompleted) {
            migrationWriteStarted.complete();
            await releaseMigrationWrite.future;
          }
          return statefulHandler(call);
        });

    final migration = storage.loadDeviceId();
    await migrationWriteStarted.future;
    var deletionCompleted = false;
    final deletion = storage.deleteDeviceId().whenComplete(
      () => deletionCompleted = true,
    );
    await Future<void>.delayed(Duration.zero);
    expect(deletionCompleted, isFalse);

    releaseMigrationWrite.complete();
    expect(await migration, 'legacy-device-id');
    await deletion;
    expect(await storage.loadDeviceId(), isNull);
    expect(prefs.containsKey(StorageKeys.deviceIdFallback), isFalse);
  });

  test('并发 fallback 清理不会覆盖另一删除操作的持久化 guard', () async {
    const firstId = 'fallback-metadata-first';
    const secondId = 'fallback-metadata-second';
    final firstFallback = StorageKeys.downloaderPasswordFallbackKey(firstId);
    final secondFallback = StorageKeys.downloaderPasswordFallbackKey(secondId);
    await storage.saveDownloaderPassword(firstId, 'first-secure');
    await storage.saveDownloaderPassword(secondId, 'second-secure');
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(firstFallback, 'first-plaintext');
    await prefs.setString(secondFallback, 'second-plaintext');

    final firstMetadataRead = Completer<void>();
    final releaseFirstMetadataRead = Completer<void>();
    final secondCleanupEntered = Completer<void>();
    final releaseSecondCleanup = Completer<void>();
    storage.overrideAfterSensitiveFallbackCleanupMetadataReadForTest((
      fallbackKey,
    ) async {
      if (fallbackKey != firstFallback || firstMetadataRead.isCompleted) {
        return;
      }
      firstMetadataRead.complete();
      await releaseFirstMetadataRead.future;
    });
    storage.overrideBeforeSensitiveFallbackCleanupForTest((fallbackKey) async {
      if (fallbackKey != secondFallback || secondCleanupEntered.isCompleted) {
        return;
      }
      secondCleanupEntered.complete();
      await releaseSecondCleanup.future;
    });

    final firstDeletion = storage.deleteDownloaderPassword(firstId);
    await firstMetadataRead.future;
    final secondDeletion = storage.deleteDownloaderPassword(secondId);
    await Future<void>.delayed(Duration.zero);
    expect(
      prefs.getStringList(StorageKeys.secureFallbackConflictsV1),
      contains(firstFallback),
    );
    expect(
      prefs.getStringList(StorageKeys.secureFallbackConflictsV1),
      isNot(contains(secondFallback)),
    );

    releaseFirstMetadataRead.complete();
    await firstDeletion;
    await secondCleanupEntered.future;
    expect(
      prefs.getStringList(StorageKeys.secureFallbackConflictsV1),
      contains(secondFallback),
    );

    storage.resetForTest();
    await storage.initializeSecureStorage();
    expect(await storage.loadDownloaderPassword(secondId), isNull);

    releaseSecondCleanup.complete();
    await expectLater(
      secondDeletion,
      throwsA(
        isA<SecureStorageUnavailableException>().having(
          (error) => error.code,
          'code',
          'secure_storage_operation_invalidated',
        ),
      ),
    );
  });

  test('删除 manifest 已提交但冲突 fallback 未清理时不会复活旧秘密', () async {
    const downloaderId = 'delete-interrupted';
    final logicalKey = StorageKeys.downloaderPasswordKey(downloaderId);
    final fallbackKey = StorageKeys.downloaderPasswordFallbackKey(downloaderId);
    await storage.saveDownloaderPassword(downloaderId, 'secure-current');
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(fallbackKey, 'plaintext-stale');
    expect(
      await storage.loadDownloaderPassword(downloaderId),
      'secure-current',
    );
    expect(await storage.hasSecureStorageFallbackConflict(), isTrue);

    final transaction = SecureStorageTransaction(
      preferences: prefs,
      readSecureValue: (key) async => secureValues[key],
      writeSecureValue: (key, value) async => secureValues[key] = value,
      deleteSecureValue: (key) async => secureValues.remove(key),
      manifestPreferenceKey: manifestKey,
      physicalKeyPrefix: 'secureStorage.sensitiveRevision.v1',
      createRevisionId: () => 'delete-committed',
    );
    await transaction.commit([SecureStorageMutation.delete(logicalKey)]);

    await storage.waitForPendingSecureStorageCleanup();
    storage.resetForTest();
    await storage.initializeSecureStorage();
    expect(await storage.loadDownloaderPassword(downloaderId), isNull);
    expect(prefs.getString(fallbackKey), 'plaintext-stale');
    expect(await storage.hasSecureStorageFallbackConflict(), isTrue);
    final manifest =
        jsonDecode(prefs.getString(manifestKey)!) as Map<String, dynamic>;
    expect(
      (manifest['entries'] as Map<String, dynamic>).containsKey(logicalKey),
      isFalse,
    );
  });
}
