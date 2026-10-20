import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pt_mate/models/app_models.dart';
import 'package:pt_mate/services/api/api_exceptions.dart';
import 'package:pt_mate/services/api/api_service.dart';
import 'package:pt_mate/services/api/mteam_adapter.dart';
import 'package:pt_mate/services/network/timeout_retry.dart';

typedef _Failure = Object Function(RequestOptions options);

class _RecordedRequest {
  _RecordedRequest(this.options, this.form, this.body);

  final RequestOptions options;
  final FormData form;
  final String body;
}

class _MTeamHttpAdapter implements HttpClientAdapter {
  final requests = <_RecordedRequest>[];
  final failures = <_Failure>[];
  int statusCode = 200;
  Map<String, dynamic> responseData = {
    'code': '0',
    'data': 'https://download.example.test/file.torrent',
  };

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final bytes = await requestStream!.fold<List<int>>(
      <int>[],
      (buffer, chunk) => buffer..addAll(chunk),
    );
    requests.add(
      _RecordedRequest(options, options.data as FormData, utf8.decode(bytes)),
    );
    if (requests.length <= failures.length) {
      throw failures[requests.length - 1](options);
    }
    return ResponseBody.fromString(
      jsonEncode(responseData),
      statusCode,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

enum _Operation { download, collect, uncollect }

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final service = ApiService.instance;
  const activeSite = SiteConfig(
    id: 'mteam-active',
    name: 'M-Team active',
    baseUrl: 'https://active.example.test',
    siteType: SiteType.mteam,
    apiKey: 'active-test-key',
  );
  const sourceSite = SiteConfig(
    id: 'mteam-source',
    name: 'M-Team source',
    baseUrl: 'https://source.example.test',
    siteType: SiteType.mteam,
    apiKey: 'source-test-key',
  );
  late _MTeamHttpAdapter activeHttp;
  late _MTeamHttpAdapter sourceHttp;

  setUp(() async {
    service.clearAdapters();
    await service.setActiveSite(activeSite);
    activeHttp = _MTeamHttpAdapter();
    (service.activeAdapter! as MTeamAdapter).setHttpClientAdapterForTesting(
      activeHttp,
    );
    sourceHttp = _MTeamHttpAdapter();
    final source = await service.getAdapter(sourceSite) as MTeamAdapter;
    source.setHttpClientAdapterForTesting(sourceHttp);
  });

  tearDown(service.clearAdapters);

  Future<void> runOperation(_Operation operation, bool useSourceSite) async {
    final site = useSourceSite ? sourceSite : null;
    if (operation == _Operation.download) {
      final url = await service.genDlToken(id: '42', siteConfig: site);
      expect(url, 'https://download.example.test/file.torrent');
    } else {
      await service.toggleCollection(
        id: '42',
        make: operation == _Operation.collect,
        siteConfig: site,
      );
    }
  }

  void verifyRequests(
    _Operation operation,
    bool useSourceSite,
    int expectedCount,
  ) {
    final http = useSourceSite ? sourceHttp : activeHttp;
    final otherHttp = useSourceSite ? activeHttp : sourceHttp;
    final site = useSourceSite ? sourceSite : activeSite;
    expect(http.requests, hasLength(expectedCount));
    expect(otherHttp.requests, isEmpty);
    expect(service.activeAdapter!.siteConfig.id, activeSite.id);
    for (final request in http.requests) {
      expect(request.options.method, 'POST');
      expect(request.options.baseUrl, site.baseUrl);
      expect(request.options.headers['x-api-key'], site.apiKey);
      expect(
        request.options.path,
        operation == _Operation.download
            ? '/api/torrent/genDlToken'
            : '/api/torrent/collection',
      );
      expect(Map.fromEntries(request.form.fields), {
        'id': '42',
        if (operation != _Operation.download)
          'make': (operation == _Operation.collect).toString(),
      });
      expect(request.body, contains('name="id"\r\n\r\n42\r\n'));
      if (operation != _Operation.download) {
        expect(
          request.body,
          contains('name="make"\r\n\r\n${operation == _Operation.collect}\r\n'),
        );
      }
    }
    if (expectedCount == 2) {
      expect(http.requests[0].form, isNot(same(http.requests[1].form)));
    }
  }

  final timeouts = <String, _Failure>{
    'native timeout': (_) => TimeoutException('request timed out'),
    'nested timeout': (options) => DioException(
      requestOptions: options,
      error: TimeoutException('request timed out'),
    ),
    'nested socket timeout': (options) => DioException(
      requestOptions: options,
      type: DioExceptionType.connectionError,
      error: const SocketException('Connection timed out'),
    ),
    'Dio receive timeout': (options) => DioException(
      requestOptions: options,
      type: DioExceptionType.receiveTimeout,
    ),
  };

  for (final useSourceSite in [false, true]) {
    final entry = useSourceSite ? 'source site' : 'active site';
    for (final operation in _Operation.values) {
      group('$entry ${operation.name}', () {
        for (final timeout in timeouts.entries) {
          test('retries ${timeout.key} with a fresh identical form', () async {
            final http = useSourceSite ? sourceHttp : activeHttp;
            http.failures.add(timeout.value);

            await runOperation(operation, useSourceSite);

            verifyRequests(operation, useSourceSite, 2);
          });
        }

        test('stops after two timeouts and reports a timeout', () async {
          final http = useSourceSite ? sourceHttp : activeHttp;
          http.failures.addAll([
            (_) => TimeoutException('first timeout'),
            (options) => DioException(
              requestOptions: options,
              type: DioExceptionType.connectionError,
              error: const SocketException('Connection timed out'),
            ),
          ]);

          await expectLater(
            runOperation(operation, useSourceSite),
            throwsA(
              isA<SiteNetworkException>().having(
                isTimeoutError,
                'isTimeoutError',
                isTrue,
              ),
            ),
          );

          verifyRequests(operation, useSourceSite, 2);
        });

        test('does not retry a business response mentioning timeout', () async {
          final http = useSourceSite ? sourceHttp : activeHttp;
          http.responseData = {'code': '1', 'message': 'business timeout'};

          await expectLater(
            runOperation(operation, useSourceSite),
            throwsA(isA<SiteApiException>()),
          );

          verifyRequests(operation, useSourceSite, 1);
        });

        for (final status in [401, 500, 504]) {
          test('does not retry HTTP $status', () async {
            final http = useSourceSite ? sourceHttp : activeHttp;
            http.statusCode = status;
            http.responseData = {'message': 'request timed out'};

            await expectLater(
              runOperation(operation, useSourceSite),
              throwsA(
                status == 401
                    ? isA<SiteAuthenticationException>()
                    : isA<SiteServiceException>(),
              ),
            );

            verifyRequests(operation, useSourceSite, 1);
          });
        }
      });
    }
  }
}
