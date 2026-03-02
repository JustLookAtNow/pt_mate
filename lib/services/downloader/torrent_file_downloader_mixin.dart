import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import '../../models/app_models.dart';
import '../api/nexusphp_web_adapter.dart';

/// 种子文件下载通用逻辑混入
mixin TorrentFileDownloaderMixin {
  /// 下载种子文件并返回字节数据（用于本地中转）
  ///
  /// [dio] Dio实例，用于执行HTTP请求
  /// [url] 种子文件URL
  /// [siteConfig] 站点配置，用于NexusPHPWeb适配器
  Future<List<int>> downloadTorrentFileCommon(
    Dio dio,
    String url, {
    SiteConfig? siteConfig,
  }) async {
    List<int> result;

    // 如果是NexusPHPWeb站点，使用适配器下载
    if (siteConfig?.siteType == SiteType.nexusphpweb) {
      try {
        final adapter = NexusPHPWebAdapter();
        await adapter.init(siteConfig!);
        result = await adapter.downloadTorrent(url);
      } catch (e) {
        // 如果适配器下载失败，尝试降级到普通下载（虽然可能因为缺Cookie失败）
        // 或者直接抛出异常
        throw Exception('NexusPHPWebAdapter下载失败: $e');
      }
    } else {
      try {
        final response = await dio.get<List<int>>(
          url,
          options: Options(
            responseType: ResponseType.bytes,
            followRedirects: true,
            maxRedirects: 5,
            validateStatus: (status) => status != null && status < 400,
          ),
        );

        if (response.data != null) {
          result = response.data!;
        } else {
          throw Exception('Failed to download torrent file: empty response');
        }
      } on DioException catch (e) {
        if (e.response?.statusCode == 401) {
          throw Exception(
            'Authentication failed when downloading torrent file',
          );
        }

        if (e.response?.statusCode != null && e.response!.statusCode! >= 400) {
          throw HttpException(
            'HTTP ${e.response!.statusCode} when downloading torrent file: ${e.response!.data}',
          );
        }

        throw Exception('Failed to download torrent file: ${e.message}');
      } catch (e) {
        throw Exception('Failed to download torrent file: $e');
      }
    }

    // DEBUG: 保存文件以供检查
    if (kDebugMode) {
      try {
        final debugFile = File('/tmp/debug_ptmate.torrent');
        await debugFile.writeAsBytes(result);
        // ignore: avoid_print
        print(
          'DEBUG: Torrent file saved to ${debugFile.path}, size: ${result.length} bytes',
        );

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
}
