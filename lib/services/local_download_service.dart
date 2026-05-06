import 'dart:io';
import 'package:archive/archive.dart';
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/app_models.dart';
import 'downloader/torrent_file_downloader_mixin.dart';

/// 本地下载服务
///
/// 提供种子文件下载并保存到本地设备的功能
class LocalDownloadService with TorrentFileDownloaderMixin {
  static final LocalDownloadService instance = LocalDownloadService._();

  LocalDownloadService._();

  late final Dio _dio = Dio();

  /// 请求存储权限（仅Android 9及以下需要）
  ///
  /// 返回true表示已获得权限，false表示权限被拒绝
  Future<bool> requestStoragePermission() async {
    if (Platform.isAndroid) {
      // Android 10+ (API 29+) 使用SAF机制，无需额外权限
      final androidInfo = await _getAndroidSdkVersion();
      if (androidInfo >= 29) {
        return true;
      }

      // Android 9及以下需要存储权限
      final status = await Permission.storage.status;
      if (status.isGranted) {
        return true;
      }

      final result = await Permission.storage.request();
      return result.isGranted;
    }

    // iOS/macOS/Linux/Windows 无需额外权限
    return true;
  }

  /// 获取Android SDK版本
  Future<int> _getAndroidSdkVersion() async {
    try {
      // 使用device_info_plus获取Android版本
      // 这里简化处理，假设大多数设备都是Android 10+
      // 实际项目中应该使用device_info_plus包
      return 29; // 默认返回29，避免不必要的权限请求
    } catch (e) {
      return 29;
    }
  }

  /// 下载单个种子文件并保存到本地
  ///
  /// [downloadUrl] 种子下载链接
  /// [torrentName] 种子名称（用作文件名）
  /// [siteConfig] 站点配置（用于NexusPHPWeb适配器）
  ///
  /// 返回保存的文件路径，失败返回null
  Future<String?> downloadAndSaveTorrent({
    required String downloadUrl,
    required String torrentName,
    SiteConfig? siteConfig,
  }) async {
    try {
      // 检查权限
      final hasPermission = await requestStoragePermission();
      if (!hasPermission) {
        throw Exception('没有存储权限，无法保存文件');
      }

      // 下载种子文件
      final torrentData = await _downloadTorrentData(
        downloadUrl,
        siteConfig: siteConfig,
      );

      // 确保文件名以.torrent结尾
      String fileName = torrentName;
      if (!fileName.endsWith('.torrent')) {
        fileName = '$fileName.torrent';
      }

      // 处理文件名中的特殊字符
      fileName = _sanitizeFileName(fileName);

      // 使用文件选择器保存文件
      final savePath = await _saveWithPicker(fileName, torrentData);

      return savePath;
    } catch (e) {
      if (kDebugMode) {
        print('下载种子文件失败: $e');
      }
      rethrow;
    }
  }

  /// 批量下载种子文件并打包成zip保存
  ///
  /// [items] 下载项列表
  /// [onProgress] 进度回调
  ///
  /// 返回保存的zip文件路径，失败返回null
  Future<String?> batchDownloadAndSaveAsZip({
    required List<TorrentDownloadItem> items,
    void Function(int current, int total, String? currentName)? onProgress,
  }) async {
    try {
      // 检查权限
      final hasPermission = await requestStoragePermission();
      if (!hasPermission) {
        throw Exception('没有存储权限，无法保存文件');
      }

      final archive = Archive();

      for (int i = 0; i < items.length; i++) {
        final item = items[i];
        onProgress?.call(i + 1, items.length, item.torrentName);

        try {
          final torrentData = await _downloadTorrentData(
            item.downloadUrl,
            siteConfig: item.siteConfig,
          );

          // 确保文件名以.torrent结尾
          String fileName = item.torrentName;
          if (!fileName.endsWith('.torrent')) {
            fileName = '$fileName.torrent';
          }
          fileName = _sanitizeFileName(fileName);

          // 处理文件名冲突：如果zip中已有同名文件，添加序号
          String uniqueFileName = fileName;
          int counter = 1;
          while (archive.files.any((f) => f.name == uniqueFileName)) {
            final nameWithoutExt = fileName.replaceAll('.torrent', '');
            uniqueFileName = '$nameWithoutExt ($counter).torrent';
            counter++;
          }

          // 添加到archive
          final archiveFile = ArchiveFile(
            uniqueFileName,
            torrentData.length,
            torrentData,
          );
          archive.addFile(archiveFile);
        } catch (e) {
          if (kDebugMode) {
            print('批量下载失败 [${item.torrentName}]: $e');
          }
          // 继续下载其他文件，不中断批量操作
        }
      }

      if (archive.files.isEmpty) {
        throw Exception('没有成功下载任何种子文件');
      }

      // 编码zip文件
      final zipData = ZipEncoder().encode(archive);

      // 生成zip文件名
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final zipFileName = 'torrents_$timestamp.zip';

      // 使用文件选择器保存zip文件
      final savePath = await _saveWithPicker(zipFileName, zipData);

      return savePath;
    } catch (e) {
      if (kDebugMode) {
        print('批量下载种子文件失败: $e');
      }
      rethrow;
    }
  }

  /// 下载种子文件并验证
  Future<List<int>> _downloadTorrentData(
    String downloadUrl, {
    SiteConfig? siteConfig,
  }) async {
    final torrentData = await downloadTorrentFileCommon(
      _dio,
      downloadUrl,
      siteConfig: siteConfig,
    );

    if (torrentData.isEmpty) {
      throw Exception('下载的种子文件为空');
    }

    // 验证是否为有效的种子文件（bencode格式以'd'开头）
    if (!_isValidTorrentData(torrentData)) {
      throw Exception('下载的文件不是有效的种子文件（可能是HTML登录页面）');
    }

    return torrentData;
  }

  /// 验证种子文件数据是否有效
  ///
  /// 有效的种子文件是bencode编码的字典，以字符'd'（ASCII 100）开头
  /// 这个简单的启发式检查可以快速拒绝HTML文件（通常以'<'开头）
  bool _isValidTorrentData(List<int> data) {
    if (data.isEmpty) return false;
    // bencode字典以'd'开头
    return data.first == 100; // ASCII 'd'
  }

  /// 使用文件选择器保存文件
  Future<String?> _saveWithPicker(String fileName, List<int> data) async {
    String? result;

    if (Platform.isLinux) {
      // Linux需要指定初始目录
      final initialDirectory =
          Platform.environment['HOME'] ?? Directory.current.path;
      result = await FilePicker.saveFile(
        dialogTitle: '保存种子文件',
        fileName: fileName,
        initialDirectory: initialDirectory,
        type: FileType.custom,
        allowedExtensions: ['zip', 'torrent'],
      );

      if (result != null) {
        final file = File(result);
        await file.writeAsBytes(data);
      }
    } else {
      // 其他平台使用FilePicker的bytes参数
      result = await FilePicker.saveFile(
        dialogTitle: '保存种子文件',
        fileName: fileName,
        type: FileType.custom,
        allowedExtensions: ['zip', 'torrent'],
        bytes: Uint8List.fromList(data),
      );
    }

    return result;
  }

  /// 清理文件名中的特殊字符
  String _sanitizeFileName(String fileName) {
    // 移除或替换文件系统不允许的字符
    return fileName
        .replaceAll('/', '_')
        .replaceAll('\\', '_')
        .replaceAll(':', '_')
        .replaceAll('*', '_')
        .replaceAll('?', '_')
        .replaceAll('"', '_')
        .replaceAll('<', '_')
        .replaceAll('>', '_')
        .replaceAll('|', '_');
  }
}

/// 种子下载项数据类
class TorrentDownloadItem {
  final String downloadUrl;
  final String torrentName;
  final SiteConfig? siteConfig;

  const TorrentDownloadItem({
    required this.downloadUrl,
    required this.torrentName,
    this.siteConfig,
  });
}
