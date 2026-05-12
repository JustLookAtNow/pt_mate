import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pt_mate/services/downloader/downloader_config.dart';
import 'package:pt_mate/services/downloader/downloader_models.dart';
import 'package:pt_mate/services/downloader/qbittorrent_client.dart';

class _RecordedRequest {
  _RecordedRequest(this.method, this.path, this.headers);

  final String method;
  final String path;
  final Map<String, dynamic> headers;
}

class _FakeHttpClientAdapter implements HttpClientAdapter {
  final List<_RecordedRequest> requests = [];
  final List<String> loginCookies = [];
  int _loginCount = 0;
  int _transferInfoCount = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(
      _RecordedRequest(
        options.method,
        options.path,
        Map<String, dynamic>.from(options.headers),
      ),
    );

    if (options.path.endsWith('/auth/login')) {
      final cookie = loginCookies[_loginCount++];
      return ResponseBody.fromString(
        'Ok.',
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.formUrlEncodedContentType],
          'set-cookie': [cookie],
        },
      );
    }

    if (options.path.endsWith('/torrents/add')) {
      return ResponseBody.fromString('', 204);
    }

    if (options.path.endsWith('/transfer/info')) {
      _transferInfoCount++;
      if (_transferInfoCount == 1) {
        return ResponseBody.fromString('Forbidden', 403);
      }
      return ResponseBody.fromString(
        jsonEncode({
          'up_info_speed': 1,
          'dl_info_speed': 2,
          'up_info_data': 3,
          'dl_info_data': 4,
        }),
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    }

    throw UnsupportedError(
      'Unexpected request: ${options.method} ${options.path}',
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  group('QbittorrentClient', () {
    QbittorrentConfig buildConfig() {
      return const QbittorrentConfig(
        id: 'qb-1',
        name: 'qb',
        host: 'http://localhost',
        port: 8080,
        username: 'admin',
        password: '',
      );
    }

    test('extracts legacy SID cookie header', () {
      final client = QbittorrentClient(
        config: buildConfig(),
        password: 'secret',
      );

      final header = client.debugExtractCookieHeader([
        'SID=legacy-session; HttpOnly; path=/',
      ]);

      expect(header, 'SID=legacy-session');
    });

    test('extracts and deduplicates arbitrary cookie names', () {
      final client = QbittorrentClient(
        config: buildConfig(),
        password: 'secret',
      );

      final header = client.debugExtractCookieHeader([
        'cookie_id=v1; HttpOnly; path=/',
        'theme=dark; path=/',
        'cookie_id=v2; HttpOnly; path=/',
      ]);

      expect(header, 'cookie_id=v2; theme=dark');
    });

    test(
      'uses parsed login cookie for authenticated requests and accepts 204',
      () async {
        final adapter = _FakeHttpClientAdapter()
          ..loginCookies.add('cookie_id=new-value; HttpOnly; path=/');
        final dio = Dio()..httpClientAdapter = adapter;
        final client = QbittorrentClient(
          config: buildConfig(),
          password: 'secret',
          dio: dio,
        );

        await client.addTask(
          AddTaskParams(url: 'https://example.com/test.torrent'),
        );

        expect(client.debugAuthCookieHeader, 'cookie_id=new-value');
        expect(adapter.requests.length, 2);
        expect(
          adapter.requests[0].path,
          'http://localhost:8080/api/v2/auth/login',
        );
        expect(adapter.requests[1].headers['Cookie'], 'cookie_id=new-value');
      },
    );

    test('retries once after 403 with refreshed login cookie', () async {
      final adapter = _FakeHttpClientAdapter()
        ..loginCookies.addAll([
          'cookie_id=first-value; HttpOnly; path=/',
          'cookie_id=second-value; HttpOnly; path=/',
        ]);
      final dio = Dio()..httpClientAdapter = adapter;
      final client = QbittorrentClient(
        config: buildConfig(),
        password: 'secret',
        dio: dio,
      );

      final result = await client.getTransferInfo();

      expect(result.upSpeed, 1);
      expect(client.debugAuthCookieHeader, 'cookie_id=second-value');
      expect(adapter.requests.length, 4);
      expect(adapter.requests[1].headers['Cookie'], 'cookie_id=first-value');
      expect(adapter.requests[3].headers['Cookie'], 'cookie_id=second-value');
    });
  });
}
