import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pt_mate/services/storage/storage_service.dart';
import 'package:pt_mate/models/app_models.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const MethodChannel channel = MethodChannel(
    'plugins.it_nomads.com/flutter_secure_storage',
  );
  late StorageService service;
  late Map<String, String> secureValues;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    service = StorageService.instance;
    service.resetForTest();
    secureValues = <String, String>{};

    // Mock FlutterSecureStorage
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
          final arguments = methodCall.arguments as Map<dynamic, dynamic>?;
          final key = arguments?['key'] as String?;
          switch (methodCall.method) {
            case 'write':
              secureValues[key!] = arguments!['value'] as String;
              return null;
            case 'read':
              return secureValues[key];
            case 'delete':
              secureValues.remove(key);
              return null;
            case 'readAll':
              return Map<String, String>.from(secureValues);
            default:
              return null;
          }
        });
  });

  tearDown(() async {
    await service.waitForPendingSecureStorageCleanup();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('StorageService caching optimization test (Add, Update, Delete)', () async {
    // 1. Initial load (should be empty)
    var configs = await service.loadSiteConfigs();
    expect(configs, isEmpty);

    // --- ADD TEST ---
    final newConfig = SiteConfig(
      id: 'test-site-1',
      name: 'Test Site',
      baseUrl: 'https://test.com',
      apiKey: 'test-key',
    );

    await service.addSiteConfig(newConfig);

    // Get the cache after add
    final cacheAfterAdd = service.siteConfigsCache;
    expect(cacheAfterAdd, isNotNull);
    expect(cacheAfterAdd!.length, 1);
    expect(cacheAfterAdd.first.id, 'test-site-1');

    // Load site configs again
    final loadedConfigsAfterAdd = await service.loadSiteConfigs();
    // Verify instance identity (no re-decoding)
    expect(loadedConfigsAfterAdd.first, same(cacheAfterAdd.first));

    // --- UPDATE TEST ---
    final updatedConfig = newConfig.copyWith(name: 'Updated Test Site');
    await service.updateSiteConfig(updatedConfig);

    final cacheAfterUpdate = service.siteConfigsCache;
    expect(cacheAfterUpdate, isNotNull);
    expect(cacheAfterUpdate!.length, 1);
    expect(cacheAfterUpdate.first.name, 'Updated Test Site');

    // Ensure the cache object is updated in place or replaced in list, but importantly,
    // loadSiteConfigs should return the *current* cache content without re-decoding from disk.
    final loadedConfigsAfterUpdate = await service.loadSiteConfigs();
    expect(loadedConfigsAfterUpdate.first.name, 'Updated Test Site');
    // Verify instance identity with the cache
    expect(loadedConfigsAfterUpdate.first, same(cacheAfterUpdate.first));

    // --- DELETE TEST ---
    await service.deleteSiteConfig('test-site-1');

    final cacheAfterDelete = service.siteConfigsCache;
    expect(cacheAfterDelete, isNotNull);
    expect(cacheAfterDelete!.isEmpty, isTrue);

    final loadedConfigsAfterDelete = await service.loadSiteConfigs();
    expect(loadedConfigsAfterDelete, isEmpty);
    // Since list is empty, identity check on elements is N/A, but we can check if the list itself
    // or the underlying mechanism didn't trigger a reload.
    // Ideally we'd check logs or mock verify, but given the previous tests passed,
    // ensuring correctness (empty list) is sufficient here.
  });

  test('模板升级的 includeApiKeys 读取不会在站点队列内自锁', () async {
    const legacy = SiteConfig(
      id: 'legacy-mteam',
      name: 'Legacy M-Team',
      baseUrl: 'https://kp.m-team.cc/',
      apiKey: null,
      templateId: 'mteam-api',
    );
    SharedPreferences.setMockInitialValues({
      StorageKeys.siteConfigs: jsonEncode([legacy.toJson()]),
    });
    service.resetForTest();
    secureValues[StorageKeys.siteApiKey(legacy.id)] = 'api-value';

    final loaded = await service
        .loadSiteConfigs(includeApiKeys: true)
        .timeout(const Duration(seconds: 3));

    expect(loaded, hasLength(1));
    expect(loaded.single.templateId, 'mteam');
    expect(loaded.single.apiKey, 'api-value');
  });

  test(
    'Linux keyring failure should disable further secure reads for current run',
    () async {
      service.overridePlatformForTest(TargetPlatform.linux);
      var secureReadCalls = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
            if (methodCall.method == 'read') {
              secureReadCalls++;
              throw PlatformException(
                code: 'libsecret_error',
                message: 'Failed to unlock the keyring',
              );
            }
            return null;
          });

      await service.saveSiteConfigs([
        const SiteConfig(
          id: 'site-a',
          name: 'Site A',
          baseUrl: 'https://a.example.com',
        ),
        const SiteConfig(
          id: 'site-b',
          name: 'Site B',
          baseUrl: 'https://b.example.com',
        ),
      ]);

      final configs = await service.loadSiteConfigs(includeApiKeys: true);
      expect(configs, hasLength(2));
      expect(service.isSecureStorageBypassedForCurrentRun, isTrue);
      expect(secureReadCalls, 1);

      await service.loadDownloaderPassword('downloader-1');
      expect(secureReadCalls, 1);
    },
  );

  test(
    'Linux keyring failure should fallback to plaintext writes after first error',
    () async {
      service.overridePlatformForTest(TargetPlatform.linux);
      var secureWriteCalls = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
            if (methodCall.method == 'write') {
              secureWriteCalls++;
              throw PlatformException(
                code: 'libsecret_error',
                message: 'Failed to unlock the keyring',
              );
            }
            return null;
          });

      await service.saveDownloaderPassword('downloader-1', 'password-1');
      expect(service.isSecureStorageBypassedForCurrentRun, isTrue);
      expect(secureWriteCalls, 1);

      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getString(
          StorageKeys.downloaderPasswordFallbackKey('downloader-1'),
        ),
        'password-1',
      );

      await service.saveDownloaderPassword('downloader-2', 'password-2');
      expect(secureWriteCalls, 1);
      expect(
        prefs.getString(
          StorageKeys.downloaderPasswordFallbackKey('downloader-2'),
        ),
        'password-2',
      );
    },
  );

  test('mergeHealthStatuses should keep newer updatedAt', () async {
    final older = DateTime(2026, 1, 1, 0, 0, 0);
    final newer = DateTime(2026, 1, 1, 1, 0, 0);

    await service.mergeHealthStatuses({
      'site-a': HealthStatus(
        ok: true,
        message: 'new',
        updatedAt: newer,
      ).toJson(),
    });

    await service.mergeHealthStatuses({
      'site-a': HealthStatus(
        ok: false,
        message: 'old',
        updatedAt: older,
      ).toJson(),
    });

    final statuses = await service.loadHealthStatuses();
    expect(statuses['site-a'], isNotNull);
    expect(statuses['site-a']!['message'], 'new');
    expect(statuses['site-a']!['ok'], true);
  });

  test(
    'download mode preference defaults to downloader and persists',
    () async {
      expect(await service.loadDefaultDownloadToLocal(), isFalse);

      await service.saveDefaultDownloadToLocal(true);
      expect(await service.loadDefaultDownloadToLocal(), isTrue);

      await service.saveDefaultDownloadToLocal(false);
      expect(await service.loadDefaultDownloadToLocal(), isFalse);
    },
  );
}
