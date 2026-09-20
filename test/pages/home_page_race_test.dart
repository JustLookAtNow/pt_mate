import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:pt_mate/app.dart';
import 'package:pt_mate/models/app_models.dart';
import 'package:pt_mate/services/settings/display_settings_manager.dart';
import 'package:pt_mate/services/storage/storage_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
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
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('category-item-1')));
    await tester.tap(find.widgetWithText(FilledButton, '确定'));
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
}

Future<void> _pumpHome(
  WidgetTester tester,
  _FakeAppState appState,
  _FakeHomeSearchExecutor search,
) async {
  tester.view.physicalSize = const Size(393, 852);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AppState>.value(value: appState),
        ChangeNotifierProvider(
          create: (_) => DisplaySettingsManager(StorageService.instance),
        ),
      ],
      child: MaterialApp(home: HomePage(searchExecutor: search.call)),
    ),
  );
  await _pumpUntil(tester, () => search.invocations.isNotEmpty);
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
