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
  Widget createWidgetUnderTest({
    required TorrentItem torrent,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 800, // Increased width to avoid overflow during tests with long text
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

  testWidgets('TorrentListItem correctly identifies valid ratings', (WidgetTester tester) async {
    // Torrent with valid ratings
    final torrent = TorrentItem(
      id: '1',
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
      doubanRating: '8.5',
      imdbRating: '7.2',
      tags: [],
    );

    await tester.pumpWidget(createWidgetUnderTest(torrent: torrent));
    await tester.pumpAndSettle();

    // Verify rating badges are displayed
    expect(find.text('豆 8.5'), findsOneWidget);
    expect(find.text('IMDB 7.2'), findsOneWidget);
  });

  testWidgets('TorrentListItem handles invalid or empty ratings', (WidgetTester tester) async {
    // Torrent with invalid ratings
    final torrent = TorrentItem(
      id: '2',
      name: 'Test Torrent Invalid',
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
      doubanRating: 'N/A', // Invalid
      imdbRating: '',      // Empty
      tags: [],
    );

    await tester.pumpWidget(createWidgetUnderTest(torrent: torrent));
    await tester.pumpAndSettle();

    // Verify rating badges are NOT displayed
    expect(find.text('豆 N/A'), findsNothing);
    expect(find.text('IMDB'), findsNothing);
  });

  testWidgets('TorrentListItem handles ratings with text', (WidgetTester tester) async {
      // Torrent with mixed text ratings
      final torrent = TorrentItem(
        id: '3',
        name: 'Test Torrent Mixed',
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
        doubanRating: 'Rating: 9.0',
        imdbRating: '7.5/10',
        tags: [],
      );

      await tester.pumpWidget(createWidgetUnderTest(torrent: torrent));
      await tester.pumpAndSettle();

      // Verify parsed values are displayed
      expect(find.text('豆 Rating: 9.0'), findsOneWidget);
      expect(find.text('IMDB 7.5/10'), findsOneWidget);
    });
}
