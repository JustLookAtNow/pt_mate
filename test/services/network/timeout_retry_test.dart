import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pt_mate/services/api/api_exceptions.dart';
import 'package:pt_mate/services/network/timeout_retry.dart';

void main() {
  group('retryOnTimeout', () {
    test('retries a site timeout once and returns the retry result', () async {
      var attempts = 0;

      final result = await retryOnTimeout(() async {
        attempts++;
        if (attempts == 1) {
          throw const SiteNetworkException(timeoutType: '接收超时');
        }
        return 'ok';
      }, retryDelay: Duration.zero);

      expect(result, 'ok');
      expect(attempts, 2);
    });

    test('recognizes Dio and dart async timeout exceptions', () {
      final options = RequestOptions(path: '/test');

      expect(
        isTimeoutError(
          DioException(
            requestOptions: options,
            type: DioExceptionType.connectionTimeout,
          ),
        ),
        isTrue,
      );
      expect(isTimeoutError(TimeoutException('timed out')), isTrue);
      expect(
        isTimeoutError(
          DioException(
            requestOptions: options,
            error: TimeoutException('nested timeout'),
          ),
        ),
        isTrue,
      );
    });

    test(
      'does not retry business errors or ordinary connection failures',
      () async {
        var businessAttempts = 0;
        var connectionAttempts = 0;

        await expectLater(
          retryOnTimeout<void>(() async {
            businessAttempts++;
            throw SiteApiException(message: '业务失败');
          }, retryDelay: Duration.zero),
          throwsA(isA<SiteApiException>()),
        );
        await expectLater(
          retryOnTimeout<void>(() async {
            connectionAttempts++;
            throw const SiteNetworkException(timeoutType: '连接失败');
          }, retryDelay: Duration.zero),
          throwsA(isA<SiteNetworkException>()),
        );

        expect(businessAttempts, 1);
        expect(connectionAttempts, 1);
      },
    );

    test('stops after the configured retry count', () async {
      var attempts = 0;

      await expectLater(
        retryOnTimeout<void>(
          () async {
            attempts++;
            throw const SiteNetworkException(timeoutType: '连接超时');
          },
          retryCount: 2,
          retryDelay: Duration.zero,
        ),
        throwsA(isA<SiteNetworkException>()),
      );

      expect(attempts, 3);
    });
  });
}
