import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pt_mate/services/downloader/downloader_config.dart';
import 'package:pt_mate/services/storage/storage_service.dart';
import 'package:pt_mate/widgets/torrent_download_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => StorageService.instance.resetForTest());

  testWidgets('QB category menu scrolls to the last category on a phone', (
    tester,
  ) async {
    final categories = List.generate(36, (index) => '分类 $index');
    await _showDownloadDialog(tester, categories);

    await tester.tap(find.byType(DropdownButtonFormField<String?>));
    await tester.pumpAndSettle();

    final menu = find.byType(ListView);
    expect(menu, findsOneWidget);
    expect(tester.getSize(menu).height, lessThanOrEqualTo(320));

    final scrollable = find.descendant(
      of: menu,
      matching: find.byType(Scrollable),
    );
    final position = tester.state<ScrollableState>(scrollable).position;
    expect(position.maxScrollExtent, greaterThan(0));

    await tester.drag(menu, const Offset(0, -1400));
    await tester.pumpAndSettle();
    await tester.drag(menu, const Offset(0, -700));
    await tester.pumpAndSettle();

    expect(position.pixels, greaterThan(0));
    expect(position.pixels, closeTo(position.maxScrollExtent, 1));
    await tester.tap(find.text('分类 35').last);
    await tester.pumpAndSettle();

    expect(find.byType(ListView), findsNothing);
    expect(find.text('分类 35'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('short QB category menu also allows clearing the selection', (
    tester,
  ) async {
    await _showDownloadDialog(tester, ['分类 0', '分类 1']);

    final field = find.byType(DropdownButtonFormField<String?>);
    await tester.tap(field);
    await tester.pumpAndSettle();
    expect(
      tester
          .state<ScrollableState>(
            find.descendant(
              of: find.byType(ListView),
              matching: find.byType(Scrollable),
            ),
          )
          .position
          .maxScrollExtent,
      0,
    );

    await tester.tap(find.text('分类 1').last);
    await tester.pumpAndSettle();
    expect(find.text('分类 1'), findsOneWidget);

    await tester.tap(field);
    await tester.pumpAndSettle();
    await tester.tap(find.text('不使用分类').last);
    await tester.pumpAndSettle();

    expect(tester.state<FormFieldState<String?>>(field).value, isNull);
    expect(find.text('不使用分类'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _showDownloadDialog(
  WidgetTester tester,
  List<String> categories,
) async {
  const config = QbittorrentConfig(
    id: 'qb-test',
    name: 'Test QB',
    host: '127.0.0.1',
    port: 8080,
    username: 'admin',
    password: 'password',
  );
  SharedPreferences.setMockInitialValues({
    StorageKeys.downloaderConfigs: jsonEncode([config.toJson()]),
    StorageKeys.defaultDownloaderId: config.id,
    StorageKeys.downloaderCategoriesKey(config.id): categories,
    StorageKeys.downloaderTagsKey(config.id): ['标签'],
    StorageKeys.downloaderPathsKey(config.id): ['/downloads'],
  });

  tester.view.physicalSize = const Size(393, 852);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => const TorrentDownloadDialog(),
            ),
            child: const Text('打开下载设置'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('打开下载设置'));
  await tester.pumpAndSettle();
}
