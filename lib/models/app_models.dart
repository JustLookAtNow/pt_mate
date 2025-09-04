import 'dart:convert';

class SiteConfig {
  final String name;
  final String baseUrl; // e.g. https://kp.m-team.cc/
  final String? apiKey; // x-api-key

  const SiteConfig({
    required this.name,
    required this.baseUrl,
    this.apiKey,
  });

  SiteConfig copyWith({String? name, String? baseUrl, String? apiKey}) => SiteConfig(
        name: name ?? this.name,
        baseUrl: baseUrl ?? this.baseUrl,
        apiKey: apiKey ?? this.apiKey,
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'baseUrl': baseUrl,
        'apiKey': apiKey,
      };

  factory SiteConfig.fromJson(Map<String, dynamic> json) => SiteConfig(
        name: json['name'] as String,
        baseUrl: json['baseUrl'] as String,
        apiKey: json['apiKey'] as String?,
      );

  @override
  String toString() => jsonEncode(toJson());
}

// 查询条件配置
class SearchCategoryConfig {
  final String id; // 唯一标识
  final String displayName; // 显示名称
  final String parameters; // 请求参数，格式如：mode:normal 或 mode:normal,teams:["44","9","43"]

  const SearchCategoryConfig({
    required this.id,
    required this.displayName,
    required this.parameters,
  });

  SearchCategoryConfig copyWith({
    String? id,
    String? displayName,
    String? parameters,
  }) => SearchCategoryConfig(
        id: id ?? this.id,
        displayName: displayName ?? this.displayName,
        parameters: parameters ?? this.parameters,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'displayName': displayName,
        'parameters': parameters,
      };

  factory SearchCategoryConfig.fromJson(Map<String, dynamic> json) => SearchCategoryConfig(
        id: json['id'] as String,
        displayName: json['displayName'] as String,
        parameters: json['parameters'] as String,
      );

  // 解析参数字符串为Map
  // 支持两种格式：
  // 1. JSON格式：{"mode": "normal", "teams": ["44", "9", "43"]}
  // 2. 键值对格式（用分号分隔）：mode: normal; teams: ["44", "9", "43"]
  Map<String, dynamic> parseParameters() {
    final result = <String, dynamic>{};
    final trimmed = parameters.trim();
    if (trimmed.isEmpty) return result;

    try {
      // 首先尝试解析为JSON格式
      if (trimmed.startsWith('{') && trimmed.endsWith('}')) {
        final jsonResult = jsonDecode(trimmed) as Map<String, dynamic>;
        return jsonResult;
      }
    } catch (_) {
      // JSON解析失败，继续使用键值对格式
    }

    // 使用分号分隔的键值对格式
    final parts = trimmed.split(';');
    for (final part in parts) {
      final trimmedPart = part.trim();
      if (trimmedPart.isEmpty) continue;

      final colonIndex = trimmedPart.indexOf(':');
      if (colonIndex == -1) continue;

      final key = trimmedPart.substring(0, colonIndex).trim();
      final valueStr = trimmedPart.substring(colonIndex + 1).trim();

      // 智能解析值类型
      try {
        if (valueStr.startsWith('[') || valueStr.startsWith('{')) {
          // JSON数组或对象
          result[key] = jsonDecode(valueStr);
        } else if (valueStr.startsWith('"') && valueStr.endsWith('"') && valueStr.length >= 2) {
          // 带引号的字符串，去掉引号
          result[key] = valueStr.substring(1, valueStr.length - 1);
        } else if (valueStr.toLowerCase() == 'true') {
          // 布尔值 true
          result[key] = true;
        } else if (valueStr.toLowerCase() == 'false') {
          // 布尔值 false
          result[key] = false;
        } else if (valueStr.toLowerCase() == 'null') {
          // null值
          result[key] = null;
        } else {
          // 尝试解析为数字
          final intValue = int.tryParse(valueStr);
          if (intValue != null) {
            result[key] = intValue;
          } else {
            final doubleValue = double.tryParse(valueStr);
            if (doubleValue != null) {
              result[key] = doubleValue;
            } else {
              // 作为字符串处理
              result[key] = valueStr;
            }
          }
        }
      } catch (_) {
        // 解析失败时作为字符串处理
        result[key] = valueStr;
      }
    }
    return result;
  }

  @override
  String toString() => jsonEncode(toJson());

  // 默认配置
  static List<SearchCategoryConfig> getDefaultConfigs() => [
        const SearchCategoryConfig(
          id: 'normal',
          displayName: '综合',
          parameters: '{"mode": "normal"}',
        ),
        const SearchCategoryConfig(
          id: 'tvshow',
          displayName: '电视',
          parameters: '{"mode": "tvshow"}',
        ),
        const SearchCategoryConfig(
          id: 'movie',
          displayName: '电影',
          parameters: '{"mode": "movie"}',
        ),
      ];
}

class QbClientConfig {
  final String id; // uuid or custom id
  final String name;
  final String host; // ip or domain
  final int port;
  final String username;
  final String? password; // stored securely, may be null when loaded from prefs-only
  final bool useLocalRelay; // 是否启用本地中转，先下载种子文件再提交给qBittorrent

  const QbClientConfig({
    required this.id,
    required this.name,
    required this.host,
    required this.port,
    required this.username,
    this.password,
    this.useLocalRelay = false, // 默认禁用
  });

  QbClientConfig copyWith({
    String? id,
    String? name,
    String? host,
    int? port,
    String? username,
    String? password,
    bool? useLocalRelay,
  }) => QbClientConfig(
        id: id ?? this.id,
        name: name ?? this.name,
        host: host ?? this.host,
        port: port ?? this.port,
        username: username ?? this.username,
        password: password ?? this.password,
        useLocalRelay: useLocalRelay ?? this.useLocalRelay,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'host': host,
        'port': port,
        'username': username,
        'useLocalRelay': useLocalRelay,
        // password intentionally excluded from plain json by default
      };

  factory QbClientConfig.fromJson(Map<String, dynamic> json) => QbClientConfig(
        id: json['id'] as String,
        name: json['name'] as String,
        host: json['host'] as String,
        port: (json['port'] as num).toInt(),
        username: json['username'] as String,
        useLocalRelay: (json['useLocalRelay'] as bool?) ?? false,
      );
}

class Defaults {
  static const List<SiteConfig> presetSites = [
    SiteConfig(name: 'M-Team api 主站', baseUrl: 'https://api.m-team.cc/'),
    SiteConfig(name: 'M-Team api 副站', baseUrl: 'https://api2.m-team.cc/'),
    SiteConfig(name: 'M-Team 旧风格api', baseUrl: 'https://api.m-team.io/'),
  ];
}