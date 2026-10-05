import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:pt_mate/models/app_models.dart';
import 'package:pt_mate/pages/torrent_detail_page.dart';
import 'package:pt_mate/services/api/api_service.dart';
import 'package:pt_mate/services/storage/storage_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final storage = StorageService.instance;
  late _TestWebViewPlatform webViewPlatform;
  InAppWebViewPlatform? previousPlatform;

  setUp(() {
    SharedPreferences.setMockInitialValues({StorageKeys.autoLoadImages: false});
    storage.resetForTest();
    ApiService.instance.clearAdapters();
    previousPlatform = InAppWebViewPlatform.instance ?? _TestWebViewPlatform();
    webViewPlatform = _TestWebViewPlatform();
    InAppWebViewPlatform.instance = webViewPlatform;
  });

  tearDown(() {
    ApiService.instance.clearAdapters();
    storage.resetForTest();
    InAppWebViewPlatform.instance = previousPlatform;
  });

  Future<void> openDetail(
    WidgetTester tester, {
    SiteConfig? siteConfig,
    String? description,
    TargetPlatform platform = TargetPlatform.iOS,
  }) async {
    if (siteConfig != null) {
      await tester.runAsync(() => ApiService.instance.getAdapter(siteConfig));
    }
    await tester.pumpWidget(
      Provider<StorageService>.value(
        value: storage,
        child: MaterialApp(
          theme: ThemeData(platform: platform),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(
                    builder: (_) => TorrentDetailPage(
                      torrentItem: TorrentItem(
                        id: '42',
                        name: '测试种子',
                        smallDescr: '',
                        discountEndTime: null,
                        downloadUrl: '',
                        description: description,
                        seeders: 0,
                        leechers: 0,
                        sizeBytes: 0,
                        createdDate: DateTime(2026),
                        imageList: const [],
                        cover: '',
                      ),
                      siteFeatures: const SiteFeatures(
                        supportDownload: false,
                        supportCollection: false,
                      ),
                      downloaderConfigs: const [],
                      siteConfig: siteConfig,
                    ),
                  ),
                ),
                child: const Text('种子列表'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('种子列表'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump();
  }

  Future<void> swipeBack(WidgetTester tester) async {
    await tester.dragFrom(const Offset(1, 200), const Offset(650, 0));
    await tester.pumpAndSettle();
  }

  SiteConfig webSite({bool nativeDetail = false}) => SiteConfig(
    id: 'back-test',
    name: '测试站点',
    baseUrl: 'https://example.invalid',
    siteType: SiteType.nexusphpweb,
    features: SiteFeatures(nativeDetail: nativeDetail),
  );

  testWidgets('iOS 详情加载失败时左边缘右滑返回列表', (tester) async {
    await openDetail(tester);
    expect(find.textContaining('加载失败:'), findsOneWidget);

    await swipeBack(tester);

    expect(find.byType(TorrentDetailPage), findsNothing);
    expect(find.text('种子列表'), findsOneWidget);
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

  testWidgets('iOS 原生详情左边缘右滑返回列表', (tester) async {
    await openDetail(
      tester,
      siteConfig: webSite(nativeDetail: true),
      description: '<p>种子描述</p>',
    );
    await tester.pumpAndSettle();
    expect(find.text('种子描述', findRichText: true), findsOneWidget);

    await swipeBack(tester);

    expect(find.byType(TorrentDetailPage), findsNothing);
    expect(find.text('种子列表'), findsOneWidget);
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

  testWidgets('iOS 侧滑跟随手指且取消后仍可再次返回', (tester) async {
    await openDetail(tester, siteConfig: webSite());
    final controller = webViewPlatform.controller;
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    final gesture = await tester.startGesture(const Offset(1, 200));
    await gesture.moveBy(const Offset(150, 0));
    await tester.pump();
    expect(navigator.userGestureInProgress, isTrue);
    expect(tester.getTopLeft(find.byType(Scaffold).last).dx, greaterThan(0));
    await tester.pump(const Duration(milliseconds: 200));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(find.byType(TorrentDetailPage), findsOneWidget);
    expect(controller.stopLoadingCalls, 0);
    expect(controller.loadUrls, isEmpty);

    await swipeBack(tester);

    expect(find.byType(TorrentDetailPage), findsNothing);
    expect(controller.goBackCalls, 0);
    expect(controller.stopLoadingCalls, 1);
    expect(controller.loadUrls, ['about:blank']);
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

  testWidgets('iOS 网页有历史时侧滑直接退出且忽略退出后的网页回调', (tester) async {
    await openDetail(tester, siteConfig: webSite());
    final webView = webViewPlatform.webView!;
    final controller = webViewPlatform.controller;
    final wrappedController = webView.controllerFromPlatform(controller);

    await swipeBack(tester);

    expect(find.text('种子列表'), findsOneWidget);
    expect(controller.canGoBackCalls, 0);
    expect(controller.goBackCalls, 0);
    expect(controller.stopLoadingCalls, 1);
    expect(controller.loadUrls, ['about:blank']);

    final url = WebUri('https://example.invalid/details.php?id=42');
    webView.params.onLoadStart!(wrappedController, url);
    webView.params.onLoadStop!(wrappedController, url);
    webView.params.onReceivedError!(
      wrappedController,
      WebResourceRequest(url: url, isForMainFrame: true),
      WebResourceError(type: WebResourceErrorType.UNKNOWN, description: '已退出'),
    );
    webView.params.onWebViewCreated!(wrappedController);
    await tester.pump();
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

  testWidgets('iOS 导航栏返回直接退出有历史的网页详情', (tester) async {
    await openDetail(tester, siteConfig: webSite());

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    expect(find.byType(TorrentDetailPage), findsNothing);
    expect(webViewPlatform.controller.canGoBackCalls, 0);
    expect(webViewPlatform.controller.goBackCalls, 0);
    expect(webViewPlatform.controller.stopLoadingCalls, 1);
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

  testWidgets('Android 系统返回先退网页历史，无历史后退出并只清理一次', (tester) async {
    await openDetail(
      tester,
      siteConfig: webSite(),
      platform: TargetPlatform.android,
    );
    final controller = webViewPlatform.controller;

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.byType(TorrentDetailPage), findsOneWidget);
    expect(controller.goBackCalls, 1);
    expect(controller.stopLoadingCalls, 0);

    controller.hasHistory = false;
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.byType(TorrentDetailPage), findsNothing);
    expect(find.text('种子列表'), findsOneWidget);
    expect(controller.stopLoadingCalls, 1);
    expect(controller.loadUrls, ['about:blank']);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  testWidgets('iOS 详情请求未完成时仍可侧滑退出', (tester) async {
    final client = _PendingHttpClient();
    final previousOverrides = HttpOverrides.current;
    HttpOverrides.global = _PendingHttpOverrides(client);
    try {
      await openDetail(
        tester,
        siteConfig: SiteConfig(
          id: 'loading-test',
          name: '加载中站点',
          baseUrl: 'https://example.invalid',
          siteType: SiteType.nexusphp,
        ),
      );
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      await swipeBack(tester);

      expect(find.byType(TorrentDetailPage), findsNothing);
      expect(find.text('种子列表'), findsOneWidget);
    } finally {
      client.request.completeError(const SocketException('测试请求结束'));
      // Dio 的错误拦截器通过事件队列逐层传播，清空其零延时任务。
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 1));
      }
      HttpOverrides.global = previousOverrides;
    }
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));
}

class _TestWebViewPlatform extends InAppWebViewPlatform {
  final controller = _TestWebViewController();
  _TestWebViewWidget? webView;

  @override
  PlatformInAppWebViewWidget createPlatformInAppWebViewWidget(
    PlatformInAppWebViewWidgetCreationParams params,
  ) => webView = _TestWebViewWidget(params, controller);
}

class _TestWebViewWidget extends PlatformInAppWebViewWidget {
  final _TestWebViewController controller;
  bool created = false;

  _TestWebViewWidget(super.params, this.controller) : super.implementation();

  @override
  Widget build(BuildContext context) {
    if (!created) {
      created = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        params.onWebViewCreated?.call(controllerFromPlatform(controller));
      });
    }
    return const SizedBox.expand();
  }

  @override
  T controllerFromPlatform<T>(PlatformInAppWebViewController controller) =>
      params.controllerFromPlatform!(controller) as T;

  @override
  void dispose() {}
}

class _TestWebViewController extends PlatformInAppWebViewController {
  bool hasHistory = true;
  int canGoBackCalls = 0;
  int goBackCalls = 0;
  int stopLoadingCalls = 0;
  final List<String> loadUrls = [];

  _TestWebViewController()
    : super.implementation(
        const PlatformInAppWebViewControllerCreationParams(id: 1),
      );

  @override
  Future<bool> canGoBack() async {
    canGoBackCalls++;
    return hasHistory;
  }

  @override
  Future<void> goBack() async => goBackCalls++;

  @override
  Future<void> stopLoading() async => stopLoadingCalls++;

  @override
  Future<void> loadUrl({
    required URLRequest urlRequest,
    Uri? iosAllowingReadAccessTo,
    WebUri? allowingReadAccessTo,
  }) async => loadUrls.add(urlRequest.url.toString());
}

class _PendingHttpOverrides extends HttpOverrides {
  final _PendingHttpClient client;
  _PendingHttpOverrides(this.client);

  @override
  HttpClient createHttpClient(SecurityContext? context) => client;
}

class _PendingHttpClient implements HttpClient {
  final request = Completer<HttpClientRequest>();

  @override
  Duration? connectionTimeout;

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) => request.future;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
