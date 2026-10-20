import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:pt_mate/models/app_models.dart';
import 'package:pt_mate/services/settings/display_settings_manager.dart';
import 'package:pt_mate/services/storage/storage_service.dart';
import 'package:pt_mate/widgets/torrent_list_item.dart';
import 'package:pt_mate/widgets/torrent_swipe_actions.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late DisplaySettingsManager settings;
  late TorrentItem torrent;
  var selectionMode = false;
  var features = const SiteFeatures();
  var collectionAvailable = true;
  var downloadAvailable = true;
  var collections = 0;
  var downloads = 0;
  var taps = 0;
  var longPresses = 0;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    StorageService.instance.resetForTest();
    settings = DisplaySettingsManager(StorageService.instance);
    await Future<void>.delayed(Duration.zero);
    addTearDown(settings.dispose);
    torrent = TorrentItem(
      id: 'swipe-test',
      name: 'Swipe test torrent',
      smallDescr: '',
      sizeBytes: 1024,
      seeders: 1,
      leechers: 0,
      createdDate: DateTime(2026),
      discountEndTime: null,
      downloadUrl: '',
      imageList: const [],
      cover: '',
      downloadStatus: DownloadStatus.none,
      discount: DiscountType.normal,
      collection: false,
      isTop: false,
      tags: const [],
    );
    selectionMode = false;
    features = const SiteFeatures();
    collectionAvailable = downloadAvailable = true;
    collections = downloads = taps = longPresses = 0;
  });

  Future<void> pumpItem(
    WidgetTester tester, {
    bool aggregate = false,
    double width = 390,
  }) async {
    tester.view.physicalSize = Size(width, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: settings),
          Provider.value(value: StorageService.instance),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: ListView(
              children: [
                TorrentListItem(
                  torrent: torrent,
                  isSelected: false,
                  isSelectionMode: selectionMode,
                  isAggregateMode: aggregate,
                  siteName: aggregate ? 'Example' : null,
                  currentSite: SiteConfig(
                    id: 'example',
                    name: 'Example',
                    baseUrl: '',
                    features: features,
                  ),
                  showCoverSetting: false,
                  onToggleCollection: collectionAvailable
                      ? () {
                          collections++;
                          torrent.collection = !torrent.collection;
                        }
                      : null,
                  onDownload: downloadAvailable ? () => downloads++ : null,
                  onTap: () => taps++,
                  onLongPress: () => longPresses++,
                ),
                const SizedBox(height: 1600),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> swipe(WidgetTester tester, double distance) async {
    await tester.drag(find.byType(TorrentListItem), Offset(distance, 0));
    await tester.pumpAndSettle();
  }

  for (final aggregate in [false, true]) {
    testWidgets('左右滑动分别切换收藏和下载，条目保留，聚合：$aggregate', (tester) async {
      await settings.setTorrentSwipeMode(TorrentSwipeMode.swipeActions);
      await pumpItem(tester, aggregate: aggregate);
      await swipe(tester, -150);
      expect(collections, 1);
      expect(torrent.collection, isTrue);
      expect(downloads, 0);
      expect(find.byType(TorrentListItem), findsOneWidget);
      expect(find.text('Swipe test torrent').hitTestable(), findsOneWidget);

      await pumpItem(tester, aggregate: aggregate);
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(TorrentListItem)),
      );
      await gesture.moveBy(const Offset(-20, 0));
      await gesture.moveBy(const Offset(-150, 0));
      await tester.pump();
      expect(find.text('取消收藏'), findsOneWidget);
      expect(collections, 1);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(collections, 2);
      expect(torrent.collection, isFalse);

      await swipe(tester, 150);
      expect(downloads, 1);
      expect(collections, 2);
      expect(taps, 0);
    });
  }

  testWidgets('默认左滑只显示按钮，点击后执行', (tester) async {
    await pumpItem(tester);
    expect(find.byType(TorrentSwipeActions), findsNothing);
    await swipe(tester, 150);
    expect(downloads, 0);
    await swipe(tester, -150);
    expect(collections, 0);
    expect(downloads, 0);
    final download = find.text('下载').hitTestable();
    expect(download, findsOneWidget);
    await tester.tap(download);
    await tester.pumpAndSettle();
    expect(downloads, 1);
  });

  testWidgets('短滑、快速短滑、取消及纵向滚动不执行操作', (tester) async {
    await settings.setTorrentSwipeMode(TorrentSwipeMode.swipeActions);
    await pumpItem(tester);
    await swipe(tester, -50);
    await tester.fling(find.byType(TorrentListItem), const Offset(50, 0), 1500);
    await tester.pumpAndSettle();
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(TorrentListItem)),
    );
    await gesture.moveBy(const Offset(-20, 0));
    await gesture.moveBy(const Offset(-160, 0));
    await gesture.cancel();
    await tester.pumpAndSettle();
    await tester.drag(find.byType(TorrentListItem), const Offset(0, -150));
    await tester.pumpAndSettle();
    expect(collections, 0);
    expect(downloads, 0);
    expect(taps, 0);
    expect(
      tester.state<ScrollableState>(find.byType(Scrollable)).position.pixels,
      greaterThan(0),
    );
  });

  testWidgets('多选禁用双向操作，点击与长按仍可用', (tester) async {
    await settings.setTorrentSwipeMode(TorrentSwipeMode.swipeActions);
    selectionMode = true;
    await pumpItem(tester);
    await swipe(tester, -150);
    await swipe(tester, 150);
    expect(collections, 0);
    expect(downloads, 0);
    await tester.tap(find.byType(TorrentListItem));
    await tester.longPress(find.byType(TorrentListItem));
    expect(taps, 1);
    expect(longPresses, 1);
  });

  testWidgets('不支持的方向不可触发，另一方向正常', (tester) async {
    await settings.setTorrentSwipeMode(TorrentSwipeMode.swipeActions);
    features = const SiteFeatures(supportCollection: false);
    await pumpItem(tester);
    await swipe(tester, -150);
    await swipe(tester, 150);
    expect(collections, 0);
    expect(downloads, 1);
    features = const SiteFeatures(supportDownload: false);
    await pumpItem(tester);
    await swipe(tester, -150);
    await swipe(tester, 150);
    expect(collections, 1);
    expect(downloads, 1);
  });

  testWidgets('回调为空时不可操作', (tester) async {
    await settings.setTorrentSwipeMode(TorrentSwipeMode.swipeActions);
    collectionAvailable = downloadAvailable = false;
    await pumpItem(tester);
    await swipe(tester, -150);
    await swipe(tester, 150);
    expect(collections, 0);
    expect(downloads, 0);
  });

  testWidgets('切换模式或进入多选时取消进行中的操作', (tester) async {
    await settings.setTorrentSwipeMode(TorrentSwipeMode.swipeActions);
    await pumpItem(tester);
    var gesture = await tester.startGesture(
      tester.getCenter(find.byType(TorrentListItem)),
    );
    await gesture.moveBy(const Offset(20, 0));
    await gesture.moveBy(const Offset(160, 0));
    await settings.setTorrentSwipeMode(TorrentSwipeMode.revealButtons);
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    expect(downloads, 0);

    await settings.setTorrentSwipeMode(TorrentSwipeMode.swipeActions);
    await tester.pumpAndSettle();
    gesture = await tester.startGesture(
      tester.getCenter(find.byType(TorrentListItem)),
    );
    await gesture.moveBy(const Offset(-20, 0));
    await gesture.moveBy(const Offset(-160, 0));
    selectionMode = true;
    await pumpItem(tester);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(collections, 0);
  });

  testWidgets('回弹过程中再次滑动不重复执行，复位后可再操作', (tester) async {
    await settings.setTorrentSwipeMode(TorrentSwipeMode.swipeActions);
    await pumpItem(tester);
    await tester.drag(find.byType(TorrentListItem), const Offset(150, 0));
    await tester.pump(const Duration(milliseconds: 30));
    await tester.drag(find.byType(TorrentListItem), const Offset(150, 0));
    await tester.pumpAndSettle();
    expect(downloads, 1);
    await swipe(tester, 150);
    expect(downloads, 2);
  });

  testWidgets('大屏保持现有按钮交互', (tester) async {
    await settings.setTorrentSwipeMode(TorrentSwipeMode.swipeActions);
    await pumpItem(tester, width: 1024);
    expect(find.byType(TorrentSwipeActions), findsNothing);
    await swipe(tester, -180);
    await swipe(tester, 180);
    expect(collections, 0);
    expect(downloads, 0);
    expect(find.byTooltip('下载'), findsOneWidget);
  });
}
