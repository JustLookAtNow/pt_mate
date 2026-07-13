import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:pt_mate/models/app_models.dart';
import 'package:pt_mate/pages/aggregate_search_page.dart';
import 'package:pt_mate/providers/aggregate_search_provider.dart';
import 'package:pt_mate/services/settings/display_settings_manager.dart';
import 'package:pt_mate/services/storage/storage_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    final settings = AggregateSearchSettings(
      searchConfigs: const [
        AggregateSearchConfig(id: 'test-strategy', name: '测试策略'),
      ],
    );
    SharedPreferences.setMockInitialValues({
      StorageKeys.aggregateSearchSettings: jsonEncode(settings.toJson()),
    });
    StorageService.instance.resetForTest();
  });

  testWidgets('search FAB opens the strategy and keyword dialog', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => AggregateSearchProvider()),
          ChangeNotifierProvider(
            create: (_) => DisplaySettingsManager(StorageService.instance),
          ),
          Provider<StorageService>.value(value: StorageService.instance),
        ],
        child: const MaterialApp(home: AggregateSearchPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('测试策略'), findsOneWidget);
    expect(find.byKey(const ValueKey('aggregate-search-fab')), findsOneWidget);
    expect(find.byType(TextField), findsNothing);

    await tester.tap(find.byKey(const ValueKey('aggregate-search-fab')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('aggregate-search-strategy-field')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('search-keyword-field')), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '搜索'), findsOneWidget);
  });
}
