import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:pt_mate/app.dart';
import 'package:pt_mate/models/app_models.dart';
import 'package:pt_mate/providers/aggregate_search_provider.dart';
import 'package:pt_mate/services/aggregate_search_service.dart';
import 'package:pt_mate/services/settings/display_settings_manager.dart';
import 'package:pt_mate/services/storage/storage_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({
      StorageKeys.aggregateSearchSettings: jsonEncode(
        AggregateSearchSettings(
          searchConfigs: const [
            AggregateSearchConfig(id: 'all-sites', name: '所有站点', type: 'all'),
          ],
        ).toJson(),
      ),
    });
    StorageService.instance.resetForTest();
  });

  tearDown(() {
    StorageService.instance.resetForTest();
  });

  testWidgets('站点切换后忽略旧站点延迟返回的内容', (tester) async {
    final siteA = _site('site-a', '站点 A');
    final siteB = _site('site-b', '站点 B');
    final appState = _FakeAppState(siteA);
    final search = _FakeHomeSearchExecutor();

    await _pumpHome(tester, appState, search);
    expect(search.invocations, hasLength(1));
    expect(search.invocations.single.siteConfig.id, siteA.id);

    appState.selectSite(siteB);
    await _pumpUntil(tester, () => search.invocations.length == 2);
    expect(search.invocations.last.siteConfig.id, siteB.id);

    search.invocations.last.complete(items: [_item('new', '新站点内容')]);
    await tester.pump();
    await tester.pump();
    expect(find.text('新站点内容'), findsOneWidget);

    search.invocations.first.complete(items: [_item('old', '旧站点内容')]);
    await tester.pump();
    await tester.pump();

    expect(find.text('新站点内容'), findsOneWidget);
    expect(find.text('旧站点内容'), findsNothing);
  });

  testWidgets('分类切换后旧请求失败不会覆盖结果或提前结束加载', (tester) async {
    final appState = _FakeAppState(_site('site-a', '站点 A'));
    final search = _FakeHomeSearchExecutor();

    await _pumpHome(tester, appState, search);
    expect(search.invocations, hasLength(1));
    expect(search.invocations.first.additionalParams, {'category': 'first'});

    await tester.tap(find.byKey(const ValueKey('home-search-fab')));
    await _pumpUntil(
      tester,
      () => find
          .byKey(const ValueKey('home-search-dialog'))
          .evaluate()
          .isNotEmpty,
    );
    await tester.tap(find.byKey(const ValueKey('category-item-1')));
    await tester.tap(find.widgetWithText(FilledButton, '搜索'));
    await _pumpUntil(tester, () => search.invocations.length == 2);

    expect(search.invocations.last.additionalParams, {'category': 'second'});

    search.invocations.first.completeError(StateError('旧请求失败'));
    await tester.pump();
    await tester.pump();

    expect(find.textContaining('旧请求失败'), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);

    search.invocations.last.complete(items: [_item('second', '第二分类内容')]);
    await tester.pump();
    await tester.pump();

    expect(find.text('第二分类内容'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });

  testWidgets('分页请求固定使用下一页页码并追加到当前结果', (tester) async {
    final appState = _FakeAppState(_site('site-a', '站点 A'));
    final search = _FakeHomeSearchExecutor();

    await _pumpHome(tester, appState, search);
    final firstPageItems = List.generate(
      30,
      (index) => _item('page-1-$index', '第一页内容 $index'),
    );
    search.invocations.single.complete(
      items: firstPageItems,
      totalPages: 2,
      total: 31,
    );
    await tester.pump();
    await tester.pump();

    final torrentList = find.byWidgetPredicate(
      (widget) => widget is ListView && widget.controller != null,
    );
    expect(torrentList, findsOneWidget);
    await tester.drag(torrentList, const Offset(0, -5000));
    await _pumpUntil(tester, () => search.invocations.length == 2);

    expect(search.invocations.last.pageNumber, 2);
    search.invocations.last.complete(
      items: [_item('page-2', '第二页内容')],
      totalPages: 2,
      total: 31,
    );
    await tester.pump();
    await tester.pump();

    await tester.drag(torrentList, const Offset(0, 5000));
    await tester.pump();
    expect(find.text('第一页内容 0'), findsOneWidget);
    await tester.drag(torrentList, const Offset(0, -5000));
    await tester.pump();
    expect(find.text('第二页内容'), findsOneWidget);
  });
  testWidgets('选择聚合模式和取消面板不会发起搜索或改变首页', (tester) async {
    final appState = _FakeAppState(_site('site-a', '站点 A'));
    final search = _FakeHomeSearchExecutor();
    final aggregate = _FakeAggregateSearchService();
    await _pumpHome(
      tester,
      appState,
      search,
      aggregateSearchService: aggregate,
    );
    search.invocations.single.complete(items: [_item('home', '原站点内容')]);
    await tester.pumpAndSettle();

    await _openAggregateDialog(tester);
    await tester.enterText(
      find.byKey(const ValueKey('search-keyword-field')),
      '沙丘',
    );
    expect(aggregate.invocations, isEmpty);
    await tester.tap(find.widgetWithText(TextButton, '取消'));
    await tester.pumpAndSettle();

    expect(find.text('原站点内容'), findsOneWidget);
    expect(search.invocations, hasLength(1));
    expect(aggregate.invocations, isEmpty);
    await tester.tap(find.byKey(const ValueKey('home-search-fab')));
    await tester.pumpAndSettle();
    expect(find.text('选择分类'), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('search-keyword-field')))
          .controller!
          .text,
      isEmpty,
    );
  });

  testWidgets('聚合结果退出后恢复当前站点滚动位置和分页状态', (tester) async {
    final site = _site('site-a', '站点 A');
    final appState = _FakeAppState(site);
    final search = _FakeHomeSearchExecutor();
    final aggregate = _FakeAggregateSearchService();
    await _pumpHome(
      tester,
      appState,
      search,
      aggregateSearchService: aggregate,
    );
    search.invocations.single.complete(
      items: List.generate(30, (index) => _item('home-$index', '原内容 $index')),
      totalPages: 2,
      total: 31,
    );
    await tester.pumpAndSettle();
    final list = tester.widget<ListView>(
      find.byWidgetPredicate(
        (widget) => widget is ListView && widget.controller != null,
      ),
    );
    final controller = list.controller!;
    controller.jumpTo(400);
    await tester.pumpAndSettle();
    final offset = controller.offset;

    await _submitAggregate(tester, keyword: '沙丘');
    expect(search.invocations, hasLength(1));
    expect(aggregate.invocations.single.keyword, '沙丘');
    aggregate.invocations.single.complete([
      _aggregateItem('site-b', 'same-id', '聚合结果'),
    ]);
    await _finishNotifications(tester);
    expect(find.text('聚合搜索 - PT Mate'), findsOneWidget);
    expect(find.text('聚合结果'), findsOneWidget);
    expect(find.text('原内容 0'), findsNothing);
    expect(appState.site.id, site.id);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is FloatingActionButton &&
            widget.heroTag == 'home-site-switch-fab',
      ),
      findsNothing,
    );

    await tester.tap(find.text('返回当前站点'));
    await tester.pumpAndSettle();
    expect(find.text('聚合搜索 - PT Mate'), findsNothing);
    expect(controller.offset, closeTo(offset, 0.1));
    expect(search.invocations, hasLength(1));
    controller.jumpTo(controller.position.maxScrollExtent);
    await _pumpUntil(tester, () => search.invocations.length == 2);
    expect(search.invocations.last.pageNumber, 2);
    search.invocations.last.complete(items: [_item('next', '恢复后的第二页')]);
    await tester.pumpAndSettle();
  });

  testWidgets('系统返回先退出聚合多选再恢复当前站点', (tester) async {
    final appState = _FakeAppState(_site('site-a', '站点 A'));
    final search = _FakeHomeSearchExecutor();
    final aggregate = _FakeAggregateSearchService();
    await _pumpHome(
      tester,
      appState,
      search,
      aggregateSearchService: aggregate,
    );
    search.invocations.single.complete(items: [_item('home', '原站点内容')]);
    await tester.pumpAndSettle();
    await _submitAggregate(tester);
    aggregate.invocations.single.complete([
      _aggregateItem('site-b', '1', '聚合条目'),
    ]);
    await _finishNotifications(tester);
    await tester.longPress(find.byKey(const ValueKey('site-b:1')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('home-search-fab')), findsNothing);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('聚合搜索 - PT Mate'), findsOneWidget);
    expect(find.byKey(const ValueKey('home-search-fab')), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('原站点内容'), findsOneWidget);
    expect(search.invocations, hasLength(1));
  });

  testWidgets('退出进行中的聚合搜索后忽略迟到结果和完成通知', (tester) async {
    final appState = _FakeAppState(_site('site-a', '站点 A'));
    final search = _FakeHomeSearchExecutor();
    final aggregate = _FakeAggregateSearchService();
    await _pumpHome(
      tester,
      appState,
      search,
      aggregateSearchService: aggregate,
    );
    search.invocations.single.complete(items: [_item('home', '原站点内容')]);
    await tester.pumpAndSettle();
    await _submitAggregate(tester);
    final invocation = aggregate.invocations.single;
    await tester.tap(find.text('返回当前站点'));
    await tester.pumpAndSettle();
    expect(invocation.cancelToken!.isCancelled, isTrue);
    invocation.onSiteResults?.call([_aggregateItem('site-b', '1', '迟到聚合条目')]);
    invocation.complete([_aggregateItem('site-b', '1', '迟到聚合条目')]);
    await tester.pumpAndSettle();
    expect(find.text('原站点内容'), findsOneWidget);
    expect(find.text('迟到聚合条目'), findsNothing);
    expect(find.textContaining('搜索完成'), findsNothing);
    expect(search.invocations, hasLength(1));
  });

  testWidgets('单站请求尚未返回时仍能重新打开面板并改用聚合搜索', (tester) async {
    final appState = _FakeAppState(_site('site-a', '站点 A'));
    final search = _FakeHomeSearchExecutor();
    final aggregate = _FakeAggregateSearchService();
    await _pumpHome(
      tester,
      appState,
      search,
      aggregateSearchService: aggregate,
    );
    search.invocations.single.complete(items: [_item('home', '原站点内容')]);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('home-search-fab')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('search-keyword-field')),
      '慢查询',
    );
    await tester.tap(find.byKey(const ValueKey('home-search-submit-button')));
    await _pumpUntil(tester, () => search.invocations.length == 2);
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.byKey(const ValueKey('home-search-fab')));
    await _pumpUntil(
      tester,
      () => find
          .byKey(const ValueKey('home-search-dialog'))
          .evaluate()
          .isNotEmpty,
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('聚合搜索'));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('home-search-submit-button')));
    await _pumpUntil(tester, () => aggregate.invocations.isNotEmpty);

    search.invocations.last.complete(items: [_item('slow', '单站后台结果')]);
    aggregate.invocations.single.complete([
      _aggregateItem('site-b', '1', '聚合结果'),
    ]);
    await _finishNotifications(tester);
    expect(find.text('聚合结果'), findsOneWidget);
    expect(find.text('单站后台结果'), findsNothing);
  });

  testWidgets('不支持单站搜索时仍可从首页进入聚合搜索', (tester) async {
    final appState = _FakeAppState(
      const SiteConfig(
        id: 'browse-only',
        name: '不支持搜索的站点',
        baseUrl: 'https://browse-only.example',
        features: SiteFeatures(supportTorrentSearch: false),
      ),
    );
    final search = _FakeHomeSearchExecutor();
    final aggregate = _FakeAggregateSearchService();
    await _pumpHome(
      tester,
      appState,
      search,
      aggregateSearchService: aggregate,
      expectInitialSearch: false,
    );
    expect(find.byKey(const ValueKey('home-search-fab')), findsOneWidget);
    await _submitAggregate(tester);
    aggregate.invocations.single.complete([
      _aggregateItem('site-b', '1', '其他站点结果'),
    ]);
    await _finishNotifications(tester);
    expect(find.text('其他站点结果'), findsOneWidget);
    expect(search.invocations, isEmpty);
  });
}

Future<void> _finishNotifications(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(seconds: 4));
  await tester.pumpAndSettle();
}

Future<void> _openAggregateDialog(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('home-search-fab')));
  await tester.pumpAndSettle();
  await tester.tap(find.text('聚合搜索'));
  await tester.pumpAndSettle();
}

Future<void> _submitAggregate(
  WidgetTester tester, {
  String keyword = '',
}) async {
  await _openAggregateDialog(tester);
  await tester.enterText(
    find.byKey(const ValueKey('search-keyword-field')),
    keyword,
  );
  await tester.tap(find.byKey(const ValueKey('home-search-submit-button')));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> _pumpHome(
  WidgetTester tester,
  _FakeAppState appState,
  _FakeHomeSearchExecutor search, {
  AggregateSearchService? aggregateSearchService,
  bool expectInitialSearch = true,
}) async {
  tester.view.physicalSize = const Size(393, 852);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AppState>.value(value: appState),
        ChangeNotifierProvider(create: (_) => AggregateSearchProvider()),
        Provider<StorageService>.value(value: StorageService.instance),
        ChangeNotifierProvider(
          create: (_) => DisplaySettingsManager(StorageService.instance),
        ),
      ],
      child: MaterialApp(
        home: HomePage(
          searchExecutor: search.call,
          aggregateSearchService: aggregateSearchService,
        ),
      ),
    ),
  );
  if (expectInitialSearch) {
    await _pumpUntil(tester, () => search.invocations.isNotEmpty);
  } else {
    await tester.pumpAndSettle();
  }
}

Future<void> _pumpUntil(WidgetTester tester, bool Function() condition) async {
  for (var attempt = 0; attempt < 20 && !condition(); attempt++) {
    await tester.pump(const Duration(milliseconds: 10));
  }
  expect(condition(), isTrue);
}

SiteConfig _site(String id, String name) {
  return SiteConfig(
    id: id,
    name: name,
    baseUrl: 'https://$id.example',
    searchCategories: const [
      SearchCategoryConfig(
        id: 'first',
        displayName: '第一分类',
        parameters: 'category: first',
      ),
      SearchCategoryConfig(
        id: 'second',
        displayName: '第二分类',
        parameters: 'category: second',
      ),
    ],
  );
}

TorrentItem _item(String id, String name) {
  return TorrentItem(
    id: id,
    name: name,
    smallDescr: '',
    discountEndTime: null,
    downloadUrl: null,
    seeders: 1,
    leechers: 0,
    sizeBytes: 1024,
    createdDate: DateTime(2026),
    imageList: const [],
    cover: '',
  );
}

class _FakeAppState extends AppState {
  _FakeAppState(this._testSite);

  SiteConfig _testSite;
  final int _testConfigVersion = 1;

  @override
  SiteConfig get site => _testSite;

  @override
  bool get isInitialized => true;

  @override
  int get configVersion => _testConfigVersion;

  void selectSite(SiteConfig site) {
    _testSite = site;
    notifyListeners();
  }
}

class _FakeHomeSearchExecutor {
  final List<_HomeSearchInvocation> invocations = [];

  Future<TorrentSearchResult> call({
    required SiteConfig siteConfig,
    required String? keyword,
    required int pageNumber,
    required int pageSize,
    required int? onlyFav,
    required Map<String, dynamic>? additionalParams,
  }) {
    final invocation = _HomeSearchInvocation(
      siteConfig: siteConfig,
      pageNumber: pageNumber,
      pageSize: pageSize,
      additionalParams: additionalParams,
    );
    invocations.add(invocation);
    return invocation.future;
  }
}

class _HomeSearchInvocation {
  _HomeSearchInvocation({
    required this.siteConfig,
    required this.pageNumber,
    required this.pageSize,
    required this.additionalParams,
  });

  final SiteConfig siteConfig;
  final int pageNumber;
  final int pageSize;
  final Map<String, dynamic>? additionalParams;
  final Completer<TorrentSearchResult> _completer = Completer();

  Future<TorrentSearchResult> get future => _completer.future;

  void complete({
    required List<TorrentItem> items,
    int totalPages = 1,
    int? total,
  }) {
    _completer.complete(
      TorrentSearchResult(
        pageNumber: pageNumber,
        pageSize: pageSize,
        total: total ?? items.length,
        totalPages: totalPages,
        items: items,
      ),
    );
  }

  void completeError(Object error) {
    _completer.completeError(error);
  }
}

AggregateSearchResultItem _aggregateItem(
  String siteId,
  String torrentId,
  String name,
) => AggregateSearchResultItem(
  siteId: siteId,
  siteName: siteId,
  torrent: _item(torrentId, name),
);

class _FakeAggregateSearchService implements AggregateSearchService {
  final List<_AggregateInvocation> invocations = [];

  @override
  Future<AggregateSearchResult> performAggregateSearch({
    required String keyword,
    required String configId,
    required Function(AggregateSearchProgress) onProgress,
    int maxResultsPerSite = 30,
    AggregateSearchCancelToken? cancelToken,
    Set<String>? targetSiteIds,
    AggregateSearchSiteResultsCallback? onSiteResults,
  }) {
    final invocation = _AggregateInvocation(
      keyword,
      cancelToken,
      onSiteResults,
    );
    invocations.add(invocation);
    onProgress(const AggregateSearchProgress(totalSites: 1, completedSites: 0));
    return invocation.completer.future;
  }
}

class _AggregateInvocation {
  _AggregateInvocation(this.keyword, this.cancelToken, this.onSiteResults);

  final String keyword;
  final AggregateSearchCancelToken? cancelToken;
  final AggregateSearchSiteResultsCallback? onSiteResults;
  final Completer<AggregateSearchResult> completer = Completer();

  void complete(List<AggregateSearchResultItem> items) {
    completer.complete(
      AggregateSearchResult(
        items: items,
        errors: const {},
        totalSites: 1,
        successSites: 1,
      ),
    );
  }
}
