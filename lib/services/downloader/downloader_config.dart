import 'downloader_models.dart';

/// 抽象下载器配置基类
abstract class DownloaderConfig {
  final String id;
  final String name;
  final DownloaderType type;
  final String host;
  final int port;
  final String username;
  final String password;
  final bool useLocalRelay;
  final String? version;
  
  const DownloaderConfig({
    required this.id,
    required this.name,
    required this.type,
    required this.host,
    required this.port,
    required this.username,
    required this.password,
    this.useLocalRelay = false,
    this.version,
  });
  
  /// 工厂方法，根据类型和数据创建具体的配置实例
  factory DownloaderConfig.fromJson(Map<String, dynamic> json) {
    final typeStr = json['type'] as String? ?? 'qbittorrent';
    final type = DownloaderType.fromString(typeStr);
    
    switch (type) {
      case DownloaderType.qbittorrent:
        return QbittorrentConfig.fromJson(json);
      case DownloaderType.transmission:
        return TransmissionConfig.fromJson(json);
    }
  }
  
  /// 通用的JSON转换方法
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
  
  /// 复制配置并修改部分字段
  DownloaderConfig copyWith({
    String? id,
    String? name,
    String? host,
    int? port,
    String? username,
    String? password,
    bool? useLocalRelay,
    String? version,
  });
  
  /// 通用的相等性比较
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is DownloaderConfig &&
        other.runtimeType == runtimeType &&
        other.id == id &&
        other.name == name &&
        other.host == host &&
        other.port == port &&
        other.username == username &&
        other.password == password &&
        other.useLocalRelay == useLocalRelay &&
        other.version == version;
  }
  
  /// 通用的哈希码计算
  @override
  int get hashCode {
    return Object.hash(
      runtimeType,
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
  
  /// 获取默认端口号（子类可重写）
  int get defaultPort;
  
  /// 从配置数据创建实例的通用方法
  static T _createFromConfig<T extends DownloaderConfig>(
    Map<String, dynamic> json,
    T Function({
      required String id,
      required String name,
      required String host,
      required int port,
      required String username,
      required String password,
      bool useLocalRelay,
      String? version,
    })
    constructor,
    int defaultPort,
  ) {
    // 支持嵌套的config结构和扁平结构（向前兼容）
    final config = json['config'] as Map<String, dynamic>? ?? json;
    
    return constructor(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      host: config['host'] ?? '',
      port: config['port'] ?? defaultPort,
      username: config['username'] ?? '',
      password: config['password'] ?? '',
      useLocalRelay: config['useLocalRelay'] ?? false,
      version: config['version'],
    );
  }
}

/// qBittorrent下载器配置
class QbittorrentConfig extends DownloaderConfig {
  const QbittorrentConfig({
    required super.id,
    required super.name,
    required super.host,
    required super.port,
    required super.username,
    required super.password,
    super.useLocalRelay = false,
    super.version,
  }) : super(type: DownloaderType.qbittorrent);
  
  @override
  int get defaultPort => 8080;

  /// 从JSON创建配置
  factory QbittorrentConfig.fromJson(Map<String, dynamic> json) {
    return DownloaderConfig._createFromConfig(
      json,
      ({
        required String id,
        required String name,
        required String host,
        required int port,
        required String username,
        required String password,
        bool useLocalRelay = false,
        String? version,
      }) => QbittorrentConfig(
        id: id,
        name: name,
        host: host,
        port: port,
        username: username,
        password: password,
        useLocalRelay: useLocalRelay,
        version: version,
      ),
      8080,
    );
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
}

/// Transmission下载器配置
class TransmissionConfig extends DownloaderConfig {
  const TransmissionConfig({
    required super.id,
    required super.name,
    required super.host,
    required super.port,
    required super.username,
    required super.password,
    super.useLocalRelay = false,
    super.version,
  }) : super(type: DownloaderType.transmission);
  
  @override
  int get defaultPort => 9091;

  /// 从JSON创建配置
  factory TransmissionConfig.fromJson(Map<String, dynamic> json) {
    return DownloaderConfig._createFromConfig(
      json,
      ({
        required String id,
        required String name,
        required String host,
        required int port,
        required String username,
        required String password,
        bool useLocalRelay = false,
        String? version,
      }) => TransmissionConfig(
        id: id,
        name: name,
        host: host,
        port: port,
        username: username,
        password: password,
        useLocalRelay: useLocalRelay,
        version: version,
      ),
      9091,
    );
  }
  
  @override
  TransmissionConfig copyWith({
    String? id,
    String? name,
    String? host,
    int? port,
    String? username,
    String? password,
    bool? useLocalRelay,
    String? version,
  }) {
    return TransmissionConfig(
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
}
