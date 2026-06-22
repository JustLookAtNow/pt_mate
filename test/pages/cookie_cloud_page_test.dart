import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:pt_mate/pages/cookie_cloud_page.dart';
import 'package:pt_mate/services/storage/storage_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const secureStorageChannel = MethodChannel(
    'plugins.it_nomads.com/flutter_secure_storage',
  );

  final secureStorage = <String, String>{};

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    PackageInfo.setMockInitialValues(
      appName: 'PT Mate',
      packageName: 'com.github.justlookatnow.ptmate',
      version: '1.3.0',
      buildNumber: '1',
      buildSignature: '',
    );
    secureStorage.clear();
    StorageService.instance.resetForTest();

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorageChannel, (
          MethodCall methodCall,
        ) async {
          switch (methodCall.method) {
            case 'write':
              secureStorage[methodCall.arguments['key'] as String] =
                  methodCall.arguments['value'] as String;
              return null;
            case 'read':
              return secureStorage[methodCall.arguments['key'] as String];
            case 'delete':
              secureStorage.remove(methodCall.arguments['key'] as String);
              return null;
            case 'containsKey':
              return secureStorage.containsKey(
                methodCall.arguments['key'] as String,
              );
            case 'readAll':
              return Map<String, String>.from(secureStorage);
            default:
              return null;
          }
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorageChannel, null);
  });

  testWidgets('clear config button clears Cookie Cloud configuration', (
    tester,
  ) async {
    await StorageService.instance.saveCookieCloudConfig(
      CookieCloudConfig(
        url: 'https://cookiecloud.example.com',
        uuid: 'uuid-1',
        password: 'password-1',
        autoSyncEnabled: true,
        lastSyncAt: DateTime(2026),
        lastSyncSummary: '更新 1 个站点，新增 0 个站点',
      ),
    );

    await tester.pumpWidget(const MaterialApp(home: CookieCloudPage()));
    await tester.pumpAndSettle();

    expect(find.text('https://cookiecloud.example.com'), findsWidgets);
    expect(find.text('清空配置'), findsOneWidget);

    await tester.tap(find.text('清空配置'));
    await tester.pumpAndSettle();
    expect(find.text('清空 Cookie Cloud 配置'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, '清空'));
    await tester.pumpAndSettle();

    final config = await StorageService.instance.loadCookieCloudConfig();
    expect(config.url, isEmpty);
    expect(config.uuid, isEmpty);
    expect(config.password, isEmpty);
    expect(config.autoSyncEnabled, isFalse);
    expect(config.lastSyncAt, isNull);
    expect(config.lastSyncSummary, isEmpty);
    final editableTexts = tester.widgetList<EditableText>(
      find.byType(EditableText),
    );
    expect(
      editableTexts.any(
        (widget) => widget.controller.text == 'https://cookiecloud.example.com',
      ),
      isFalse,
    );
    await tester.pump(const Duration(seconds: 4));
  });
}
