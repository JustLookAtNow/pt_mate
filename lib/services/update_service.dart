import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'device_id_service.dart';

class UpdateService {
  static const String _baseUrl =
      'https://ptmate.fly2sky.dpdns.org'; // 替换为实际的服务器地址
  static const String _lastCheckKey = 'last_update_check';
  static const Duration _checkInterval = Duration(hours: 24); // 24小时检查一次

  static UpdateService? _instance;
  static UpdateService get instance => _instance ??= UpdateService._();

  UpdateService._();

  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
      headers: {'Content-Type': 'application/json'},
    ),
  );

  /// 检查更新并上报统计信息
  Future<UpdateCheckResult?> checkForUpdates({bool force = false}) async {
    try {
      // 检查是否需要进行更新检查
      if (!force && !await _shouldCheckForUpdates()) {
        return null;
      }

      // 获取设备信息
      String deviceId = await DeviceIdService.instance.getDeviceId();
      String platform = DeviceIdService.instance.getPlatform();
      PackageInfo packageInfo = await PackageInfo.fromPlatform();

      // 构建请求数据
      Map<String, dynamic> requestData = {
        'device_id': deviceId,
        'platform': platform,
        'app_version': packageInfo.version,
      };

      // 发送请求
      Response response = await _dio.post(
        '$_baseUrl/api/v1/check-update',
        data: jsonEncode(requestData),
      );

      if (response.statusCode == 200) {
        // 更新最后检查时间
        await _updateLastCheckTime();

        // 解析响应
        Map<String, dynamic> responseData = response.data;
        return UpdateCheckResult.fromJson(responseData);
      }
    } catch (e) {
      if (kDebugMode) {
        print('Update check failed: $e');
      }
      // 网络错误时静默失败，不影响应用正常使用
    }

    return null;
  }

  /// 检查是否应该进行更新检查
  Future<bool> _shouldCheckForUpdates() async {
    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      int? lastCheck = prefs.getInt(_lastCheckKey);

      if (lastCheck == null) {
        return true; // 首次检查
      }

      DateTime lastCheckTime = DateTime.fromMillisecondsSinceEpoch(lastCheck);
      DateTime now = DateTime.now();

      return now.difference(lastCheckTime) >= _checkInterval;
    } catch (e) {
      return true; // 出错时默认检查
    }
  }

  /// 更新最后检查时间
  Future<void> _updateLastCheckTime() async {
    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_lastCheckKey, DateTime.now().millisecondsSinceEpoch);
    } catch (e) {
      // 忽略保存错误
    }
  }

  /// 手动触发更新检查
  Future<UpdateCheckResult?> manualCheckForUpdates() async {
    return await checkForUpdates(force: true);
  }

  /// 获取上次检查时间
  Future<DateTime?> getLastCheckTime() async {
    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      int? lastCheck = prefs.getInt(_lastCheckKey);

      if (lastCheck != null) {
        return DateTime.fromMillisecondsSinceEpoch(lastCheck);
      }
    } catch (e) {
      // 忽略错误
    }

    return null;
  }

  /// 设置服务器地址（用于配置）
  void setServerUrl(String url) {
    _dio.options.baseUrl = url;
  }

  /// 测试服务器连接
  Future<bool> testConnection() async {
    try {
      Response response = await _dio.get('$_baseUrl/health');
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }
}

/// 更新检查结果
class UpdateCheckResult {
  final bool hasUpdate;
  final String? latestVersion;
  final String? releaseNotes;
  final String? downloadUrl;

  UpdateCheckResult({
    required this.hasUpdate,
    this.latestVersion,
    this.releaseNotes,
    this.downloadUrl,
  });

  factory UpdateCheckResult.fromJson(Map<String, dynamic> json) {
    return UpdateCheckResult(
      hasUpdate: json['has_update'] ?? false,
      latestVersion: json['latest_version'],
      releaseNotes: json['release_notes'],
      downloadUrl: json['download_url'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'has_update': hasUpdate,
      'latest_version': latestVersion,
      'release_notes': releaseNotes,
      'download_url': downloadUrl,
    };
  }

  @override
  String toString() {
    return 'UpdateCheckResult(hasUpdate: $hasUpdate, latestVersion: $latestVersion)';
  }
}
