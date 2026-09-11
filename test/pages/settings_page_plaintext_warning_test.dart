import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:pt_mate/pages/settings_page.dart';
import 'package:pt_mate/services/settings/display_settings_manager.dart';
import 'package:pt_mate/services/storage/android_secure_storage_profile_resolver.dart';
import 'package:pt_mate/services/storage/storage_service.dart';
import 'package:pt_mate/services/theme/theme_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const profileChannel = MethodChannel('pt_mate/secure_storage_profile');
  final storage = StorageService.instance;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    storage.resetForTest();
    storage.overridePlatformForTest(TargetPlatform.android);
    storage.overrideAndroidSecureStorageProfileForTest(
      AndroidSecureStorageProfile.plaintext,
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(profileChannel, (_) async => null);
    await storage.initializeSecureStorage();
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(profileChannel, null);
    storage.resetForTest();
  });

  testWidgets('设置页持续显示 Android 明文凭据存储警告', (tester) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<ThemeManager>(
            create: (_) => ThemeManager(storage),
          ),
          ChangeNotifierProvider<DisplaySettingsManager>(
            create: (_) => DisplaySettingsManager(storage),
          ),
          Provider<StorageService>.value(value: storage),
        ],
        child: const MaterialApp(home: SettingsPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Android 明文凭据存储'), findsOneWidget);
    expect(find.textContaining('Cookie、API Key 和密码正以明文'), findsOneWidget);
  });
}
