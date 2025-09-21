import 'dart:convert';

// 用户资料信息
class MemberProfile {
  final String username;
  final double bonus; // magic points
  final double shareRate;
  final int uploadedBytes;
  final int downloadedBytes;
  final String uploadedBytesString; // 上传量字符串格式，如"1.2 GB"
  final String downloadedBytesString; // 下载量字符串格式，如"500 MB"
  final String? userId; // 用户ID，NexusPHP类型从data.data.id获取
  final String? passKey; // Pass Key，nexusphpweb类型从usercp.php获取

  MemberProfile({
    required this.username,
    required this.bonus,
    required this.shareRate,
    required this.uploadedBytes,
    required this.downloadedBytes,
    required this.uploadedBytesString,
    required this.downloadedBytesString,
    this.userId,
    this.passKey,
  });
}

// 种子详情
class TorrentDetail {
  final String descr;
  
  TorrentDetail({required this.descr});
}

// 下载状态枚举
enum DownloadStatus {
  none,        // 未下载
  downloading, // 下载中
  completed,   // 已完成
}

// 种子项目
class TorrentItem {
  final String id;
  final String name;
  final String smallDescr;
  final DiscountType discount; // 优惠类型枚举
  final String? discountEndTime; // e.g., 2025-08-27 21:16:48
  final String? downloadUrl; //下载链接，有些网站可以直接通过列表接口获取到
  final int seeders;
  final int leechers;
  final int sizeBytes;
  final List<String> imageList;
  final DownloadStatus downloadStatus;
  bool collection; // 是否已收藏（改为可变）

  TorrentItem({
    required this.id,
    required this.name,
    required this.smallDescr,
    this.discount = DiscountType.normal,
    required this.discountEndTime,
    required this.downloadUrl,
    required this.seeders,
    required this.leechers,
    required this.sizeBytes,
    required this.imageList,
    this.downloadStatus = DownloadStatus.none,
    this.collection = false,
  });

  TorrentItem copyWith({
    String? id,
    String? name,
    String? smallDescr,
    DiscountType? discount,
    String? discountEndTime,
    String? downloadUrl,
    int? seeders,
    int? leechers,
    int? sizeBytes,
    List<String>? imageList,
    DownloadStatus? downloadStatus,
    bool? collection,
  }) {
    return TorrentItem(
      id: id ?? this.id,
      name: name ?? this.name,
      smallDescr: smallDescr ?? this.smallDescr,
      discount: discount ?? this.discount,
      discountEndTime: discountEndTime ?? this.discountEndTime,
      downloadUrl: downloadUrl ?? this.downloadUrl,
      seeders: seeders ?? this.seeders,
      leechers: leechers ?? this.leechers,
      sizeBytes: sizeBytes ?? this.sizeBytes,
      imageList: imageList ?? this.imageList,
      downloadStatus: downloadStatus ?? this.downloadStatus,
      collection: collection ?? this.collection,
    );
  }
}

// 种子搜索结果
class TorrentSearchResult {
  final int pageNumber;
  final int pageSize;
  final int total;
  final int totalPages;
  final List<TorrentItem> items;

  TorrentSearchResult({
    required this.pageNumber,
    required this.pageSize,
    required this.total,
    required this.totalPages,
    required this.items,
  });
}

// 优惠类型枚举
enum DiscountType {
  normal('NORMAL'),
  free('FREE'),
  twoXFree('2xFREE'),
  percent10('PERCENT_10'),
  percent20('PERCENT_20'),
  percent30('PERCENT_30'),
  percent40('PERCENT_40'),
  percent50('PERCENT_50'),
  percent60('PERCENT_60'),
  percent70('PERCENT_70'),
  percent80('PERCENT_80'),
  percent90('PERCENT_90');

  const DiscountType(this.value);
  final String value;


  
  // 获取显示文本
  String get displayText {
    switch (this) {
      case DiscountType.normal:
        return '';
      case DiscountType.free:
        return 'FREE';
      case DiscountType.twoXFree:
        return '2xFREE';
      case DiscountType.percent10:
        return '10%';
      case DiscountType.percent20:
        return '20%';
      case DiscountType.percent30:
        return '30%';
      case DiscountType.percent40:
        return '40%';
      case DiscountType.percent50:
        return '50%';
      case DiscountType.percent60:
        return '60%';
      case DiscountType.percent70:
        return '70%';
      case DiscountType.percent80:
        return '80%';
      case DiscountType.percent90:
        return '90%';
    }
  }
  
  // 获取显示颜色类型
  DiscountColorType get colorType {
    switch (this) {
      case DiscountType.normal:
        return DiscountColorType.none;
      case DiscountType.free:
      case DiscountType.twoXFree:
        return DiscountColorType.green;
      case DiscountType.percent10:
      case DiscountType.percent20:
      case DiscountType.percent30:
      case DiscountType.percent40:
      case DiscountType.percent50:
      case DiscountType.percent60:
      case DiscountType.percent70:
      case DiscountType.percent80:
      case DiscountType.percent90:
        return DiscountColorType.yellow;
    }
  }
}

// 优惠显示颜色类型
enum DiscountColorType {
  none,
  green,
  yellow,
}

// 网站类型枚举
enum SiteType {
  mteam('M-Team', 'M-Team 站点', 'API Key (x-api-key)', '从 控制台-实验室-存储令牌 获取并粘贴此处'),
  nexusphp('NexusPHP', 'NexusPHP(1.9+ with api)', 'API Key (访问令牌)', '控制面板-设定首页-访问令牌（权限都勾上）'),
  nexusphpweb('NexusPHPWeb', 'NexusPHP(web)', 'Cookie认证', '通过网页登录获取认证信息'),
  // 未来可以添加其他站点类型
  // gazelle('Gazelle', 'Gazelle 站点'),
  ;

  const SiteType(this.id, this.displayName, this.apiKeyLabel, this.apiKeyHint);
  final String id;
  final String displayName;
  final String apiKeyLabel;
  final String apiKeyHint;

  String get passKeyLabel {
    switch (this) {   
      case SiteType.mteam:
        return 'Pass Key'; // M-Team通常不需要passKey
      case SiteType.nexusphp:
        return 'Pass Key (可选)';
      case SiteType.nexusphpweb:
        return 'Pass Key';
    }
  }

  String get passKeyHint {
    switch (this) {
      case SiteType.mteam:
        return '请输入Pass Key（可选）';
      case SiteType.nexusphp:
        return '控制面板-设定首页-密钥（可选）';
      case SiteType.nexusphpweb:
        return '控制面板-设定首页-密钥（必填）';
    }
  }

  bool get requiresPassKey {
    switch (this) {
      case SiteType.mteam:
        return false;
      case SiteType.nexusphp:
        return false;
      case SiteType.nexusphpweb:
        return false; // 改为可选，从fetchMemberProfile获取
    }
  }
}

// 站点功能配置
class SiteFeatures {
  final bool supportMemberProfile; // 支持用户资料
  final bool supportTorrentSearch; // 支持种子搜索
  final bool supportTorrentDetail; // 支持种子详情
  final bool supportDownload; // 支持下载
  final bool supportCollection; // 支持收藏功能
  final bool supportHistory; // 支持下载历史
  final bool supportCategories; // 支持分类搜索
  final bool supportAdvancedSearch; // 支持高级搜索

  const SiteFeatures({
    this.supportMemberProfile = true,
    this.supportTorrentSearch = true,
    this.supportTorrentDetail = true,
    this.supportDownload = true,
    this.supportCollection = true,
    this.supportHistory = true,
    this.supportCategories = true,
    this.supportAdvancedSearch = true,
  });

  SiteFeatures copyWith({
    bool? supportMemberProfile,
    bool? supportTorrentSearch,
    bool? supportTorrentDetail,
    bool? supportDownload,
    bool? supportCollection,
    bool? supportHistory,
    bool? supportCategories,
    bool? supportAdvancedSearch,
  }) => SiteFeatures(
        supportMemberProfile: supportMemberProfile ?? this.supportMemberProfile,
        supportTorrentSearch: supportTorrentSearch ?? this.supportTorrentSearch,
        supportTorrentDetail: supportTorrentDetail ?? this.supportTorrentDetail,
        supportDownload: supportDownload ?? this.supportDownload,
        supportCollection: supportCollection ?? this.supportCollection,
        supportHistory: supportHistory ?? this.supportHistory,
        supportCategories: supportCategories ?? this.supportCategories,
        supportAdvancedSearch: supportAdvancedSearch ?? this.supportAdvancedSearch,
      );

  Map<String, dynamic> toJson() => {
        'supportMemberProfile': supportMemberProfile,
        'supportTorrentSearch': supportTorrentSearch,
        'supportTorrentDetail': supportTorrentDetail,
        'supportDownload': supportDownload,
        'supportCollection': supportCollection,
        'supportHistory': supportHistory,
        'supportCategories': supportCategories,
        'supportAdvancedSearch': supportAdvancedSearch,
      };

  factory SiteFeatures.fromJson(Map<String, dynamic> json) => SiteFeatures(
        supportMemberProfile: json['userProfile'] ?? json['supportMemberProfile'] as bool? ?? true,
        supportTorrentSearch: json['torrentSearch'] ?? json['supportTorrentSearch'] as bool? ?? true,
        supportTorrentDetail: json['torrentDetail'] ?? json['supportTorrentDetail'] as bool? ?? true,
        supportDownload: json['download'] ?? json['supportDownload'] as bool? ?? true,
        supportCollection: json['favorites'] ?? json['supportCollection'] as bool? ?? true,
        supportHistory: json['downloadHistory'] ?? json['supportHistory'] as bool? ?? true,
        supportCategories: json['categorySearch'] ?? json['supportCategories'] as bool? ?? true,
        supportAdvancedSearch: json['advancedSearch'] ?? json['supportAdvancedSearch'] as bool? ?? true,
      );

  // M-Team 站点的默认功能配置
  static const SiteFeatures mteamDefault = SiteFeatures(
    supportMemberProfile: true,
    supportTorrentSearch: true,
    supportTorrentDetail: true,
    supportDownload: true,
    supportCollection: true,
    supportHistory: true,
    supportCategories: true,
    supportAdvancedSearch: true,
  );

  @override
  String toString() => jsonEncode(toJson());
}

class SiteConfig {
  final String id; // 唯一标识符
  final String name;
  final String baseUrl; // e.g. https://kp.m-team.cc/
  final String? apiKey; // x-api-key
  final String? passKey; // NexusPHP类型网站的passKey
  final String? cookie; // NexusPHPWeb类型网站的登录cookie
  final String? userId; // 用户ID，从fetchMemberProfile获取
  final SiteType siteType; // 网站类型
  final bool isActive; // 是否激活
  final List<SearchCategoryConfig> searchCategories; // 查询分类配置
  final SiteFeatures features; // 功能支持配置

  const SiteConfig({
    required this.id,
    required this.name,
    required this.baseUrl,
    this.apiKey,
    this.passKey,
    this.cookie,
    this.userId,
    this.siteType = SiteType.mteam,
    this.isActive = true,
    this.searchCategories = const [],
    this.features = SiteFeatures.mteamDefault,
  });

  SiteConfig copyWith({
    String? id,
    String? name,
    String? baseUrl,
    String? apiKey,
    String? passKey,
    String? cookie,
    String? userId,
    SiteType? siteType,
    bool? isActive,
    List<SearchCategoryConfig>? searchCategories,
    SiteFeatures? features,
  }) => SiteConfig(
        id: id ?? this.id,
        name: name ?? this.name,
        baseUrl: baseUrl ?? this.baseUrl,
        apiKey: apiKey ?? this.apiKey,
        passKey: passKey ?? this.passKey,
        cookie: cookie ?? this.cookie,
        userId: userId ?? this.userId,
        siteType: siteType ?? this.siteType,
        isActive: isActive ?? this.isActive,
        searchCategories: searchCategories ?? this.searchCategories,
        features: features ?? this.features,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'baseUrl': baseUrl,
        'apiKey': apiKey,
        'passKey': passKey,
        'cookie': cookie,
        'userId': userId,
        'siteType': siteType.id,
        'isActive': isActive,
        'searchCategories': searchCategories.map((e) => e.toJson()).toList(),
        'features': features.toJson(),
      };

  factory SiteConfig.fromJson(Map<String, dynamic> json) {
    List<SearchCategoryConfig> categories = [];
    if (json['searchCategories'] != null) {
      try {
        final list = (json['searchCategories'] as List).cast<Map<String, dynamic>>();
        categories = list.map(SearchCategoryConfig.fromJson).toList();
      } catch (_) {
        // 解析失败时使用默认配置
        categories = SearchCategoryConfig.getDefaultConfigs();
      }
    } else {
      // 如果没有配置，使用默认配置
      categories = SearchCategoryConfig.getDefaultConfigs();
    }
    
    // 解析功能配置
    SiteFeatures features = SiteFeatures.mteamDefault;
    if (json['features'] != null) {
      try {
        features = SiteFeatures.fromJson(json['features'] as Map<String, dynamic>);
      } catch (_) {
        // 解析失败时使用默认配置
        features = SiteFeatures.mteamDefault;
      }
    }
    
    return SiteConfig(
      id: json['id'] as String? ?? 'legacy-${DateTime.now().millisecondsSinceEpoch}',
      name: json['name'] as String,
      baseUrl: json['baseUrl'] as String,
      apiKey: json['apiKey'] as String?,
      passKey: json['passKey'] as String?,
      cookie: json['cookie'] as String?,
      userId: json['userId'] as String?,
      siteType: SiteType.values.firstWhere(
        (type) => type.id == (json['siteType'] as String? ?? 'M-Team'),
        orElse: () => SiteType.mteam,
      ),
      isActive: json['isActive'] as bool? ?? true,
      searchCategories: categories,
      features: features,
    );
  }

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

// WebDAV同步状态枚举
enum WebDAVSyncStatus {
  idle,        // 空闲
  syncing,     // 同步中
  uploading,   // 上传中
  downloading, // 下载中
  success,     // 成功
  error,       // 错误
}

// WebDAV配置类
class WebDAVConfig {
  final String id; // 唯一标识符
  final String name; // 配置名称
  final String serverUrl; // WebDAV服务器地址，如：https://dav.jianguoyun.com/dav/
  final String username; // 用户名
  // 注意：密码通过安全存储单独管理，不再作为模型字段
  final String remotePath; // 远程路径，如：/PTMate/backups/
  final bool isEnabled; // 是否启用
  final bool autoSync; // 是否自动同步
  final int syncIntervalMinutes; // 自动同步间隔（分钟）
  final DateTime? lastSyncTime; // 最后同步时间
  final WebDAVSyncStatus lastSyncStatus; // 最后同步状态
  final String? lastSyncError; // 最后同步错误信息

  const WebDAVConfig({
    required this.id,
    required this.name,
    required this.serverUrl,
    required this.username,
    this.remotePath = '/PTMate/backups/',
    this.isEnabled = false,
    this.autoSync = false,
    this.syncIntervalMinutes = 60,
    this.lastSyncTime,
    this.lastSyncStatus = WebDAVSyncStatus.idle,
    this.lastSyncError,
  });

  WebDAVConfig copyWith({
    String? id,
    String? name,
    String? serverUrl,
    String? username,
    String? remotePath,
    bool? isEnabled,
    bool? autoSync,
    int? syncIntervalMinutes,
    DateTime? lastSyncTime,
    WebDAVSyncStatus? lastSyncStatus,
    String? lastSyncError,
  }) => WebDAVConfig(
        id: id ?? this.id,
        name: name ?? this.name,
        serverUrl: serverUrl ?? this.serverUrl,
        username: username ?? this.username,
        remotePath: remotePath ?? this.remotePath,
        isEnabled: isEnabled ?? this.isEnabled,
        autoSync: autoSync ?? this.autoSync,
        syncIntervalMinutes: syncIntervalMinutes ?? this.syncIntervalMinutes,
        lastSyncTime: lastSyncTime ?? this.lastSyncTime,
        lastSyncStatus: lastSyncStatus ?? this.lastSyncStatus,
        lastSyncError: lastSyncError ?? this.lastSyncError,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'serverUrl': serverUrl,
        'username': username,
        // 注意：密码通过安全存储单独管理，不包含在JSON中
        'remotePath': remotePath,
        'isEnabled': isEnabled,
        'autoSync': autoSync,
        'syncIntervalMinutes': syncIntervalMinutes,
        'lastSyncTime': lastSyncTime?.toIso8601String(),
        'lastSyncStatus': lastSyncStatus.name,
        'lastSyncError': lastSyncError,
      };

  factory WebDAVConfig.fromJson(Map<String, dynamic> json) => WebDAVConfig(
        id: json['id'] as String,
        name: json['name'] as String,
        serverUrl: json['serverUrl'] as String,
        username: json['username'] as String,
        // 注意：密码通过安全存储单独管理，不从JSON中读取
        remotePath: json['remotePath'] as String? ?? '/PTMate/backups/',
        isEnabled: json['isEnabled'] as bool? ?? false,
        autoSync: json['autoSync'] as bool? ?? false,
        syncIntervalMinutes: json['syncIntervalMinutes'] as int? ?? 60,
        lastSyncTime: json['lastSyncTime'] != null 
            ? DateTime.parse(json['lastSyncTime'] as String) 
            : null,
        lastSyncStatus: WebDAVSyncStatus.values.firstWhere(
          (status) => status.name == (json['lastSyncStatus'] as String? ?? 'idle'),
          orElse: () => WebDAVSyncStatus.idle,
        ),
        lastSyncError: json['lastSyncError'] as String?,
      );

  @override
  String toString() => jsonEncode(toJson());

  // 创建默认配置
  static WebDAVConfig createDefault() => WebDAVConfig(
        id: 'default-${DateTime.now().millisecondsSinceEpoch}',
        name: '默认WebDAV配置',
        serverUrl: '',
        username: '',
      );

  // 常用WebDAV服务提供商的预设配置
  static List<WebDAVPreset> getPresets() => [
        WebDAVPreset(
          name: '坚果云',
          serverUrl: 'https://dav.jianguoyun.com/dav/',
          description: '使用坚果云的WebDAV服务，需要在坚果云设置中开启第三方应用管理并创建应用密码',
        ),
        WebDAVPreset(
          name: 'Nextcloud',
          serverUrl: 'https://your-nextcloud.com/remote.php/dav/files/username/',
          description: '自建或第三方Nextcloud服务，请替换为您的实际服务器地址',
        ),
        WebDAVPreset(
          name: 'ownCloud',
          serverUrl: 'https://your-owncloud.com/remote.php/webdav/',
          description: '自建或第三方ownCloud服务，请替换为您的实际服务器地址',
        ),
        WebDAVPreset(
          name: 'Box',
          serverUrl: 'https://dav.box.com/dav/',
          description: 'Box云存储的WebDAV接口',
        ),
      ];
}

// WebDAV预设配置
class WebDAVPreset {
  final String name;
  final String serverUrl;
  final String description;

  const WebDAVPreset({
    required this.name,
    required this.serverUrl,
    required this.description,
  });
}

class Defaults {
  // 预设站点配置现在从JSON文件加载
  // 使用 SiteConfigService.loadPresetSites() 来获取预设站点
  
  /// 获取默认的搜索分类配置
  static List<SearchCategoryConfig> getDefaultSearchCategories() {
    return SearchCategoryConfig.getDefaultConfigs();
  }
  
  /// 获取默认的站点功能配置
  static SiteFeatures getDefaultSiteFeatures() {
    return SiteFeatures.mteamDefault;
  }
}