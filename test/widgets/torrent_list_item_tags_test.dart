import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pt_mate/widgets/torrent_list_item.dart';
import 'package:pt_mate/models/app_models.dart';
import 'package:provider/provider.dart';
import 'package:pt_mate/services/storage/storage_service.dart';

// Fake StorageService
class FakeStorageService implements StorageService {
  @override
  List<SiteConfig>? get siteConfigsCache => [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  // Helper to create the widget under test
  Widget createWidgetUnderTest({
    required double width,
    required TorrentItem torrent,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: width,
            child: Provider<StorageService>(
              create: (_) => FakeStorageService(),
              child: TorrentListItem(
                torrent: torrent,
                isSelected: false,
                isSelectionMode: false,
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('Expand button should be visible on small screen when overflow', (
    WidgetTester tester,
  ) async {
    // Create a torrent with a long description to force tags overflow
    final torrent = TorrentItem(
      id: '1',
      name: 'Test Torrent',
      smallDescr:
          '4K 1080p HDR H265 WEB-DL DIY Blu-ray 4K 1080p HDR H265 WEB-DL DIY Blu-ray 4K 1080p HDR H265 WEB-DL DIY Blu-ray',
      sizeBytes: 1024,
      seeders: 10,
      leechers: 5,
      createdDate: '2023-01-01',
      discountEndTime: '',
      downloadUrl: '',
      imageList: [],
      cover: '',

      downloadStatus: DownloadStatus.none,
      discount: DiscountType.normal,
      collection: false,
      isTop: false,
      doubanRating: '0',
      imdbRating: '0',
    );

    // Set screen size to small (e.g., 400px width)
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;

    await tester.pumpWidget(
      createWidgetUnderTest(width: 400, torrent: torrent),
    );
    await tester.pumpAndSettle();

    // Verify expand button is present (Icons.keyboard_arrow_down)
    expect(find.byIcon(Icons.keyboard_arrow_down), findsOneWidget);

    // Reset window size
    addTearDown(tester.view.resetPhysicalSize);
  });

  testWidgets(
    'Expand button should NOT be visible on large screen even when overflow',
    (WidgetTester tester) async {
      final torrent = TorrentItem(
        id: '1',
        name: 'Test Torrent',
        smallDescr:
            'Tag1 Tag2 Tag3 Tag4 Tag5 Tag6 Tag7 Tag8 Tag9 Tag10 Tag11 Tag12 Tag13 Tag14 Tag15',
        sizeBytes: 1024,
        seeders: 10,
        leechers: 5,
        createdDate: '2023-01-01',
        discountEndTime: '',
        downloadUrl: '',
        imageList: [],
        cover: '',

        downloadStatus: DownloadStatus.none,
        discount: DiscountType.normal,
        collection: false,
        isTop: false,
        doubanRating: '0',
        imdbRating: '0',
      );

      // Set screen size to large (e.g., 1000px width)
      tester.view.physicalSize = const Size(1000, 800);
      tester.view.devicePixelRatio = 1.0;

      // We constrain the widget width to be small to ensure overflow happens internally in the wrap
      await tester.pumpWidget(
        createWidgetUnderTest(width: 400, torrent: torrent),
      );
      await tester.pumpAndSettle();

      // Verify expand button is NOT present
      expect(find.byIcon(Icons.keyboard_arrow_down), findsNothing);

      // Reset window size
      addTearDown(tester.view.resetPhysicalSize);
    },
  );
}
