import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:pt_mate/models/app_models.dart';
import 'package:pt_mate/services/storage/storage_service.dart';
import 'package:pt_mate/widgets/torrent_list_item.dart';

class FakeStorageService implements StorageService {
  @override
  List<SiteConfig>? get siteConfigsCache => [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
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
                showCoverSetting: false,
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
}
