import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pt_mate/models/app_models.dart';
import 'package:pt_mate/widgets/torrent_list_item.dart';

void main() {
  TorrentItem buildTorrent({String cover = 'https://example.invalid/c.jpg'}) {
    return TorrentItem(
      id: 't1',
      name: 'Cover tap test',
      smallDescr: '',
      sizeBytes: 0,
      seeders: 0,
      leechers: 0,
      createdDate: DateTime(2026),
      discountEndTime: null,
      downloadUrl: '',
      imageList: const [],
      cover: cover,
      downloadStatus: DownloadStatus.none,
      discount: DiscountType.normal,
      collection: false,
      isTop: false,
      tags: const [],
    );
  }

  testWidgets('设置 onCoverTap 时点击封面触发回调', (tester) async {
    var tapped = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TorrentCover(
            torrent: buildTorrent(),
            isMobile: true,
            hasDouban: false,
            hasImdb: false,
            onTap: () => tapped = true,
          ),
        ),
      ),
    );

    await tester.tap(find.byType(TorrentCover));
    await tester.pump();

    expect(tapped, isTrue);
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('未设置 onCoverTap 时点击封面走内置重载逻辑', (tester) async {
    const coverUrl = 'https://example.invalid/builtin.jpg';
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TorrentCover(
            torrent: buildTorrent(cover: coverUrl),
            isMobile: true,
            hasDouban: false,
            hasImdb: false,
          ),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('$coverUrl::0')), findsOneWidget);
    await tester.tap(find.byType(TorrentCover));
    await tester.pump();
    // 内置行为：无缓存数据时点击会触发重载（reloadKey 递增）
    expect(find.byKey(const ValueKey('$coverUrl::1')), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1));
  });
}
