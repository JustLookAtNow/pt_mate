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
    // Create a torrent with explicit tags to force overflow
    final tags = List.generate(
      20,
      (index) => TagType.diy,
    ); // Use many tags to ensure overflow

    final torrent = TorrentItem(
      id: '1',
      name: 'Test Torrent',
      smallDescr: 'Test Description',
      sizeBytes: 1024,
      seeders: 10,
      leechers: 5,
      createdDate: DateTime.parse('2023-10-27T10:00:00Z'),
      discountEndTime: DateTime.parse('2023-10-27T12:00:00Z'),
      downloadUrl: '',
      imageList: [],
      cover: '',
      tags: tags, // Explicitly pass tags
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
      // Create a torrent with explicit tags to force overflow
      final tags = List.generate(
        20,
        (index) => TagType.diy,
      ); // Use many tags to ensure overflow

      final torrent = TorrentItem(
        id: '1',
        name: 'Test Torrent',
        smallDescr: 'Description',
        sizeBytes: 1024,
        seeders: 10,
        leechers: 5,
        createdDate: DateTime.parse('2023-10-27T10:00:00Z'),
        discountEndTime: DateTime.parse('2023-10-27T12:00:00Z'),
        downloadUrl: '',
        imageList: [],
        cover: '',
        tags: tags, // Explicitly pass tags
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
