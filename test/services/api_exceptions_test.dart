import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pt_mate/services/api/api_exceptions.dart';
import 'package:pt_mate/services/network/timeout_retry.dart';

void main() {
  final options = RequestOptions(path: '/test');
  final timeouts = <String, Object>{
    'native timeout': TimeoutException('request timed out'),
    'nested timeout': DioException(
      requestOptions: options,
      error: TimeoutException('request timed out'),
    ),
    'multiply nested timeout': DioException(
      requestOptions: options,
      error: DioException(
        requestOptions: options,
        error: TimeoutException('request timed out'),
      ),
    ),
    'socket timeout': const SocketException('Connection timed out'),
    'socket OS timeout': const SocketException(
      'Connection failed',
      osError: OSError('Operation timed out', 60),
    ),
    'nested socket timeout': DioException(
      requestOptions: options,
      type: DioExceptionType.connectionError,
      error: const SocketException('Connection timed out'),
    ),
    'nested site timeout': DioException(
      requestOptions: options,
      error: const SiteNetworkException(timeoutType: '接收超时'),
    ),
    for (final type in [
      DioExceptionType.connectionTimeout,
      DioExceptionType.sendTimeout,
      DioExceptionType.receiveTimeout,
    ])
      type.name: DioException(requestOptions: options, type: type),
  };

  group('timeout conversion', () {
    for (final entry in timeouts.entries) {
      test('${entry.key} remains retryable after wrapping', () {
        final wrapped = ApiExceptionAdapter.wrapError(entry.value, '收藏操作');

        expect(isTimeoutError(entry.value), isTrue);
        expect(wrapped, isA<SiteNetworkException>());
        expect(isTimeoutError(wrapped), isTrue);
        expect(ApiExceptionAdapter.wrapError(wrapped, '收藏操作'), same(wrapped));
      });
    }

    test('uses a general request timeout when the phase is unknown', () {
      final wrapped = ApiExceptionAdapter.wrapError(
        TimeoutException('request timed out'),
        '生成下载链接',
      );

      expect(
        wrapped,
        isA<SiteNetworkException>().having(
          (error) => error.timeoutType,
          'timeoutType',
          '请求超时',
        ),
      );
      expect(wrapped.detail, contains('TimeoutException'));
    });
  });

  group('non-timeout errors', () {
    final errors = <String, Object>{
      'business error mentioning timeout': SiteApiException(
        message: 'timeout: 业务失败',
      ),
      'ordinary exception mentioning timeout': Exception('request timed out'),
      'ordinary socket failure': const SocketException('Connection refused'),
      'DNS failure': const SocketException('Failed host lookup: timeout.test'),
      'authentication error': const SiteAuthenticationException(),
      'Cloudflare challenge': const CloudflareChallengeException(),
      'connection failure': const SiteNetworkException(timeoutType: '连接失败'),
      'Dio message mentioning timeout': DioException(
        requestOptions: options,
        message: 'request timed out',
      ),
      'wrapped business error': DioException(
        requestOptions: options,
        error: SiteApiException(message: 'timeout'),
      ),
      'explicit Dio timeout carrying a business error': DioException(
        requestOptions: options,
        type: DioExceptionType.receiveTimeout,
        error: SiteApiException(message: 'timeout'),
      ),
      'unknown Dio error with HTTP response': DioException(
        requestOptions: options,
        response: Response(requestOptions: options, statusCode: 401),
        error: TimeoutException('stale timeout'),
      ),
      for (final type in [
        DioExceptionType.cancel,
        DioExceptionType.badCertificate,
        DioExceptionType.badResponse,
      ])
        type.name: DioException(
          requestOptions: options,
          type: type,
          error: TimeoutException('stale timeout'),
        ),
      for (final type in [
        DioExceptionType.cancel,
        DioExceptionType.badCertificate,
        DioExceptionType.badResponse,
      ])
        '${type.name} with site timeout': DioException(
          requestOptions: options,
          type: type,
          error: const SiteNetworkException(timeoutType: '接收超时'),
        ),
      for (final status in [401, 403, 408, 500, 504])
        'HTTP $status': DioException(
          requestOptions: options,
          type: DioExceptionType.badResponse,
          response: Response(
            requestOptions: options,
            statusCode: status,
            data: 'request timed out',
          ),
          error: TimeoutException('stale timeout'),
        ),
    };

    for (final entry in errors.entries) {
      test('${entry.key} is not retried before or after wrapping', () async {
        final wrapped = ApiExceptionAdapter.wrapError(entry.value, '收藏操作');
        expect(isTimeoutError(entry.value), isFalse);
        expect(isTimeoutError(wrapped), isFalse);

        var attempts = 0;
        await expectLater(
          retryOnTimeout<void>(() async {
            attempts++;
            throw wrapped;
          }, retryDelay: Duration.zero),
          throwsA(same(wrapped)),
        );
        expect(attempts, 1);
      });
    }

    test('preserves an authentication exception nested in Dio', () {
      const auth = SiteAuthenticationException();
      final wrapped = ApiExceptionAdapter.wrapError(
        DioException(requestOptions: options, error: auth),
        '收藏操作',
      );
      expect(wrapped, same(auth));
    });
  });
}
