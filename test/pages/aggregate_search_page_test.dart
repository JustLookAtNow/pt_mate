import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:pt_mate/models/app_models.dart';
import 'package:pt_mate/pages/aggregate_search_page.dart';
import 'package:pt_mate/providers/aggregate_search_provider.dart';
import 'package:pt_mate/services/aggregate_search_service.dart';
import 'package:pt_mate/services/settings/display_settings_manager.dart';
import 'package:pt_mate/services/storage/storage_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    final settings = AggregateSearchSettings(
      searchConfigs: const [
        AggregateSearchConfig(id: 'test-strategy', name: '测试策略'),
      ],
    );
    SharedPreferences.setMockInitialValues({
      StorageKeys.aggregateSearchSettings: jsonEncode(settings.toJson()),
      StorageKeys.siteConfigs: jsonEncode(
        const [
          SiteConfig(id: 'mteam', name: 'M-Team', baseUrl: 'https://m.team'),
          SiteConfig(
            id: 'audiences',
            name: 'Audiences',
            baseUrl: 'https://audiences.example',
          ),
          SiteConfig(
            id: 'hddolby',
            name: 'HDDolby',
            baseUrl: 'https://hddolby.example',
          ),
          SiteConfig(
            id: 'hhanclub',
            name: 'HHanClub',
            baseUrl: 'https://hhanclub.example',
          ),
          SiteConfig(
            id: 'ourbits',
            name: 'OurBits',
            baseUrl: 'https://ourbits.example',
          ),
        ].map((site) => site.toJson()).toList(),
      ),
    });
    StorageService.instance.resetForTest();
  });

  testWidgets('search FAB opens the strategy and keyword dialog', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => AggregateSearchProvider()),
          ChangeNotifierProvider(
            create: (_) => DisplaySettingsManager(StorageService.instance),
          ),
          Provider<StorageService>.value(value: StorageService.instance),
        ],
        child: const MaterialApp(home: AggregateSearchPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('测试策略'), findsOneWidget);
    expect(find.byKey(const ValueKey('aggregate-search-fab')), findsOneWidget);
    expect(find.byType(TextField), findsNothing);

    await tester.tap(find.byKey(const ValueKey('aggregate-search-fab')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('aggregate-search-strategy-field')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('search-keyword-field')), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '搜索'), findsOneWidget);
  });

  testWidgets('partial failures use a compact banner and bottom sheet', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final provider = AggregateSearchProvider();
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: provider),
          ChangeNotifierProvider(
            create: (_) => DisplaySettingsManager(StorageService.instance),
          ),
          Provider<StorageService>.value(value: StorageService.instance),
        ],
        child: const MaterialApp(home: AggregateSearchPage()),
      ),
    );
    await tester.pumpAndSettle();

    provider.setSearchErrors({
      'mteam': '网络请求超时: 连接超时',
      'audiences': 'timeout',
      'hddolby': '网络请求超时',
      'hhanclub': 'Exception: 请求超时',
      'ourbits': '连接超时',
    });
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('aggregate-search-error-banner')),
      findsOneWidget,
    );
    expect(find.text('5 个站点未响应'), findsOneWidget);
    expect(find.text('其他站点结果已正常显示'), findsOneWidget);
    expect(find.text('网络请求超时: 连接超时'), findsNothing);

    await tester.ensureVisible(find.text('查看'));
    await tester.tap(find.text('查看'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(
      find.byKey(const ValueKey('aggregate-search-error-sheet')),
      findsOneWidget,
    );
    expect(find.text('未响应的站点'), findsOneWidget);
    expect(find.text('请求超时，不影响其他搜索结果'), findsOneWidget);
    // 测试环境没有系统安全存储，站点名称读取失败时回退到站点 ID。
    expect(find.text('mteam'), findsOneWidget);
    expect(find.text('audiences'), findsOneWidget);
    expect(find.text('hddolby'), findsOneWidget);
    expect(find.text('hhanclub'), findsOneWidget);
    expect(find.text('ourbits'), findsOneWidget);
    expect(find.text('连接超时'), findsNWidgets(5));
    expect(find.text('重试 5 个站点'), findsOneWidget);
    expect(find.text('暂不处理'), findsOneWidget);
  });

  testWidgets('default sorting displays each completed site immediately', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final provider = AggregateSearchProvider();
    final searchService = _FakeAggregateSearchService();
    await _pumpSearchPage(tester, provider, searchService);
    await _startSearch(tester);

    final item = _resultItem(
      siteId: 'mteam',
      torrentId: 'incremental',
      name: '首个站点即时结果',
    );
    searchService.invocations.single.emit([item]);
    await tester.pump();

    expect(provider.searching, isTrue);
    expect(provider.searchResults, [item]);
    expect(find.text('首个站点即时结果'), findsOneWidget);
    expect(
      tester
          .widget<PopupMenuButton<String>>(find.byType(PopupMenuButton<String>))
          .enabled,
      isFalse,
    );

    searchService.invocations.single.complete(items: [item]);
    await _finishSearchNotifications(tester);

    expect(provider.searching, isFalse);
    expect(provider.searchResults, [item]);
  });

  testWidgets('non-default sorting waits for the final result', (tester) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final provider = AggregateSearchProvider()..setSortBy('time');
    final searchService = _FakeAggregateSearchService();
    await _pumpSearchPage(tester, provider, searchService);
    await _startSearch(tester);

    final item = _resultItem(
      siteId: 'mteam',
      torrentId: 'deferred',
      name: '等待完成后展示',
    );
    searchService.invocations.single.emit([item]);
    await tester.pump();

    expect(provider.searching, isTrue);
    expect(provider.searchResults, isEmpty);
    expect(find.text('等待完成后展示'), findsNothing);

    searchService.invocations.single.complete(items: [item]);
    await _finishSearchNotifications(tester);

    expect(provider.searching, isFalse);
    expect(find.text('等待完成后展示'), findsOneWidget);
  });

  testWidgets('late results from a replaced search are ignored', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final provider = AggregateSearchProvider();
    final searchService = _FakeAggregateSearchService();
    await _pumpSearchPage(tester, provider, searchService);
    await _startSearch(tester);
    await _startSearch(tester);

    final staleItem = _resultItem(
      siteId: 'old-site',
      torrentId: 'old',
      name: '旧搜索结果',
    );
    final currentItem = _resultItem(
      siteId: 'new-site',
      torrentId: 'new',
      name: '当前搜索结果',
    );

    searchService.invocations.first.emit([staleItem]);
    searchService.invocations.last.emit([currentItem]);
    await tester.pump();

    expect(find.text('旧搜索结果'), findsNothing);
    expect(find.text('当前搜索结果'), findsOneWidget);

    searchService.invocations.last.complete(items: [currentItem]);
    searchService.invocations.first.complete(items: [staleItem]);
    await _finishSearchNotifications(tester);

    expect(provider.searchResults, [currentItem]);
  });

  testWidgets('stopping keeps results that were already displayed', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final provider = AggregateSearchProvider();
    final searchService = _FakeAggregateSearchService();
    await _pumpSearchPage(tester, provider, searchService);
    await _startSearch(tester);

    final item = _resultItem(
      siteId: 'mteam',
      torrentId: 'before-stop',
      name: '停止前已展示',
    );
    final invocation = searchService.invocations.single;
    invocation.emit([item]);
    await tester.pump();

    await tester.tap(find.text('停止'));
    await tester.pump();
    expect(invocation.cancelToken?.isCancelled, isTrue);
    expect(find.text('停止前已展示'), findsOneWidget);

    invocation.complete(items: [item]);
    await _finishSearchNotifications(tester);

    expect(provider.searching, isFalse);
    expect(provider.searchResults, [item]);
  });
}

Future<void> _pumpSearchPage(
  WidgetTester tester,
  AggregateSearchProvider provider,
  AggregateSearchService searchService,
) async {
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
        home: AggregateSearchPage(searchService: searchService),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _startSearch(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('aggregate-search-fab')));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  await tester.tap(find.widgetWithText(FilledButton, '搜索'));
  await tester.pump();
}

Future<void> _finishSearchNotifications(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(seconds: 4));
  await tester.pump();
}

AggregateSearchResultItem _resultItem({
  required String siteId,
  required String torrentId,
  required String name,
}) {
  return AggregateSearchResultItem(
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
      sizeBytes: 1024,
      createdDate: DateTime(2026),
      imageList: const [],
      cover: '',
    ),
  );
}

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
      onSiteResults: onSiteResults,
      cancelToken: cancelToken,
    );
    invocations.add(invocation);
    onProgress(const AggregateSearchProgress(totalSites: 1, completedSites: 0));
    return invocation.completer.future;
  }
}

class _SearchInvocation {
  _SearchInvocation({required this.onSiteResults, required this.cancelToken});

  final AggregateSearchSiteResultsCallback? onSiteResults;
  final AggregateSearchCancelToken? cancelToken;
  final Completer<AggregateSearchResult> completer =
      Completer<AggregateSearchResult>();

  void emit(List<AggregateSearchResultItem> items) {
    onSiteResults?.call(items);
  }

  void complete({required List<AggregateSearchResultItem> items}) {
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
