import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pt_mate/models/app_models.dart';
import 'package:pt_mate/services/api/api_exceptions.dart';
import 'package:pt_mate/services/api/api_service.dart';
import 'package:pt_mate/services/api/site_adapter.dart';
import 'package:pt_mate/services/api/web_adapter.dart';

class _UnmockedHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context);
    client.idleTimeout = const Duration(seconds: 10);
    return client;
  }
}

Future<T> _withUnmockedHttp<T>(Future<T> Function() action) async {
  return HttpOverrides.runZoned<Future<T>>(
    action,
    createHttpClient: _UnmockedHttpOverrides().createHttpClient,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('WebAdapterCore', () {
    test('replaces placeholders and normalizes only HTTP(S) URLs', () {
      expect(
        WebAdapterCore.replacePlaceholders(
          '/user.php?id={userId}&q={keyword}',
          {'userId': 42, 'keyword': 'hello'},
        ),
        '/user.php?id=42&q=hello',
      );
      expect(
        WebAdapterCore.resolveHttpUrl(
          '/download.php?id=1',
          'https://example.test/base/',
        ),
        'https://example.test/download.php?id=1',
      );
      expect(
        WebAdapterCore.resolveHttpUrl('//cdn.example.test/a', 'https://x.test'),
        'https://cdn.example.test/a',
      );
      expect(
        WebAdapterCore.resolveHttpUrl('javascript:alert(1)', 'https://x.test'),
        isNull,
      );
    });
  });

  group('Web adapter integration', () {
    test('factory creates WebAdapter for the Web site type', () {
      final adapter = SiteAdapterFactory.createAdapter(
        const SiteConfig(
          id: 'web-factory',
          name: 'Web factory',
          baseUrl: 'https://example.test',
          siteType: SiteType.web,
        ),
      );

      expect(adapter, isA<WebAdapter>());
    });

    test('ApiService forwards parsed detail URLs to WebAdapter', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      const site = SiteConfig(
        id: 'web-api-detail',
        name: 'Web API detail',
        baseUrl: 'https://example.test',
        siteType: SiteType.web,
      );

      try {
        final detail = await ApiService.instance.fetchTorrentDetail(
          '99',
          siteConfig: site,
          detailUrl: '/torrents.php?id=99&source=list',
        );
        expect(
          detail.webviewUrl,
          'https://example.test/torrents.php?id=99&source=list',
        );
      } finally {
        ApiService.instance.removeAdapter(site.id);
      }
    });
  });

  group('WebSearchParser', () {
    test(
      'parses the Jpopsuki grouped fixture with inherited group data',
      () async {
        final html = await File(
          'test/fixtures/jpopsuki_torrents.html',
        ).readAsString();
        final site =
            jsonDecode(await File('assets/sites/jpopsuki.json').readAsString())
                as Map<String, dynamic>;
        final infoFinder = site['infoFinder'] as Map<String, dynamic>;
        final searchConfig = infoFinder['search'] as Map<String, dynamic>;

        final result = WebSearchParser.parse(
          html: html,
          searchConfig: searchConfig,
          baseUrl: 'https://jpopsuki.eu/',
          discountMapping: const {'Freeleech!': 'FREE'},
        );

        expect(result.totalPages, 6505);
        expect(result.candidateItemRows, 2);
        expect(result.items, hasLength(2));

        final grouped = result.items.first;
        expect(grouped.id, '901');
        expect(grouped.name, 'Example Album - Example Artist');
        expect(grouped.smallDescr, 'MP3 / 320 / Log / Cue');
        expect(
          grouped.cover,
          'https://jpopsuki.eu/static/covers/example-album.jpg',
        );
        expect(grouped.discount, DiscountType.free);
        expect(grouped.seeders, 7);
        expect(grouped.leechers, 2);
        expect(grouped.sizeBytes, 1288490189);
        expect(grouped.createdDate.toUtc(), DateTime.utc(2025, 4, 1, 15, 12));
        expect(
          grouped.detailUrl,
          'https://jpopsuki.eu/torrents.php?id=900&torrentid=901',
        );
        expect(
          grouped.downloadUrl,
          'https://jpopsuki.eu/torrents.php?action=download&id=901&token=fixture-download',
        );

        final standalone = result.items.last;
        expect(standalone.id, '300');
        expect(standalone.name, 'Independent Single - Independent Artist');
        expect(
          standalone.cover,
          'https://cdn.jpopsuki.example/covers/independent-single.webp',
        );
        expect(standalone.discount, DiscountType.free);
        expect(standalone.seeders, 4);
        expect(standalone.leechers, 1);
        expect(standalone.sizeBytes, 734003200);
        expect(standalone.detailUrl, 'https://jpopsuki.eu/torrents.php?id=300');
      },
    );

    test('joins a configured artist after the release title', () {
      const html = '''
        <table><tbody>
          <tr class="group_redline">
            <td class="title">
              <a class="artist" href="/artist.php?id=100">Example Artist</a> -
              <a class="release" href="/torrents.php?id=900">Example Album</a>
            </td>
          </tr>
          <tr class="group_torrent_redline">
            <td>
              <a class="detail" href="/torrents.php?id=900&amp;torrentid=901">MP3</a>
              <a class="download" href="/torrents.php?action=download&amp;id=901">Download</a>
            </td>
          </tr>
          <tr class="torrent_redline">
            <td>
              <a class="artist" href="/artist.php?id=200">Independent Artist</a>
              <a class="release" href="/torrents.php?id=300&amp;torrentid=300">Independent Single</a>
              <a class="download" href="/torrents.php?action=download&amp;id=300">Download</a>
            </td>
          </tr>
          <tr class="torrent_redline">
            <td>
              <a class="release" href="/torrents.php?id=400&amp;torrentid=400">Artistless Release</a>
              <a class="download" href="/torrents.php?action=download&amp;id=400">Download</a>
            </td>
          </tr>
        </tbody></table>
      ''';
      const searchConfig = <String, dynamic>{
        'parser': 'gazelleGrouped',
        'rows': {'selector': '@@table tbody > tr'},
        'groupRows': {'selector': '@@tr.group_redline'},
        'torrentRows': {
          'selector': '@@tr.group_torrent_redline, tr.torrent_redline',
        },
        'groupFields': {
          'title': {'selector': '@@a.release', 'attribute': 'text'},
          'artist': {'selector': '@@a.artist', 'attribute': 'text'},
          'torrentName': {
            'join': ['title', 'artist'],
            'separator': ' - ',
          },
        },
        'fields': {
          'torrentId': {
            'selector': '@@a.download',
            'attribute': 'href',
            'filter': {
              'name': 'regexp',
              'args': '[?&]id=(\\d+)',
              'value': '\$1',
            },
          },
          'detailUrl': {'selector': '@@a.detail', 'attribute': 'href'},
          'downloadUrl': {'selector': '@@a.download', 'attribute': 'href'},
        },
        'standaloneFields': {
          'title': {'selector': '@@a.release', 'attribute': 'text'},
          'artist': {'selector': '@@a.artist', 'attribute': 'text'},
          'torrentName': {
            'join': ['title', 'artist'],
            'separator': ' - ',
          },
        },
      };

      final result = WebSearchParser.parse(
        html: html,
        searchConfig: searchConfig,
        baseUrl: 'https://jpopsuki.eu/',
      );

      expect(result.items, hasLength(3));
      // 分组子行继承父级的 title/artist 计算字段。
      expect(result.items.first.name, 'Example Album - Example Artist');
      expect(result.items[1].name, 'Independent Single - Independent Artist');
      expect(result.items.last.name, 'Artistless Release');
    });

    test('fails explicitly for a missing rows configuration', () {
      expect(
        () => WebSearchParser.parse(
          html: '<html></html>',
          searchConfig: const {'fields': {}},
          baseUrl: 'https://example.test',
        ),
        throwsA(isA<WebAdapterConfigurationException>()),
      );
    });
  });

  group('WebAdapter requests', () {
    test(
      'uses Cookie, performs userInfo steps, and merges search parameters',
      () async {
        await _withUnmockedHttp(() async {
          final requests = <Uri>[];
          final cookies = <String?>[];
          final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
          server.listen((request) async {
            requests.add(request.uri);
            cookies.add(request.headers.value(HttpHeaders.cookieHeader));
            request.response.headers.contentType = ContentType.html;
            switch (request.uri.path) {
              case '/index.php':
                request.response.write(
                  '<a class="username" href="/user.php?id=42">tester</a>',
                );
              case '/user.php':
                request.response.write('''
              <div id="stats">
                <span class="ratio">1.50</span>
                <span class="upload">1.5 GiB</span>
                <span class="download">500 MiB</span>
                <span class="bonus">123.4</span>
              </div>
            ''');
              case '/torrents.php':
                request.response.write('''
              <table><tr class="torrent">
                <td class="name"><a href="/torrents.php?id=99">Example</a></td>
                <td class="size">2 MiB</td><td class="seeders">3</td><td class="leechers">4</td>
                <td><a class="download" href="/download.php?id=99&token=kept">Download</a></td>
              </tr></table>
            ''');
              default:
                request.response.statusCode = HttpStatus.notFound;
            }
            await request.response.close();
          });

          final baseUrl = 'http://${server.address.host}:${server.port}';
          final diagnostics = <WebAdapterDiagnostic>[];
          final adapter = WebAdapter(diagnosticSink: diagnostics.add);
          adapter.setCustomTemplate(_webTemplate());
          await adapter.init(
            SiteConfig(
              id: 'web-test',
              name: 'Web test',
              baseUrl: baseUrl,
              siteType: SiteType.web,
              cookie: 'session=test-cookie',
            ),
          );

          try {
            final profile = await adapter.fetchMemberProfile();
            expect(profile.username, 'tester');
            expect(profile.userId, '42');
            expect(profile.shareRate, 1.5);
            expect(profile.uploadedBytes, 1610612736);
            expect(profile.downloadedBytes, 524288000);

            final result = await adapter.searchTorrents(
              keyword: 'J-pop',
              pageNumber: 2,
              pageSize: 50,
              additionalParams: {
                'category': 'normal#7',
                'filter_cat[3]': '1',
                'extra': 'kept',
              },
            );
            expect(result.items, hasLength(1));
            expect(
              result.items.single.detailUrl,
              '$baseUrl/torrents.php?id=99',
            );
            expect(
              result.items.single.downloadUrl,
              '$baseUrl/download.php?id=99&token=kept',
            );

            final searchUri = requests.last;
            expect(searchUri.path, '/torrents.php');
            expect(searchUri.queryParameters['q'], 'J-pop');
            expect(searchUri.queryParameters['page'], '2');
            expect(searchUri.queryParameters['size'], '50');
            expect(searchUri.queryParameters['categoryId'], '7');
            expect(searchUri.queryParameters['filter_cat[3]'], '1');
            expect(searchUri.queryParameters['extra'], 'kept');
            expect(cookies, everyElement('session=test-cookie'));

            final requestDiagnostic = diagnostics.firstWhere(
              (diagnostic) =>
                  diagnostic.stage == WebAdapterDiagnosticStage.request &&
                  diagnostic.path == '/torrents.php',
            );
            expect(
              requestDiagnostic.parameterKeys,
              orderedEquals(<String>[
                'categoryId',
                'extra',
                'filter_cat[3]',
                'page',
                'q',
                'size',
              ]),
            );
            expect(requestDiagnostic.statusCode, 200);
            expect(requestDiagnostic.responseBytes, greaterThan(0));
            final safeRequestLine = requestDiagnostic.toSafeLogLine();
            expect(safeRequestLine, isNot(contains('test-cookie')));
            expect(safeRequestLine, isNot(contains('J-pop')));
            expect(safeRequestLine, isNot(contains('kept')));

            final parseDiagnostic = diagnostics.firstWhere(
              (diagnostic) =>
                  diagnostic.stage == WebAdapterDiagnosticStage.searchParse,
            );
            expect(parseDiagnostic.candidateItemRows, 1);
            expect(parseDiagnostic.parsedItems, 1);
            expect(parseDiagnostic.totalPages, 1);
          } finally {
            await server.close(force: true);
          }
        });
      },
    );

    test('turns a redirect to login into an authentication error', () async {
      await _withUnmockedHttp(() async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        server.listen((request) async {
          if (request.uri.path == '/index.php') {
            request.response.statusCode = HttpStatus.found;
            request.response.headers.set(
              HttpHeaders.locationHeader,
              '/login.php',
            );
          } else {
            request.response.write('<html>login</html>');
          }
          await request.response.close();
        });
        final adapter = WebAdapter();
        adapter.setCustomTemplate(
          _webTemplate(
            search: const {
              'rows': {'selector': '@@tr'},
              'fields': {},
            },
            userInfo: const {
              'steps': [
                {
                  'path': '/index.php',
                  'fields': {
                    'userName': {'selector': '@@body', 'attribute': 'text'},
                  },
                },
              ],
            },
          ),
        );
        await adapter.init(
          SiteConfig(
            id: 'auth-test',
            name: 'Auth test',
            baseUrl: 'http://${server.address.host}:${server.port}',
            siteType: SiteType.web,
          ),
        );

        try {
          await expectLater(
            adapter.fetchMemberProfile(),
            throwsA(isA<SiteAuthenticationException>()),
          );
        } finally {
          await server.close(force: true);
        }
      });
    });

    test(
      'treats a 200 login page without required fields as auth failure',
      () async {
        await _withUnmockedHttp(() async {
          final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
          server.listen((request) async {
            request.response.headers.contentType = ContentType.html;
            request.response.write('<form id="login">Please sign in</form>');
            await request.response.close();
          });
          final adapter = WebAdapter();
          adapter.setCustomTemplate(
            _webTemplate(
              userInfo: const {
                'steps': [
                  {
                    'path': '/index.php',
                    'fields': {
                      'userId': {
                        'selector': '@@a.username',
                        'attribute': 'href',
                        'required': true,
                      },
                    },
                  },
                ],
              },
            ),
          );
          await adapter.init(
            SiteConfig(
              id: 'login-body-test',
              name: 'Login body test',
              baseUrl: 'http://${server.address.host}:${server.port}',
              siteType: SiteType.web,
              cookie: 'expired-cookie',
            ),
          );

          try {
            await expectLater(
              adapter.fetchMemberProfile(),
              throwsA(isA<SiteAuthenticationException>()),
            );
          } finally {
            await server.close(force: true);
          }
        });
      },
    );

    test(
      'does not fall back to a Nexus template when Web configuration is absent',
      () async {
        final adapter = WebAdapter();
        adapter.setCustomTemplate(
          _webTemplate(
            userInfo: const {},
            search: const {
              'rows': {'selector': '@@tr'},
              'fields': {},
            },
          ),
        );
        await adapter.init(
          const SiteConfig(
            id: 'missing-config',
            name: 'Missing config',
            baseUrl: 'https://example.test',
            siteType: SiteType.web,
          ),
        );

        await expectLater(
          adapter.fetchMemberProfile(),
          throwsA(isA<SiteServiceException>()),
        );
      },
    );

    test('uses the parsed detail URL for WebView detail', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final adapter = WebAdapter();
      adapter.setCustomTemplate(_webTemplate());
      await adapter.init(
        const SiteConfig(
          id: 'detail-test',
          name: 'Detail test',
          baseUrl: 'https://example.test',
          siteType: SiteType.web,
        ),
      );

      final detail = await adapter.fetchTorrentDetail(
        '99',
        detailUrl: '/torrents.php?id=99&source=list',
      );
      expect(
        detail.webviewUrl,
        'https://example.test/torrents.php?id=99&source=list',
      );
    });
  });
}

SiteConfigTemplate _webTemplate({
  Map<String, dynamic>? userInfo,
  Map<String, dynamic>? search,
}) {
  return SiteConfigTemplate(
    id: 'web-test-template',
    name: 'Web test template',
    baseUrls: const ['https://example.test'],
    siteType: SiteType.web,
    infoFinder: {
      'userInfo':
          userInfo ??
          const {
            'steps': [
              {
                'path': '/index.php',
                'rows': {'selector': '@@body'},
                'fields': {
                  'userId': {
                    'selector': '@@a.username',
                    'attribute': 'href',
                    'filter': {
                      'name': 'regexp',
                      'args': r'id=(\d+)',
                      'value': r'$1',
                    },
                  },
                  'userName': {'selector': '@@a.username', 'attribute': 'text'},
                },
              },
              {
                'path': '/user.php?id={userId}',
                'rows': {'selector': '@@div#stats'},
                'fields': {
                  'ratio': {'selector': '@@span.ratio', 'attribute': 'text'},
                  'upload': {'selector': '@@span.upload', 'attribute': 'text'},
                  'download': {
                    'selector': '@@span.download',
                    'attribute': 'text',
                  },
                  'bonus': {'selector': '@@span.bonus', 'attribute': 'text'},
                },
              },
            ],
          },
      'search':
          search ??
          const {
            'rows': {'selector': '@@tr.torrent'},
            'fields': {
              'torrentId': {
                'selector': '@@a.download',
                'attribute': 'href',
                'filter': {
                  'name': 'regexp',
                  'args': r'id=(\d+)',
                  'value': r'$1',
                },
              },
              'torrentName': {'selector': '@@td.name a', 'attribute': 'text'},
              'detailUrl': {'selector': '@@td.name a', 'attribute': 'href'},
              'downloadUrl': {'selector': '@@a.download', 'attribute': 'href'},
              'sizeText': {'selector': '@@td.size', 'attribute': 'text'},
              'seedersText': {'selector': '@@td.seeders', 'attribute': 'text'},
              'leechersText': {
                'selector': '@@td.leechers',
                'attribute': 'text',
              },
            },
          },
    },
    request: const {
      'search': {
        'path': '/torrents.php',
        'params': {
          'q': '{keyword}',
          'page': '{page}',
          'size': '{pageSize}',
          'categoryId': '{categoryId}',
        },
      },
    },
  );
}
