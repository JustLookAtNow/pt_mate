import 'downloader_client.dart';
import 'downloader_config.dart';
import 'downloader_models.dart';
import 'qbittorrent_client.dart';

/// 下载器工厂
/// 
/// 根据配置类型创建相应的下载器客户端实例
class DownloaderFactory {
  DownloaderFactory._();
  
  /// 创建下载器客户端
  /// 
  /// [config] 下载器配置
  /// [password] 密码（对于需要密码的下载器）
  /// [onConfigUpdated] 配置更新回调（可选）
  static DownloaderClient createClient({
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
    final client = createClient(config: config, password: password);
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
}