import 'dart:io';

import 'package:archive/archive.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/app_models.dart';
import 'downloader/torrent_file_downloader_mixin.dart';
import 'storage/storage_service.dart';

/// 本地下载服务
///
/// 提供种子文件下载并保存到本地设备的功能。
class LocalDownloadService with TorrentFileDownloaderMixin {
  static final LocalDownloadService instance = LocalDownloadService._();

  LocalDownloadService._();

  static const String downloadsDisplayPath = 'Downloads/PT Mate';
  static const MethodChannel _androidDownloadsChannel = MethodChannel(
    'pt_mate/local_downloads',
  );

  late final Dio _dio = Dio();

  /// 请求存储权限（仅 Android 9 及以下需要）。
  Future<bool> requestStoragePermission() async {
    if (Platform.isAndroid) {
      final androidSdk = await _getAndroidSdkVersion();
      if (androidSdk >= 29) {
        return true;
      }

      final status = await Permission.storage.status;
      if (status.isGranted) {
        return true;
      }

      final result = await Permission.storage.request();
      return result.isGranted;
    }

    return true;
  }

  Future<int> _getAndroidSdkVersion() async {
    try {
      final info = await DeviceInfoPlugin().androidInfo;
      return info.version.sdkInt;
    } catch (_) {
      return 29;
    }
  }

  Future<String> getLocalDownloadDisplayPath() async {
    if (!Platform.isAndroid) {
      return '用户选择的位置';
    }

    try {
      return await _androidDownloadsChannel.invokeMethod<String>(
            'getDownloadsDisplayPath',
          ) ??
          downloadsDisplayPath;
    } catch (_) {
      return downloadsDisplayPath;
    }
  }

  Future<String> getLocalDownloadHint() async {
    if (Platform.isAndroid) {
      return '每个种子会单独保存为 .torrent 文件。';
    }

    return '将使用系统保存面板选择保存位置。';
  }

  /// 下载单个种子文件并保存到本地。
  Future<String?> downloadAndSaveTorrent({
    required String downloadUrl,
    required String torrentName,
    SiteConfig? siteConfig,
  }) async {
    try {
      final hasPermission = await requestStoragePermission();
      if (!hasPermission) {
        throw Exception('没有存储权限，无法保存文件');
      }

      final torrentData = await _downloadTorrentData(
        downloadUrl,
        siteConfig: siteConfig,
      );
      final fileName = _buildTorrentFileName(torrentName);

      return Platform.isAndroid
          ? await _saveToAndroidDownloads(fileName, torrentData)
          : await _saveWithPicker(fileName, torrentData);
    } catch (e) {
      if (kDebugMode) {
        print('下载种子文件失败: $e');
      }
      rethrow;
    }
  }

  /// 批量下载种子文件并保存到本地。
  ///
  /// Android 直接保存多个 .torrent 文件到 Downloads/PT Mate。
  /// 其他平台仍打包成 zip 并通过保存面板导出。
  Future<BatchLocalDownloadResult> batchDownloadAndSave({
    required List<TorrentDownloadItem> items,
    void Function(int current, int total, String? currentName)? onProgress,
  }) async {
    try {
      final hasPermission = await requestStoragePermission();
      if (!hasPermission) {
        throw Exception('没有存储权限，无法保存文件');
      }

      if (Platform.isAndroid) {
        return await _batchDownloadAndSaveToAndroidDownloads(
          items: items,
          onProgress: onProgress,
        );
      }

      final savePath = await _batchDownloadAndSaveAsZipWithPicker(
        items: items,
        onProgress: onProgress,
      );

      return BatchLocalDownloadResult(
        displayPath: savePath,
        savedCount: savePath == null ? 0 : items.length,
        failedItems: const [],
        usedZipFallback: true,
      );
    } catch (e) {
      if (kDebugMode) {
        print('批量下载种子文件失败: $e');
      }
      rethrow;
    }
  }

  Future<BatchLocalDownloadResult> _batchDownloadAndSaveToAndroidDownloads({
    required List<TorrentDownloadItem> items,
    void Function(int current, int total, String? currentName)? onProgress,
  }) async {
    final failedItems = <BatchLocalDownloadFailure>[];
    var savedCount = 0;

    for (int i = 0; i < items.length; i++) {
      final item = items[i];
      onProgress?.call(i + 1, items.length, item.torrentName);

      try {
        final torrentData = await _downloadTorrentData(
          item.downloadUrl,
          siteConfig: item.siteConfig,
        );
        final fileName = _buildTorrentFileName(item.torrentName);
        await _saveToAndroidDownloads(fileName, torrentData);
        savedCount++;
      } catch (e) {
        failedItems.add(
          BatchLocalDownloadFailure(
            itemId: item.id,
            torrentName: item.torrentName,
            error: e.toString(),
          ),
        );
        if (kDebugMode) {
          print('批量下载失败 [${item.torrentName}]: $e');
        }
      }
    }

    if (savedCount == 0) {
      throw Exception('没有成功下载任何种子文件');
    }

    return BatchLocalDownloadResult(
      displayPath: await getLocalDownloadDisplayPath(),
      savedCount: savedCount,
      failedItems: failedItems,
      usedZipFallback: false,
    );
  }

  Future<String?> _batchDownloadAndSaveAsZipWithPicker({
    required List<TorrentDownloadItem> items,
    void Function(int current, int total, String? currentName)? onProgress,
  }) async {
    final archive = Archive();

    for (int i = 0; i < items.length; i++) {
      final item = items[i];
      onProgress?.call(i + 1, items.length, item.torrentName);

      try {
        final torrentData = await _downloadTorrentData(
          item.downloadUrl,
          siteConfig: item.siteConfig,
        );
        final fileName = _buildTorrentFileName(item.torrentName);

        String uniqueFileName = fileName;
        int counter = 1;
        while (archive.files.any((f) => f.name == uniqueFileName)) {
          final nameWithoutExt = fileName.replaceAll('.torrent', '');
          uniqueFileName = '$nameWithoutExt ($counter).torrent';
          counter++;
        }

        archive.addFile(
          ArchiveFile(uniqueFileName, torrentData.length, torrentData),
        );
      } catch (e) {
        if (kDebugMode) {
          print('批量下载失败 [${item.torrentName}]: $e');
        }
      }
    }

    if (archive.files.isEmpty) {
      throw Exception('没有成功下载任何种子文件');
    }

    final zipData = ZipEncoder().encode(archive);
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    return _saveWithPicker('torrents_$timestamp.zip', zipData);
  }

  Future<String> _saveToAndroidDownloads(
    String fileName,
    List<int> data,
  ) async {
    try {
      return await _androidDownloadsChannel
              .invokeMethod<String>('saveToDownloads', {
                'fileName': fileName,
                'bytes': Uint8List.fromList(data),
                'mimeType': fileName.toLowerCase().endsWith('.zip')
                    ? 'application/zip'
                    : 'application/x-bittorrent',
              }) ??
          '$downloadsDisplayPath/$fileName';
    } on MissingPluginException catch (e) {
      if (kDebugMode) {
        print('Android Downloads 保存通道不可用，回退到保存面板: $e');
      }
      final savePath = await _saveWithPicker(fileName, data);
      if (savePath == null) {
        throw Exception('用户取消保存');
      }
      return savePath;
    } on PlatformException catch (e) {
      throw Exception(e.message ?? '保存到 Downloads 失败');
    }
  }

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

    if (!_isValidTorrentData(torrentData)) {
      throw Exception('下载的文件不是有效的种子文件（可能是HTML登录页面）');
    }

    return torrentData;
  }

  bool _isValidTorrentData(List<int> data) {
    if (data.isEmpty) return false;
    return data.first == 100; // ASCII 'd'
  }

  String _buildTorrentFileName(String torrentName) {
    String fileName = torrentName;
    if (!fileName.toLowerCase().endsWith('.torrent')) {
      fileName = '$fileName.torrent';
    }
    return _sanitizeFileName(fileName);
  }

  Future<String?> _saveWithPicker(String fileName, List<int> data) async {
    final initialDirectory = await _resolveInitialDirectory();
    final result = await FilePicker.saveFile(
      dialogTitle: '保存种子文件',
      fileName: fileName,
      initialDirectory: initialDirectory,
      type: FileType.custom,
      allowedExtensions: ['zip', 'torrent'],
      bytes: Uint8List.fromList(data),
    );

    if (result == null) {
      return null;
    }

    await _rememberSaveDirectory(result);

    if (Platform.isLinux) {
      final file = File(result);
      await file.writeAsBytes(data);
    }

    return result;
  }

  Future<String?> _resolveInitialDirectory() async {
    final lastDirectory = await StorageService.instance
        .loadLocalDownloadLastDirectory();
    if (lastDirectory != null && Directory(lastDirectory).existsSync()) {
      return lastDirectory;
    }

    if (Platform.isLinux) {
      return Platform.environment['HOME'] ?? Directory.current.path;
    }

    return null;
  }

  Future<void> _rememberSaveDirectory(String filePath) async {
    if (Platform.isAndroid) {
      return;
    }

    final directory = File(filePath).parent.path;
    await StorageService.instance.saveLocalDownloadLastDirectory(directory);
  }

  String _sanitizeFileName(String fileName) {
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

class BatchLocalDownloadResult {
  final String? displayPath;
  final int savedCount;
  final List<BatchLocalDownloadFailure> failedItems;
  final bool usedZipFallback;

  const BatchLocalDownloadResult({
    required this.displayPath,
    required this.savedCount,
    required this.failedItems,
    required this.usedZipFallback,
  });

  int get failedCount => failedItems.length;
}

class BatchLocalDownloadFailure {
  final String? itemId;
  final String torrentName;
  final String error;

  const BatchLocalDownloadFailure({
    required this.itemId,
    required this.torrentName,
    required this.error,
  });
}

/// 种子下载项数据类。
class TorrentDownloadItem {
  final String? id;
  final String downloadUrl;
  final String torrentName;
  final SiteConfig? siteConfig;

  const TorrentDownloadItem({
    this.id,
    required this.downloadUrl,
    required this.torrentName,
    this.siteConfig,
  });
}
