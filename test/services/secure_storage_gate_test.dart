import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pt_mate/models/app_models.dart';
import 'package:pt_mate/services/backup_service.dart';
import 'package:pt_mate/services/network/cookie_cloud_auto_sync_service.dart';
import 'package:pt_mate/services/site_health_refresh_service.dart';
import 'package:pt_mate/services/storage/storage_service.dart';
import 'package:pt_mate/services/webdav_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const secureStorageChannel = MethodChannel(
    'plugins.it_nomads.com/flutter_secure_storage',
  );
  final storage = StorageService.instance;
  var secureReadCount = 0;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    storage.resetForTest();
    storage.overridePlatformForTest(TargetPlatform.iOS);
    secureReadCount = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorageChannel, (call) async {
          if (call.method == 'read') {
            secureReadCount++;
            throw PlatformException(code: 'invalid_key');
          }
          return null;
        });
  });

  tearDown(() async {
    await storage.waitForPendingSecureStorageCleanup();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorageChannel, null);
    storage.resetForTest();
  });

  test('backup creation stops before collecting any data', () async {
    await expectLater(
      BackupService(storage).createBackup(),
      throwsA(isA<SecureStorageUnavailableException>()),
    );

    expect(secureReadCount, 1);
  });

  test('WebDAV upload stops before creating a client', () async {
    await expectLater(
      WebDAVService.instance.uploadBackup('{}'),
      throwsA(isA<SecureStorageUnavailableException>()),
    );

    expect(secureReadCount, 1);
  });

  test(
    'WebDAV listing does not turn secure storage failure into empty data',
    () async {
      await WebDAVService.instance.saveConfig(
        const WebDAVConfig(
          id: 'test-webdav',
          name: 'Test WebDAV',
          serverUrl: 'https://example.invalid/dav',
          username: 'tester',
          isEnabled: true,
        ),
      );

      await expectLater(
        WebDAVService.instance.getRemoteBackups(),
        throwsA(isA<SecureStorageUnavailableException>()),
      );

      expect(secureReadCount, 1);
    },
  );

  test('automatic Cookie Cloud sync silently pauses', () async {
    await CookieCloudAutoSyncService.instance.syncIfNeeded(force: true);

    expect(storage.canAccessSensitiveStorage, isFalse);
    expect(secureReadCount, 1);
  });

  test('automatic site health refresh does not persist a check time', () async {
    final result = await SiteHealthRefreshService.instance.refreshIfNeeded();

    expect(result, isNull);
    expect(await storage.loadLastSiteHealthRefreshCheck(), isNull);
    expect(secureReadCount, 1);
  });
}
