// 数据模型定义文件
// 原有的API实现已迁移到各站点适配器中

class MemberProfile {
  final String username;
  final double bonus; // magic points
  final double shareRate;
  final int uploadedBytes;
  final int downloadedBytes;
  final String uploadedBytesString; // 上传量字符串格式，如"1.2 GB"
  final String downloadedBytesString; // 下载量字符串格式，如"500 MB"
  final String? userId; // 用户ID，NexusPHP类型从data.data.id获取

  MemberProfile({
    required this.username,
    required this.bonus,
    required this.shareRate,
    required this.uploadedBytes,
    required this.downloadedBytes,
    required this.uploadedBytesString,
    required this.downloadedBytesString,
    this.userId,
  });

  // fromJson 方法已移至各站点适配器中实现
}

class TorrentDetail {
  final String descr;
  
  TorrentDetail({required this.descr});
  
  // fromJson 方法已移至各站点适配器中实现
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
  final String? downloadUrl; //下载链接，有些网站可以直接通过列表接口获取到
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
    required this.downloadUrl,
    required this.seeders,
    required this.leechers,
    required this.sizeBytes,
    required this.imageList,
    this.downloadStatus = DownloadStatus.none,
    this.collection = false,
  });

  // fromJson 方法已移至各站点适配器中实现
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

  // fromJson 方法已移至各站点适配器中实现
}