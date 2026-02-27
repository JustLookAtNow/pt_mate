import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart';

import '../../models/app_models.dart';
import 'downloader_config.dart';
import 'downloader_factory.dart';
import 'downloader_models.dart';
import '../storage/storage_service.dart';

/// 下载器服务
/// 
/// 管理下载器配置，提供统一的下载器访问接口
class DownloaderService {
  final StorageService _storageService;

  DownloaderService._([StorageService? storageService])
      : _storageService = storageService ?? StorageService.instance;

  static final DownloaderService instance = DownloaderService._();

  @visibleForTesting
  DownloaderService.test({StorageService? storageService})
      : _storageService = storageService ?? StorageService.instance;

  static final Logger _logger = Logger();
  
  /// 配置变更通知流
  final StreamController<String> _configChangeController = StreamController<String>.broadcast();
  
  /// 配置变更通知流
  Stream<String> get configChangeStream => _configChangeController.stream;
  
  /// 清除所有缓存
  void clearCache() {
    DownloaderFactory.clearCache();
  }
  
  /// 清除指定配置的缓存
  void clearConfigCache(String configId) {
    DownloaderFactory.clearConfigCache(configId);
  }
  
  /// 通知配置变更
  /// 
  /// [configId] 变更的配置ID
  void notifyConfigChanged(String configId) {
    clearConfigCache(configId);
    _configChangeController.add(configId);
  }
  
  /// 获取客户端实例
  /// 
  /// [config] 下载器配置
  /// [password] 密码
  dynamic getClient({
    required DownloaderConfig config,
    required String password,
  }) {
    return DownloaderFactory.getClient(
      config: config, 
      password: password,
      onConfigUpdated: (updatedConfig) async {
        // 当配置更新时（比如获取到版本信息），持久化到存储中
        try {
          final configs = await _storageService.loadDownloaderConfigs();
          final currentDefaultId = await _storageService.loadDefaultDownloaderId();
          
          // 找到对应的配置并更新
          final configIndex = configs.indexWhere((c) => c['id'] == updatedConfig.id);
          if (configIndex != -1) {
            configs[configIndex] = updatedConfig.toJson();
            await _storageService.saveDownloaderConfigs(
              configs.map((c) => DownloaderConfig.fromJson(c)).toList(),
              defaultId: currentDefaultId, // 保留当前的默认下载器ID
            );
            
            if (kDebugMode) {
              _logger.i('配置已更新并持久化: ${updatedConfig.id}, 版本: ${updatedConfig is QbittorrentConfig ? updatedConfig.version : 'N/A'}');
            }
          }
        } catch (e) {
          if (kDebugMode) {
            _logger.e('保存配置更新失败: $e');
          }
        }
      },
    );
  }
  
  /// 测试连接
  /// 
  /// [config] 下载器配置
  /// [password] 密码
  Future<void> testConnection({
    required DownloaderConfig config,
    required String password,
  }) async {
    await DownloaderFactory.testConnection(
      config: config,
      password: password,
    );
  }
  
  /// 获取传输信息
  /// 
  /// [config] 下载器配置
  /// [password] 密码
  Future<TransferInfo> getTransferInfo({
    required DownloaderConfig config,
    required String password,
  }) async {
    final client = DownloaderFactory.getClient(config: config, password: password);
    return await client.getTransferInfo();
  }
  
  /// 获取服务器状态
  /// 
  /// [config] 下载器配置
  /// [password] 密码
  Future<ServerState> getServerState({
    required DownloaderConfig config,
    required String password,
  }) async {
    final client = DownloaderFactory.getClient(config: config, password: password);
    return await client.getServerState();
  }
  
  /// 获取下载任务列表
  /// 
  /// [config] 下载器配置
  /// [password] 密码
  /// [params] 查询参数
  Future<List<DownloadTask>> getTasks({
    required DownloaderConfig config,
    required String password,
    GetTasksParams? params,
  }) async {
    final client = DownloaderFactory.getClient(config: config, password: password);
    return await client.getTasks(params);
  }
  
  /// 添加下载任务
  /// 
  /// [config] 下载器配置
  /// [password] 密码
  /// [params] 添加任务参数
  Future<void> addTask({
    required DownloaderConfig config,
    required String password,
    required AddTaskParams params,
    SiteConfig? siteConfig,
  }) async {
    final client = DownloaderFactory.getClient(config: config, password: password);
    await client.addTask(params, siteConfig: siteConfig);
  }
  
  /// 暂停下载任务
  /// 
  /// [config] 下载器配置
  /// [password] 密码
  /// [hashes] 任务哈希列表
  Future<void> pauseTasks({
    required DownloaderConfig config,
    required String password,
    required List<String> hashes,
  }) async {
    final client = DownloaderFactory.getClient(config: config, password: password);
    await client.pauseTasks(hashes);
  }
  
  /// 恢复下载任务
  /// 
  /// [config] 下载器配置
  /// [password] 密码
  /// [hashes] 任务哈希列表
  Future<void> resumeTasks({
    required DownloaderConfig config,
    required String password,
    required List<String> hashes,
  }) async {
    final client = DownloaderFactory.getClient(config: config, password: password);
    await client.resumeTasks(hashes);
  }
  
  /// 删除下载任务
  /// 
  /// [config] 下载器配置
  /// [password] 密码
  /// [hashes] 任务哈希列表
  /// [deleteFiles] 是否删除文件
  Future<void> deleteTasks({
    required DownloaderConfig config,
    required String password,
    required List<String> hashes,
    bool deleteFiles = false,
  }) async {
    final client = DownloaderFactory.getClient(config: config, password: password);
    await client.deleteTasks(hashes, deleteFiles: deleteFiles);
  }
  
  /// 获取分类列表
  /// 
  /// [config] 下载器配置
  /// [password] 密码
  Future<List<String>> getCategories({
    required DownloaderConfig config,
    required String password,
  }) async {
    final client = DownloaderFactory.getClient(config: config, password: password);
    return await client.getCategories();
  }
  
  /// 获取标签列表
  /// 
  /// [config] 下载器配置
  /// [password] 密码
  Future<List<String>> getTags({
    required DownloaderConfig config,
    required String password,
  }) async {
    final client = DownloaderFactory.getClient(config: config, password: password);
    return await client.getTags();
  }
  
  /// 获取版本信息
  /// 
  /// [config] 下载器配置
  /// [password] 密码
  Future<String> getVersion({
    required DownloaderConfig config,
    required String password,
  }) async {
    final client = DownloaderFactory.getClient(config: config, password: password);
    return await client.getVersion();
  }
  
  /// 获取现有下载路径列表
  /// 
  /// [config] 下载器配置
  /// [password] 密码
  Future<List<String>> getPaths({
    required DownloaderConfig config,
    required String password,
  }) async {
    final client = DownloaderFactory.getClient(config: config, password: password);
    return await client.getPaths();
  }
  
  /// 获取包含版本信息的配置并自动保存
  /// 
  /// [config] 下载器配置
  /// [password] 密码
  /// [autoSave] 是否自动保存更新后的配置，默认为true
  /// 返回包含版本信息的配置
  Future<DownloaderConfig> getUpdatedConfigAndSave({
    required DownloaderConfig config,
    required String password,
    bool autoSave = true,
  }) async {
    // 如果配置中已有版本信息，直接返回
    if (config is QbittorrentConfig && 
        config.version != null && 
        config.version!.isNotEmpty) {
      return config;
    }
    
    try {
      // 获取版本信息
      final version = await getVersion(config: config, password: password);
      
      // 创建包含版本信息的新配置
      DownloaderConfig updatedConfig;
      if (config is QbittorrentConfig) {
        updatedConfig = config.copyWith(version: version);
      } else {
        // 其他类型的下载器配置暂时直接返回原配置
        updatedConfig = config;
      }
      
      // 自动保存配置
      if (autoSave) {
        await _saveUpdatedConfig(updatedConfig);
      }
      
      return updatedConfig;
    } catch (e) {
      // 如果获取版本失败，返回原配置
      return config;
    }
  }
  
  /// 保存更新后的配置
  /// 
  /// [updatedConfig] 更新后的配置
  Future<void> _saveUpdatedConfig(DownloaderConfig updatedConfig) async {
    try {
      // 加载当前所有配置
      final allConfigMaps = await _storageService.loadDownloaderConfigs();
      final allConfigs = allConfigMaps.map((configMap) => DownloaderConfig.fromJson(configMap)).toList();
      final defaultId = await _storageService.loadDefaultDownloaderId();
      
      // 查找并更新对应的配置
      bool configUpdated = false;
      for (int i = 0; i < allConfigs.length; i++) {
        if (allConfigs[i].id == updatedConfig.id) {
          allConfigs[i] = updatedConfig;
          configUpdated = true;
          break;
        }
      }
      
      // 如果找到了配置并且有更新，保存到存储
      if (configUpdated) {
        await _storageService.saveDownloaderConfigs(
          allConfigs,
          defaultId: defaultId,
        );
        
        // 清除缓存，确保下次使用新配置
        clearConfigCache(updatedConfig.id);
      }
    } catch (e) {
       // 保存失败时不抛出异常，避免影响主要功能
       debugPrint('保存配置失败: $e');
     }
  }
  
  /// 暂停单个任务
  /// 
  /// [config] 下载器配置
  /// [password] 密码
  /// [hash] 任务哈希
  Future<void> pauseTask({
    required DownloaderConfig config,
    required String password,
    required String hash,
  }) async {
    await pauseTasks(
      config: config,
      password: password,
      hashes: [hash],
    );
  }
  
  /// 恢复单个任务
  /// 
  /// [config] 下载器配置
  /// [password] 密码
  /// [hash] 任务哈希
  Future<void> resumeTask({
    required DownloaderConfig config,
    required String password,
    required String hash,
  }) async {
    await resumeTasks(
      config: config,
      password: password,
      hashes: [hash],
    );
  }
  
  /// 删除单个任务
  /// 
  /// [config] 下载器配置
  /// [password] 密码
  /// [hash] 任务哈希
  /// [deleteFiles] 是否删除文件
  Future<void> deleteTask({
    required DownloaderConfig config,
    required String password,
    required String hash,
    bool deleteFiles = false,
  }) async {
    await deleteTasks(
      config: config,
      password: password,
      hashes: [hash],
      deleteFiles: deleteFiles,
    );
  }
}