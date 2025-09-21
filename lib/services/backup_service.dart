import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:flutter/foundation.dart';
import '../models/app_models.dart';
import 'storage/storage_service.dart';
import '../utils/backup_migrators.dart';
import 'webdav_service.dart';

// 备份数据版本
class BackupVersion {
  static const String current = '1.0.0';
  
  // 版本比较
  static int compare(String version1, String version2) {
    final v1Parts = version1.split('.').map(int.parse).toList();
    final v2Parts = version2.split('.').map(int.parse).toList();
    
    for (int i = 0; i < 3; i++) {
      final v1 = i < v1Parts.length ? v1Parts[i] : 0;
      final v2 = i < v2Parts.length ? v2Parts[i] : 0;
      if (v1 != v2) return v1.compareTo(v2);
    }
    return 0;
  }
  
  // 检查版本兼容性
  static bool isCompatible(String backupVersion) {
    return compare(backupVersion, current) <= 0;
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
  
  // 创建备份
  Future<BackupData> createBackup() async {
    final data = <String, dynamic>{};
    
    // 获取应用版本信息
    final packageInfo = await PackageInfo.fromPlatform();
    
    // 收集站点配置
    final siteConfigs = await _storageService.loadSiteConfigs();
    data['siteConfigs'] = siteConfigs.map((config) => config.toJson()).toList();
    
    // 收集当前激活的站点ID
    final activeSiteId = await _storageService.getActiveSiteId();
    data['activeSiteId'] = activeSiteId;
    
    // 收集QB客户端配置
    final qbConfigs = await _storageService.loadQbClients();
    data['qbClientConfigs'] = qbConfigs.map((config) => config.toJson()).toList();
    
    // 收集默认下载器ID
    final defaultQbId = await _storageService.loadDefaultQbId();
    data['defaultQbId'] = defaultQbId;
    
    // 收集QB客户端密码
    final qbPasswords = <String, String>{};
    for (final qbConfig in qbConfigs) {
      final password = await _storageService.loadQbPassword(qbConfig.id);
      if (password != null && password.isNotEmpty) {
        qbPasswords[qbConfig.id] = password;
      }
    }
    data['qbPasswords'] = qbPasswords;
    
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
    };
    
    // 收集QB客户端的分类和标签缓存
    final qbCategoriesCache = <String, List<String>>{};
    final qbTagsCache = <String, List<String>>{};
    for (final qbConfig in qbConfigs) {
      qbCategoriesCache[qbConfig.id] = await _storageService.loadQbCategories(qbConfig.id);
      qbTagsCache[qbConfig.id] = await _storageService.loadQbTags(qbConfig.id);
    }
    data['qbCategoriesCache'] = qbCategoriesCache;
    data['qbTagsCache'] = qbTagsCache;
    
    return BackupData(
      version: BackupVersion.current,
      timestamp: DateTime.now(),
      appVersion: packageInfo.version,
      data: data,
    );
  }
  
  // 导出备份到文件
  Future<String?> exportBackup() async {
    try {
      final backup = await createBackup();
      final timestamp = backup.timestamp.toIso8601String().replaceAll(':', '-');
      final fileName = '$_backupFilePrefix${backup.version}_$timestamp$_backupFileExtension';
      final backupContent = jsonEncode(backup.toJson());
      
      String? result;
      if (defaultTargetPlatform == TargetPlatform.linux) {
        // Linux平台：使用传统的文件路径方式
        result = await FilePicker.platform.saveFile(
          dialogTitle: '导出备份文件 (建议文件名: $fileName)',
          type: FileType.custom,
          allowedExtensions: ['json'],
        );
        
        if (result != null) {
          final file = File(result);
          await file.writeAsString(backupContent);
        }
      } else {
        // Android和iOS平台：使用bytes参数直接保存文件内容
        result = await FilePicker.platform.saveFile(
          dialogTitle: '导出备份文件',
          fileName: fileName,
          type: FileType.custom,
          allowedExtensions: ['json'],
          bytes: utf8.encode(backupContent),
        );
      }
      
      return result;
    } catch (e) {
      throw BackupException('导出备份失败: $e');
    }
  }
  
  // 从文件导入备份
  Future<BackupData?> importBackup() async {
    try {
      final result = await FilePicker.platform.pickFiles(
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
  Future<BackupRestoreResult> restoreBackup(BackupData backup) async {
    try {
      // 检查版本兼容性
      if (!BackupVersion.isCompatible(backup.version)) {
        throw BackupException('备份版本 ${backup.version} 不兼容当前应用版本');
      }
      
      // 执行数据迁移（如果需要）
      var migratedData = backup.data;
      if (backup.version != BackupVersion.current) {
        try {
          final backupDataJson = {
            'version': backup.version,
            ...backup.data,
          };
          final migratedJson = BackupMigrationManager.migrate(backupDataJson, BackupVersion.current);
          migratedData = Map<String, dynamic>.from(migratedJson)..remove('version');
        } catch (e) {
          return BackupRestoreResult(
            success: false,
            message: '数据迁移失败: $e',
          );
        }
      }
      
      // 恢复站点配置
      if (migratedData['siteConfigs'] != null) {
        final siteConfigs = (migratedData['siteConfigs'] as List)
            .map((json) => SiteConfig.fromJson(json as Map<String, dynamic>))
            .toList();
        await _storageService.saveSiteConfigs(siteConfigs);
      }
      
      // 恢复当前激活的站点ID
      if (migratedData['activeSiteId'] != null) {
        await _storageService.setActiveSiteId(migratedData['activeSiteId'] as String?);
      }
      
      // 恢复QB客户端配置
      if (migratedData['qbClientConfigs'] != null) {
        final qbConfigs = (migratedData['qbClientConfigs'] as List)
            .map((json) => QbClientConfig.fromJson(json as Map<String, dynamic>))
            .toList();
        
        // 恢复默认下载器ID
        String? defaultQbId;
        if (migratedData['defaultQbId'] != null) {
          defaultQbId = migratedData['defaultQbId'] as String?;
        }
        
        await _storageService.saveQbClients(qbConfigs, defaultId: defaultQbId);
      }
      
      // 恢复QB客户端密码
      if (migratedData['qbPasswords'] != null) {
        final qbPasswords = migratedData['qbPasswords'] as Map<String, dynamic>;
        for (final entry in qbPasswords.entries) {
          final clientId = entry.key;
          final password = entry.value as String;
          await _storageService.saveQbPassword(clientId, password);
        }
      }
      
      // 恢复用户偏好设置
      if (migratedData['userPreferences'] != null) {
        final prefs = migratedData['userPreferences'] as Map<String, dynamic>;
        
        if (prefs['themeMode'] != null) {
          await _storageService.saveThemeMode(prefs['themeMode'] as String);
        }
        if (prefs['dynamicColor'] != null) {
          await _storageService.saveUseDynamicColor(prefs['dynamicColor'] as bool);
        }
        if (prefs['seedColor'] != null) {
          await _storageService.saveSeedColor(prefs['seedColor'] as int);
        }
        if (prefs['autoLoadImages'] != null) {
          await _storageService.saveAutoLoadImages(prefs['autoLoadImages'] as bool);
        }
        
        // 恢复默认下载设置
        if (prefs['defaultDownloadSettings'] != null) {
          final downloadSettings = prefs['defaultDownloadSettings'] as Map<String, dynamic>;
          if (downloadSettings['category'] != null) {
            await _storageService.saveDefaultDownloadCategory(downloadSettings['category'] as String);
          }
          if (downloadSettings['tags'] != null) {
            final tags = downloadSettings['tags'] as dynamic;
            if (tags is String) {
              await _storageService.saveDefaultDownloadTags([tags]);
            } else if (tags is List) {
              await _storageService.saveDefaultDownloadTags(tags.cast<String>());
            }
          }
          if (downloadSettings['savePath'] != null) {
            await _storageService.saveDefaultDownloadSavePath(downloadSettings['savePath'] as String);
          }
        }
      }
      
      // 恢复QB客户端的分类和标签缓存
      if (migratedData['qbCategoriesCache'] != null) {
        final categoriesCache = migratedData['qbCategoriesCache'] as Map<String, dynamic>;
        for (final entry in categoriesCache.entries) {
          final categories = (entry.value as List).cast<String>();
          await _storageService.saveQbCategories(entry.key, categories);
        }
      }
      if (migratedData['qbTagsCache'] != null) {
        final tagsCache = migratedData['qbTagsCache'] as Map<String, dynamic>;
        for (final entry in tagsCache.entries) {
          final tags = (entry.value as List).cast<String>();
          await _storageService.saveQbTags(entry.key, tags);
        }
      }
      
      return BackupRestoreResult(
        success: true,
        message: '数据恢复成功',
      );
    } catch (e) {
      return BackupRestoreResult(
        success: false,
        message: '恢复失败: $e',
      );
    }
  }

  // WebDAV集成方法

  /// 创建备份并自动上传到WebDAV（如果已配置且启用）
  Future<String?> exportBackupWithWebDAV() async {
    try {
      // 创建备份数据
      final backupData = await createBackup();
      final backupJson = jsonEncode(backupData.toJson());

      // 检查WebDAV配置
      final webdavConfig = await _webdavService.loadConfig();
      if (webdavConfig != null && webdavConfig.isEnabled) {
        try {
          // 直接上传到WebDAV，不创建本地文件
          await _webdavService.uploadBackup(backupJson);
          // WebDAV上传成功，返回特殊标识表示上传到云端
          return 'WebDAV云端备份';
        } catch (e) {
          // WebDAV上传失败，在Linux平台上直接抛出异常，避免文件选择器问题
          if (defaultTargetPlatform == TargetPlatform.linux) {
            throw BackupException('WebDAV上传失败: $e');
          } else {
            // 其他平台回退到本地备份
            final localPath = await exportBackup();
            return localPath;
          }
        }
      } else {
        // 没有WebDAV配置，创建本地备份文件
        final localPath = await exportBackup();
        return localPath;
      }
    } catch (e) {
      throw BackupException('导出备份失败: $e');
    }
  }

  /// 从WebDAV下载并恢复备份
  Future<BackupRestoreResult> restoreFromWebDAV(String backupFileName) async {
    try {
      final webdavConfig = await _webdavService.loadConfig();
      if (webdavConfig == null || !webdavConfig.isEnabled) {
        return const BackupRestoreResult(
          success: false,
          message: 'WebDAV未配置或未启用',
        );
      }

      // 从WebDAV下载备份内容
      final backupContent = await _webdavService.downloadBackup(backupFileName);
      if (backupContent == null) {
        return const BackupRestoreResult(
          success: false,
          message: '从WebDAV下载备份失败',
        );
      }

      // 解析备份内容
      var json = jsonDecode(backupContent) as Map<String, dynamic>;
      
      // 检查是否需要数据迁移
      final backupVersion = json['version'] as String? ?? '1.0.0';
      if (backupVersion != BackupVersion.current) {
        json = BackupMigrationManager.migrate(json, BackupVersion.current);
      }
      
      final backup = BackupData.fromJson(json);
      
      // 恢复备份
      await restoreBackup(backup);
      
      return const BackupRestoreResult(
        success: true,
        message: '从WebDAV恢复备份成功',
      );
    } catch (e) {
      return BackupRestoreResult(
        success: false,
        message: '从WebDAV恢复备份失败: $e',
      );
    }
  }

  /// 获取WebDAV上的备份文件列表
  Future<List<Map<String, dynamic>>> getWebDAVBackups() async {
    try {
      final webdavConfig = await _webdavService.loadConfig();
      if (webdavConfig == null || !webdavConfig.isEnabled) {
        return [];
      }

      return await _webdavService.getRemoteBackups();
    } catch (e) {
      return [];
    }
  }

  /// 检查是否应该执行自动WebDAV同步
  Future<bool> shouldAutoSync() async {
    try {
      final webdavConfig = await _webdavService.loadConfig();
      if (webdavConfig == null || !webdavConfig.isEnabled || !webdavConfig.autoSync) {
        return false;
      }

      // 检查上次同步时间
      if (webdavConfig.lastSyncTime == null) {
        return true; // 从未同步过
      }

      final now = DateTime.now();
      final lastSync = webdavConfig.lastSyncTime!;
      final intervalMinutes = webdavConfig.syncIntervalMinutes;
      
      return now.difference(lastSync).inMinutes >= intervalMinutes;
    } catch (e) {
      return false;
    }
  }

  /// 执行自动WebDAV同步
  Future<void> performAutoSync() async {
    try {
      if (!await shouldAutoSync()) return;

      final webdavConfig = await _webdavService.loadConfig();
      if (webdavConfig == null || !webdavConfig.isEnabled) return;

      // 上传到WebDAV
      final success = await _webdavService.performAutoSync();
      
      // 更新同步状态
      final updatedConfig = webdavConfig.copyWith(
        lastSyncTime: DateTime.now(),
        lastSyncStatus: success ? WebDAVSyncStatus.success : WebDAVSyncStatus.error,
        lastSyncError: success ? null : '自动同步失败',
      );
      
      await _webdavService.saveConfig(updatedConfig);
    } catch (e) {
      // 更新错误状态
      final webdavConfig = await _webdavService.loadConfig();
      if (webdavConfig != null) {
        final updatedConfig = webdavConfig.copyWith(
          lastSyncTime: DateTime.now(),
          lastSyncStatus: WebDAVSyncStatus.error,
          lastSyncError: '自动同步失败: $e',
        );
        await _webdavService.saveConfig(updatedConfig);
      }
    }
  }
  
}

// 备份导入结果
class BackupImportResult {
  final bool success;
  final String message;
  final BackupData? backupData;
  
  const BackupImportResult({
    required this.success,
    required this.message,
    this.backupData,
  });
}

// 备份恢复结果
class BackupRestoreResult {
  final bool success;
  final String message;
  
  const BackupRestoreResult({
    required this.success,
    required this.message,
  });
}

// 备份异常
class BackupException implements Exception {
  final String message;
  const BackupException(this.message);
  
  @override
  String toString() => 'BackupException: $message';
}