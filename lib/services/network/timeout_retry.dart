import 'dart:async';

import 'package:dio/dio.dart';

import '../api/api_exceptions.dart';

/// 超时请求的统一重试策略。
const int defaultTimeoutRetryCount = 1;
const Duration defaultTimeoutRetryDelay = Duration(milliseconds: 300);

/// 判断异常是否明确表示请求超时。
///
/// 业务错误、HTTP 响应错误和普通连接失败不会被视为超时，避免对不应
/// 重复执行的请求进行无意义重试。
bool isTimeoutError(Object error) {
  if (error is TimeoutException) return true;
  if (error is SiteNetworkException) return error.isTimeout;

  if (error is DioException) {
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return true;
      default:
        final innerError = error.error;
        return innerError is Object &&
            !identical(innerError, error) &&
            isTimeoutError(innerError);
    }
  }

  return false;
}

/// 当 [operation] 明确因超时失败时自动重试。
Future<T> retryOnTimeout<T>(
  Future<T> Function() operation, {
  int retryCount = defaultTimeoutRetryCount,
  Duration retryDelay = defaultTimeoutRetryDelay,
}) async {
  var retries = 0;

  while (true) {
    try {
      return await operation();
    } catch (error) {
      if (!isTimeoutError(error) || retries >= retryCount) {
        rethrow;
      }

      retries++;
      if (retryDelay > Duration.zero) {
        await Future<void>.delayed(retryDelay);
      }
    }
  }
}
