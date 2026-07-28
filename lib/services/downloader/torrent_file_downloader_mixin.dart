import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import '../../models/app_models.dart';

/// 种子文件下载通用逻辑混入
mixin TorrentFileDownloaderMixin {
  /// 下载种子文件并返回字节数据（用于本地中转）
  ///
  /// [dio] Dio实例，用于执行HTTP请求
  /// [url] 种子文件URL
  /// [siteConfig] 站点配置，用于在同源 Cookie 认证站点下载时附带登录态
  Future<List<int>> downloadTorrentFileCommon(
    Dio dio,
    String url, {
    SiteConfig? siteConfig,
  }) async {
    List<int> result;
    final requestUrl = url.startsWith('##') ? url.substring(2) : url;

    try {
      final headers = <String, dynamic>{};
      if (_shouldAttachSiteCookie(requestUrl, siteConfig)) {
        headers['Cookie'] = siteConfig!.cookie!;
      }

      final response = await dio.get<List<int>>(
        requestUrl,
        options: Options(
          responseType: ResponseType.bytes,
          followRedirects: true,
          maxRedirects: 5,
          headers: headers.isEmpty ? null : headers,
          validateStatus: (status) => status != null && status < 400,
        ),
      );

      if (response.realUri.toString().contains('login') ||
          response.realUri.toString().contains('verify')) {
        throw Exception('下载请求被重定向到登录页，请检查 Cookie');
      }

      if (response.data != null) {
        result = response.data!;
      } else {
        throw Exception('Failed to download torrent file: empty response');
      }
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        throw Exception('Authentication failed when downloading torrent file');
      }

      if (e.response?.statusCode != null && e.response!.statusCode! >= 400) {
        throw HttpException(
          'HTTP ${e.response!.statusCode} when downloading torrent file',
        );
      }

      throw Exception('Failed to download torrent file: ${e.message}');
    } catch (e) {
      throw Exception('Failed to download torrent file: $e');
    }

    // DEBUG: 保存文件以供检查
    if (kDebugMode) {
      try {
        if (Platform.isLinux) {
          final debugFile = File('/tmp/debug_ptmate.torrent');
          await debugFile.writeAsBytes(result);
          // ignore: avoid_print
          print(
            'DEBUG: Torrent file saved to ${debugFile.path}, size: ${result.length} bytes',
          );
        }

        if (result.isNotEmpty) {
          // 打印前100个字符，检查是否为HTML
          final prefix = String.fromCharCodes(result.take(100).toList());
          // ignore: avoid_print
          print('DEBUG: File content prefix: $prefix');
        }
      } catch (e) {
        // ignore: avoid_print
        print('DEBUG: Failed to save debug file: $e');
      }
    }

    return result;
  }

  bool _shouldAttachSiteCookie(String url, SiteConfig? siteConfig) {
    if (siteConfig == null ||
        !siteConfig.siteType.usesCookieAuthentication ||
        siteConfig.cookie == null ||
        siteConfig.cookie!.isEmpty) {
      return false;
    }

    final requestUri = Uri.tryParse(url);
    final siteUri = Uri.tryParse(siteConfig.baseUrl);
    if (requestUri == null || siteUri == null) return false;

    // 避免把站点 Cookie 发送给下载链接中意外出现的第三方域名。
    return requestUri.host.isEmpty || requestUri.host == siteUri.host;
  }
}
