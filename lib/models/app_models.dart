import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart';
import '../services/site_config_service.dart';
import '../utils/format.dart';

final Logger _logger = Logger();

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
  final String? authKey; // 认证密钥，Gazelle类型使用
  final DateTime? lastAccess; // 最后访问时间，来自 API data['last_access']
  // 额外信息（可选）：时魔与做种体积，仅部分站点提供
  final double? bonusPerHour; // 时魔：每小时魔力增长值
  final int? seedingSizeBytes; // 做种体积（字节）

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
    this.authKey,
    this.lastAccess,
    this.bonusPerHour,
    this.seedingSizeBytes,
  });

  // 序列化方法，支持持久化缓存与向后兼容解析
  factory MemberProfile.fromJson(Map<String, dynamic> json) {
    final username = (json['username'] ?? json['name'] ?? '').toString();
    final bonusVal = json['bonus'];
    final shareVal = json['shareRate'] ?? json['share_rate'];
    final uploadedVal = json['uploadedBytes'] ?? json['uploaded_bytes'];
    final downloadedVal = json['downloadedBytes'] ?? json['downloaded_bytes'];
    final uploadedStr =
        json['uploadedBytesString'] ?? json['uploaded_str'] ?? '';
    final downloadedStr =
        json['downloadedBytesString'] ?? json['downloaded_str'] ?? '';
    // 新增字段兼容旧版本与不同命名
    final bonusPerHourVal = json['bonusPerHour'] ?? json['bonus_per_hour'];
    final seedingSizeVal = json['seedingSizeBytes'] ?? json['seedingSize'] ?? json['seederSize'];

    double parseDouble(dynamic v) {
      if (v is num) return v.toDouble();
      if (v is String) return double.tryParse(v) ?? 0.0;
      return 0.0;
    }

    int parseInt(dynamic v) {
      if (v is int) return v;
      if (v is num) return v.toInt();
      return FormatUtil.parseInt(v) ?? 0;
    }

    return MemberProfile(
      username: username,
      bonus: parseDouble(bonusVal),
      shareRate: parseDouble(shareVal),
      uploadedBytes: parseInt(uploadedVal),
      downloadedBytes: parseInt(downloadedVal),
      uploadedBytesString: uploadedStr.toString(),
      downloadedBytesString: downloadedStr.toString(),
      userId: json['userId']?.toString(),
      passKey: json['passKey']?.toString(),
      authKey: (json['authKey'] ?? json['auth_key'] ?? json['authkey'])
          ?.toString(),
      lastAccess: json['lastAccess'] != null
          ? DateTime.tryParse(json['lastAccess'].toString())?.toLocal()
          : (json['last_access'] != null
                ? Formatters.parseDateTimeCustom(json['last_access'].toString())
                : null),
      bonusPerHour: bonusPerHourVal == null ? null : parseDouble(bonusPerHourVal),
      seedingSizeBytes: seedingSizeVal == null ? null : parseInt(seedingSizeVal),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'username': username,
      'bonus': bonus,
      'shareRate': shareRate,
      'uploadedBytes': uploadedBytes,
      'downloadedBytes': downloadedBytes,
      'uploadedBytesString': uploadedBytesString,
      'downloadedBytesString': downloadedBytesString,
      'userId': userId,
      'passKey': passKey,
      if (authKey != null) 'authKey': authKey,
      'lastAccess': lastAccess?.toIso8601String(),
      if (bonusPerHour != null) 'bonusPerHour': bonusPerHour,
      if (seedingSizeBytes != null) 'seedingSizeBytes': seedingSizeBytes,
    };
  }
}

// 种子详情
class TorrentDetail {
  final String descr;
  final String? descrHtml; // 可选的HTML描述，用于原生HTML渲染
  final String? webviewUrl; // 可选的webview URL，用于嵌入式显示

  TorrentDetail({required this.descr, this.descrHtml, this.webviewUrl});
}

// 下载状态枚举
enum DownloadStatus {
  none, // 未下载
  downloading, // 下载中
  completed, // 已完成
}

// 种子项目
class TorrentItem {
  final String id;
  final String name;
  final String smallDescr;
  final DiscountType discount; // 优惠类型枚举
  final DateTime? discountEndTime; // 优惠结束时间
  final String? downloadUrl; //下载链接，有些网站可以直接通过列表接口获取到
  final String? description; //描述，有些网站可以直接通过列表接口获取到
  final int seeders;
  final int leechers;
  final int sizeBytes;
  //仅mteam，暂时没啥用
  final List<String> imageList;
  final String cover;
  final DownloadStatus downloadStatus;
  bool collection; // 是否已收藏（改为可变）
  final DateTime createdDate; // 种子创建时间
  final String? doubanRating; // 豆瓣评分
  final String? imdbRating; // IMDB评分
  final bool isTop; // 是否置顶（M-Team：toppingLevel>0）
  final List<TagType> tags; // 种子标签
  final int comments; // 评论数量

  TorrentItem({
    required this.id,
    required this.name,
    required this.smallDescr,
    this.discount = DiscountType.normal,
    required this.discountEndTime,
    required this.downloadUrl,
    this.description,
    required this.seeders,
    required this.leechers,
    required this.sizeBytes,
    required this.createdDate,
    required this.imageList,
    required this.cover,
    this.downloadStatus = DownloadStatus.none,
    this.collection = false,
    this.doubanRating = 'N/A',
    this.imdbRating = 'N/A',
    this.isTop = false,
    this.tags = const [],
    this.comments = 0,
  });

  TorrentItem copyWith({
    String? id,
    String? name,
    String? smallDescr,
    DiscountType? discount,
    DateTime? discountEndTime,
    String? downloadUrl,
    String? description,
    int? seeders,
    int? leechers,
    int? sizeBytes,
    List<String>? imageList,
    String? cover,
    DownloadStatus? downloadStatus,
    bool? collection,
    DateTime? createdDate,
    bool? isTop,
    List<TagType>? tags,
    int? comments,
  }) {
    return TorrentItem(
      id: id ?? this.id,
      name: name ?? this.name,
      smallDescr: smallDescr ?? this.smallDescr,
      discount: discount ?? this.discount,
      discountEndTime: discountEndTime ?? this.discountEndTime,
      downloadUrl: downloadUrl ?? this.downloadUrl,
      description: description ?? this.description,
      seeders: seeders ?? this.seeders,
      leechers: leechers ?? this.leechers,
      sizeBytes: sizeBytes ?? this.sizeBytes,
      imageList: imageList ?? this.imageList,
      cover: cover ?? this.cover,
      downloadStatus: downloadStatus ?? this.downloadStatus,
      collection: collection ?? this.collection,
      createdDate: createdDate ?? this.createdDate,
      isTop: isTop ?? this.isTop,
      tags: tags ?? this.tags,
      comments: comments ?? this.comments,
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
  twoX50Percent('2x50%'),
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
      case DiscountType.twoX50Percent:
        return '2x50%';
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
      case DiscountType.twoX50Percent:
        return DiscountColorType.yellow;
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
enum DiscountColorType { none, green, yellow }

// 标签类型枚举
enum TagType {
  hot('HOT', Color.fromARGB(255, 255, 128, 59), ''),
  official('官方', Color.fromARGB(255, 76, 130, 175), ''),
  chinese('中字', Colors.green, 'chinese_simplified'),
  chineseTraditional('繁体', Colors.green, 'chinese_traditional'),
  mandarin('国语', Colors.blue, ''),
  diy('DIY', Colors.brown, ''),
  complete('完结', Color.fromARGB(255, 110, 8, 206), r'\b完结\b|全[^\s]+集'),
  zero('零魔',Color.fromARGB(159, 4, 164, 239),''),
  ep(
    '分集',
    Color.fromARGB(255, 110, 8, 206),
    r'\bEP\d*\b|S\d+E\d+|E\d+\-E\d+|第[^\s]+集',
  ),
  fourK('4K', Colors.orange, r'\b4K\b|\b2160p\b'),
  resolution1080('1080p', Colors.blue, r'\b1080p\b|x1080'),
  hdr('HDR', Colors.purple, r'\bHDR\b|\bHDR10\b'),
  h265(
    'H265',
    Color.fromARGB(255, 51, 162, 217),
    r'\bH\.?265\b|\bHEVC\b|\bx265\b',
  ),
  webDl(
    'WEB-DL',
    Color.fromARGB(255, 162, 41, 178),
    r'\bWEB-DL\b|\bWEBDL\b|\bWEB\.DL\b',
  ),
  dovi('DOVI', Colors.pink, r'\bDOVI\b|Dolby Vision|\bDV\b|杜比(视界)*'),
  blueRay('Blu-ray', Colors.red, r'\bblu-ray\b|\bbluray\b');


  const TagType(this.content, this.color, this.regex);
  final String content;
  final Color color;
  final String regex;

  // 从字符串中匹配所有标签
  static List<TagType> matchTags(String text) {
    List<TagType> matchedTags = [];
    for (TagType tag in TagType.values) {
      if (tag.regex.isEmpty) continue;
      RegExp regExp = RegExp(tag.regex, caseSensitive: false);
      if (regExp.hasMatch(text)) {
        matchedTags.add(tag);
      }
    }
    return matchedTags;
  }

  // 序列化为 JSON
  Map<String, dynamic> toJson() => {
    'name': name,
    'content': content,
  };
}

// 网站类型枚举
enum SiteType {
  mteam('M-Team', 'M-Team', 'API Key (x-api-key)', '从 控制台-实验室-存储令牌 获取并粘贴此处'),
  nexusphp(
    'NexusPHP',
    'NexusPHP(api)',
    'API Key (访问令牌)',
    '控制面板-设定首页-访问令牌（权限都勾上）',
  ),
  nexusphpweb('NexusPHPWeb', 'NexusPHP(web)', 'Cookie认证', '通过网页登录获取认证信息'),
  rousi(
    'RousiPro',
    'Rousi pro',
    'paaskey认证',
    '可以在网站的「账户设置」页面查看和重置自己的 Passkey。',
  ),
  gazelle('Gazelle', 'Gazelle (Alpha)', 'Cookie认证', '通过网页登录获取认证信息'),
  unit3d('Unit3D', 'Unit3D (beta)', 'API Key', '安全设置 - API Token')
  ;

  const SiteType(this.id, this.displayName, this.apiKeyLabel, this.apiKeyHint);
  final String id;
  final String displayName;
  final String apiKeyLabel;
  final String apiKeyHint;

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
  final bool showCover; // 列表显示封面与评分
  final bool supportCommentDetail; // 支持评论详情
  final bool nativeDetail; // 是否提取DOM原生渲染详情（而非WebView）

  const SiteFeatures({
    this.supportMemberProfile = true,
    this.supportTorrentSearch = true,
    this.supportTorrentDetail = true,
    this.supportDownload = true,
    this.supportCollection = true,
    this.supportHistory = true,
    this.supportCategories = true,
    this.supportAdvancedSearch = true,
    this.showCover = true,
    this.supportCommentDetail = false,
    this.nativeDetail = false,
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
    bool? showCover,
    bool? supportCommentDetail,
    bool? nativeDetail,
  }) => SiteFeatures(
    supportMemberProfile: supportMemberProfile ?? this.supportMemberProfile,
    supportTorrentSearch: supportTorrentSearch ?? this.supportTorrentSearch,
    supportTorrentDetail: supportTorrentDetail ?? this.supportTorrentDetail,
    supportDownload: supportDownload ?? this.supportDownload,
    supportCollection: supportCollection ?? this.supportCollection,
    supportHistory: supportHistory ?? this.supportHistory,
    supportCategories: supportCategories ?? this.supportCategories,
    supportAdvancedSearch: supportAdvancedSearch ?? this.supportAdvancedSearch,
    showCover: showCover ?? this.showCover,
    supportCommentDetail: supportCommentDetail ?? this.supportCommentDetail,
    nativeDetail: nativeDetail ?? this.nativeDetail,
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
    'showCover': showCover,
    'supportCommentDetail': supportCommentDetail,
    'nativeDetail': nativeDetail,
  };

  factory SiteFeatures.fromJson(Map<String, dynamic> json) => SiteFeatures(
    supportMemberProfile:
        json['userProfile'] ?? json['supportMemberProfile'] as bool? ?? true,
    supportTorrentSearch:
        json['torrentSearch'] ?? json['supportTorrentSearch'] as bool? ?? true,
    supportTorrentDetail:
        json['torrentDetail'] ?? json['supportTorrentDetail'] as bool? ?? true,
    supportDownload:
        json['download'] ?? json['supportDownload'] as bool? ?? true,
    supportCollection:
        json['favorites'] ?? json['supportCollection'] as bool? ?? true,
    supportHistory:
        json['downloadHistory'] ?? json['supportHistory'] as bool? ?? true,
    supportCategories:
        json['categorySearch'] ?? json['supportCategories'] as bool? ?? true,
    supportAdvancedSearch:
        json['advancedSearch'] ??
        json['supportAdvancedSearch'] as bool? ??
        true,
    showCover: json['showCover'] as bool? ?? true,
    supportCommentDetail:
        json['commentDetail'] ?? json['supportCommentDetail'] as bool? ?? false,
    nativeDetail: json['nativeDetail'] as bool? ?? false,
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
    showCover: true,
    supportCommentDetail: true,
  );

  @override
  String toString() => jsonEncode(toJson());
}

// 站点搜索项目
class SiteSearchItem {
  final String id; // 站点ID
  final Map<String, dynamic>? additionalParams; // 额外参数

  const SiteSearchItem({required this.id, this.additionalParams});

  SiteSearchItem copyWith({
    String? id,
    Map<String, dynamic>? additionalParams,
  }) => SiteSearchItem(
    id: id ?? this.id,
    additionalParams: additionalParams ?? this.additionalParams,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'additionalParams': additionalParams,
  };

  factory SiteSearchItem.fromJson(Map<String, dynamic> json) => SiteSearchItem(
    id: json['id'] as String,
    additionalParams: json['additionalParams'] as Map<String, dynamic>?,
  );

  @override
  String toString() => jsonEncode(toJson());

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SiteSearchItem &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}

// 聚合搜索配置
class AggregateSearchConfig {
  final String id; // 唯一标识符
  final String name; // 配置名称
  final String type; // 配置类型：'all' 表示所有站点，'custom' 表示自定义
  final List<SiteSearchItem> enabledSites; // 启用的站点列表（type为'all'时忽略）
  final bool isActive; // 是否激活

  const AggregateSearchConfig({
    required this.id,
    required this.name,
    this.type = 'custom',
    this.enabledSites = const [],
    this.isActive = true,
  });

  AggregateSearchConfig copyWith({
    String? id,
    String? name,
    String? type,
    List<SiteSearchItem>? enabledSites,
    bool? isActive,
  }) => AggregateSearchConfig(
    id: id ?? this.id,
    name: name ?? this.name,
    type: type ?? this.type,
    enabledSites: enabledSites ?? this.enabledSites,
    isActive: isActive ?? this.isActive,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'type': type,
    'enabledSites': enabledSites.map((site) => site.toJson()).toList(),
    'isActive': isActive,
  };

  factory AggregateSearchConfig.fromJson(Map<String, dynamic> json) {
    List<SiteSearchItem> enabledSites = [];

    // 兼容新格式：enabledSites
    if (json['enabledSites'] != null) {
      enabledSites = (json['enabledSites'] as List<dynamic>)
          .map((item) => SiteSearchItem.fromJson(item as Map<String, dynamic>))
          .toList();
    }

    return AggregateSearchConfig(
      id:
          json['id'] as String? ??
          'legacy-${DateTime.now().millisecondsSinceEpoch}',
      name: json['name'] as String,
      type: json['type'] as String? ?? 'custom', // 兼容旧版本
      enabledSites: enabledSites,
      isActive: json['isActive'] as bool? ?? true,
    );
  }

  @override
  String toString() => jsonEncode(toJson());

  // 创建默认的"所有站点"配置
  static AggregateSearchConfig createDefaultConfig(List<String> allSiteIds) {
    return AggregateSearchConfig(
      id: 'all-sites',
      name: '所有',
      type: 'all',
      enabledSites: [], // all类型不需要具体的站点列表
      isActive: true,
    );
  }

  // 判断是否为"所有站点"类型
  bool get isAllSitesType => type == 'all';

  // 判断是否可以编辑或删除
  bool get canEdit => type != 'all'; // 允许编辑所有配置，包括"所有站点"配置

  // 判断是否可以删除
  bool get canDelete => type != 'all';

  // 获取实际启用的站点ID列表
  List<String> getEnabledSiteIds(List<String> allSiteIds) {
    if (type == 'all') {
      return allSiteIds; // 返回所有站点
    }
    return enabledSites.map((site) => site.id).toList(); // 返回自定义列表的ID
  }

  // 获取启用的站点对象列表
  List<SiteSearchItem> getEnabledSites(List<String> allSiteIds) {
    if (type == 'all') {
      // 对于"所有站点"配置，需要合并已配置的站点参数和所有可用站点
      final Map<String, SiteSearchItem> configuredSites = {};
      for (final site in enabledSites) {
        configuredSites[site.id] = site;
      }

      return allSiteIds.map((id) {
        // 如果该站点已有配置（包含分类等参数），使用已配置的版本
        if (configuredSites.containsKey(id)) {
          return configuredSites[id]!;
        }
        // 否则创建默认的站点项
        return SiteSearchItem(id: id);
      }).toList();
    }
    return enabledSites; // 返回自定义列表
  }
}

// 聚合搜索设置
class AggregateSearchSettings {
  final List<AggregateSearchConfig> searchConfigs; // 搜索配置列表
  final int searchThreads; // 搜索线程数

  const AggregateSearchSettings({
    this.searchConfigs = const [],
    this.searchThreads = 3,
  });

  AggregateSearchSettings copyWith({
    List<AggregateSearchConfig>? searchConfigs,
    int? searchThreads,
  }) => AggregateSearchSettings(
    searchConfigs: searchConfigs ?? this.searchConfigs,
    searchThreads: searchThreads ?? this.searchThreads,
  );

  Map<String, dynamic> toJson() => {
    'searchConfigs': searchConfigs.map((e) => e.toJson()).toList(),
    'searchThreads': searchThreads,
  };

  factory AggregateSearchSettings.fromJson(Map<String, dynamic> json) {
    List<AggregateSearchConfig> configs = [];
    if (json['searchConfigs'] != null) {
      try {
        final list = (json['searchConfigs'] as List)
            .cast<Map<String, dynamic>>();
        configs = list.map(AggregateSearchConfig.fromJson).toList();
      } catch (_) {
        // 解析失败时使用空列表
        configs = [];
      }
    }

    return AggregateSearchSettings(
      searchConfigs: configs,
      searchThreads: json['searchThreads'] as int? ?? 3,
    );
  }

  @override
  String toString() => jsonEncode(toJson());
}

/// 站点配置加载结果
class SiteConfigLoadResult {
  final SiteConfig config;
  final bool needsUpdate; // 是否需要更新持久化数据

  const SiteConfigLoadResult({required this.config, required this.needsUpdate});
}

class SiteConfig {
  final String id; // 唯一标识符
  final String name;
  final String baseUrl; // e.g. https://kp.m-team.cc/
  final String? apiKey; // x-api-key
  final String? passKey; // NexusPHP类型网站的passKey
  final String? authKey; // Gazelle类型网站的authKey
  final String? cookie; // NexusPHPWeb类型网站的登录cookie
  final String? userId; // 用户ID，从fetchMemberProfile获取
  final SiteType siteType; // 网站类型
  final bool isActive; // 是否激活
  final List<SearchCategoryConfig> searchCategories; // 查询分类配置
  final SiteFeatures features; // 功能支持配置
  final String templateId; // 模板ID，记录创建时的模板，自定义为-1
  final int? siteColor; // 站点颜色（ARGB int），可选，缺失时使用哈希色

  const SiteConfig({
    required this.id,
    required this.name,
    required this.baseUrl,
    this.apiKey,
    this.passKey,
    this.authKey,
    this.cookie,
    this.userId,
    this.siteType = SiteType.mteam,
    this.isActive = true,
    this.searchCategories = const [],
    this.features = SiteFeatures.mteamDefault,
    this.templateId = '',
    this.siteColor,
  });

  SiteConfig copyWith({
    String? id,
    String? name,
    String? baseUrl,
    String? apiKey,
    String? passKey,
    String? authKey,
    String? cookie,
    String? userId,
    SiteType? siteType,
    bool? isActive,
    List<SearchCategoryConfig>? searchCategories,
    SiteFeatures? features,
    String? templateId,
    int? siteColor,
  }) => SiteConfig(
    id: id ?? this.id,
    name: name ?? this.name,
    baseUrl: baseUrl ?? this.baseUrl,
    apiKey: apiKey ?? this.apiKey,
    passKey: passKey ?? this.passKey,
    authKey: authKey ?? this.authKey,
    cookie: cookie ?? this.cookie,
    userId: userId ?? this.userId,
    siteType: siteType ?? this.siteType,
    isActive: isActive ?? this.isActive,
    searchCategories: searchCategories ?? this.searchCategories,
    features: features ?? this.features,
    templateId: templateId ?? this.templateId,
    siteColor: siteColor ?? this.siteColor,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'baseUrl': baseUrl,
    'apiKey': apiKey,
    'passKey': passKey,
    'authKey': authKey,
    'cookie': cookie,
    'userId': userId,
    'siteType': siteType.id,
    'isActive': isActive,
    'searchCategories': searchCategories.map((e) => e.toJson()).toList(),
    'features': features.toJson(),
    'templateId': templateId,
    'siteColor': siteColor,
  };

  factory SiteConfig.fromJson(Map<String, dynamic> json) {
    List<SearchCategoryConfig> categories = [];
    if (json['searchCategories'] != null) {
      try {
        final list = (json['searchCategories'] as List)
            .cast<Map<String, dynamic>>();
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
        features = SiteFeatures.fromJson(
          json['features'] as Map<String, dynamic>,
        );
      } catch (_) {
        // 解析失败时使用默认配置
        features = SiteFeatures.mteamDefault;
      }
    }

    // 处理 templateId 字段的兼容性
    String templateId = json['templateId'] as String? ?? '';
    if (templateId.isEmpty) {
      // 如果没有 templateId，根据 baseUrl 匹配预设站点
      final baseUrl = json['baseUrl'] as String;
      templateId = SiteConfig._getTemplateIdByBaseUrl(baseUrl);
    }

    // 兼容解析站点颜色：支持 int 或字符串 #RRGGBB/#AARRGGBB
    int? siteColor;
    try {
      final colorJson = json['siteColor'];
      if (colorJson is int) {
        siteColor = colorJson;
      } else if (colorJson is String) {
        final v = colorJson.trim();
        if (v.startsWith('#')) {
          final hex = v.substring(1);
          final parsed = int.parse(
            hex.length == 6 ? 'FF$hex' : hex,
            radix: 16,
          );
          siteColor = parsed;
        }
      }
    } catch (_) {}

    return SiteConfig(
      id:
          json['id'] as String? ??
          'legacy-${DateTime.now().millisecondsSinceEpoch}',
      name: json['name'] as String,
      baseUrl: json['baseUrl'] as String,
      apiKey: json['apiKey'] as String?,
      passKey: json['passKey'] as String?,
      authKey: json['authKey'] as String?,
      cookie: json['cookie'] as String?,
      userId: json['userId'] as String?,
      siteType: SiteType.values.firstWhere(
        (type) => type.id == (json['siteType'] as String? ?? 'M-Team'),
        orElse: () => SiteType.mteam,
      ),
      isActive: json['isActive'] as bool? ?? true,
      searchCategories: categories,
      features: features,
      templateId: templateId,
      siteColor: siteColor,
    );
  }

  /// 异步版本的fromJson方法，使用配置文件中的URL映射
  static Future<SiteConfigLoadResult> fromJsonAsync(
    Map<String, dynamic> json,
  ) async {
    final swTotal = Stopwatch()..start();
    List<SearchCategoryConfig> categories = [];
    if (json['searchCategories'] != null) {
      try {
        final list = (json['searchCategories'] as List)
            .cast<Map<String, dynamic>>();
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
        features = SiteFeatures.fromJson(
          json['features'] as Map<String, dynamic>,
        );
      } catch (_) {
        // 解析失败时使用默认配置
        features = SiteFeatures.mteamDefault;
      }
    }

    // 处理 templateId 字段的兼容性（异步版本）
    String templateId = json['templateId'] as String? ?? '';
    bool needsUpdate = false;

    if (templateId.isEmpty || templateId == '-1') {
      // 如果没有 templateId，根据 baseUrl 匹配预设站点（使用异步方法）
      final baseUrl = json['baseUrl'] as String;
      final swMap = Stopwatch()..start();
      templateId = await SiteConfig.getTemplateIdByBaseUrlAsync(baseUrl);
      swMap.stop();
      if (kDebugMode) {
        _logger.d(
          'SiteConfig.fromJsonAsync: URL映射耗时=${swMap.elapsedMilliseconds}ms，baseUrl=$baseUrl，templateId=$templateId',
        );
      }
      // 如果成功获取到了有效的templateId，标记需要更新持久化数据
      needsUpdate = templateId.isNotEmpty && templateId != '-1';
    } else {
      // 校验 templateId 的合法性：检查是否存在对应的模板配置
      try {
        final swValidate = Stopwatch()..start();
        final templates = await SiteConfigService.loadPresetSiteTemplates();
        final templateExists = templates.any(
          (template) => template.id == templateId,
        );
        swValidate.stop();

        if (!templateExists) {
          // 如果找不到对应的模板配置，重新通过 baseUrl 匹配
          if (kDebugMode) {
            _logger.w(
              'SiteConfig.fromJsonAsync: templateId=$templateId 无效(校验耗时=${swValidate.elapsedMilliseconds}ms)，尝试重新匹配',
            );
          }
          final baseUrl = json['baseUrl'] as String;
          final swRemap = Stopwatch()..start();
          final newTemplateId = await SiteConfig.getTemplateIdByBaseUrlAsync(
            baseUrl,
          );
          swRemap.stop();
          if (kDebugMode) {
            _logger.d(
              'SiteConfig.fromJsonAsync: 重新映射耗时=${swRemap.elapsedMilliseconds}ms，baseUrl=$baseUrl，旧templateId=$templateId，新templateId=$newTemplateId',
            );
          }
          // 如果成功获取到了有效的templateId，更新并标记需要持久化
          if (newTemplateId.isNotEmpty && newTemplateId != '-1') {
            templateId = newTemplateId;
            needsUpdate = true;
          }
        } else {
          if (kDebugMode) {
            _logger.d(
              'SiteConfig.fromJsonAsync: templateId=$templateId 有效(校验耗时=${swValidate.elapsedMilliseconds}ms)',
            );
          }
        }
      } catch (e) {
        // 校验失败时记录错误但不影响流程，保留原 templateId
        if (kDebugMode) {
          _logger.e('SiteConfig.fromJsonAsync: templateId校验失败: $e');
        }
      }
    }
    // 迁移老馒头数据
    if (templateId == 'mteam-api') {
      // 如果没有 templateId，根据 baseUrl 匹配预设站点（使用异步方法）
      templateId = 'mteam';
      // 如果成功获取到了有效的templateId，标记需要更新持久化数据
      needsUpdate = true;
    }
    // 兼容解析站点颜色：支持 int 或字符串 #RRGGBB/#AARRGGBB
    int? siteColor;
    try {
      final colorJson = json['siteColor'];
      if (colorJson is int) {
        siteColor = colorJson;
      } else if (colorJson is String) {
        final v = colorJson.trim();
        if (v.startsWith('#')) {
          final hex = v.substring(1);
          final parsed = int.parse(
            hex.length == 6 ? 'FF$hex' : hex,
            radix: 16,
          );
          siteColor = parsed;
        }
      }
    } catch (_) {}

    final config = SiteConfig(
      id:
          json['id'] as String? ??
          'legacy-${DateTime.now().millisecondsSinceEpoch}',
      name: json['name'] as String,
      baseUrl: json['baseUrl'] as String,
      apiKey: json['apiKey'] as String?,
      passKey: json['passKey'] as String?,
      authKey: json['authKey'] as String?,
      cookie: json['cookie'] as String?,
      userId: json['userId'] as String?,
      siteType: SiteType.values.firstWhere(
        (type) => type.id == (json['siteType'] as String? ?? 'M-Team'),
        orElse: () => SiteType.mteam,
      ),
      isActive: json['isActive'] as bool? ?? true,
      searchCategories: categories,
      features: features,
      templateId: templateId,
      siteColor: siteColor,
    );

    final result = SiteConfigLoadResult(
      config: config,
      needsUpdate: needsUpdate,
    );
    swTotal.stop();
    if (kDebugMode) {
      _logger.d(
        'SiteConfig.fromJsonAsync: 总耗时=${swTotal.elapsedMilliseconds}ms，siteId=${config.id}',
      );
    }
    return result;
  }

  /// 根据 baseUrl 匹配预设站点的模板ID
  static String _getTemplateIdByBaseUrl(String baseUrl) {
    // 标准化 baseUrl，移除末尾的斜杠
    final normalizedBaseUrl = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;

    // 注意：这个方法保留硬编码映射作为后备方案
    // 主要的URL映射现在从配置文件中读取，请使用 getTemplateIdByBaseUrlAsync 方法

    // 兼容性映射（后备方案）
    final Map<String, String> fallbackMapping = {
      'https://api.m-team.cc': 'mteam',
      'https://www.ptskit.org': 'ptskit',
      'https://www.hxpt.org': 'hxpt',
      'https://zmpt.cc': 'zmpt',
      'https://www.afun.tv': 'afun',
      'https://cangbao.tv': 'cangbao',
      'https://lajidui.org': 'lajidui',
      'https://ptfans.org': 'ptfans',
      'https://xingyunge.org': 'xingyunge',
    };

    return fallbackMapping[normalizedBaseUrl] ?? '-1';
  }

  /// 异步方法：根据 baseUrl 匹配预设站点的模板ID（从配置文件读取）
  static Future<String> getTemplateIdByBaseUrlAsync(String baseUrl) async {
    // 标准化 baseUrl，移除末尾的斜杠
    final normalizedBaseUrl = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;

    // 优先使用快速映射（同步后备方案），避免首帧阻塞读取资产
    final quick = _getTemplateIdByBaseUrl(normalizedBaseUrl);
    if (quick != '-1') {
      return quick;
    }

    // 若快速映射未命中，再尝试从配置文件读取（可能涉及IO，但只在必要时发生）
    try {
      final urlMapping = await SiteConfigService.getUrlToTemplateIdMapping();
      final templateId = urlMapping[normalizedBaseUrl];
      if (templateId != null) {
        return templateId;
      }
    } catch (e) {
      // 读取失败则继续使用后备方案
    }

    // 最终后备：仍未命中则返回同步方法的结果（可能为'-1'）
    return '-1';
  }

  @override
  String toString() => jsonEncode(toJson());
}

/// 站点配置模板类
/// 用于配置文件中的站点模板，支持多个URL
class SiteConfigTemplate {
  final String id; // 唯一标识符
  final String name; // 站点名称
  final bool isShow; // 是否在下拉列表中显示，默认为 true
  final List<String> baseUrls; // 支持多个URL地址
  final String? primaryUrl; // 主要URL（可选，用于标识默认选择）
  final SiteType siteType; // 网站类型
  final List<SearchCategoryConfig> searchCategories; // 查询分类配置
  final SiteFeatures features; // 功能支持配置
  final Map<String, String> discountMapping; // 优惠映射配置
  final Map<String, String> tagMapping; // 标签映射配置
  final Map<String, dynamic>? infoFinder; // 信息提取器配置
  final Map<String, dynamic>? request; // 请求配置
  final String? logo; // 可选的 logo 资源路径（assets/sites_icon/...）

  const SiteConfigTemplate({
    required this.id,
    required this.name,
    this.isShow = true,
    required this.baseUrls,
    this.primaryUrl,
    this.siteType = SiteType.mteam,
    this.searchCategories = const [],
    this.features = SiteFeatures.mteamDefault,
    this.discountMapping = const {},
    this.tagMapping = const {},
    this.infoFinder,
    this.request,
    this.logo,
  });

  SiteConfigTemplate copyWith({
    String? id,
    String? name,
    bool? isShow,
    List<String>? baseUrls,
    String? primaryUrl,
    SiteType? siteType,
    List<SearchCategoryConfig>? searchCategories,
    SiteFeatures? features,
    Map<String, String>? discountMapping,
    Map<String, String>? tagMapping,
    Map<String, dynamic>? infoFinder,
    Map<String, dynamic>? request,
    String? logo,
  }) => SiteConfigTemplate(
    id: id ?? this.id,
    name: name ?? this.name,
    isShow: isShow ?? this.isShow,
    baseUrls: baseUrls ?? this.baseUrls,
    primaryUrl: primaryUrl ?? this.primaryUrl,
    siteType: siteType ?? this.siteType,
    searchCategories: searchCategories ?? this.searchCategories,
    features: features ?? this.features,
    discountMapping: discountMapping ?? this.discountMapping,
    tagMapping: tagMapping ?? this.tagMapping,
    infoFinder: infoFinder ?? this.infoFinder,
    request: request ?? this.request,
    logo: logo ?? this.logo,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'isShow': isShow,
    'baseUrls': baseUrls,
    'primaryUrl': primaryUrl,
    'siteType': siteType.id,
    'searchCategories': searchCategories.map((e) => e.toJson()).toList(),
    'features': features.toJson(),
    'discountMapping': discountMapping,
    'tagMapping': tagMapping,
    'infoFinder': infoFinder,
    'request': request,
    if (logo != null) 'logo': logo,
  };

  factory SiteConfigTemplate.fromJson(Map<String, dynamic> json) {
    List<SearchCategoryConfig> categories = [];
    if (json['searchCategories'] != null) {
      try {
        final list = (json['searchCategories'] as List)
            .cast<Map<String, dynamic>>();
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
        features = SiteFeatures.fromJson(
          json['features'] as Map<String, dynamic>,
        );
      } catch (_) {
        // 解析失败时使用默认配置
        features = SiteFeatures.mteamDefault;
      }
    }

    // 处理baseUrls字段，支持向前兼容
    List<String> baseUrls = [];
    if (json['baseUrls'] != null) {
      // 新格式：多个URL
      baseUrls = (json['baseUrls'] as List).cast<String>();
    } else if (json['baseUrl'] != null) {
      // 旧格式：单个URL，转换为列表
      baseUrls = [json['baseUrl'] as String];
    }

    // 处理优惠映射配置
    Map<String, String> discountMapping = {};
    if (json['discountMapping'] != null) {
      try {
        discountMapping = Map<String, String>.from(
          json['discountMapping'] as Map<String, dynamic>,
        );
      } catch (_) {
        // 解析失败时使用空映射
        discountMapping = {};
      }
    }

    // 处理 infoFinder 配置
    Map<String, dynamic>? infoFinder;
    if (json['infoFinder'] != null) {
      try {
        infoFinder = Map<String, dynamic>.from(
          json['infoFinder'] as Map<String, dynamic>,
        );
      } catch (_) {
        // 解析失败时使用 null
        infoFinder = null;
      }
    }

    return SiteConfigTemplate(
      id: json['id'] as String,
      name: json['name'] as String,
      isShow: json['isShow'] as bool? ?? true,
      baseUrls: baseUrls,
      primaryUrl: json['primaryUrl'] as String?,
      siteType: SiteType.values.firstWhere(
        (type) => type.id == (json['siteType'] as String? ?? 'M-Team'),
        orElse: () => SiteType.mteam,
      ),
      searchCategories: categories,
      features: features,
      discountMapping: discountMapping,
      infoFinder: infoFinder,
      request: json['request'] as Map<String, dynamic>?,
      logo: json['logo'] as String?, // 兼容旧版：没有该字段则为 null
      tagMapping: json['tagMapping'] != null
          ? Map<String, String>.from(json['tagMapping'] as Map<String, dynamic>)
          : const {},
    );
  }

  /// 转换为SiteConfig实例
  /// [selectedUrl] 指定要使用的URL，如果为null则使用primaryUrl或第一个URL
  SiteConfig toSiteConfig({
    String? selectedUrl,
    String? apiKey,
    String? passKey,
    String? cookie,
    String? userId,
    bool isActive = true,
  }) {
    // 确定要使用的URL
    String baseUrl;
    if (selectedUrl != null) {
      baseUrl = selectedUrl;
    } else if (primaryUrl != null && baseUrls.contains(primaryUrl)) {
      baseUrl = primaryUrl!;
    } else if (baseUrls.isNotEmpty) {
      baseUrl = baseUrls.first;
    } else {
      throw ArgumentError('No valid baseUrl available in template');
    }

    return SiteConfig(
      id: id,
      name: name,
      baseUrl: baseUrl,
      apiKey: apiKey,
      passKey: passKey,
      cookie: cookie,
      userId: userId,
      siteType: siteType,
      isActive: isActive,
      searchCategories: searchCategories,
      features: features,
      templateId: id,
    );
  }

  /// 获取主要URL（用于显示）
  String get displayUrl {
    if (primaryUrl != null && baseUrls.contains(primaryUrl)) {
      return primaryUrl!;
    }
    return baseUrls.isNotEmpty ? baseUrls.first : '';
  }

  @override
  String toString() => jsonEncode(toJson());
}

// 查询条件配置
class SearchCategoryConfig {
  final String id; // 唯一标识
  final String displayName; // 显示名称
  final String
  parameters; // 请求参数，格式如：mode:normal 或 mode:normal,teams:["44","9","43"]

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

  factory SearchCategoryConfig.fromJson(Map<String, dynamic> json) =>
      SearchCategoryConfig(
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
        } else if (valueStr.startsWith('"') &&
            valueStr.endsWith('"') &&
            valueStr.length >= 2) {
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
          final intValue = FormatUtil.parseInt(valueStr);
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

/// @deprecated 此类仅用于数据迁移，不应在新代码中使用
/// 请使用 DownloaderConfig 和 QbittorrentConfig 替代
class QbClientConfig {
  final String id; // uuid or custom id
  final String name;
  final String host; // ip or domain
  final int port;
  final String username;
  final String?
  password; // stored securely, may be null when loaded from prefs-only
  final bool useLocalRelay; // 是否启用本地中转，先下载种子文件再提交给qBittorrent
  final String? version; // qBittorrent版本号，用于API兼容性

  const QbClientConfig({
    required this.id,
    required this.name,
    required this.host,
    required this.port,
    required this.username,
    this.password,
    this.useLocalRelay = false, // 默认禁用
    this.version, // 版本号可为空，首次使用时自动获取
  });

  QbClientConfig copyWith({
    String? id,
    String? name,
    String? host,
    int? port,
    String? username,
    String? password,
    bool? useLocalRelay,
    String? version,
  }) => QbClientConfig(
    id: id ?? this.id,
    name: name ?? this.name,
    host: host ?? this.host,
    port: port ?? this.port,
    username: username ?? this.username,
    password: password ?? this.password,
    useLocalRelay: useLocalRelay ?? this.useLocalRelay,
    version: version ?? this.version,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'host': host,
    'port': port,
    'username': username,
    'useLocalRelay': useLocalRelay,
    if (version != null) 'version': version,
    // password intentionally excluded from plain json by default
  };

  factory QbClientConfig.fromJson(Map<String, dynamic> json) => QbClientConfig(
    id: json['id'] as String,
    name: json['name'] as String,
    host: json['host'] as String,
    port: (json['port'] as num).toInt(),
    username: json['username'] as String,
    useLocalRelay: (json['useLocalRelay'] as bool?) ?? false,
    version: json['version'] as String?, // 兼容老数据，可为空
  );
}

// WebDAV同步状态枚举
enum WebDAVSyncStatus {
  idle, // 空闲
  syncing, // 同步中
  uploading, // 上传中
  downloading, // 下载中
  success, // 成功
  error, // 错误
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

// 种子评论
class TorrentComment {
  final String id;
  final DateTime createdDate;
  final DateTime lastModifiedDate;
  final String torrentId;
  final String author;
  final String text;
  final String editedBy;
  final String subject;

  TorrentComment({
    required this.id,
    required this.createdDate,
    required this.lastModifiedDate,
    required this.torrentId,
    required this.author,
    required this.text,
    required this.editedBy,
    required this.subject,
  });

  factory TorrentComment.fromJson(Map<String, dynamic> json) {
    return TorrentComment(
      id: (json['id'] ?? '').toString(),
      createdDate: Formatters.parseDateTimeCustom(
        json['createdDate']?.toString(),
      ),
      lastModifiedDate: Formatters.parseDateTimeCustom(
        json['lastModifiedDate']?.toString(),
      ),
      torrentId: (json['torrent'] ?? '').toString(),
      author: (json['author'] ?? '').toString(),
      text: (json['text'] ?? '').toString(),
      editedBy: (json['editedBy'] ?? '').toString(),
      subject: (json['subject'] ?? '').toString(),
    );
  }
}

// 种子评论列表
class TorrentCommentList {
  final int pageNumber;
  final int pageSize;
  final int total;
  final int totalPages;
  final List<TorrentComment> comments;

  TorrentCommentList({
    required this.pageNumber,
    required this.pageSize,
    required this.total,
    required this.totalPages,
    required this.comments,
  });

  factory TorrentCommentList.fromJson(Map<String, dynamic> json) {
    int parseInt(dynamic v) => FormatUtil.parseInt(v) ?? 0;

    final list = (json['data'] as List? ?? const []).cast<dynamic>();

    return TorrentCommentList(
      pageNumber: parseInt(json['pageNumber']),
      pageSize: parseInt(json['pageSize']),
      total: parseInt(json['total']),
      totalPages: parseInt(json['totalPages']),
      comments: list
          .map((e) => TorrentComment.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}
