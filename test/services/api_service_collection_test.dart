import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pt_mate/models/app_models.dart';
import 'package:pt_mate/services/api/api_service.dart';

class _UnmockedHttpOverrides extends HttpOverrides {}

Future<T> _withRealHttp<T>(Future<T> Function() action) {
  return HttpOverrides.runZoned<Future<T>>(
    action,
    createHttpClient: _UnmockedHttpOverrides().createHttpClient,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final service = ApiService.instance;
  late _CollectionSite activeSite;
  late _CollectionSite sourceSite;

  setUp(() async {
    service.clearAdapters();
    activeSite = await _CollectionSite.start('active');
    sourceSite = await _CollectionSite.start('source');
  });

  tearDown(() async {
    service.clearAdapters();
    await activeSite.close();
    await sourceSite.close();
  });

  test('收藏指定来源站点的种子，不改变首页当前站点', () async {
    await _withRealHttp(() async {
      await service.setActiveSite(activeSite.config);

      await service.toggleCollection(
        id: '42',
        make: true,
        siteConfig: sourceSite.config,
      );

      expect(activeSite.requests, isEmpty);
      expect(sourceSite.requests, hasLength(1));
      expect(sourceSite.requests.single.path, '/api/v1/bookmarks');
      expect(sourceSite.requests.single.authorization, 'Bearer source-key');
      expect(sourceSite.requests.single.body, contains('name="torrent_id"'));
      expect(sourceSite.requests.single.body, contains('\r\n42\r\n'));
      expect(service.activeAdapter?.siteConfig.id, activeSite.config.id);

      await service.toggleCollection(id: '42', make: false);

      expect(activeSite.requests, hasLength(1));
      expect(activeSite.requests.single.path, '/api/v1/bookmarks/delete');
      expect(activeSite.requests.single.authorization, 'Bearer active-key');
      expect(sourceSite.requests, hasLength(1));
    });
  });

  test('未选择当前站点时仍可收藏指定来源站点的种子', () async {
    await _withRealHttp(() async {
      await service.toggleCollection(
        id: '42',
        make: false,
        siteConfig: sourceSite.config,
      );

      expect(sourceSite.requests, hasLength(1));
      expect(sourceSite.requests.single.path, '/api/v1/bookmarks/delete');
      expect(activeSite.requests, isEmpty);
      expect(service.activeAdapter, isNull);
    });
  });

  test('未指定来源且没有当前站点时保留原有错误', () async {
    await expectLater(
      service.toggleCollection(id: '42', make: true),
      throwsStateError,
    );

    expect(activeSite.requests, isEmpty);
    expect(sourceSite.requests, isEmpty);
  });
}

class _CollectionSite {
  final HttpServer server;
  final SiteConfig config;
  final List<({String path, String? authorization, String body})> requests = [];

  _CollectionSite(this.server, this.config);

  static Future<_CollectionSite> start(String id) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final site = _CollectionSite(
      server,
      SiteConfig(
        id: id,
        name: id,
        baseUrl: 'http://${server.address.address}:${server.port}',
        siteType: SiteType.nexusphp,
        apiKey: '$id-key',
      ),
    );
    server.listen((request) async {
      site.requests.add((
        path: request.uri.path,
        authorization: request.headers.value(HttpHeaders.authorizationHeader),
        body: await utf8.decoder.bind(request).join(),
      ));
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({'ret': 0}));
      await request.response.close();
    });
    return site;
  }

  Future<void> close() => server.close(force: true);
}
