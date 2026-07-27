import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pt_mate/app.dart';
import 'package:pt_mate/services/storage/storage_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const secureStorageChannel = MethodChannel(
    'plugins.it_nomads.com/flutter_secure_storage',
  );
  final storage = StorageService.instance;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    storage.resetForTest();
    storage.overridePlatformForTest(TargetPlatform.iOS);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorageChannel, (call) async => null);
    await storage.initializeSecureStorage();
  });

  tearDown(() async {
    await storage.waitForPendingSecureStorageCleanup();
    storage.resetForTest();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorageChannel, null);
  });

  test(
    'WebDAV restore completes before startup Cookie Cloud sync begins',
    () async {
      final state = AppState();
      final webDavStarted = Completer<void>();
      final releaseWebDav = Completer<void>();
      final events = <String>[];
      state.overrideAutomaticSyncChecksForTest(
        webDav: () async {
          events.add('webdav-start');
          webDavStarted.complete();
          await releaseWebDav.future;
          events.add('webdav-complete');
        },
        cookieCloud: () async {
          events.add('cookie-cloud');
        },
      );

      final startup = state.runAutomaticSyncSequenceForTest();
      await webDavStarted.future.timeout(const Duration(seconds: 1));
      expect(events, ['webdav-start']);

      releaseWebDav.complete();
      await startup.timeout(const Duration(seconds: 1));

      expect(events, ['webdav-start', 'webdav-complete', 'cookie-cloud']);
      state.dispose();
    },
  );
}
