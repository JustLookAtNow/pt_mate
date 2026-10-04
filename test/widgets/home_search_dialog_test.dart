import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pt_mate/models/app_models.dart';
import 'package:pt_mate/models/home_search_request.dart';
import 'package:pt_mate/widgets/home_search_dialog.dart';

void main() {
  testWidgets('submits the current site category and keyword', (tester) async {
    HomeSearchRequest? result;
    await _openDialog(tester, onResult: (value) => result = value);

    await tester.enterText(
      find.byKey(const ValueKey('search-keyword-field')),
      '沙丘',
    );
    await tester.tap(find.byKey(const ValueKey('category-item-2')));
    await tester.tap(find.byKey(const ValueKey('home-search-submit-button')));
    await tester.pumpAndSettle();

    expect(result?.mode, HomeSearchMode.currentSite);
    expect(result?.keyword, '沙丘');
    expect(result?.categoryIndex, 2);
    expect(result?.strategyId, isNull);
  });

  testWidgets('mode and strategy changes stay in the draft until submission', (
    tester,
  ) async {
    var completed = false;
    HomeSearchRequest? result;
    await _openDialog(
      tester,
      keyword: '旧关键词',
      onResult: (value) {
        completed = true;
        result = value;
      },
    );

    await tester.enterText(
      find.byKey(const ValueKey('search-keyword-field')),
      '新关键词',
    );
    await tester.tap(find.text('聚合搜索'));
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey('aggregate-search-strategy-movies')),
    );
    await tester.pump();

    expect(completed, isFalse);
    expect(find.byKey(const ValueKey('home-search-dialog')), findsOneWidget);
    expect(find.text('新关键词'), findsOneWidget);
    expect(find.byKey(const ValueKey('category-list-viewport')), findsNothing);
    expect(find.text('聚合搜索设置'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('home-search-submit-button')));
    await tester.pumpAndSettle();
    expect(result?.mode, HomeSearchMode.aggregate);
    expect(result?.keyword, '新关键词');
    expect(result?.strategyId, 'movies');
    expect(result?.categoryIndex, isNull);
  });

  testWidgets('cancel discards mode, category and strategy changes', (
    tester,
  ) async {
    var completed = false;
    HomeSearchRequest? result;
    await _openDialog(
      tester,
      onResult: (value) {
        completed = true;
        result = value;
      },
    );
    await tester.tap(find.byKey(const ValueKey('category-item-2')));
    await tester.tap(find.text('聚合搜索'));
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey('aggregate-search-strategy-movies')),
    );
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    expect(completed, isTrue);
    expect(result, isNull);
  });

  testWidgets('preserves category selection while switching modes', (
    tester,
  ) async {
    HomeSearchRequest? result;
    await _openDialog(tester, onResult: (value) => result = value);
    await tester.tap(find.byKey(const ValueKey('category-item-2')));
    await tester.tap(find.text('聚合搜索'));
    await tester.pump();
    await tester.tap(find.text('当前站点'));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('home-search-submit-button')));
    await tester.pumpAndSettle();

    expect(result?.mode, HomeSearchMode.currentSite);
    expect(result?.categoryIndex, 2);
  });

  testWidgets('keyboard search submits empty aggregate keywords', (
    tester,
  ) async {
    HomeSearchRequest? result;
    await _openDialog(
      tester,
      initialMode: HomeSearchMode.aggregate,
      onResult: (value) => result = value,
    );
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();

    expect(result?.mode, HomeSearchMode.aggregate);
    expect(result?.keyword, '');
    expect(result?.strategyId, 'all-sites');
  });

  testWidgets('honors an existing strategy before the all sites default', (
    tester,
  ) async {
    await _openDialog(
      tester,
      initialMode: HomeSearchMode.aggregate,
      selectedStrategy: 'movies',
    );
    expect(
      tester
          .widget<ListTile>(
            find.byKey(const ValueKey('aggregate-search-strategy-movies')),
          )
          .selected,
      isTrue,
    );
  });

  testWidgets(
    'inactive strategies cannot submit and settings refresh the list',
    (tester) async {
      HomeSearchRequest? result;
      var settingsOpened = 0;
      await _openDialog(
        tester,
        initialMode: HomeSearchMode.aggregate,
        searchConfigs: const [
          AggregateSearchConfig(id: 'inactive', name: '已停用', isActive: false),
        ],
        selectedStrategy: 'inactive',
        onConfigureAggregate: () async {
          settingsOpened++;
          return _configs;
        },
        onResult: (value) => result = value,
      );

      expect(find.text('暂无可用策略'), findsOneWidget);
      expect(find.text('已停用'), findsNothing);
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('home-search-submit-button')),
            )
            .onPressed,
        isNull,
      );
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pump();
      expect(find.byKey(const ValueKey('home-search-dialog')), findsOneWidget);

      await tester.tap(
        find.byKey(const ValueKey('aggregate-search-settings-button')),
      );
      await tester.pumpAndSettle();
      expect(settingsOpened, 1);
      expect(find.text('暂无可用策略'), findsNothing);
      expect(
        tester
            .widget<ListTile>(
              find.byKey(const ValueKey('aggregate-search-strategy-all-sites')),
            )
            .selected,
        isTrue,
      );
      await tester.tap(find.byKey(const ValueKey('home-search-submit-button')));
      await tester.pumpAndSettle();
      expect(result?.strategyId, 'all-sites');
    },
  );

  testWidgets('unsupported current site search still allows aggregate search', (
    tester,
  ) async {
    HomeSearchRequest? result;
    await _openDialog(
      tester,
      supportsCurrentSiteSearch: false,
      onResult: (value) => result = value,
    );
    expect(find.text('当前站点不支持搜索，可切换到聚合搜索'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('home-search-submit-button')),
          )
          .onPressed,
      isNull,
    );
    await tester.tap(find.text('聚合搜索'));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('home-search-submit-button')));
    await tester.pumpAndSettle();
    expect(result?.mode, HomeSearchMode.aggregate);
  });

  testWidgets('omits unsupported categories from current site requests', (
    tester,
  ) async {
    HomeSearchRequest? result;
    await _openDialog(
      tester,
      supportsCategories: false,
      onResult: (value) => result = value,
    );
    expect(find.text('选择分类'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('home-search-submit-button')));
    await tester.pumpAndSettle();
    expect(result?.categoryIndex, isNull);
  });

  testWidgets(
    'keeps a long selection visible on a narrow screen with keyboard',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewInsets);
      await _openDialog(
        tester,
        categories: List.generate(
          20,
          (index) => SearchCategoryConfig(
            id: '$index',
            displayName: '这是一个很长的分类名称 $index',
            parameters: '{}',
          ),
        ),
        selectedCategoryIndex: 12,
      );
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      final viewport = tester.getRect(
        find.byKey(const ValueKey('category-list-viewport')),
      );
      final selection = tester.getRect(
        find.byKey(const ValueKey('category-item-12')),
      );
      expect((viewport.center.dy - selection.center.dy).abs(), lessThan(1));
      expect(
        tester
            .getRect(find.byKey(const ValueKey('home-search-submit-button')))
            .bottom,
        lessThanOrEqualTo(340),
      );
    },
  );
}

const _configs = [
  AggregateSearchConfig(id: 'movies', name: '电影'),
  AggregateSearchConfig(id: 'all-sites', name: '所有站点', type: 'all'),
];

const _categories = [
  SearchCategoryConfig(id: 'all', displayName: '全部', parameters: '{}'),
  SearchCategoryConfig(id: 'movies', displayName: '电影', parameters: '{}'),
  SearchCategoryConfig(id: 'series', displayName: '剧集', parameters: '{}'),
];

Future<void> _openDialog(
  WidgetTester tester, {
  List<SearchCategoryConfig> categories = _categories,
  int selectedCategoryIndex = 0,
  String keyword = '',
  HomeSearchMode initialMode = HomeSearchMode.currentSite,
  List<AggregateSearchConfig> searchConfigs = _configs,
  String? selectedStrategy,
  bool supportsCurrentSiteSearch = true,
  bool supportsCategories = true,
  Future<List<AggregateSearchConfig>?> Function()? onConfigureAggregate,
  ValueChanged<HomeSearchRequest?>? onResult,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              final result = await showDialog<HomeSearchRequest>(
                context: context,
                builder: (_) => HomeSearchDialog(
                  categories: categories,
                  selectedCategoryIndex: selectedCategoryIndex,
                  keyword: keyword,
                  initialMode: initialMode,
                  searchConfigs: searchConfigs,
                  selectedStrategy: selectedStrategy,
                  supportsCurrentSiteSearch: supportsCurrentSiteSearch,
                  supportsCategories: supportsCategories,
                  onConfigureAggregate: onConfigureAggregate,
                ),
              );
              onResult?.call(result);
            },
            child: const Text('打开弹窗'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('打开弹窗'));
  await tester.pumpAndSettle();
}
