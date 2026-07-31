import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pt_mate/models/app_models.dart';
import 'package:pt_mate/widgets/aggregate_search_strategy_list.dart';

void main() {
  testWidgets('caps a long strategy list and centers the selection', (
    tester,
  ) async {
    await _pumpList(
      tester,
      configs: _configs(20),
      selectedStrategy: 'strategy-12',
    );

    final viewportFinder = find.byKey(
      const ValueKey('aggregate-search-strategy-list'),
    );
    final selectedItemFinder = find.byKey(
      const ValueKey('aggregate-search-strategy-strategy-12'),
    );
    final viewport = tester.widget<Material>(viewportFinder);

    expect(viewport.type, MaterialType.transparency);
    expect(viewport.clipBehavior, Clip.hardEdge);
    expect(tester.getSize(viewportFinder).height, inInclusiveRange(96, 200));
    expect(
      tester
          .widget<ListView>(find.byType(ListView))
          .controller!
          .position
          .maxScrollExtent,
      greaterThan(0),
    );

    final viewportRect = tester.getRect(viewportFinder);
    final selectedItemRect = tester.getRect(selectedItemFinder);
    expect(
      (selectedItemRect.center.dy - viewportRect.center.dy).abs(),
      lessThan(1),
    );
  });

  testWidgets('updates and highlights the selected strategy', (tester) async {
    String? selectedStrategy = 'strategy-0';
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => AggregateSearchStrategyList(
              configs: _configs(3),
              selectedStrategy: selectedStrategy,
              onChanged: (value) {
                setState(() {
                  selectedStrategy = value;
                });
              },
            ),
          ),
        ),
      ),
    );

    await tester.tap(
      find.byKey(const ValueKey('aggregate-search-strategy-strategy-2')),
    );
    await tester.pump();

    expect(selectedStrategy, 'strategy-2');
    expect(
      tester
          .widget<ListTile>(
            find.byKey(const ValueKey('aggregate-search-strategy-strategy-2')),
          )
          .selected,
      isTrue,
    );
  });

  testWidgets('handles empty configs and long names', (tester) async {
    await _pumpList(tester, configs: const [], selectedStrategy: null);
    expect(find.text('暂无可用策略'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('aggregate-search-strategy-list')),
      findsNothing,
    );

    const longName = '这是一个非常非常长且需要在有限宽度内省略显示的聚合搜索策略名称';
    await _pumpList(
      tester,
      configs: const [AggregateSearchConfig(id: 'long', name: longName)],
      selectedStrategy: 'long',
    );

    final name = tester.widget<Text>(find.text(longName));
    expect(name.maxLines, 1);
    expect(name.overflow, TextOverflow.ellipsis);
  });
}

List<AggregateSearchConfig> _configs(int count) {
  return List.generate(
    count,
    (index) => AggregateSearchConfig(id: 'strategy-$index', name: '策略 $index'),
  );
}

Future<void> _pumpList(
  WidgetTester tester, {
  required List<AggregateSearchConfig> configs,
  required String? selectedStrategy,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: AggregateSearchStrategyList(
          configs: configs,
          selectedStrategy: selectedStrategy,
          onChanged: (_) {},
        ),
      ),
    ),
  );
  await tester.pump();
}
