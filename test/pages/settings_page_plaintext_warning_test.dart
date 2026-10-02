import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:pt_mate/models/app_models.dart';
import 'package:pt_mate/pages/settings_page.dart';
import 'package:pt_mate/services/settings/display_settings_manager.dart';
import 'package:pt_mate/services/storage/android_secure_storage_profile_resolver.dart';
import 'package:pt_mate/services/storage/storage_service.dart';
import 'package:pt_mate/services/theme/theme_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FailingSiteTagStorage implements StorageService {
  @override
  Future<bool> loadAutoAddSiteTag() async => false;

  @override
  Future<bool> loadAutoLoadImages() =>
      StorageService.instance.loadAutoLoadImages();

  @override
  Future<void> saveAutoAddSiteTag(bool enabled) async {
    throw StateError('test preference write failure');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FailingVisibleTagStorage implements StorageService {
  @override
  Future<bool> loadShowCoverImages() =>
      StorageService.instance.loadShowCoverImages();

  @override
  Future<void> loadVisibleTags() => StorageService.instance.loadVisibleTags();

  @override
  List<String> get visibleTags => StorageService.instance.visibleTags;

  @override
  Future<void> saveVisibleTags(List<String> tags) async {
    throw StateError('test preference write failure');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

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

  Future<void> pumpSettings(
    WidgetTester tester, {
    StorageService? settingsStorage,
    StorageService? displayStorage,
  }) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<ThemeManager>(
            create: (_) => ThemeManager(storage),
          ),
          ChangeNotifierProvider<DisplaySettingsManager>(
            create: (_) => DisplaySettingsManager(displayStorage ?? storage),
          ),
          Provider<StorageService>.value(value: settingsStorage ?? storage),
        ],
        child: const MaterialApp(home: SettingsPage()),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder siteTagSwitch() => find.widgetWithText(SwitchListTile, '自动添加站点标签');

  Future<Finder> expandVisibleTags(WidgetTester tester) async {
    final title = find.text('过滤标签设置');
    await tester.scrollUntilVisible(
      title,
      300,
      scrollable: find.descendant(
        of: find.byType(ListView).last,
        matching: find.byType(Scrollable),
      ),
    );
    await tester.tap(title);
    await tester.pumpAndSettle();
    final chip = find.widgetWithText(FilterChip, '4K');
    await tester.ensureVisible(chip);
    await tester.pumpAndSettle();
    return chip;
  }

  testWidgets('标签展示设置保存后更新共享状态，重建设置页仍保留', (tester) async {
    await pumpSettings(tester);
    final chip = await expandVisibleTags(tester);
    expect(tester.widget<FilterChip>(chip).selected, isTrue);

    await tester.tap(chip);
    await tester.pumpAndSettle();

    expect(tester.widget<FilterChip>(chip).selected, isFalse);
    final settings = tester
        .element(find.byType(SettingsPage))
        .read<DisplaySettingsManager>();
    expect(settings.visibleTags, isNot(contains(TagType.fourK.name)));
    expect(storage.visibleTags, isNot(contains(TagType.fourK.name)));
    expect(find.text('设置顶部快捷过滤和列表项中显示的标签'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await pumpSettings(tester);
    final restoredChip = await expandVisibleTags(tester);
    expect(tester.widget<FilterChip>(restoredChip).selected, isFalse);
  });

  testWidgets('标签展示设置保存失败时保留选中状态并提示错误', (tester) async {
    await pumpSettings(tester, displayStorage: _FailingVisibleTagStorage());
    final chip = await expandVisibleTags(tester);
    await tester.tap(chip);
    await tester.pumpAndSettle();

    expect(tester.widget<FilterChip>(chip).selected, isTrue);
    expect(tester.widget<FilterChip>(chip).onSelected, isNotNull);
    expect(storage.visibleTags, contains(TagType.fourK.name));
    expect(find.textContaining('保存标签展示设置失败'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });

  testWidgets('自动站点标签总开关默认关闭，保存后重建设置页仍开启', (tester) async {
    await pumpSettings(tester);
    await tester.ensureVisible(siteTagSwitch());
    expect(tester.widget<SwitchListTile>(siteTagSwitch()).value, isFalse);
    await tester.tap(siteTagSwitch());
    await tester.pumpAndSettle();
    expect(tester.widget<SwitchListTile>(siteTagSwitch()).value, isTrue);
    expect(await storage.loadAutoAddSiteTag(), isTrue);

    await tester.pumpWidget(const SizedBox.shrink());
    await pumpSettings(tester);
    await tester.ensureVisible(siteTagSwitch());
    expect(tester.widget<SwitchListTile>(siteTagSwitch()).value, isTrue);
  });

  testWidgets('自动站点标签保存失败时保持开关原值并显示错误', (tester) async {
    await pumpSettings(tester, settingsStorage: _FailingSiteTagStorage());
    await tester.ensureVisible(siteTagSwitch());
    await tester.tap(siteTagSwitch());
    await tester.pumpAndSettle();
    expect(tester.widget<SwitchListTile>(siteTagSwitch()).value, isFalse);
    expect(find.textContaining('保存自动站点标签设置失败'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });

  testWidgets('设置页持续显示 Android 明文凭据存储警告', (tester) async {
    await pumpSettings(tester);

    expect(find.text('Android 明文凭据存储'), findsOneWidget);
    expect(find.textContaining('Cookie、API Key 和密码正以明文'), findsOneWidget);
  });
}
