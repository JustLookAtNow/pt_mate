import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pt_mate/models/app_models.dart';
import 'package:pt_mate/widgets/cached_network_image.dart';
import 'package:pt_mate/widgets/torrent_list_item.dart';

void main() {
  testWidgets('点击封面空白区域也会重新加载图片', (tester) async {
    const coverUrl = 'https://example.invalid/cover.jpg';
    final torrent = TorrentItem(
      id: 'cover-retry',
      name: 'Cover retry test',
      smallDescr: '',
      sizeBytes: 0,
      seeders: 0,
      leechers: 0,
      createdDate: DateTime(2026),
      discountEndTime: null,
      downloadUrl: '',
      imageList: const [],
      cover: coverUrl,
      downloadStatus: DownloadStatus.none,
      discount: DiscountType.normal,
      collection: false,
      isTop: false,
      tags: const [],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TorrentCover(
            torrent: torrent,
            isMobile: true,
            hasDouban: false,
            hasImdb: false,
          ),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('$coverUrl::0')), findsOneWidget);

    final coverRect = tester.getRect(find.byType(TorrentCover));
    await tester.tapAt(coverRect.topLeft + const Offset(2, 2));
    await tester.pump();

    expect(find.byKey(const ValueKey('$coverUrl::1')), findsOneWidget);

    await tester.tapAt(coverRect.bottomRight - const Offset(2, 2));
    await tester.pump();

    expect(find.byKey(const ValueKey('$coverUrl::2')), findsOneWidget);
    expect(find.byType(CachedNetworkImage), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 1));
  });
}
