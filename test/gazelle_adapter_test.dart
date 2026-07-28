import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pt_mate/models/app_models.dart';
import 'package:pt_mate/services/api/gazelle_adapter.dart';

void main() {
  test(
    'Gazelle JSON adapter still reads profile and browse responses',
    () async {
      HttpOverrides.global = null;

      final receivedCookies = <String?>[];
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        receivedCookies.add(request.headers.value(HttpHeaders.cookieHeader));
        request.response.headers.contentType = ContentType.json;
        final action = request.uri.queryParameters['action'];
        if (action == 'index') {
          request.response.write(
            jsonEncode({
              'status': 'success',
              'response': {
                'username': 'json-gazelle-user',
                'id': 42,
                'passkey': 'profile-passkey',
                'authkey': 'profile-authkey',
                'userstats': {
                  'uploaded': 2048,
                  'downloaded': 1024,
                  'ratio': 2.0,
                  'bonusPoints': 12.5,
                },
              },
            }),
          );
        } else if (action == 'browse') {
          request.response.write(
            jsonEncode({
              'status': 'success',
              'response': {
                'pages': 1,
                'results': [
                  {
                    'groupName': 'Example Album',
                    'artist': 'Example Artist',
                    'torrents': [
                      {
                        'torrentId': 99,
                        'format': 'FLAC',
                        'encoding': 'Lossless',
                        'isFreeleech': true,
                        'seeders': 3,
                        'leechers': 1,
                        'size': 4096,
                        'time': '2025-04-01 15:12:00',
                      },
                    ],
                  },
                ],
              },
            }),
          );
        } else {
          request.response.statusCode = HttpStatus.notFound;
        }
        await request.response.close();
      });

      final baseUrl = 'http://${server.address.host}:${server.port}';
      final adapter = GazelleAdapter();
      await adapter.init(
        SiteConfig(
          id: 'gazelle-json-test',
          name: 'Gazelle JSON test',
          baseUrl: baseUrl,
          siteType: SiteType.gazelle,
          cookie: 'session=json-gazelle-cookie',
          authKey: 'configured-authkey',
          passKey: 'configured-passkey',
        ),
      );

      try {
        final profile = await adapter.fetchMemberProfile();
        expect(profile.username, 'json-gazelle-user');
        expect(profile.userId, '42');
        expect(profile.uploadedBytes, 2048);

        final result = await adapter.searchTorrents(keyword: 'example');
        expect(result.items, hasLength(1));
        final item = result.items.single;
        expect(item.id, '99');
        expect(item.name, 'Example Artist - Example Album - FLAC / Lossless');
        expect(item.discount, DiscountType.free);
        expect(item.downloadUrl, contains('authkey=configured-authkey'));
        expect(item.downloadUrl, contains('torrent_pass=configured-passkey'));
        expect(receivedCookies, everyElement('session=json-gazelle-cookie'));
      } finally {
        await server.close(force: true);
      }
    },
  );
}
