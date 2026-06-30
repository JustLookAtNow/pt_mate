import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:pt_mate/models/app_models.dart';
import 'package:pt_mate/services/storage/storage_service.dart';
import 'package:pt_mate/widgets/torrent_list_item.dart';

class FakeStorageService implements StorageService {
  final List<SiteConfig> sites;

  FakeStorageService({this.sites = const []});

  @override
  List<SiteConfig>? get siteConfigsCache => sites;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  Widget createWidgetUnderTest({
    required double width,
    required TorrentItem torrent,
    bool isAggregateMode = false,
    String? siteName,
    List<SiteConfig> siteConfigs = const [],
  }) {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: width,
            child: Provider<StorageService>(
              create: (_) => FakeStorageService(sites: siteConfigs),
              child: TorrentListItem(
                torrent: torrent,
                isSelected: false,
                isSelectionMode: false,
                showCoverSetting: false,
                isAggregateMode: isAggregateMode,
                siteName: siteName,
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('mobile torrent size stays on one line on narrow screens', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final torrent = TorrentItem(
      id: '1',
      name: 'Once and Forever 2023 S01 Complete 2160p WEB-DL HEVC DDP5.1',
      smallDescr: '曾少年【全35集】【4K高码+杜比环绕】',
      sizeBytes: (174.90 * 1024 * 1024 * 1024).round(),
      seeders: 18,
      leechers: 96,
      createdDate: DateTime.parse('2023-10-27T10:00:00Z'),
      discountEndTime: null,
      downloadUrl: '',
      imageList: [],
      cover: '',
      downloadStatus: DownloadStatus.none,
      discount: DiscountType.free,
      collection: false,
      isTop: false,
      doubanRating: '0',
      imdbRating: '0',
      tags: const [TagType.fourK, TagType.h265, TagType.webDl],
    );

    await tester.pumpWidget(
      createWidgetUnderTest(width: 360, torrent: torrent),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);

    final sizeFinder = find.text('174.90 GB');
    expect(sizeFinder, findsOneWidget);
    expect(
      find.ancestor(of: sizeFinder, matching: find.byType(FittedBox)),
      findsOneWidget,
    );

    final sizeText = tester.widget<Text>(sizeFinder);
    expect(sizeText.maxLines, 1);
    expect(sizeText.softWrap, isFalse);
  });

  testWidgets('aggregate site chip sits below inline ratings without cover', (
    WidgetTester tester,
  ) async {
    final torrent = TorrentItem(
      id: '2',
      name: 'Test Torrent',
      smallDescr: 'Test Description',
      sizeBytes: 1024,
      seeders: 10,
      leechers: 5,
      createdDate: DateTime.parse('2023-10-27T10:00:00Z'),
      discountEndTime: null,
      downloadUrl: '',
      imageList: [],
      cover: 'https://example.com/cover.jpg',
      downloadStatus: DownloadStatus.none,
      discount: DiscountType.normal,
      collection: false,
      isTop: false,
      doubanRating: '8.5',
      imdbRating: '7.2',
      tags: const [],
    );

    await tester.pumpWidget(
      createWidgetUnderTest(
        width: 360,
        torrent: torrent,
        isAggregateMode: true,
        siteName: 'LightSite',
        siteConfigs: const [
          SiteConfig(
            id: 'light',
            name: 'LightSite',
            baseUrl: 'https://example.com',
            siteColor: 0xFFFFF59D,
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('豆 8.5'), findsOneWidget);
    expect(find.text('IMDB 7.2'), findsOneWidget);
    expect(find.text('LightSite'), findsOneWidget);

    final ratingBottom = tester.getBottomLeft(find.text('豆 8.5')).dy;
    final siteTop = tester.getTopLeft(find.text('LightSite')).dy;
    expect(siteTop, greaterThan(ratingBottom));
  });

  testWidgets('aggregate site chip uses readable text and site border color', (
    WidgetTester tester,
  ) async {
    const siteColor = Color(0xFFFFF59D);
    final torrent = TorrentItem(
      id: '3',
      name: 'Test Torrent',
      smallDescr: 'Test Description',
      sizeBytes: 1024,
      seeders: 10,
      leechers: 5,
      createdDate: DateTime.parse('2023-10-27T10:00:00Z'),
      discountEndTime: null,
      downloadUrl: '',
      imageList: [],
      cover: '',
      downloadStatus: DownloadStatus.none,
      discount: DiscountType.normal,
      collection: false,
      isTop: false,
      doubanRating: '0',
      imdbRating: '0',
      tags: const [],
    );

    await tester.pumpWidget(
      createWidgetUnderTest(
        width: 360,
        torrent: torrent,
        isAggregateMode: true,
        siteName: 'LightSite',
        siteConfigs: const [
          SiteConfig(
            id: 'light',
            name: 'LightSite',
            baseUrl: 'https://example.com',
            siteColor: 0xFFFFF59D,
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    final siteNameText = tester.widget<Text>(find.text('LightSite'));
    expect(siteNameText.style?.color, Colors.black);

    final siteBorderFinder = find.byWidgetPredicate((widget) {
      if (widget is! Container) return false;
      final decoration = widget.decoration;
      if (decoration is! BoxDecoration) return false;
      final border = decoration.border;
      if (border is! Border) return false;
      return border.top.color == siteColor.withValues(alpha: 0.65);
    });
    expect(siteBorderFinder, findsOneWidget);
  });

  testWidgets('aggregate site chip does not increase item height', (
    WidgetTester tester,
  ) async {
    final torrent = TorrentItem(
      id: '4',
      name: 'Test Torrent',
      smallDescr: 'Test Description',
      sizeBytes: 1024,
      seeders: 10,
      leechers: 5,
      createdDate: DateTime.parse('2023-10-27T10:00:00Z'),
      discountEndTime: null,
      downloadUrl: '',
      imageList: [],
      cover: '',
      downloadStatus: DownloadStatus.none,
      discount: DiscountType.normal,
      collection: false,
      isTop: false,
      doubanRating: '0',
      imdbRating: '0',
      tags: const [],
    );

    await tester.pumpWidget(
      createWidgetUnderTest(width: 360, torrent: torrent),
    );
    await tester.pumpAndSettle();
    final normalHeight = tester.getSize(find.byType(TorrentListItem)).height;

    await tester.pumpWidget(
      createWidgetUnderTest(
        width: 360,
        torrent: torrent,
        isAggregateMode: true,
        siteName: 'LightSite',
        siteConfigs: const [
          SiteConfig(
            id: 'light',
            name: 'LightSite',
            baseUrl: 'https://example.com',
            siteColor: 0xFFFFF59D,
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();
    final aggregateHeight = tester.getSize(find.byType(TorrentListItem)).height;

    expect(aggregateHeight, normalHeight);
  });
}
