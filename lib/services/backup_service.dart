import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../models/app_models.dart';
import '../utils/backup_migrators.dart';
import 'storage/storage_service.dart';
import 'webdav_service.dart';

// 备份版本管理
class BackupVersion {
  static const String current = '1.1.0';
  
  static bool isCompatible(String version) {
    // 支持的版本列表
    const supportedVersions = ['1.0.0', '1.1.0'];
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
  
  BackupData({
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
    final aggregateSearchSettings = await _storageService.loadAggregateSearchSettings();
    data['aggregateSearchSettings'] = aggregateSearchSettings.toJson();
    
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
      
      // 恢复下载器配置
      if (migratedData['downloaderConfigs'] != null) {
        final downloaderConfigs = migratedData['downloaderConfigs'] as List<Map<String, dynamic>>;
        
        // 恢复默认下载器ID
        String? defaultDownloaderId;
        if (migratedData['defaultDownloaderId'] != null) {
          defaultDownloaderId = migratedData['defaultDownloaderId'] as String?;
        }
        
        await _storageService.saveDownloaderConfigs(downloaderConfigs, defaultId: defaultDownloaderId);
      }
      
      // 恢复下载器密码
      if (migratedData['downloaderPasswords'] != null) {
        final downloaderPasswords = migratedData['downloaderPasswords'] as Map<String, dynamic>;
        for (final entry in downloaderPasswords.entries) {
          final clientId = entry.key;
          final password = entry.value as String;
          await _storageService.saveDownloaderPassword(clientId, password);
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
      
      // 恢复下载器的分类和标签缓存
      if (migratedData['downloaderCategoriesCache'] != null) {
        final categoriesCache = migratedData['downloaderCategoriesCache'] as Map<String, dynamic>;
        for (final entry in categoriesCache.entries) {
          final categories = (entry.value as List).cast<String>();
          await _storageService.saveDownloaderCategories(entry.key, categories);
        }
      }
      if (migratedData['downloaderTagsCache'] != null) {
        final tagsCache = migratedData['downloaderTagsCache'] as Map<String, dynamic>;
        for (final entry in tagsCache.entries) {
          final tags = (entry.value as List).cast<String>();
          await _storageService.saveDownloaderTags(entry.key, tags);
        }
      }
      
      // 恢复聚合搜索设置
      if (migratedData['aggregateSearchSettings'] != null) {
        try {
          final aggregateSearchSettings = AggregateSearchSettings.fromJson(
            migratedData['aggregateSearchSettings'] as Map<String, dynamic>
          );
          await _storageService.saveAggregateSearchSettings(aggregateSearchSettings);
        } catch (e) {
          // 如果恢复聚合搜索设置失败，记录错误但不影响整体恢复过程
          // 这样可以确保其他数据的恢复不受影响
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
            throw BackupException('WebDAV备份失败: $e');
          }
          // 在移动平台上，WebDAV失败时回退到本地导出
          return await exportBackup();
        }
      } else {
        // 没有配置WebDAV或未启用，直接导出到本地
        return await exportBackup();
      }
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
  
  BackupRestoreResult({
    required this.success,
    required this.message,
  });
}