import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class AndroidInstallPermissionService {
  AndroidInstallPermissionService._();

  static final AndroidInstallPermissionService instance =
      AndroidInstallPermissionService._();

  static const MethodChannel _channel = MethodChannel(
    'pt_mate/android_install_permission',
  );

  bool get supportsInstallPermissionCheck =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Future<bool> isInstallPermissionGranted() async {
    if (!supportsInstallPermissionCheck) {
      return true;
    }

    final granted = await _channel.invokeMethod<bool>(
      'isInstallPermissionGranted',
    );
    return granted ?? false;
  }

  Future<bool> openInstallPermissionSettings() async {
    if (!supportsInstallPermissionCheck) {
      return false;
    }

    final opened = await _channel.invokeMethod<bool>(
      'openInstallPermissionSettings',
    );
    return opened ?? false;
  }

  Future<String> getUpdateApkPath(String filename) async {
    final path = await _channel.invokeMethod<String>('getUpdateApkPath', {
      'filename': filename,
    });
    if (path == null) throw StateError('无法创建更新包文件');
    return path;
  }

  Future<bool> completeUpdateDownload(String filename) async {
    return await _channel.invokeMethod<bool>('completeUpdateDownload', {
          'filename': filename,
        }) ??
        false;
  }

  Future<bool> tryInstallDownloadedApk(String filename) async {
    if (!supportsInstallPermissionCheck) return false;
    return await _channel.invokeMethod<bool>('tryInstallDownloadedApk', {
          'filename': filename,
        }) ??
        false;
  }

  Future<int> clearDownloadedApks() async {
    if (!supportsInstallPermissionCheck) {
      return 0;
    }

    final deletedCount = await _channel.invokeMethod<int>(
      'clearDownloadedApks',
    );
    return deletedCount ?? 0;
  }
}
