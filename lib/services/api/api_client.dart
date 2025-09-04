// 数据模型定义文件
// 原有的API实现已迁移到各站点适配器中

class MemberProfile {
  final String username;
  final double bonus; // magic points
  final double shareRate;
  final int uploadedBytes;
  final int downloadedBytes;

  MemberProfile({
    required this.username,
    required this.bonus,
    required this.shareRate,
    required this.uploadedBytes,
    required this.downloadedBytes,
  });

  factory MemberProfile.fromJson(Map<String, dynamic> json) {
    final mc = json['memberCount'] as Map<String, dynamic>?;
    double parseDouble(dynamic v) => v == null ? 0.0 : double.tryParse(v.toString()) ?? 0.0;
    int parseInt(dynamic v) => v == null ? 0 : int.tryParse(v.toString()) ?? 0;
    return MemberProfile(
      username: (json['username'] ?? '').toString(),
      bonus: parseDouble(mc?['bonus']),
      shareRate: parseDouble(mc?['shareRate']),
      uploadedBytes: parseInt(mc?['uploaded']),
      downloadedBytes: parseInt(mc?['downloaded']),
    );
  }
}

class TorrentDetail {
  final String descr;
  
  TorrentDetail({required this.descr});
  
  factory TorrentDetail.fromJson(Map<String, dynamic> json) {
    return TorrentDetail(
      descr: (json['descr'] ?? '').toString(),
    );
  }
}

enum DownloadStatus {
  none,        // 未下载
  downloading, // 下载中
  completed,   // 已完成
}

class TorrentItem {
  final String id;
  final String name;
  final String smallDescr;
  final String? discount; // e.g., FREE, PERCENT_50
  final String? discountEndTime; // e.g., 2025-08-27 21:16:48
  final int seeders;
  final int leechers;
  final int sizeBytes;
  final List<String> imageList;
  final DownloadStatus downloadStatus;
  final bool collection; // 是否已收藏

  TorrentItem({
    required this.id,
    required this.name,
    required this.smallDescr,
    required this.discount,
    required this.discountEndTime,
    required this.seeders,
    required this.leechers,
    required this.sizeBytes,
    required this.imageList,
    this.downloadStatus = DownloadStatus.none,
    this.collection = false,
  });

  factory TorrentItem.fromJson(Map<String, dynamic> json, {DownloadStatus? downloadStatus}) {
    int parseInt(dynamic v) => v == null ? 0 : int.tryParse(v.toString()) ?? 0;
    bool parseBool(dynamic v) => v == true || v.toString().toLowerCase() == 'true';
    final status = (json['status'] as Map<String, dynamic>?) ?? const {};
    final promotionRule = (status['promotionRule'] as Map<String, dynamic>?) ?? const {};
    final imgs = (json['imageList'] as List?)?.map((e) => e.toString()).toList() ?? const <String>[];
    
    // 优先使用promotionRule中的字段，如果不存在则使用status中的字段
    final discount = promotionRule['discount']?.toString() ?? status['discount']?.toString();
    final discountEndTime = promotionRule['endTime']?.toString() ?? status['discountEndTime']?.toString();
    
    return TorrentItem(
      id: (json['id'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      smallDescr: (json['smallDescr'] ?? '').toString(),
      discount: discount,
      discountEndTime: discountEndTime,
      seeders: parseInt(status['seeders']),
      leechers: parseInt(status['leechers']),
      sizeBytes: parseInt(json['size']),
      imageList: imgs,
      downloadStatus: downloadStatus ?? DownloadStatus.none,
      collection: parseBool(json['collection']),
    );
  }
}

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

  factory TorrentSearchResult.fromJson(Map<String, dynamic> json) {
    int parseInt(dynamic v) => v == null ? 0 : int.tryParse(v.toString()) ?? 0;
    final list = (json['data'] as List? ?? const []).cast<dynamic>();
    return TorrentSearchResult(
      pageNumber: parseInt(json['pageNumber']),
      pageSize: parseInt(json['pageSize']),
      total: parseInt(json['total']),
      totalPages: parseInt(json['totalPages']),
      items: list.map((e) => TorrentItem.fromJson(e as Map<String, dynamic>)).toList(),
    );
  }
}