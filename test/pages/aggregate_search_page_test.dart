import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:pt_mate/models/app_models.dart';
import 'package:pt_mate/models/home_search_request.dart';
import 'package:pt_mate/pages/aggregate_search_page.dart';
import 'package:pt_mate/providers/aggregate_search_provider.dart';
import 'package:pt_mate/services/aggregate_search_service.dart';
import 'package:pt_mate/services/settings/display_settings_manager.dart';
import 'package:pt_mate/services/storage/storage_service.dart';
import 'package:pt_mate/widgets/torrent_list_item.dart';
import 'package:pt_mate/widgets/tag_filter_bar.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _configs = [
  AggregateSearchConfig(id: 'test-strategy', name: '测试策略'),
  AggregateSearchConfig(id: 'backup-strategy', name: '备用策略'),
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({
      StorageKeys.aggregateSearchSettings: jsonEncode(
        const AggregateSearchSettings(searchConfigs: _configs).toJson(),
      ),
      StorageKeys.siteConfigs: jsonEncode(
        const [
          SiteConfig(id: 'site-a', name: '站点 A', baseUrl: 'https://a.example'),
          SiteConfig(id: 'site-b', name: '站点 B', baseUrl: 'https://b.example'),
        ].map((site) => site.toJson()).toList(),
      ),
    });
    StorageService.instance.resetForTest();
  });

  testWidgets('submitted request starts search and summary delegates to home', (
    tester,
  ) async {
    final provider = AggregateSearchProvider();
    final service = _FakeAggregateSearchService();
    final harness = await _pumpView(tester, provider, service, keyword: '电影');

    expect(service.invocations.single.keyword, '电影');
    expect(service.invocations.single.configId, 'test-strategy');
    expect(find.text('测试策略 · 电影'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(find.byType(FloatingActionButton), findsNothing);
    expect(find.byType(ExpansionTile), findsNothing);
    expect(find.byType(TagFilterBar), findsOneWidget);
    expect(find.byTooltip('排序'), findsOneWidget);
    final sort = tester.widget<PopupMenuButton<String>>(
      find.byType(PopupMenuButton<String>),
    );
    expect((sort.icon as Icon).icon, Icons.sort);
    expect(sort.enabled, isFalse);

    await tester.tap(find.byKey(const ValueKey('aggregate-search-summary')));
    await tester.pump();
    expect(harness.currentState!.searchPanelOpenCount, 1);
    expect(service.invocations, hasLength(1));
    service.invocations.single.complete();
    await _finishNotifications(tester);
  });

  testWidgets('only a new request sequence starts a replacement search', (
    tester,
  ) async {
    final provider = AggregateSearchProvider();
    final service = _FakeAggregateSearchService();
    final harness = await _pumpView(tester, provider, service);

    harness.currentState!.rebuild();
    await tester.pump();
    expect(service.invocations, hasLength(1));

    harness.currentState!.submit(keyword: '', strategyId: 'backup-strategy');
    await tester.pump();
    expect(service.invocations, hasLength(2));
    expect(service.invocations.first.cancelToken!.isCancelled, isTrue);
    expect(service.invocations.last.keyword, '');
    expect(service.invocations.last.configId, 'backup-strategy');
    expect(provider.selectedStrategy, 'backup-strategy');
    service.invocations.last.complete();
    service.invocations.first.complete();
    await _finishNotifications(tester);
  });

  testWidgets('partial failures use a compact banner and bottom sheet', (
    tester,
  ) async {
    final provider = AggregateSearchProvider();
    final service = _FakeAggregateSearchService();
    await _pumpView(tester, provider, service);
    service.invocations.single.complete(
      errors: {'site-a': '网络请求超时: 连接超时', 'site-b': 'timeout'},
    );
    await _finishNotifications(tester);

    expect(find.text('2 个站点未响应'), findsOneWidget);
    expect(find.text('网络请求超时: 连接超时'), findsNothing);
    await tester.tap(find.text('查看'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('aggregate-search-error-sheet')),
      findsOneWidget,
    );
    expect(find.text('连接超时'), findsNWidgets(2));
    expect(find.text('重试 2 个站点'), findsOneWidget);
  });

  testWidgets('default sorting displays each completed site immediately', (
    tester,
  ) async {
    final provider = AggregateSearchProvider();
    final service = _FakeAggregateSearchService();
    await _pumpView(tester, provider, service);
    final item = _resultItem(siteId: 'site-a', torrentId: '1', name: '即时结果');
    service.invocations.single.emit([item]);
    await tester.pump();
    expect(provider.searching, isTrue);
    expect(find.text('即时结果'), findsOneWidget);
    service.invocations.single.complete(items: [item]);
    await _finishNotifications(tester);
    expect(provider.searching, isFalse);
    expect(provider.searchResults, [item]);
  });

  testWidgets('non-default sorting waits for final globally sorted results', (
    tester,
  ) async {
    final provider = AggregateSearchProvider()..setSortBy('size');
    final service = _FakeAggregateSearchService();
    await _pumpView(tester, provider, service);
    final small = _resultItem(siteId: 'site-a', torrentId: '1', name: '小种子');
    final large = _resultItem(
      siteId: 'site-b',
      torrentId: '2',
      name: '大种子',
      sizeBytes: 4096,
    );
    service.invocations.single.emit([small]);
    await tester.pump();
    expect(provider.searchResults, isEmpty);
    service.invocations.single.complete(items: [small, large]);
    await _finishNotifications(tester);
    expect(provider.searchResults, [large, small]);
  });

  testWidgets('late results from a replaced search are ignored', (
    tester,
  ) async {
    final provider = AggregateSearchProvider();
    final service = _FakeAggregateSearchService();
    final harness = await _pumpView(tester, provider, service);
    harness.currentState!.submit(keyword: '新关键词');
    await tester.pump();
    final stale = _resultItem(siteId: 'site-a', torrentId: '1', name: '旧结果');
    final current = _resultItem(siteId: 'site-b', torrentId: '2', name: '新结果');
    service.invocations.first.emit([stale]);
    service.invocations.last.emit([current]);
    await tester.pump();
    expect(find.text('旧结果'), findsNothing);
    expect(find.text('新结果'), findsOneWidget);
    service.invocations.last.complete(items: [current]);
    service.invocations.first.complete(items: [stale]);
    await _finishNotifications(tester);
    expect(provider.searchResults, [current]);
  });

  testWidgets('stopping keeps results that were already displayed', (
    tester,
  ) async {
    final provider = AggregateSearchProvider();
    final service = _FakeAggregateSearchService();
    await _pumpView(tester, provider, service);
    final item = _resultItem(siteId: 'site-a', torrentId: '1', name: '停止前结果');
    service.invocations.single.emit([item]);
    await tester.pump();
    await tester.tap(find.text('停止'));
    await tester.pump();
    expect(service.invocations.single.cancelToken!.isCancelled, isTrue);
    expect(find.text('停止前结果'), findsOneWidget);
    service.invocations.single.complete(items: [item]);
    await _finishNotifications(tester);
    expect(provider.searchResults, [item]);
  });

  testWidgets('exit keeps the mounted view but ignores late search callbacks', (
    tester,
  ) async {
    final provider = AggregateSearchProvider();
    final service = _FakeAggregateSearchService();
    final harness = await _pumpView(tester, provider, service);
    final before = _resultItem(siteId: 'site-a', torrentId: '1', name: '已有结果');
    final after = _resultItem(siteId: 'site-b', torrentId: '2', name: '退出后结果');
    service.invocations.single.emit([before]);
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('aggregate-search-exit')));
    await tester.pump();
    expect(harness.currentState!.active, isFalse);
    expect(harness.currentState!.viewKey.currentState, isNotNull);
    expect(service.invocations.single.cancelToken!.isCancelled, isTrue);
    expect(provider.searching, isFalse);
    service.invocations.single.emit([after]);
    service.invocations.single.progress();
    service.invocations.single.complete(items: [before, after]);
    await _finishNotifications(tester);
    expect(provider.searchResults, [before]);
    expect(provider.searchProgress, isNull);
    expect(find.textContaining('搜索完成：'), findsNothing);
  });

  testWidgets('scrolling hides filters while the summary remains visible', (
    tester,
  ) async {
    final provider = AggregateSearchProvider();
    final service = _FakeAggregateSearchService();
    await _pumpView(tester, provider, service);
    service.invocations.single.complete(
      items: List.generate(
        40,
        (index) => _resultItem(
          siteId: 'site-a',
          torrentId: '$index',
          name: '种子 $index',
        ),
      ),
    );
    await _finishNotifications(tester);
    final visibility = find.byKey(
      const ValueKey('aggregate-search-filter-visibility'),
    );
    expect(tester.widget<Align>(visibility).heightFactor, 1);
    await tester.drag(find.byType(ListView).first, const Offset(0, -400));
    await tester.pumpAndSettle();
    expect(tester.widget<Align>(visibility).heightFactor, 0);
    expect(find.text('返回当前站点').hitTestable(), findsOneWidget);
    expect(
      find.byKey(const ValueKey('aggregate-search-summary')).hitTestable(),
      findsOneWidget,
    );
    await tester.drag(find.byType(ListView).first, const Offset(0, 250));
    await tester.pumpAndSettle();
    expect(tester.widget<Align>(visibility).heightFactor, greaterThan(0));
  });

  testWidgets('disposing a view cancels its search token', (tester) async {
    final provider = AggregateSearchProvider();
    final service = _FakeAggregateSearchService();
    await _pumpView(tester, provider, service);
    await tester.pumpWidget(const SizedBox());
    expect(service.invocations.single.cancelToken!.isCancelled, isTrue);
    expect(provider.searching, isFalse);
    service.invocations.single.complete();
    await tester.pump();
  });

  testWidgets('same torrent ID in two sites can be selected independently', (
    tester,
  ) async {
    final provider = AggregateSearchProvider();
    final service = _FakeAggregateSearchService();
    final harness = await _pumpView(tester, provider, service);
    final first = _resultItem(
      siteId: 'site-a',
      torrentId: '1',
      name: '站点 A 结果',
    );
    final second = _resultItem(
      siteId: 'site-b',
      torrentId: '1',
      name: '站点 B 结果',
    );
    service.invocations.single.complete(items: [first, second]);
    await _finishNotifications(tester);
    expect(find.byKey(ValueKey(first.identity)), findsOneWidget);
    expect(find.byKey(ValueKey(second.identity)), findsOneWidget);

    await tester.longPress(find.byKey(ValueKey(first.identity)));
    await tester.pump();
    expect(find.text('下载 (1)'), findsOneWidget);
    final rows = tester.widgetList<TorrentListItem>(
      find.byType(TorrentListItem),
    );
    expect(rows.where((row) => row.isSelected), hasLength(1));
    await tester.tap(find.text('站点 B 结果'));
    await tester.pump();
    expect(find.text('下载 (2)'), findsOneWidget);
    harness.currentState!.viewKey.currentState!.cancelSelection();
    await tester.pump();
    expect(harness.currentState!.selectionMode, isFalse);
    expect(find.text('下载 (2)'), findsNothing);
  });

  testWidgets('retry retains good results and is cancelled when leaving', (
    tester,
  ) async {
    final provider = AggregateSearchProvider();
    final service = _FakeAggregateSearchService();
    final harness = await _pumpView(tester, provider, service, keyword: '电影');
    final good = _resultItem(siteId: 'site-a', torrentId: '1', name: '成功站点结果');
    service.invocations.single.complete(
      items: [good],
      errors: {'site-b': '超时'},
    );
    await _finishNotifications(tester);
    await tester.tap(find.text('查看'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('重试 1 个站点'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(service.invocations.last.targetSiteIds, {'site-b'});
    expect(service.invocations.last.keyword, '电影');
    expect(provider.searchResults, [good]);
    expect(harness.currentState!.searchAvailable, isFalse);
    harness.currentState!.exit();
    await tester.pump();
    expect(service.invocations.last.cancelToken!.isCancelled, isTrue);
    final late = _resultItem(siteId: 'site-b', torrentId: '2', name: '重试晚结果');
    service.invocations.last.emit([late]);
    service.invocations.last.complete(items: [late]);
    await _finishNotifications(tester);
    expect(provider.searchResults, [good]);
    expect(provider.searchErrors, {'site-b': '超时'});
    expect(harness.currentState!.searchAvailable, isTrue);
  });
}

Future<GlobalKey<_HarnessState>> _pumpView(
  WidgetTester tester,
  AggregateSearchProvider provider,
  AggregateSearchService service, {
  String keyword = '',
}) async {
  tester.view.physicalSize = const Size(393, 852);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  provider.setSearchConfigs(_configs);
  provider.setLoading(false);
  final key = GlobalKey<_HarnessState>();
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: provider),
        ChangeNotifierProvider(
          create: (_) => DisplaySettingsManager(StorageService.instance),
        ),
        Provider<StorageService>.value(value: StorageService.instance),
      ],
      child: MaterialApp(
        home: _Harness(key: key, service: service, keyword: keyword),
      ),
    ),
  );
  await tester.pump();
  return key;
}

class _Harness extends StatefulWidget {
  const _Harness({super.key, required this.service, required this.keyword});
  final AggregateSearchService service;
  final String keyword;

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  final viewKey = GlobalKey<AggregateSearchViewState>();
  late HomeSearchRequest request;
  bool active = true;
  bool selectionMode = false;
  bool searchAvailable = true;
  int searchPanelOpenCount = 0;

  @override
  void initState() {
    super.initState();
    request = HomeSearchRequest(
      mode: HomeSearchMode.aggregate,
      keyword: widget.keyword,
      strategyId: 'test-strategy',
    );
  }

  void rebuild() => setState(() {});

  void submit({String keyword = '', String strategyId = 'test-strategy'}) {
    setState(() {
      active = true;
      request = HomeSearchRequest(
        mode: HomeSearchMode.aggregate,
        keyword: keyword,
        strategyId: strategyId,
        sequence: request.sequence + 1,
      );
    });
  }

  void exit() {
    viewKey.currentState!.leaveAggregate();
    setState(() => active = false);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: IndexedStack(
      index: active ? 1 : 0,
      children: [
        const Center(child: Text('当前站点列表')),
        AggregateSearchView(
          key: viewKey,
          request: request,
          active: active,
          searchService: widget.service,
          onSearchRequested: () => searchPanelOpenCount++,
          onExitRequested: exit,
          onSelectionModeChanged: (value) => selectionMode = value,
          onSearchAvailabilityChanged: (value) => searchAvailable = value,
        ),
      ],
    ),
  );
}

Future<void> _finishNotifications(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(seconds: 4));
  await tester.pump();
}

AggregateSearchResultItem _resultItem({
  required String siteId,
  required String torrentId,
  required String name,
  int sizeBytes = 1024,
}) => AggregateSearchResultItem(
  siteId: siteId,
  siteName: siteId,
  torrent: TorrentItem(
    id: torrentId,
    name: name,
    smallDescr: '',
    discountEndTime: null,
    downloadUrl: null,
    seeders: 1,
    leechers: 0,
    sizeBytes: sizeBytes,
    createdDate: DateTime(2026),
    imageList: const [],
    cover: '',
  ),
);

class _FakeAggregateSearchService implements AggregateSearchService {
  final List<_SearchInvocation> invocations = [];

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
    final invocation = _SearchInvocation(
      keyword: keyword,
      configId: configId,
      onSiteResults: onSiteResults,
      onProgress: onProgress,
      cancelToken: cancelToken,
      targetSiteIds: targetSiteIds,
    );
    invocations.add(invocation);
    invocation.progress();
    return invocation.completer.future;
  }
}

class _SearchInvocation {
  _SearchInvocation({
    required this.keyword,
    required this.configId,
    required this.onSiteResults,
    required this.onProgress,
    required this.cancelToken,
    required this.targetSiteIds,
  });

  final String keyword;
  final String configId;
  final AggregateSearchSiteResultsCallback? onSiteResults;
  final Function(AggregateSearchProgress) onProgress;
  final AggregateSearchCancelToken? cancelToken;
  final Set<String>? targetSiteIds;
  final Completer<AggregateSearchResult> completer = Completer();

  void emit(List<AggregateSearchResultItem> items) =>
      onSiteResults?.call(items);
  void progress() => onProgress(
    const AggregateSearchProgress(totalSites: 2, completedSites: 0),
  );

  void complete({
    List<AggregateSearchResultItem> items = const [],
    Map<String, String> errors = const {},
  }) => completer.complete(
    AggregateSearchResult(
      items: items,
      errors: errors,
      totalSites: 2,
      successSites: 2 - errors.length,
    ),
  );
}
