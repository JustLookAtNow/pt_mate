import 'downloader_client.dart';
import 'downloader_config.dart';
import 'downloader_models.dart';
import 'qbittorrent_client.dart';
import 'transmission_client.dart';
import 'rutorrent_client.dart';

/// 下载器工厂
/// 
/// 根据配置类型创建相应的下载器客户端实例，并提供客户端缓存管理
class DownloaderFactory {
  DownloaderFactory._();
  
  /// 客户端缓存
  static final Map<String, DownloaderClient> _clientCache = {};
  
  /// 密码缓存
  static final Map<String, String> _passwordCache = {};
  
  /// 获取或创建下载器客户端（带缓存）
  /// 
  /// [config] 下载器配置
  /// [password] 密码（对于需要密码的下载器）
  /// [onConfigUpdated] 配置更新回调（可选）
  static DownloaderClient getClient({
    required DownloaderConfig config,
    required String password,
    Function(DownloaderConfig)? onConfigUpdated,
  }) {
    final configId = config.id;
    final cachedPassword = _passwordCache[configId];
    
    // 检查是否需要重新创建客户端
    // 1. 缓存中没有客户端
    // 2. 密码发生变化
    if (!_clientCache.containsKey(configId) || cachedPassword != password) {
      // 清除旧的客户端（如果存在）
      _clientCache.remove(configId);
      
      // 创建新的客户端
      final client = _createClient(
        config: config,
        password: password,
        onConfigUpdated: onConfigUpdated,
      );
      
      // 缓存客户端和密码
      _clientCache[configId] = client;
      _passwordCache[configId] = password;
      
      return client;
    }
    
    // 返回缓存的客户端
    return _clientCache[configId]!;
  }
  
  /// 创建下载器客户端（内部方法）
  /// 
  /// [config] 下载器配置
  /// [password] 密码（对于需要密码的下载器）
  /// [onConfigUpdated] 配置更新回调（可选）
  static DownloaderClient _createClient({
    required DownloaderConfig config,
    required String password,
    Function(DownloaderConfig)? onConfigUpdated,
  }) {
    switch (config.type) {
      case DownloaderType.qbittorrent:
        if (config is QbittorrentConfig) {
          return QbittorrentClient(
            config: config,
            password: password,
            onConfigUpdated: onConfigUpdated != null
              ? (updatedConfig) => onConfigUpdated(updatedConfig)
              : null,
          );
        } else {
          throw ArgumentError('Invalid config type for qBittorrent: ${config.runtimeType}');
        }
      case DownloaderType.transmission:
        if (config is TransmissionConfig) {
          return TransmissionClient(
            config: config,
            password: password,
            onConfigUpdated: onConfigUpdated != null
              ? (updatedConfig) => onConfigUpdated(updatedConfig)
              : null,
          );
        } else {
          throw ArgumentError('Invalid config type for Transmission: ${config.runtimeType}');
        }
      case DownloaderType.rutorrent:
        if (config is RuTorrentConfig) {
          return RuTorrentClient(
            config: config,
            password: password,
            onConfigUpdated: onConfigUpdated != null
              ? (updatedConfig) => onConfigUpdated(updatedConfig)
              : null,
          );
        } else {
          throw ArgumentError('Invalid config type for ruTorrent: ${config.runtimeType}');
        }
    }
  }
  
  /// 测试下载器连接
  /// 
  /// [config] 下载器配置
  /// [password] 密码
  static Future<void> testConnection({
    required DownloaderConfig config,
    required String password,
  }) async {
    final client = getClient(config: config, password: password);
    await client.testConnection();
  }
  
  /// 获取支持的下载器类型列表
  static List<DownloaderType> getSupportedTypes() {
    return DownloaderType.values;
  }
  
  /// 检查是否支持指定的下载器类型
  static bool isTypeSupported(DownloaderType type) {
    return DownloaderType.values.contains(type);
  }
  
  /// 清除所有缓存
  static void clearCache() {
    _clientCache.clear();
    _passwordCache.clear();
  }
  
  /// 清除指定配置的缓存
  static void clearConfigCache(String configId) {
    _clientCache.remove(configId);
    _passwordCache.remove(configId);
  }
  
  /// 获取缓存的客户端数量
  static int getCachedClientCount() {
    return _clientCache.length;
  }
  
  /// 检查指定配置是否有缓存的客户端
  static bool hasCachedClient(String configId) {
    return _clientCache.containsKey(configId);
  }
}