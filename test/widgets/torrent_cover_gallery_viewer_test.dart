import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:pt_mate/widgets/torrent_cover_gallery_viewer.dart';

Uint8List _png(Color color) {
  final image = img.Image(width: 240, height: 320);
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

  Widget buildViewer({
    int initialIndex = 0,
    ValueChanged<int>? onPageChanged,
    int Function()? itemCount,
    bool Function()? hasMore,
    Future<void> Function()? onLoadMore,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: TorrentCoverGalleryViewer(
          itemCount: itemCount ?? () => images.length,
          initialIndex: initialIndex,
          loadCover: loadCover,
          titleFor: (p) => 'Title $p',
          onPageChanged: onPageChanged,
          hasMore: hasMore,
          onLoadMore: onLoadMore,
        ),
      ),
    );
  }

  /// 以对话框形式打开查看器，用于验证“保持打开/点击关闭”等弹窗级行为。
  Future<void> pumpViewerInDialog(
    WidgetTester tester, {
    int initialIndex = 0,
    ValueChanged<int>? onPageChanged,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  barrierColor: Colors.black.withValues(alpha: 0.7),
                  builder: (_) => TorrentCoverGalleryViewer(
                    itemCount: () => images.length,
                    initialIndex: initialIndex,
                    loadCover: loadCover,
                    titleFor: (p) => 'Title $p',
                    onPageChanged: onPageChanged,
                  ),
                ),
                child: const Text('打开'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    // 图片解码在测试时钟之外完成，等待后再发送多指事件，确保命中图片。
    await tester.runAsync(() async {
      await precacheImage(
        MemoryImage(images[initialIndex]),
        tester.element(find.byType(TorrentCoverGalleryViewer)),
      );
    });
    await tester.pumpAndSettle();
  }

  TransformationController controllerFor(WidgetTester tester) => tester
      .widget<InteractiveViewer>(find.byType(InteractiveViewer))
      .transformationController!;

  Future<void> pinch(
    WidgetTester tester, {
    double startSpread = 30,
    double endSpread = 90,
  }) async {
    final center = tester.getCenter(find.byType(InteractiveViewer));
    final first = await tester.startGesture(
      center - Offset(0, startSpread),
      pointer: 1,
    );
    final second = await tester.startGesture(
      center + Offset(0, startSpread),
      pointer: 2,
    );
    for (var step = 1; step <= 6; step++) {
      final spread = startSpread + (endSpread - startSpread) * step / 6;
      await first.moveTo(center - Offset(0, spread));
      await second.moveTo(center + Offset(0, spread));
      await tester.pump(const Duration(milliseconds: 20));
    }
    await first.up();
    await second.up();
    await tester.pumpAndSettle();
  }

  for (final zoomIn in [true, false]) {
    testWidgets('初始状态直接双指${zoomIn ? '放大' : '缩小'}且不翻页或关闭', (tester) async {
      final changes = <int>[];
      await pumpViewerInDialog(tester, onPageChanged: changes.add);

      await pinch(
        tester,
        startSpread: zoomIn ? 30 : 90,
        endSpread: zoomIn ? 90 : 30,
      );

      expect(
        controllerFor(tester).value.getMaxScaleOnAxis(),
        zoomIn ? greaterThan(1.0) : lessThan(1.0),
      );
      expect(changes, isEmpty);
      expect(find.text('Title 0  (1 / 3)'), findsOneWidget);
      expect(find.byType(TorrentCoverGalleryViewer), findsOneWidget);
    });
  }

  testWidgets('单指先滑动再加入第二指可缩放且取消本次翻页', (tester) async {
    final changes = <int>[];
    await pumpViewerInDialog(tester, onPageChanged: changes.add);
    final center = tester.getCenter(find.byType(InteractiveViewer));
    final first = await tester.startGesture(center, pointer: 1);
    await first.moveBy(const Offset(0, -80));
    await tester.pump();
    expect(controllerFor(tester).value, Matrix4.identity());

    final second = await tester.startGesture(
      center + const Offset(0, 30),
      pointer: 2,
    );
    await first.moveBy(const Offset(0, -20));
    await second.moveBy(const Offset(0, 20));
    await tester.pump();
    await first.moveBy(const Offset(0, -20));
    await second.moveBy(const Offset(0, 20));
    await tester.pump();
    expect(controllerFor(tester).value.getMaxScaleOnAxis(), greaterThan(1));

    await second.up();
    await first.up();
    await tester.pumpAndSettle();
    expect(changes, isEmpty);
    expect(find.byType(TorrentCoverGalleryViewer), findsOneWidget);
  });

  testWidgets('双指手势剩余单指继续移动不翻页，全部抬起后恢复翻页', (tester) async {
    final changes = <int>[];
    await pumpViewerInDialog(tester, onPageChanged: changes.add);
    final center = tester.getCenter(find.byType(InteractiveViewer));
    final first = await tester.startGesture(
      center - const Offset(0, 30),
      pointer: 1,
    );
    final second = await tester.startGesture(
      center + const Offset(0, 30),
      pointer: 2,
    );
    await first.moveBy(const Offset(0, -30));
    await second.moveBy(const Offset(0, 30));
    await tester.pump();
    await first.moveBy(const Offset(0, -20));
    await second.moveBy(const Offset(0, 20));
    await tester.pump();
    expect(controllerFor(tester).value.getMaxScaleOnAxis(), greaterThan(1));
    await second.up();

    // 即使剩下一指时已复位，也不能把同一手势误判为翻页。
    controllerFor(tester).value = Matrix4.identity();
    await tester.pump();
    await first.moveBy(const Offset(0, -120));
    await first.up();
    await tester.pumpAndSettle();
    expect(changes, isEmpty);

    await tester.drag(find.byType(InteractiveViewer), const Offset(0, -120));
    await tester.pumpAndSettle();
    expect(changes, [1]);
  });

  testWidgets('双指放大后可平移，双击复位后恢复单指翻页', (tester) async {
    final changes = <int>[];
    await pumpViewerInDialog(tester, onPageChanged: changes.add);
    await pinch(tester);
    final controller = controllerFor(tester);
    final before = controller.value.getTranslation().y;

    await tester.drag(find.byType(InteractiveViewer), const Offset(0, -80));
    await tester.pumpAndSettle();
    expect(controller.value.getTranslation().y, isNot(before));
    expect(changes, isEmpty);

    final center = tester.getCenter(find.byType(InteractiveViewer));
    await tester.tapAt(center);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tapAt(center);
    await tester.pumpAndSettle();
    expect(controller.value, Matrix4.identity());

    await tester.drag(find.byType(InteractiveViewer), const Offset(0, -120));
    await tester.pumpAndSettle();
    expect(changes, [1]);
  });

  testWidgets('双指放大后按钮切图会复位并恢复单指翻页', (tester) async {
    final changes = <int>[];
    await pumpViewerInDialog(tester, onPageChanged: changes.add);
    await pinch(tester);
    expect(controllerFor(tester).value.getMaxScaleOnAxis(), greaterThan(1));

    await tester.tap(find.byTooltip('下一个'));
    await tester.pumpAndSettle();
    expect(controllerFor(tester).value, Matrix4.identity());

    await tester.drag(find.byType(InteractiveViewer), const Offset(0, -120));
    await tester.pumpAndSettle();
    expect(changes, [1, 2]);
  });

  testWidgets('取消单指滑动不翻页，下一次滑动仍可翻页', (tester) async {
    final changes = <int>[];
    await pumpViewerInDialog(tester, onPageChanged: changes.add);
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(InteractiveViewer)),
    );
    await gesture.moveBy(const Offset(0, -100));
    await gesture.cancel();
    await tester.pumpAndSettle();
    expect(changes, isEmpty);

    await tester.drag(find.byType(InteractiveViewer), const Offset(0, -120));
    await tester.pumpAndSettle();
    expect(changes, [1]);
  });

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

  testWidgets('未放大时向上滑动翻到下一张并触发回调', (tester) async {
    var changed = -1;
    await tester.pumpWidget(buildViewer(onPageChanged: (p) => changed = p));
    await tester.pumpAndSettle();

    await tester.drag(find.byType(InteractiveViewer), const Offset(0, -120));
    await tester.pumpAndSettle();

    expect(changed, 1);
    expect(find.text('Title 1  (2 / 3)'), findsOneWidget);
  });

  testWidgets('未放大时向下滑动翻回上一张', (tester) async {
    var changed = -1;
    await tester.pumpWidget(
      buildViewer(initialIndex: 1, onPageChanged: (p) => changed = p),
    );
    await tester.pumpAndSettle();

    await tester.drag(find.byType(InteractiveViewer), const Offset(0, 120));
    await tester.pumpAndSettle();

    expect(changed, 0);
    expect(find.text('Title 0  (1 / 3)'), findsOneWidget);
  });

  testWidgets('水平拖动不翻页', (tester) async {
    var changed = -1;
    await tester.pumpWidget(buildViewer(onPageChanged: (p) => changed = p));
    await tester.pumpAndSettle();

    await tester.drag(find.byType(InteractiveViewer), const Offset(-200, 0));
    await tester.pumpAndSettle();

    expect(changed, -1);
    expect(find.text('Title 0  (1 / 3)'), findsOneWidget);
  });

  testWidgets('小幅垂直拖动不翻页', (tester) async {
    var changed = -1;
    await tester.pumpWidget(buildViewer(onPageChanged: (p) => changed = p));
    await tester.pumpAndSettle();

    await tester.timedDrag(
      find.byType(InteractiveViewer),
      const Offset(0, -20),
      const Duration(milliseconds: 400),
    );
    await tester.pumpAndSettle();

    expect(changed, -1);
    expect(find.text('Title 0  (1 / 3)'), findsOneWidget);
  });

  testWidgets('第一张向下滑动不翻页也不关闭查看器', (tester) async {
    var changed = -1;
    await pumpViewerInDialog(tester, onPageChanged: (p) => changed = p);

    await tester.drag(find.byType(InteractiveViewer), const Offset(0, 120));
    await tester.pumpAndSettle();

    expect(changed, -1);
    expect(find.text('Title 0  (1 / 3)'), findsOneWidget);
    expect(find.byType(TorrentCoverGalleryViewer), findsOneWidget);
  });

  testWidgets('点击空白处仍可关闭查看器', (tester) async {
    await pumpViewerInDialog(tester);

    await tester.tapAt(const Offset(20, 300));
    await tester.pumpAndSettle();

    expect(find.byType(TorrentCoverGalleryViewer), findsNothing);
  });

  testWidgets('末尾向上滑动触发加载下一页', (tester) async {
    var count = 2;
    var loadMoreCalls = 0;
    Future<void> loadMore() async {
      loadMoreCalls++;
      await Future<void>.delayed(const Duration(milliseconds: 10));
      count = 3;
    }

    await tester.pumpWidget(
      buildViewer(
        initialIndex: 1,
        itemCount: () => count,
        hasMore: () => count < 3,
        onLoadMore: loadMore,
      ),
    );
    await tester.pumpAndSettle();

    await tester.drag(find.byType(InteractiveViewer), const Offset(0, -120));
    await tester.pumpAndSettle();

    expect(loadMoreCalls, 1);
    expect(find.text('Title 2  (3 / 3)'), findsOneWidget);
  });

  testWidgets('放大后拖动只平移图片，重置缩放后恢复滑动翻页', (tester) async {
    var changed = -1;
    await tester.pumpWidget(buildViewer(onPageChanged: (p) => changed = p));
    await tester.pumpAndSettle();

    final controller = tester
        .widget<InteractiveViewer>(find.byType(InteractiveViewer))
        .transformationController!;
    controller.value = Matrix4.diagonal3Values(2.0, 2.0, 1.0);
    await tester.pump();

    final translationBefore = controller.value.getTranslation().y;
    await tester.drag(find.byType(InteractiveViewer), const Offset(0, -60));
    await tester.pumpAndSettle();

    expect(changed, -1);
    expect(controller.value.getTranslation().y, isNot(translationBefore));

    controller.value = Matrix4.identity();
    await tester.pump();

    await tester.drag(find.byType(InteractiveViewer), const Offset(0, -120));
    await tester.pumpAndSettle();

    expect(changed, 1);
    expect(find.text('Title 1  (2 / 3)'), findsOneWidget);
  });

  testWidgets('加载失败时显示错误并可继续翻页', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TorrentCoverGalleryViewer(
            itemCount: () => 2,
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

  testWidgets('末尾且 hasMore 为 true 时右侧按钮可见并触发加载', (tester) async {
    var count = 2;
    var loadMoreCalls = 0;
    Future<void> loadMore() async {
      loadMoreCalls++;
      await Future<void>.delayed(const Duration(milliseconds: 10));
      count = 3;
    }

    await tester.pumpWidget(
      buildViewer(
        initialIndex: 1,
        itemCount: () => count,
        hasMore: () => count < 3,
        onLoadMore: loadMore,
      ),
    );
    await tester.pumpAndSettle();

    // 已是已知末尾，但宿主还有更多数据，右侧按钮仍显示
    expect(find.byTooltip('下一个'), findsOneWidget);

    await tester.tap(find.byTooltip('下一个'));
    await tester.pumpAndSettle();

    expect(loadMoreCalls, 1);
    expect(find.text('Title 2  (3 / 3)'), findsOneWidget);
    // 没有更多数据后按钮隐藏
    expect(find.byTooltip('下一个'), findsNothing);
  });

  testWidgets('onLoadMore 完成后无新数据时停留在原位', (tester) async {
    var loadMoreCalls = 0;
    await tester.pumpWidget(
      buildViewer(
        initialIndex: 1,
        itemCount: () => 2,
        hasMore: () => loadMoreCalls == 0,
        onLoadMore: () async {
          loadMoreCalls++;
        },
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('下一个'));
    await tester.pumpAndSettle();

    expect(loadMoreCalls, 1);
    expect(find.text('Title 1  (2 / 2)'), findsOneWidget);
    expect(find.byTooltip('下一个'), findsNothing);
  });
}
