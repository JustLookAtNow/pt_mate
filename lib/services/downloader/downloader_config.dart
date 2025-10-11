import 'downloader_models.dart';

/// 抽象下载器配置基类
abstract class DownloaderConfig {
  final String id;
  final String name;
  final DownloaderType type;
  
  const DownloaderConfig({
    required this.id,
    required this.name,
    required this.type,
  });
  
  /// 工厂方法，根据类型和数据创建具体的配置实例
  factory DownloaderConfig.fromJson(Map<String, dynamic> json) {
    final typeStr = json['type'] as String? ?? 'qbittorrent';
    final type = DownloaderType.fromString(typeStr);
    
    switch (type) {
      case DownloaderType.qbittorrent:
        return QbittorrentConfig.fromJson(json);
    }
  }
  
  /// 转换为JSON
  Map<String, dynamic> toJson();
  
  /// 复制配置并修改部分字段
  DownloaderConfig copyWith({
    String? id,
    String? name,
  });
}

/// qBittorrent下载器配置
class QbittorrentConfig extends DownloaderConfig {
  final String host;
  final int port;
  final String username;
  final String password;
  final bool useLocalRelay;
  final String? version;
  
  const QbittorrentConfig({
    required super.id,
    required super.name,
    required this.host,
    required this.port,
    required this.username,
    required this.password,
    this.useLocalRelay = false,
    this.version,
  }) : super(type: DownloaderType.qbittorrent);
  
  /// 从JSON创建配置
  factory QbittorrentConfig.fromJson(Map<String, dynamic> json) {
    // 支持嵌套的config结构和扁平结构（向后兼容）
    final config = json['config'] as Map<String, dynamic>? ?? json;
    
    return QbittorrentConfig(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      host: config['host'] ?? '',
      port: config['port'] ?? 8080,
      username: config['username'] ?? '',
      password: config['password'] ?? '',
      useLocalRelay: config['useLocalRelay'] ?? false,
      version: config['version'],
    );
  }
  

  
  @override
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'type': type.value,
      'config': {
        'host': host,
        'port': port,
        'username': username,
        'password': password,
        'useLocalRelay': useLocalRelay,
        if (version != null) 'version': version,
      },
    };
  }
  
  @override
  QbittorrentConfig copyWith({
    String? id,
    String? name,
    String? host,
    int? port,
    String? username,
    String? password,
    bool? useLocalRelay,
    String? version,
  }) {
    return QbittorrentConfig(
      id: id ?? this.id,
      name: name ?? this.name,
      host: host ?? this.host,
      port: port ?? this.port,
      username: username ?? this.username,
      password: password ?? this.password,
      useLocalRelay: useLocalRelay ?? this.useLocalRelay,
      version: version ?? this.version,
    );
  }
  
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is QbittorrentConfig &&
        other.id == id &&
        other.name == name &&
        other.host == host &&
        other.port == port &&
        other.username == username &&
        other.password == password &&
        other.useLocalRelay == useLocalRelay &&
        other.version == version;
  }
  
  @override
  int get hashCode {
    return Object.hash(
      id,
      name,
      host,
      port,
      username,
      password,
      useLocalRelay,
      version,
    );
  }
}
