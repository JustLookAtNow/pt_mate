import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pt_mate/models/app_models.dart';
import 'package:pt_mate/pages/server_settings_page.dart';
import 'package:pt_mate/services/storage/storage_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const secureStorageChannel = MethodChannel(
    'plugins.it_nomads.com/flutter_secure_storage',
  );
  final storage = StorageService.instance;
  late Map<String, String> secureValues;

  setUp(() async {
    final sites = List.generate(
      12,
      (index) => SiteConfig(
        id: 'site-${index + 1}',
        name: '站点 ${index + 1}',
        baseUrl: 'https://site-${index + 1}.example',
        siteColor: Colors.blue.toARGB32(),
      ),
    );
    SharedPreferences.setMockInitialValues({
      StorageKeys.siteConfigs: jsonEncode(
        sites.map((site) => site.toJson()).toList(),
      ),
      StorageKeys.activeSiteId: sites.first.id,
      StorageKeys.lastSiteHealthRefreshCheck:
          DateTime.now().millisecondsSinceEpoch,
    });
    storage.resetForTest();
    storage.overridePlatformForTest(TargetPlatform.iOS);
    secureValues = <String, String>{};
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorageChannel, (call) async {
          final arguments = call.arguments as Map<dynamic, dynamic>?;
          final key = arguments?['key'] as String?;
          switch (call.method) {
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
    await storage.initializeSecureStorage();
    expect(await storage.loadSiteConfigs(), hasLength(12));
  });

  tearDown(() async {
    await storage.waitForPendingSecureStorageCleanup();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorageChannel, null);
    storage.resetForTest();
  });

  testWidgets('列表末项可滚动到悬浮按钮组上方', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MaterialApp(home: ServerSettingsPage()));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    for (var attempt = 0; attempt < 50; attempt++) {
      await tester.pump(const Duration(milliseconds: 100));
      if (find.text('站点 1').evaluate().isNotEmpty) {
        break;
      }
    }
    expect(find.text('站点 1'), findsOneWidget);

    await tester.drag(find.byType(ListView).last, const Offset(0, -5000));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('站点 12'), findsOneWidget);

    final lastCard = find.ancestor(
      of: find.text('站点 12'),
      matching: find.byType(Card),
    );
    final topFab = find.byType(FloatingActionButton).first;

    expect(lastCard, findsOneWidget);
    expect(topFab, findsOneWidget);
    expect(
      tester.getBottomLeft(lastCard).dy,
      lessThan(tester.getTopLeft(topFab).dy),
    );
  });
}
