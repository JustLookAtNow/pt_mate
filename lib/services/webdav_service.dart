import 'dart:convert';

import 'package:webdav_client/webdav_client.dart' as webdav;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_models.dart';
import 'storage/storage_service.dart';

// 连接测试结果类
class WebDAVTestResult {
  final bool success;
  final String? errorMessage;

  WebDAVTestResult({required this.success, this.errorMessage});
}

class WebDAVService {
  static const String _configKey = 'webdav_config';
  static const String _lastSyncKey = 'webdav_last_sync';
  static const String _autoSyncKey = 'webdav_auto_sync';

  WebDAVService._();
  static final WebDAVService instance = WebDAVService._();

  webdav.Client? _client;
  WebDAVConfig? _currentConfig;
  final StorageService _storageService = StorageService.instance;

  // 配置管理
  Future<void> saveConfig(WebDAVConfig config, {String? password}) async {
    // 敏感值必须先写入并读回；失败时不能留下新的普通配置。
    if (password != null) {
      await _storageService.saveWebDAVPassword(config.id, password);
    }

    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(config.toJson());
    final committed = await prefs.setString(_configKey, encoded);
    if (!committed || prefs.getString(_configKey) != encoded) {
      throw StateError('webdav_config_commit_failed');
    }

    _currentConfig = config;
    _client = null; // 重置客户端，下次使用时重新创建
  }

  Future<WebDAVConfig?> loadConfig() async {
    if (_currentConfig != null) return _currentConfig;

    final prefs = await SharedPreferences.getInstance();
    final configStr = prefs.getString(_configKey);
    if (configStr == null) return null;

    try {
      final json = jsonDecode(configStr) as Map<String, dynamic>;
      _currentConfig = WebDAVConfig.fromJson(json);
      return _currentConfig;
    } catch (e) {
      return null;
    }
  }

  Future<List<WebDAVConfig>> loadConfigHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final historyStr = prefs.getString('${_configKey}_history');
    if (historyStr == null) return [];

    try {
      final list = (jsonDecode(historyStr) as List)
          .cast<Map<String, dynamic>>();
      return list.map((json) => WebDAVConfig.fromJson(json)).toList();
    } catch (e) {
      return [];
    }
  }

  Future<void> saveConfigHistory(List<WebDAVConfig> configs) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = configs.map((config) => config.toJson()).toList();
    await prefs.setString('${_configKey}_history', jsonEncode(jsonList));
  }

  // 自动同步设置
  Future<void> setAutoSync(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_autoSyncKey, enabled);
  }

  Future<bool> getAutoSync() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_autoSyncKey) ?? false;
  }

  Future<DateTime?> getLastSyncTime() async {
    final prefs = await SharedPreferences.getInstance();
    final timestamp = prefs.getInt(_lastSyncKey);
    return timestamp != null
        ? DateTime.fromMillisecondsSinceEpoch(timestamp)
        : null;
  }

  Future<void> _setLastSyncTime(
    DateTime time, {
    int? expectedSecureStorageEpoch,
  }) async {
    final expected = expectedSecureStorageEpoch;
    if (expected != null) {
      _storageService.requireSecureStorageOperationEpoch(expected);
    }
    final prefs = await SharedPreferences.getInstance();
    if (expected != null) {
      _storageService.requireSecureStorageOperationEpoch(expected);
    }
    final timestamp = time.millisecondsSinceEpoch;
    final committed = await prefs.setInt(_lastSyncKey, timestamp);
    if (expected != null) {
      _storageService.requireSecureStorageOperationEpoch(expected);
    }
    if (!committed || prefs.getInt(_lastSyncKey) != timestamp) {
      throw StateError('webdav_last_sync_commit_failed');
    }
  }

  // WebDAV客户端管理
  Future<webdav.Client?> _getClient() async {
    final config = await loadConfig();
    if (config == null || !config.isEnabled) return null;

    // 从安全存储中获取密码
    final password = await _storageService.loadWebDAVPassword(config.id);
    if (password == null || password.isEmpty) return null;

    // 检查配置是否发生变化，如果变化则重新创建客户端
    if (_client != null && _currentConfig != null) {
      final currentPassword = await _storageService.loadWebDAVPassword(
        _currentConfig!.id,
      );
      if (_currentConfig!.serverUrl != config.serverUrl ||
          _currentConfig!.username != config.username ||
          currentPassword != password) {
        _client = null; // 配置变化，重置客户端
      }
    }

    if (_client != null) return _client;

    _currentConfig = config;
    _client = webdav.newClient(
      config.serverUrl,
      user: config.username,
      password: password,
    );
    _client!.setConnectTimeout(30000); // 30秒超时
    _client!.setSendTimeout(30000);
    _client!.setReceiveTimeout(30000);

    return _client;
  }

  // 连接测试
  Future<WebDAVTestResult> testConnection([
    WebDAVConfig? config,
    String? password,
  ]) async {
    try {
      final testConfig = config ?? await loadConfig();
      if (testConfig == null) {
        return WebDAVTestResult(success: false, errorMessage: '未找到WebDAV配置');
      }

      // 获取密码：优先使用传入的密码，否则从安全存储中获取
      final testPassword =
          password ?? await _storageService.loadWebDAVPassword(testConfig.id);
      if (testPassword == null || testPassword.isEmpty) {
        return WebDAVTestResult(success: false, errorMessage: '密码不能为空');
      }

      final client = webdav.newClient(
        testConfig.serverUrl,
        user: testConfig.username,
        password: testPassword,
      );
      client.setConnectTimeout(30000); // 30秒超时
      client.setSendTimeout(30000);
      client.setReceiveTimeout(30000);

      // 尝试读取根目录
      await client.readDir('/');
      return WebDAVTestResult(success: true);
    } on SecureStorageUnavailableException {
      rethrow;
    } catch (e) {
      String errorMessage = '连接失败';
      if (e.toString().contains('timeout')) {
        errorMessage = '连接超时，请检查服务器地址和网络连接';
      } else if (e.toString().contains('401') ||
          e.toString().contains('Unauthorized')) {
        errorMessage = '用户名或密码错误';
      } else if (e.toString().contains('404') ||
          e.toString().contains('Not Found')) {
        errorMessage = '服务器地址不正确或WebDAV服务未启用';
      } else if (e.toString().contains('SSL') ||
          e.toString().contains('certificate')) {
        errorMessage = 'SSL证书验证失败，请检查HTTPS配置';
      } else {
        errorMessage = '连接失败: ${e.toString()}';
      }
      return WebDAVTestResult(success: false, errorMessage: errorMessage);
    }
  }

  // 备份上传
  Future<void> uploadBackup(String backupData, {String? filename}) async {
    await _runWithStableSecureStorageEpoch((epoch) async {
      try {
        final client = await _getClient();
        if (client == null) {
          throw Exception('无法创建WebDAV客户端，请检查配置');
        }

        final config = _currentConfig!;
        final now = DateTime.now();
        final backupFilename =
            filename ?? 'pt_mate_backup_${now.millisecondsSinceEpoch}.json';
        final remotePath = '${config.remotePath}/$backupFilename';

        // 确保远程目录存在
        await _ensureDirectoryExists(
          client,
          config.remotePath,
          expectedSecureStorageEpoch: epoch,
        );

        // 上传备份文件
        _storageService.requireSecureStorageOperationEpoch(epoch);
        final bytes = utf8.encode(backupData);
        await client.write(remotePath, bytes);
        _storageService.requireSecureStorageOperationEpoch(epoch);

        await _setLastSyncTime(
          DateTime.now(),
          expectedSecureStorageEpoch: epoch,
        );
      } on SecureStorageUnavailableException {
        rethrow;
      } catch (e) {
        // 重新抛出异常，让调用方能够获取具体的错误信息
        throw Exception('WebDAV上传失败: $e');
      }
    });
  }

  // 备份下载
  Future<String?> downloadLatestBackup() async {
    return _runWithStableSecureStorageEpoch((epoch) async {
      try {
        final client = await _getClient();
        if (client == null) return null;

        final config = _currentConfig!;

        // 列出远程目录中的备份文件
        final files = await client.readDir(config.remotePath);
        final backupFiles = files
            .where((file) => file.name?.endsWith('.json') == true)
            .toList();

        if (backupFiles.isEmpty) return null;

        // 按修改时间排序，获取最新的备份
        backupFiles.sort(
          (a, b) => (b.mTime ?? DateTime(0)).compareTo(a.mTime ?? DateTime(0)),
        );
        final latestFile = backupFiles.first;

        // 下载最新备份
        final remotePath = '${config.remotePath}/${latestFile.name}';
        final bytes = await client.read(remotePath);
        _storageService.requireSecureStorageOperationEpoch(epoch);

        await _setLastSyncTime(
          DateTime.now(),
          expectedSecureStorageEpoch: epoch,
        );
        return utf8.decode(bytes);
      } on SecureStorageUnavailableException {
        rethrow;
      } catch (e) {
        return null;
      }
    });
  }

  // 获取远程备份列表
  Future<List<Map<String, dynamic>>> getRemoteBackups() async {
    return _runWithStableSecureStorageEpoch((epoch) async {
      try {
        final client = await _getClient();
        if (client == null) return [];

        final config = _currentConfig!;

        final files = await client.readDir(config.remotePath);
        _storageService.requireSecureStorageOperationEpoch(epoch);
        final backupFiles = files
            .where((file) => file.name?.endsWith('.json') == true)
            .map(
              (file) => {
                'name': file.name,
                'size': file.size,
                'modifiedTime': file.mTime,
                'path': '${config.remotePath}/${file.name}',
              },
            )
            .toList();

        // 按修改时间倒序排列
        backupFiles.sort(
          (a, b) => (b['modifiedTime'] as DateTime? ?? DateTime(0)).compareTo(
            a['modifiedTime'] as DateTime? ?? DateTime(0),
          ),
        );

        return backupFiles;
      } on SecureStorageUnavailableException {
        rethrow;
      } catch (e) {
        return [];
      }
    });
  }

  // 下载指定备份
  Future<String?> downloadBackup(String remotePath) async {
    return _runWithStableSecureStorageEpoch((epoch) async {
      try {
        final client = await _getClient();
        if (client == null) return null;

        final bytes = await client.read(remotePath);
        _storageService.requireSecureStorageOperationEpoch(epoch);
        return utf8.decode(bytes);
      } on SecureStorageUnavailableException {
        rethrow;
      } catch (e) {
        return null;
      }
    });
  }

  // 删除远程备份
  Future<bool> deleteRemoteBackup(String remotePath) async {
    return _runWithStableSecureStorageEpoch((epoch) async {
      try {
        final client = await _getClient();
        if (client == null) return false;

        _storageService.requireSecureStorageOperationEpoch(epoch);
        await client.remove(remotePath);
        _storageService.requireSecureStorageOperationEpoch(epoch);
        return true;
      } on SecureStorageUnavailableException {
        rethrow;
      } catch (e) {
        return false;
      }
    });
  }

  // 清理旧备份（保留指定数量的最新备份）
  Future<void> cleanupOldBackups({int keepCount = 10}) async {
    await _runWithStableSecureStorageEpoch((epoch) async {
      try {
        final backups = await getRemoteBackups();
        if (backups.length <= keepCount) return;

        final client = await _getClient();
        if (client == null) return;

        // 删除超出保留数量的旧备份
        final toDelete = backups.skip(keepCount);
        for (final backup in toDelete) {
          _storageService.requireSecureStorageOperationEpoch(epoch);
          try {
            await client.remove(backup['path'] as String);
            _storageService.requireSecureStorageOperationEpoch(epoch);
          } on SecureStorageUnavailableException {
            rethrow;
          } catch (e) {
            // 忽略单个文件删除失败
          }
        }
      } on SecureStorageUnavailableException {
        rethrow;
      } catch (e) {
        // 忽略清理失败
      }
    });
  }

  // 自动同步
  Future<bool> performAutoSync() async {
    await _requireSecureStorageReady();
    if (!await getAutoSync()) return false;

    try {
      // 获取本地最新备份
      // 这里需要与BackupService集成，暂时返回true
      // final localBackup = await BackupService.instance.createBackup();
      // return await uploadBackup(localBackup);
      return true;
    } catch (e) {
      return false;
    }
  }

  // 确保远程目录存在
  Future<void> _ensureDirectoryExists(
    webdav.Client client,
    String path, {
    required int expectedSecureStorageEpoch,
  }) async {
    try {
      await client.readDir(path);
    } catch (e) {
      if (e is SecureStorageUnavailableException) rethrow;
      // 目录不存在，尝试创建
      try {
        _storageService.requireSecureStorageOperationEpoch(
          expectedSecureStorageEpoch,
        );
        await client.mkdir(path);
      } catch (e) {
        if (e is SecureStorageUnavailableException) rethrow;
        // 创建失败，可能是父目录不存在，递归创建
        final parts = path.split('/').where((part) => part.isNotEmpty).toList();
        String currentPath = '';
        for (final part in parts) {
          currentPath += '/$part';
          try {
            _storageService.requireSecureStorageOperationEpoch(
              expectedSecureStorageEpoch,
            );
            await client.mkdir(currentPath);
          } on SecureStorageUnavailableException {
            rethrow;
          } catch (e) {
            // 忽略已存在的目录错误
          }
        }
      }
    }
  }

  // 获取同步状态
  Future<WebDAVSyncStatus> getSyncStatus() async {
    final config = await loadConfig();
    if (config == null || !config.isEnabled) {
      return WebDAVSyncStatus.idle;
    }

    final testResult = await testConnection();
    if (!testResult.success) {
      return WebDAVSyncStatus.error;
    }

    final lastSync = await getLastSyncTime();
    if (lastSync == null) {
      return WebDAVSyncStatus.idle;
    }

    final now = DateTime.now();
    final timeDiff = now.difference(lastSync);

    if (timeDiff.inHours < 1) {
      return WebDAVSyncStatus.success;
    } else if (timeDiff.inDays < 1) {
      return WebDAVSyncStatus.success;
    } else {
      return WebDAVSyncStatus.error;
    }
  }

  // 删除配置
  Future<void> deleteConfig() async {
    final config = await loadConfig();
    if (config != null) {
      // 删除安全存储中的密码
      await _storageService.deleteWebDAVPassword(config.id);
    }

    final prefs = await SharedPreferences.getInstance();
    final committed = await prefs.remove(_configKey);
    if (!committed || prefs.containsKey(_configKey)) {
      throw StateError('webdav_config_delete_failed');
    }
    _currentConfig = null;
    _client = null;
  }

  // 获取密码（用于UI显示等场景）
  Future<String?> getPassword(String configId) async {
    return await _storageService.loadWebDAVPassword(configId);
  }

  Future<void> _requireSecureStorageReady() async {
    await _storageService.initializeSecureStorage();
    if (!_storageService.canAccessSensitiveStorage) {
      throw SecureStorageUnavailableException(
        _storageService.secureStorageFailureCode ?? 'secure_storage_not_ready',
      );
    }
  }

  Future<T> _runWithStableSecureStorageEpoch<T>(
    Future<T> Function(int epoch) operation,
  ) {
    // Capture synchronously whenever a run is already usable. Awaiting an
    // already-complete initialization Future would otherwise leave a
    // microtask-sized window for a failure + retry to replace this epoch.
    if (_storageService.canAccessSensitiveStorage) {
      final epoch = _storageService.captureSecureStorageOperationEpoch();
      return _storageService.runWithSecureStorageOperationEpoch(
        epoch,
        () => operation(epoch),
      );
    }
    return _initializeAndRunWithStableSecureStorageEpoch(operation);
  }

  Future<T> _initializeAndRunWithStableSecureStorageEpoch<T>(
    Future<T> Function(int epoch) operation,
  ) async {
    await _requireSecureStorageReady();
    final epoch = _storageService.captureSecureStorageOperationEpoch();
    return _storageService.runWithSecureStorageOperationEpoch(
      epoch,
      () => operation(epoch),
    );
  }
}
