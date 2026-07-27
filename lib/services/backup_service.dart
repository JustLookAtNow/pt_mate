import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

import '../models/app_models.dart';
import '../utils/backup_migrators.dart';
import 'downloader/downloader_config.dart';
import 'storage/storage_service.dart';
import 'webdav_service.dart';

// 备份版本管理
class BackupVersion {
  static const String current = '1.3.0';

  static bool isCompatible(String version) {
    // 支持的版本列表
    const supportedVersions = ['1.0.0', '1.1.0', '1.2.0', '1.3.0'];
    return supportedVersions.contains(version);
  }

  static int compare(String version1, String version2) {
    final v1Parts = version1.split('.').map(int.parse).toList();
    final v2Parts = version2.split('.').map(int.parse).toList();

    for (int i = 0; i < 3; i++) {
      final v1Part = i < v1Parts.length ? v1Parts[i] : 0;
      final v2Part = i < v2Parts.length ? v2Parts[i] : 0;

      if (v1Part < v2Part) return -1;
      if (v1Part > v2Part) return 1;
    }

    return 0;
  }
}

// 备份数据结构
class BackupData {
  final String version;
  final DateTime timestamp;
  final String appVersion;
  final Map<String, dynamic> data;

  const BackupData({
    required this.version,
    required this.timestamp,
    required this.appVersion,
    required this.data,
  });

  Map<String, dynamic> toJson() => {
    'version': version,
    'timestamp': timestamp.toIso8601String(),
    'appVersion': appVersion,
    'data': data,
  };

  factory BackupData.fromJson(Map<String, dynamic> json) {
    return BackupData(
      version: json['version'] as String? ?? '1.0.0',
      timestamp: DateTime.parse(json['timestamp'] as String),
      appVersion: json['appVersion'] as String? ?? 'unknown',
      data: json['data'] as Map<String, dynamic>,
    );
  }
}

// 数据迁移器接口
abstract class DataMigrator {
  String get fromVersion;
  String get toVersion;
  Map<String, dynamic> migrate(Map<String, dynamic> data);
}

// 备份服务
class BackupService {
  static const String _backupFilePrefix = 'backup_v';
  static const String _backupFileExtension = '.json';

  final StorageService _storageService;
  final WebDAVService _webdavService;

  BackupService(this._storageService) : _webdavService = WebDAVService.instance;

  Future<_PreparedBackupFile>
  _prepareBackupFile() => _storageService.runWithCurrentSecureStorageOperation((
    epoch,
  ) async {
    final backup = await _createBackupInCurrentEpoch();
    final timestamp = backup.timestamp.toIso8601String().replaceAll(':', '-');
    final fileName =
        '$_backupFilePrefix${backup.version}_$timestamp$_backupFileExtension';
    final backupContent = jsonEncode(backup.toJson());

    return _PreparedBackupFile(
      fileName: fileName,
      content: backupContent,
      secureStorageEpoch: epoch,
    );
  });

  // 创建备份
  Future<BackupData> createBackup() =>
      _storageService.runWithCurrentSecureStorageOperation(
        (_) => _createBackupInCurrentEpoch(),
      );

  Future<BackupData> _createBackupInCurrentEpoch() async {
    final data = <String, dynamic>{};

    // 获取应用版本信息
    final packageInfo = await PackageInfo.fromPlatform();

    // 收集站点配置
    final siteConfigs = await _storageService.loadSiteConfigs(
      includeApiKeys: true,
    );
    data['siteConfigs'] = siteConfigs.map((config) => config.toJson()).toList();

    // 收集当前激活的站点ID
    final activeSiteId = await _storageService.getActiveSiteId();
    data['activeSiteId'] = activeSiteId;

    // 收集下载器配置
    final downloaderConfigs = await _storageService.loadDownloaderConfigs();
    data['downloaderConfigs'] = downloaderConfigs;

    // 收集默认下载器ID
    final defaultDownloaderId = await _storageService.loadDefaultDownloaderId();
    data['defaultDownloaderId'] = defaultDownloaderId;

    // 收集下载器密码
    final downloaderPasswords = <String, String>{};
    for (final config in downloaderConfigs) {
      final configId = config['id'] as String?;
      if (configId != null) {
        final password = await _storageService.loadDownloaderPassword(configId);
        if (password != null && password.isNotEmpty) {
          downloaderPasswords[configId] = password;
        }
      }
    }
    data['downloaderPasswords'] = downloaderPasswords;

    // 收集用户偏好设置
    data['userPreferences'] = {
      'themeMode': await _storageService.loadThemeMode(),
      'dynamicColor': await _storageService.loadUseDynamicColor(),
      'seedColor': await _storageService.loadSeedColor(),
      'autoLoadImages': await _storageService.loadAutoLoadImages(),
      'defaultDownloadSettings': {
        'category': await _storageService.loadDefaultDownloadCategory(),
        'tags': await _storageService.loadDefaultDownloadTags(),
        'savePath': await _storageService.loadDefaultDownloadSavePath(),
      },
      'proxy': {
        'enabled': await _storageService.loadProxyEnabled(),
        'host': await _storageService.loadProxyHost(),
        'port': await _storageService.loadProxyPort(),
        'username': await _storageService.loadProxyUsername(),
        'password': await _storageService.loadProxyPassword(),
        'bypassLan': await _storageService.loadProxyBypassLan(),
        'bypassRules': await _storageService.loadProxyBypassRules(),
      },
    };

    // 收集下载器的分类和标签缓存
    final downloaderCategoriesCache = <String, List<String>>{};
    final downloaderTagsCache = <String, List<String>>{};
    for (final config in downloaderConfigs) {
      final configId = config['id'] as String?;
      if (configId != null) {
        downloaderCategoriesCache[configId] = await _storageService
            .loadDownloaderCategories(configId);
        downloaderTagsCache[configId] = await _storageService
            .loadDownloaderTags(configId);
      }
    }
    data['downloaderCategoriesCache'] = downloaderCategoriesCache;
    data['downloaderTagsCache'] = downloaderTagsCache;

    // 收集聚合搜索设置
    final aggregateSearchSettings = await _storageService
        .loadAggregateSearchSettings();
    data['aggregateSearchSettings'] = aggregateSearchSettings.toJson();

    // 收集 Cookie Cloud 配置
    final cookieCloudConfig = await _storageService.loadCookieCloudConfig();
    data['cookieCloudConfig'] = cookieCloudConfig.toJson();

    return BackupData(
      version: BackupVersion.current,
      timestamp: DateTime.now(),
      appVersion: packageInfo.version,
      data: data,
    );
  }

  // 导出备份到文件
  Future<String?> exportBackup({
    void Function(String message)? onProgress,
  }) async {
    try {
      onProgress?.call('正在创建备份...');
      final prepared = await _prepareBackupFile();
      _storageService.requireSecureStorageOperationEpoch(
        prepared.secureStorageEpoch,
      );

      String? result;
      if (defaultTargetPlatform == TargetPlatform.linux) {
        onProgress?.call('请选择导出位置...');
        final initialDirectory =
            (await getDownloadsDirectory())?.path ??
            Platform.environment['HOME'] ??
            Directory.current.path;
        result = await FilePicker.saveFile(
          dialogTitle: '导出备份文件',
          fileName: prepared.fileName,
          initialDirectory: initialDirectory,
          type: FileType.custom,
          allowedExtensions: ['json'],
          bytes: Uint8List.fromList(utf8.encode(prepared.content)),
        );

        if (result != null) {
          _storageService.requireSecureStorageOperationEpoch(
            prepared.secureStorageEpoch,
          );
          final file = File(result);
          await file.writeAsString(prepared.content);
        }
      } else {
        onProgress?.call('正在导出备份...');
        result = await FilePicker.saveFile(
          dialogTitle: '导出备份文件',
          fileName: prepared.fileName,
          type: FileType.custom,
          allowedExtensions: ['json'],
          bytes: utf8.encode(prepared.content),
        );
      }

      return result;
    } on SecureStorageUnavailableException {
      rethrow;
    } catch (e) {
      throw BackupException('导出备份失败: $e');
    }
  }

  // 从文件导入备份
  Future<BackupData?> importBackup() async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
        dialogTitle: '选择备份文件',
      );

      if (result != null && result.files.single.path != null) {
        final file = File(result.files.single.path!);
        final content = await file.readAsString();
        var json = jsonDecode(content) as Map<String, dynamic>;

        // 检查是否需要数据迁移
        final backupVersion = json['version'] as String? ?? '1.0.0';
        if (backupVersion != BackupVersion.current) {
          json = BackupMigrationManager.migrate(json, BackupVersion.current);
        }

        return BackupData.fromJson(json);
      }
      return null;
    } catch (e) {
      throw BackupException('导入备份失败: $e');
    }
  }

  // 恢复备份
  Future<BackupRestoreResult> restoreBackup(
    BackupData backup, {
    int? expectedSecureStorageEpoch,
  }) async {
    try {
      final expected = expectedSecureStorageEpoch;
      if (expected != null) {
        _storageService.requireSecureStorageOperationEpoch(expected);
      }
      // 检查版本兼容性
      if (!BackupVersion.isCompatible(backup.version)) {
        throw BackupException('备份版本 ${backup.version} 不兼容当前应用版本');
      }

      // 执行数据迁移（如果需要）
      var migratedData = backup.data;
      if (backup.version != BackupVersion.current) {
        try {
          final backupDataJson = {'version': backup.version, ...backup.data};
          final migratedJson = BackupMigrationManager.migrate(
            backupDataJson,
            BackupVersion.current,
          );
          migratedData = Map<String, dynamic>.from(migratedJson)
            ..remove('version');
        } on SecureStorageUnavailableException {
          rethrow;
        } catch (e) {
          return BackupRestoreResult(success: false, message: '数据迁移失败: $e');
        }
      }

      final restoredSiteConfigs = migratedData['siteConfigs'] == null
          ? null
          : (migratedData['siteConfigs'] as List)
                .map(
                  (json) => SiteConfig.fromJson(json as Map<String, dynamic>),
                )
                .toList();
      final restoredCookieCloudConfig =
          migratedData['cookieCloudConfig'] == null
          ? null
          : CookieCloudConfig.fromJson(
              migratedData['cookieCloudConfig'] as Map<String, dynamic>,
            );
      final restoredDownloaderPasswords = <String, String>{
        if (migratedData['downloaderPasswords'] != null)
          ...(migratedData['downloaderPasswords'] as Map<String, dynamic>).map(
            (id, value) => MapEntry(id, value as String),
          ),
      };
      List<Map<String, dynamic>>? sanitizedDownloaderConfigs;
      Set<String>? restoredDownloaderIds;
      if (migratedData['downloaderConfigs'] != null) {
        sanitizedDownloaderConfigs = <Map<String, dynamic>>[];
        restoredDownloaderIds = <String>{};
        for (final value
            in migratedData['downloaderConfigs'] as List<dynamic>) {
          final parsed = DownloaderConfig.fromJson(
            value as Map<String, dynamic>,
          );
          if (parsed.id.isNotEmpty) {
            restoredDownloaderIds.add(parsed.id);
            if (parsed.password.isNotEmpty) {
              final separatePassword = restoredDownloaderPasswords[parsed.id];
              if (separatePassword != null &&
                  separatePassword != parsed.password) {
                throw BackupException('下载器密码来源冲突，未执行任何恢复写入');
              }
              restoredDownloaderPasswords[parsed.id] = parsed.password;
            }
          }
          final sanitized = Map<String, dynamic>.from(
            parsed.copyWith(password: '').toJson(),
          );
          final config = Map<String, dynamic>.from(
            sanitized['config'] as Map<String, dynamic>,
          )..remove('password');
          sanitized['config'] = config;
          sanitizedDownloaderConfigs.add(sanitized);
        }
      }
      final restoredUserPreferences =
          migratedData['userPreferences'] as Map<String, dynamic>?;
      final restoredProxy =
          restoredUserPreferences?['proxy'] as Map<String, dynamic>?;
      final hasProxyPassword = restoredProxy?.containsKey('password') ?? false;
      final restoredProxyPassword = hasProxyPassword
          ? restoredProxy!['password'] as String? ?? ''
          : '';
      final backupPreferences = _buildRestorePreferenceSnapshot(
        migratedData,
        sanitizedDownloaderConfigs: sanitizedDownloaderConfigs,
      );
      if (expected != null) {
        _storageService.requireSecureStorageOperationEpoch(expected);
      }

      // 敏感字段与全部普通偏好共享一个 manifest/companion 提交边界。
      await _storageService.restoreSensitiveBackupData(
        siteConfigs: restoredSiteConfigs,
        cookieCloudConfig: restoredCookieCloudConfig,
        downloaderPasswords: restoredDownloaderPasswords.isEmpty
            ? null
            : restoredDownloaderPasswords,
        downloaderIds: restoredDownloaderIds,
        backupPreferences: backupPreferences.isEmpty ? null : backupPreferences,
        hasProxyPassword: hasProxyPassword,
        proxyPassword: restoredProxyPassword,
        expectedSecureStorageEpoch: expected,
      );

      return BackupRestoreResult(success: true, message: '数据恢复成功');
    } catch (e) {
      return BackupRestoreResult(success: false, message: '恢复失败: $e');
    }
  }

  Map<String, dynamic> _buildRestorePreferenceSnapshot(
    Map<String, dynamic> data, {
    required List<Map<String, dynamic>>? sanitizedDownloaderConfigs,
  }) {
    final snapshot = <String, dynamic>{};
    final activeSiteId = data['activeSiteId'];
    if (activeSiteId != null) snapshot['activeSiteId'] = activeSiteId as String;

    if (sanitizedDownloaderConfigs != null) {
      snapshot['downloaderConfigs'] = sanitizedDownloaderConfigs;
      // Presence with null means the old default must be removed.
      snapshot['defaultDownloaderId'] = data['defaultDownloaderId'] as String?;
    }

    final preferences = data['userPreferences'] as Map<String, dynamic>?;
    if (preferences != null) {
      void copyIfPresent(String source, String destination) {
        final value = preferences[source];
        if (value != null) snapshot[destination] = value;
      }

      copyIfPresent('themeMode', 'themeMode');
      copyIfPresent('dynamicColor', 'dynamicColor');
      copyIfPresent('seedColor', 'seedColor');
      copyIfPresent('autoLoadImages', 'autoLoadImages');

      final downloadSettings =
          preferences['defaultDownloadSettings'] as Map<String, dynamic>?;
      if (downloadSettings != null) {
        if (downloadSettings['category'] != null) {
          snapshot['defaultDownloadCategory'] =
              downloadSettings['category'] as String;
        }
        final tags = downloadSettings['tags'];
        if (tags is String) {
          snapshot['defaultDownloadTags'] = <String>[tags];
        } else if (tags is List<dynamic>) {
          snapshot['defaultDownloadTags'] = tags.cast<String>();
        }
        if (downloadSettings['savePath'] != null) {
          snapshot['defaultDownloadSavePath'] =
              downloadSettings['savePath'] as String;
        }
      }

      final proxy = preferences['proxy'] as Map<String, dynamic>?;
      if (proxy != null) {
        const proxyFields = <String, String>{
          'enabled': 'proxyEnabled',
          'host': 'proxyHost',
          'port': 'proxyPort',
          'username': 'proxyUsername',
          'bypassLan': 'proxyBypassLan',
          'bypassRules': 'proxyBypassRules',
        };
        for (final entry in proxyFields.entries) {
          final value = proxy[entry.key];
          if (value != null) snapshot[entry.value] = value;
        }
      }
    }

    Map<String, dynamic>? copyStringListMap(String key) {
      final source = data[key] as Map<String, dynamic>?;
      if (source == null) return null;
      return source.map(
        (id, value) => MapEntry(id, (value as List<dynamic>).cast<String>()),
      );
    }

    final categories = copyStringListMap('downloaderCategoriesCache');
    if (categories != null) snapshot['downloaderCategoriesCache'] = categories;
    final tags = copyStringListMap('downloaderTagsCache');
    if (tags != null) snapshot['downloaderTagsCache'] = tags;

    final aggregate = data['aggregateSearchSettings'];
    if (aggregate != null) {
      try {
        snapshot['aggregateSearchSettings'] = AggregateSearchSettings.fromJson(
          aggregate as Map<String, dynamic>,
        ).toJson();
      } catch (_) {
        // Preserve the historical behavior: an invalid optional search
        // preference does not invalidate the rest of a backup.
      }
    }
    return snapshot;
  }

  // WebDAV集成方法

  /// 创建备份并自动上传到WebDAV（如果已配置且启用）
  Future<String?> exportBackupWithWebDAV({
    void Function(String message)? onProgress,
  }) async {
    try {
      onProgress?.call('正在创建备份...');
      final prepared = await _prepareBackupFile();
      _storageService.requireSecureStorageOperationEpoch(
        prepared.secureStorageEpoch,
      );

      // 检查WebDAV配置
      onProgress?.call('正在检查导出方式...');
      final webdavConfig = await _webdavService.loadConfig();
      if (webdavConfig != null && webdavConfig.isEnabled) {
        try {
          // 直接上传到WebDAV，不创建本地文件
          onProgress?.call('正在上传到 WebDAV...');
          await _storageService.runWithSecureStorageOperationEpoch(
            prepared.secureStorageEpoch,
            () => _webdavService.uploadBackup(
              prepared.content,
              filename: prepared.fileName,
            ),
          );
          // WebDAV上传成功，返回特殊标识表示上传到云端
          return 'WebDAV云端备份';
        } on SecureStorageUnavailableException {
          rethrow;
        } catch (e) {
          // WebDAV上传失败，在Linux平台上直接抛出异常，避免文件选择器问题
          if (defaultTargetPlatform == TargetPlatform.linux) {
            throw BackupException('WebDAV备份失败: $e');
          }
          // 在移动平台上，WebDAV失败时回退到本地导出
          return await exportBackup();
        }
      } else {
        // 没有配置WebDAV或未启用，直接导出到本地
        if (defaultTargetPlatform == TargetPlatform.linux) {
          onProgress?.call('请选择导出位置...');
          final initialDirectory =
              (await getDownloadsDirectory())?.path ??
              Platform.environment['HOME'] ??
              Directory.current.path;
          final result = await FilePicker.saveFile(
            dialogTitle: '导出备份文件',
            fileName: prepared.fileName,
            initialDirectory: initialDirectory,
            type: FileType.custom,
            allowedExtensions: ['json'],
            bytes: Uint8List.fromList(utf8.encode(prepared.content)),
          );

          if (result != null) {
            _storageService.requireSecureStorageOperationEpoch(
              prepared.secureStorageEpoch,
            );
            final file = File(result);
            await file.writeAsString(prepared.content);
          }
          return result;
        }

        onProgress?.call('正在导出备份...');
        return await FilePicker.saveFile(
          dialogTitle: '导出备份文件',
          fileName: prepared.fileName,
          type: FileType.custom,
          allowedExtensions: ['json'],
          bytes: utf8.encode(prepared.content),
        );
      }
    } on SecureStorageUnavailableException {
      rethrow;
    } catch (e) {
      throw BackupException('备份失败: $e');
    }
  }

  /// 从WebDAV导入最新备份
  Future<BackupData?> importBackupFromWebDAV() async {
    try {
      final webdavConfig = await _webdavService.loadConfig();
      if (webdavConfig == null || !webdavConfig.isEnabled) {
        throw BackupException('WebDAV未配置或未启用');
      }

      final backupContent = await _webdavService.downloadLatestBackup();
      if (backupContent == null) {
        return null; // 没有找到备份文件
      }

      var json = jsonDecode(backupContent) as Map<String, dynamic>;

      // 检查是否需要数据迁移
      final backupVersion = json['version'] as String? ?? '1.0.0';
      if (backupVersion != BackupVersion.current) {
        json = BackupMigrationManager.migrate(json, BackupVersion.current);
      }

      return BackupData.fromJson(json);
    } on SecureStorageUnavailableException {
      rethrow;
    } catch (e) {
      throw BackupException('从WebDAV导入备份失败: $e');
    }
  }

  /// 列出WebDAV中的所有备份文件
  Future<List<Map<String, dynamic>>> listWebDAVBackups() async {
    try {
      final webdavConfig = await _webdavService.loadConfig();
      if (webdavConfig == null || !webdavConfig.isEnabled) {
        throw BackupException('WebDAV未配置或未启用');
      }

      return await _webdavService.getRemoteBackups();
    } on SecureStorageUnavailableException {
      rethrow;
    } catch (e) {
      throw BackupException('获取WebDAV备份列表失败: $e');
    }
  }

  /// 从WebDAV下载指定的备份文件
  Future<BackupData?> downloadWebDAVBackup(String fileName) async {
    try {
      final webdavConfig = await _webdavService.loadConfig();
      if (webdavConfig == null || !webdavConfig.isEnabled) {
        throw BackupException('WebDAV未配置或未启用');
      }

      final backupContent = await _webdavService.downloadBackup(fileName);
      if (backupContent == null) {
        return null;
      }

      var json = jsonDecode(backupContent) as Map<String, dynamic>;

      // 检查是否需要数据迁移
      final backupVersion = json['version'] as String? ?? '1.0.0';
      if (backupVersion != BackupVersion.current) {
        json = BackupMigrationManager.migrate(json, BackupVersion.current);
      }

      return BackupData.fromJson(json);
    } on SecureStorageUnavailableException {
      rethrow;
    } catch (e) {
      throw BackupException('从WebDAV下载备份失败: $e');
    }
  }

  /// 删除WebDAV中的指定备份文件
  Future<void> deleteWebDAVBackup(String fileName) async {
    try {
      final webdavConfig = await _webdavService.loadConfig();
      if (webdavConfig == null || !webdavConfig.isEnabled) {
        throw BackupException('WebDAV未配置或未启用');
      }

      await _webdavService.deleteRemoteBackup(fileName);
    } on SecureStorageUnavailableException {
      rethrow;
    } catch (e) {
      throw BackupException('删除WebDAV备份失败: $e');
    }
  }
}

// 备份异常
class BackupException implements Exception {
  final String message;
  BackupException(this.message);

  @override
  String toString() => 'BackupException: $message';
}

// 备份恢复结果
class BackupRestoreResult {
  final bool success;
  final String message;

  BackupRestoreResult({required this.success, required this.message});
}

class _PreparedBackupFile {
  final String fileName;
  final String content;
  final int secureStorageEpoch;

  const _PreparedBackupFile({
    required this.fileName,
    required this.content,
    required this.secureStorageEpoch,
  });
}
