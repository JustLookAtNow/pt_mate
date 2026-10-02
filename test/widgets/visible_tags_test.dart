import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:pt_mate/models/app_models.dart';
import 'package:pt_mate/services/settings/display_settings_manager.dart';
import 'package:pt_mate/services/storage/storage_service.dart';
import 'package:pt_mate/widgets/tag_filter_bar.dart';
import 'package:pt_mate/widgets/torrent_list_item.dart';
import 'package:shared_preferences/shared_preferences.dart';

TorrentItem _torrent({
  String id = 'tagged',
  List<TagType> tags = const [TagType.fourK, TagType.h265, TagType.webDl],
  bool showBadges = false,
}) {
  return TorrentItem(
    id: id,
    name: 'Torrent $id',
    smallDescr: 'Description',
    discountEndTime: null,
    downloadUrl: '',
    seeders: 10,
    leechers: 2,
    sizeBytes: 1024,
    createdDate: DateTime(2026, 1, 1),
    imageList: const [],
    cover: '',
    tags: tags,
    isTop: showBadges,
    discount: showBadges ? DiscountType.free : DiscountType.normal,
    doubanRating: showBadges ? '8.5' : null,
    imdbRating: showBadges ? '7.2' : null,
  );
}

Widget _harness(
  DisplaySettingsManager settings,
  List<TorrentItem> torrents, {
  bool isAggregateMode = false,
}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<DisplaySettingsManager>.value(value: settings),
      Provider<StorageService>.value(value: StorageService.instance),
    ],
    child: MaterialApp(
      home: Scaffold(
        body: Column(
          children: [
            TagFilterBar(
              includedTags: const {},
              excludedTags: const {},
              onIncludedChanged: (_) {},
              onExcludedChanged: (_) {},
            ),
            for (final torrent in torrents)
              TorrentListItem(
                key: ValueKey(torrent.id),
                torrent: torrent,
                isSelected: false,
                isSelectionMode: false,
                showCoverSetting: false,
                isAggregateMode: isAggregateMode,
                siteName: isAggregateMode ? 'Test Site' : null,
              ),
          ],
        ),
      ),
    ),
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    StorageService.instance.resetForTest();
  });

  for (final width in [360.0, 1024.0]) {
    for (final isAggregateMode in [false, true]) {
      testWidgets('标签设置即时更新顶部与列表项：width=$width aggregate=$isAggregateMode', (
        tester,
      ) async {
        tester.view.physicalSize = Size(width, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final settings = DisplaySettingsManager(StorageService.instance);
        addTearDown(settings.dispose);
        final torrent = _torrent();
        await tester.pumpWidget(
          _harness(settings, [torrent], isAggregateMode: isAggregateMode),
        );
        await tester.pumpAndSettle();
        final item = find.byType(TorrentListItem);
        final originalElement = tester.element(item);

        expect(find.text('4K'), findsNWidgets(2));
        expect(find.text('H265'), findsNWidgets(2));

        await settings.setVisibleTags({TagType.webDl.name, TagType.fourK.name});
        await tester.pumpAndSettle();

        expect(tester.element(item), same(originalElement));
        expect(find.text('4K'), findsNWidgets(2));
        expect(find.text('WEB-DL'), findsNWidgets(2));
        expect(find.text('H265'), findsNothing);
        expect(
          tester
              .widgetList<Text>(
                find.descendant(of: item, matching: find.byType(Text)),
              )
              .map((text) => text.data)
              .where((text) => ['4K', 'WEB-DL'].contains(text))
              .toList(),
          ['4K', 'WEB-DL'],
        );

        await settings.setVisibleTags({});
        await tester.pumpAndSettle();
        expect(find.text('4K'), findsNothing);
        expect(find.text('WEB-DL'), findsNothing);
        expect(find.text(torrent.name), findsOneWidget);
        expect(torrent.tags, [TagType.fourK, TagType.h265, TagType.webDl]);

        await settings.setVisibleTags(
          TagType.values.map((tag) => tag.name).toSet(),
        );
        await tester.pumpAndSettle();
        expect(find.text('H265'), findsNWidgets(2));
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('隐藏全部标签后与无标签项布局相同：width=$width', (tester) async {
      tester.view.physicalSize = Size(width, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final settings = DisplaySettingsManager(StorageService.instance);
      addTearDown(settings.dispose);
      final tagged = _torrent();
      final plain = _torrent(id: 'plain', tags: const []);
      await tester.pumpWidget(_harness(settings, [tagged, plain]));
      await tester.pumpAndSettle();

      await settings.setVisibleTags({});
      await tester.pumpAndSettle();

      final taggedItem = find.byKey(ValueKey(tagged.id));
      final plainItem = find.byKey(ValueKey(plain.id));
      expect(
        tester.getSize(taggedItem).height,
        tester.getSize(plainItem).height,
      );
      expect(
        tester.getTopLeft(find.text(tagged.name)).dy -
            tester.getTopLeft(taggedItem).dy,
        tester.getTopLeft(find.text(plain.name)).dy -
            tester.getTopLeft(plainItem).dy,
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('隐藏标签仍保留优惠、置顶和评分', (tester) async {
    final settings = DisplaySettingsManager(StorageService.instance);
    addTearDown(settings.dispose);
    await tester.pumpWidget(_harness(settings, [_torrent(showBadges: true)]));
    await tester.pumpAndSettle();

    await settings.setVisibleTags({});
    await tester.pumpAndSettle();

    expect(find.text('4K'), findsNothing);
    expect(find.text('FREE'), findsOneWidget);
    expect(find.byIcon(Icons.push_pin), findsOneWidget);
    expect(find.text('豆 8.5'), findsOneWidget);
    expect(find.text('IMDB 7.2'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
