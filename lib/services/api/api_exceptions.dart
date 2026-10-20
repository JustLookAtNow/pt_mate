import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';

/// 站点异常基类
/// 所有站点相关的异常都继承自此类
class SiteException implements Exception {
  final String message;
  final String? detail;

  const SiteException(this.message, [this.detail]);

  @override
  String toString() {
    if (detail != null && detail!.isNotEmpty) {
      return '$message\n$detail';
    }
    return message;
  }
}

/// Cloudflare 挑战异常
/// 当检测到 Cloudflare 验证页面时抛出
class CloudflareChallengeException extends SiteException {
  const CloudflareChallengeException([String? detail])
    : super('检测到 Cloudflare 验证，请在浏览器中完成验证后重试', detail);
}

/// 认证失效异常
/// 当 API Key / Cookie 过期或无效时抛出 (401, 403, 302)
class SiteAuthenticationException extends SiteException {
  final int? statusCode;

  const SiteAuthenticationException({
    String message = '登录已失效，请重新配置站点认证信息',
    this.statusCode,
    String? detail,
  }) : super(message, detail);

  @override
  String toString() {
    final codeInfo = statusCode != null ? ' (HTTP $statusCode)' : '';
    if (detail != null && detail!.isNotEmpty) {
      return '$message$codeInfo\n$detail';
    }
    return '$message$codeInfo';
  }
}

/// 网络超时异常
/// 当请求超时时抛出；无法确定阶段时使用“请求超时”。
class SiteNetworkException extends SiteException {
  final String timeoutType;

  const SiteNetworkException({required this.timeoutType, String? detail})
    : super('网络请求超时: $timeoutType', detail);

  bool get isTimeout =>
      const {'连接超时', '发送超时', '接收超时', '请求超时'}.contains(timeoutType);
}

/// 服务端异常
/// 当服务器返回 500 等错误或响应格式异常时抛出
class SiteServiceException extends SiteException {
  final int? statusCode;

  const SiteServiceException({
    String message = '服务端响应异常',
    this.statusCode,
    String? detail,
  }) : super(message, detail);

  @override
  String toString() {
    final codeInfo = statusCode != null ? ' (HTTP $statusCode)' : '';
    if (detail != null && detail!.isNotEmpty) {
      return '$message$codeInfo\n$detail';
    }
    return '$message$codeInfo';
  }
}

/// API 接口业务异常
/// 当 HTTP 200 成功但业务逻辑返回错误时抛出 (如 ret != 0)
/// 用于 API 类型适配器 (非 Web 适配器)
class SiteApiException extends SiteException {
  final dynamic responseData;

  SiteApiException({required String message, this.responseData})
    : super(message, responseData?.toString());

  @override
  String toString() {
    if (responseData != null) {
      return '$message\n$responseData';
    }
    return message;
  }
}

/// 异常转换工具类
/// 将原生异常转换为结构化的站点异常
class ApiExceptionAdapter {
  /// 截断内容的最大长度
  static const int _maxDetailLength = 200;

  static final RegExp _socketTimeoutPattern = RegExp(
    r'\btimed\s+out\b',
    caseSensitive: false,
  );

  /// 统一识别原生异常和站点异常中的超时，供异常转换与请求重试共用。
  /// 只展开无 HTTP 错误响应的 Dio 网络异常，不匹配普通错误的文本。
  static String? timeoutTypeOf(Object error) {
    Object? current = error;
    final visited = Set<Object>.identity();
    while (current != null && visited.add(current)) {
      if (current is SiteNetworkException) {
        return current.isTimeout ? current.timeoutType : null;
      }
      if (current is SiteException) return null;
      if (current is TimeoutException) return '请求超时';
      if (current is SocketException) {
        return _socketTimeoutPattern.hasMatch(current.message) ||
                _socketTimeoutPattern.hasMatch(current.osError?.message ?? '')
            ? '连接超时'
            : null;
      }
      if (current is! DioException) return null;

      // 取消、证书及 HTTP 错误不能因附带的旧异常而触发重试。
      if (current.type == DioExceptionType.cancel ||
          current.type == DioExceptionType.badCertificate ||
          current.type == DioExceptionType.badResponse ||
          (current.response?.statusCode ?? 0) >= 400) {
        return null;
      }
      // 与 wrapError 一致，保留已结构化的内部站点异常的含义。
      if (current.error is SiteException) {
        current = current.error;
        continue;
      }
      switch (current.type) {
        case DioExceptionType.connectionTimeout:
          return '连接超时';
        case DioExceptionType.sendTimeout:
          return '发送超时';
        case DioExceptionType.receiveTimeout:
          return '接收超时';
        default:
          current = current.error;
      }
    }
    return null;
  }

  /// Cloudflare 特征关键字
  static const List<String> _cfKeywords = [
    'cloudflare',
    'cf-ray',
    'challenge-form',
    'cf_chl_opt',
    'ray id:',
    'checking your browser',
  ];

  /// 将原生异常包装为站点异常
  /// [e] 原生异常
  /// [actionName] 操作名称，用于生成友好的错误提示
  static SiteException wrapError(dynamic e, String actionName) {
    // 如果已经是 SiteException，直接返回
    if (e is SiteException) {
      return e;
    }

    // 处理 Dio 异常
    if (e is DioException) {
      return _handleDioException(e, actionName);
    }

    final timeoutType = e is Object ? timeoutTypeOf(e) : null;
    if (timeoutType != null) {
      return SiteNetworkException(
        timeoutType: timeoutType,
        detail: _truncateDetail(e.toString()),
      );
    }

    // 其他异常包装为服务异常
    return SiteServiceException(
      message: '$actionName失败',
      detail: _truncateDetail(e.toString()),
    );
  }

  /// 处理 Dio 异常
  static SiteException _handleDioException(DioException e, String actionName) {
    final timeoutType = timeoutTypeOf(e);
    // 保留结构化站点异常，但不能让内部超时覆盖外层的取消或 HTTP 错误。
    final innerError = e.error;
    if (innerError is SiteException &&
        (innerError is! SiteNetworkException ||
            !innerError.isTimeout ||
            timeoutType != null)) {
      return innerError;
    }

    // 1. 超时检测
    if (timeoutType != null) {
      return SiteNetworkException(
        timeoutType: timeoutType,
        detail: _truncateDetail(e.error?.toString()),
      );
    }

    // 2. 响应状态码检测
    final response = e.response;
    if (response != null) {
      final statusCode = response.statusCode;
      final body = _extractBodyString(response.data);

      // 2.1 检测 Cloudflare
      if (_isCloudflareChallenge(body)) {
        return const CloudflareChallengeException();
      }

      // 2.2 认证失效 (401, 403, 302)
      if (statusCode == 401 || statusCode == 403 || statusCode == 302) {
        return SiteAuthenticationException(
          statusCode: statusCode,
          detail: _truncateDetail(body),
        );
      }

      // 2.3 服务端错误 (5xx)
      if (statusCode != null && statusCode >= 500) {
        return SiteServiceException(
          message: '$actionName时服务端异常',
          statusCode: statusCode,
          detail: _truncateDetail(body),
        );
      }

      // 2.4 其他 HTTP 错误
      return SiteServiceException(
        message: '$actionName失败',
        statusCode: statusCode,
        detail: _truncateDetail(body),
      );
    }

    // 3. 无响应的网络错误
    if (e.type == DioExceptionType.connectionError) {
      return SiteNetworkException(timeoutType: '连接失败', detail: e.message);
    }

    // 4. 其他 Dio 异常
    return SiteServiceException(
      message: '$actionName失败',
      detail: _truncateDetail(e.message ?? e.toString()),
    );
  }

  /// 检测是否为 Cloudflare 挑战页面
  static bool _isCloudflareChallenge(String? body) {
    if (body == null || body.isEmpty) return false;
    final lowerBody = body.toLowerCase();
    return _cfKeywords.any((keyword) => lowerBody.contains(keyword));
  }

  /// 从响应数据中提取字符串
  static String? _extractBodyString(dynamic data) {
    if (data == null) return null;
    if (data is String) return data;
    try {
      return data.toString();
    } catch (_) {
      return null;
    }
  }

  /// 截断详情内容
  static String? _truncateDetail(String? content) {
    if (content == null || content.isEmpty) return null;
    if (content.length <= _maxDetailLength) return content;
    return '${content.substring(0, _maxDetailLength)}...';
  }
}
