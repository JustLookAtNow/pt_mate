import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pt_mate/widgets/list_index_scroller.dart';

void main() {
  testWidgets('scrollToIndex 将远端条目滚动到可见区域', (tester) async {
    final controller = ScrollController();
    final listKey = GlobalKey();
    final scroller = ListIndexScroller(
      controller: controller,
      listViewKey: listKey,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView.builder(
            key: listKey,
            controller: controller,
            itemCount: 100,
            itemBuilder: (context, index) => MetaData(
              metaData: index,
              behavior: HitTestBehavior.translucent,
              child: SizedBox(
                height: 60,
                child: Text('Item $index', key: ValueKey('item-$index')),
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('Item 50', skipOffstage: false), findsNothing);

    final future = scroller.scrollToIndex(50);
    // 驱动帧调度，让 endOfFrame 能完成
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    await future;
    await tester.pumpAndSettle();

    expect(find.text('Item 50', skipOffstage: false), findsOneWidget);

    controller.dispose();
  });

  testWidgets('目标已在视口内时平滑滚动对齐顶部', (tester) async {
    final controller = ScrollController();
    final listKey = GlobalKey();
    final scroller = ListIndexScroller(
      controller: controller,
      listViewKey: listKey,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 300,
            child: ListView.builder(
              key: listKey,
              controller: controller,
              itemCount: 50,
              itemBuilder: (context, index) => MetaData(
                metaData: index,
                behavior: HitTestBehavior.translucent,
                child: SizedBox(height: 60, child: Text('Item $index')),
              ),
            ),
          ),
        ),
      ),
    );

    final future = scroller.scrollToIndex(3);
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    await future;
    await tester.pumpAndSettle();

    // 3 * 60 - 300 * 0.1 = 150
    expect(controller.offset, closeTo(150, 1));

    controller.dispose();
  });
}
