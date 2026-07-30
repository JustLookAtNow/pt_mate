import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pt_mate/models/app_models.dart';
import 'package:pt_mate/widgets/category_filter_dialog.dart';

void main() {
  testWidgets('centers the selected category inside a clipped Material', (
    tester,
  ) async {
    await _openDialog(
      tester,
      categories: _categories(20),
      selectedCategoryIndex: 12,
    );

    final viewportFinder = find.byKey(const ValueKey('category-list-viewport'));
    final selectedItemFinder = find.byKey(const ValueKey('category-item-12'));
    final viewport = tester.widget<Material>(viewportFinder);

    expect(viewport.type, MaterialType.transparency);
    expect(viewport.clipBehavior, Clip.hardEdge);
    expect(
      find.ancestor(of: selectedItemFinder, matching: viewportFinder),
      findsOneWidget,
    );

    final viewportRect = tester.getRect(viewportFinder);
    final selectedItemRect = tester.getRect(selectedItemFinder);
    expect(
      (selectedItemRect.center.dy - viewportRect.center.dy).abs(),
      lessThan(1.0),
    );
  });

  testWidgets('keeps a selected category at the scroll boundaries visible', (
    tester,
  ) async {
    await _openDialog(
      tester,
      categories: _categories(20),
      selectedCategoryIndex: 19,
    );

    final viewportRect = tester.getRect(
      find.byKey(const ValueKey('category-list-viewport')),
    );
    final selectedItemRect = tester.getRect(
      find.byKey(const ValueKey('category-item-19')),
    );

    expect(selectedItemRect.top, greaterThanOrEqualTo(viewportRect.top));
    expect(selectedItemRect.bottom, lessThanOrEqualTo(viewportRect.bottom));
  });

  testWidgets('recenters after the keyboard shrinks the list viewport', (
    tester,
  ) async {
    addTearDown(tester.view.resetViewInsets);
    await _openDialog(
      tester,
      categories: _categories(20),
      selectedCategoryIndex: 12,
    );

    tester.view.viewInsets = const FakeViewPadding(bottom: 350);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();

    final viewportRect = tester.getRect(
      find.byKey(const ValueKey('category-list-viewport')),
    );
    final selectedItemRect = tester.getRect(
      find.byKey(const ValueKey('category-item-12')),
    );
    expect(
      (selectedItemRect.center.dy - viewportRect.center.dy).abs(),
      lessThan(1.0),
    );
  });

  testWidgets('does not scroll a short category list', (tester) async {
    await _openDialog(
      tester,
      categories: _categories(3),
      selectedCategoryIndex: 1,
    );

    final shortList = tester.widget<ListView>(find.byType(ListView));
    expect(shortList.controller!.offset, 0);
    expect(
      tester
          .widget<ListTile>(find.byKey(const ValueKey('category-item-1')))
          .selected,
      isTrue,
    );
  });

  testWidgets('handles an invalid category selection', (tester) async {
    await _openDialog(
      tester,
      categories: _categories(3),
      selectedCategoryIndex: 99,
    );

    expect(tester.takeException(), isNull);
    expect(
      tester.widget<ListView>(find.byType(ListView)).controller!.offset,
      0,
    );
    for (var index = 0; index < 3; index++) {
      expect(
        tester
            .widget<ListTile>(find.byKey(ValueKey('category-item-$index')))
            .selected,
        isFalse,
      );
    }
  });

  testWidgets('shows the empty state without a category viewport', (
    tester,
  ) async {
    await _openDialog(tester, categories: const [], selectedCategoryIndex: -1);

    expect(find.text('暂无可用分类'), findsOneWidget);
    expect(find.byKey(const ValueKey('category-list-viewport')), findsNothing);
  });

  testWidgets('returns the updated category and keyword', (tester) async {
    Map<String, dynamic>? result;
    await _openDialog(
      tester,
      categories: _categories(8),
      selectedCategoryIndex: 2,
      keyword: '旧关键词',
      onResult: (value) => result = value,
    );

    await tester.enterText(
      find.byKey(const ValueKey('search-keyword-field')),
      '新关键词',
    );
    await tester.drag(
      find.byKey(const ValueKey('category-list-viewport')),
      const Offset(0, -150),
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('category-item-5')));
    await tester.pump();
    await tester.tap(find.text('确定'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(result, {'categoryIndex': 5, 'keyword': '新关键词'});
  });
}

List<SearchCategoryConfig> _categories(int count) {
  return List.generate(
    count,
    (index) => SearchCategoryConfig(
      id: 'category-$index',
      displayName: '分类 $index',
      parameters: '{}',
    ),
  );
}

Future<void> _openDialog(
  WidgetTester tester, {
  required List<SearchCategoryConfig> categories,
  required int selectedCategoryIndex,
  String keyword = '',
  ValueChanged<Map<String, dynamic>?>? onResult,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) {
            return TextButton(
              onPressed: () async {
                final result = await showDialog<Map<String, dynamic>>(
                  context: context,
                  builder: (_) => CategoryFilterDialog(
                    categories: categories,
                    selectedCategoryIndex: selectedCategoryIndex,
                    keyword: keyword,
                  ),
                );
                onResult?.call(result);
              },
              child: const Text('打开弹窗'),
            );
          },
        ),
      ),
    ),
  );

  await tester.tap(find.text('打开弹窗'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump();
}
