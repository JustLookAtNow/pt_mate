import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pt_mate/models/app_models.dart';
import 'package:pt_mate/services/downloader/torrent_file_downloader_mixin.dart';

class _DownloadHarness with TorrentFileDownloaderMixin {}

class _RecordingHttpClientAdapter implements HttpClientAdapter {
  Map<String, dynamic>? lastHeaders;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    lastHeaders = Map<String, dynamic>.from(options.headers);
    return ResponseBody.fromBytes(const <int>[100, 51, 58, 52], 200);
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  group('TorrentFileDownloaderMixin', () {
    test(
      'attaches a generic Web site cookie to same-origin downloads',
      () async {
        final adapter = _RecordingHttpClientAdapter();
        final dio = Dio()..httpClientAdapter = adapter;
        final harness = _DownloadHarness();

        final result = await harness.downloadTorrentFileCommon(
          dio,
          '##https://jpopsuki.eu/torrents.php?action=download&id=1',
          siteConfig: const SiteConfig(
            id: 'jpopsuki',
            name: 'JPopSuki',
            baseUrl: 'https://jpopsuki.eu/',
            cookie: 'PHPSESSID=fixture',
            siteType: SiteType.web,
          ),
        );

        expect(result, const <int>[100, 51, 58, 52]);
        expect(adapter.lastHeaders?['Cookie'], 'PHPSESSID=fixture');
      },
    );

    test('never sends a site cookie to a third-party download host', () async {
      final adapter = _RecordingHttpClientAdapter();
      final dio = Dio()..httpClientAdapter = adapter;
      final harness = _DownloadHarness();

      await harness.downloadTorrentFileCommon(
        dio,
        'https://cdn.example.net/file.torrent',
        siteConfig: const SiteConfig(
          id: 'web-site',
          name: 'Web Site',
          baseUrl: 'https://tracker.example.org/',
          cookie: 'sid=fixture',
          siteType: SiteType.web,
        ),
      );

      expect(adapter.lastHeaders?.containsKey('Cookie'), isFalse);
    });
  });
}
