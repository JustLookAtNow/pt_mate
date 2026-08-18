import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:pt_mate/widgets/torrent_cover_gallery_viewer.dart';

Uint8List _png(Color color) {
  final image = img.Image(width: 4, height: 4);
  img.fill(
    image,
    color: img.ColorRgba8(
      (color.r * 255.0).round().clamp(0, 255),
      (color.g * 255.0).round().clamp(0, 255),
      (color.b * 255.0).round().clamp(0, 255),
      255,
    ),
  );
  return Uint8List.fromList(img.encodePng(image));
}

void main() {
  final images = <Uint8List>[
    _png(const Color(0xFFFF0000)),
    _png(const Color(0xFF00FF00)),
    _png(const Color(0xFF0000FF)),
  ];

  Future<Uint8List?> loadCover(int position) async {
    await Future<void>.delayed(const Duration(milliseconds: 10));
    if (position < 0 || position >= images.length) return null;
    return images[position];
  }

  Widget buildViewer({int initialIndex = 0, ValueChanged<int>? onPageChanged}) {
    return MaterialApp(
      home: Scaffold(
        body: TorrentCoverGalleryViewer(
          itemCount: images.length,
          initialIndex: initialIndex,
          loadCover: loadCover,
          titleFor: (p) => 'Title $p',
          onPageChanged: onPageChanged,
        ),
      ),
    );
  }

  testWidgets('初始加载显示第一张图与位置指示', (tester) async {
    await tester.pumpWidget(buildViewer());
    await tester.pumpAndSettle();

    expect(find.byType(Image), findsOneWidget);
    expect(find.text('Title 0  (1 / 3)'), findsOneWidget);
    // 第一张时左侧按钮隐藏（不可后退）
    expect(find.byTooltip('上一个'), findsNothing);
    expect(find.byTooltip('下一个'), findsOneWidget);
  });

  testWidgets('点击右侧按钮翻到下一张并触发回调', (tester) async {
    var changed = -1;
    await tester.pumpWidget(buildViewer(onPageChanged: (p) => changed = p));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('下一个'));
    await tester.pumpAndSettle();

    expect(changed, 1);
    expect(find.text('Title 1  (2 / 3)'), findsOneWidget);
    expect(find.byTooltip('上一个'), findsOneWidget);
    expect(find.byTooltip('下一个'), findsOneWidget);
  });

  testWidgets('最后一张时右侧按钮隐藏', (tester) async {
    await tester.pumpWidget(buildViewer(initialIndex: 2));
    await tester.pumpAndSettle();

    expect(find.byTooltip('上一个'), findsOneWidget);
    expect(find.byTooltip('下一个'), findsNothing);
  });

  testWidgets('方向键可以翻页', (tester) async {
    var changed = -1;
    await tester.pumpWidget(buildViewer(onPageChanged: (p) => changed = p));
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();

    expect(changed, 1);
  });

  testWidgets('加载失败时显示错误并可继续翻页', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TorrentCoverGalleryViewer(
            itemCount: 2,
            initialIndex: 0,
            loadCover: (p) async => p == 0 ? null : images[1],
            titleFor: (p) => 'T$p',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('图片加载失败'), findsOneWidget);
    await tester.tap(find.byTooltip('下一个'));
    await tester.pumpAndSettle();
    expect(find.byType(Image), findsOneWidget);
  });
}
