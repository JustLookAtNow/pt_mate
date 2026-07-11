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

  testWidgets('shows selected strategy and uses a floating search button', (
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

    final searchField = tester.widget<TextField>(find.byType(TextField));
    expect(searchField.decoration?.suffixIcon, isNull);
  });
}
