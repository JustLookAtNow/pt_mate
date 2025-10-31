/// 通用下载器数据模型
/// 
/// 这些模型提供了统一的接口，用于不同下载器实现之间的数据交换
library;

/// 下载器类型枚举
enum DownloaderType {
  qbittorrent('qbittorrent', 'qBittorrent'),
  transmission('transmission', 'Transmission');

  const DownloaderType(this.value, this.displayName);
  
  final String value;
  final String displayName;
  
  static DownloaderType fromString(String value) {
    for (final type in DownloaderType.values) {
      if (type.value == value) {
        return type;
      }
    }
    throw ArgumentError('Unknown downloader type: $value');
  }
}

/// 传输信息
class TransferInfo {
  final int upSpeed;
  final int dlSpeed;
  final int upTotal;
  final int dlTotal;
  
  const TransferInfo({
    required this.upSpeed,
    required this.dlSpeed,
    required this.upTotal,
    required this.dlTotal,
  });
  
  factory TransferInfo.fromJson(Map<String, dynamic> json) {
    return TransferInfo(
      upSpeed: json['upSpeed'] ?? 0,
      dlSpeed: json['dlSpeed'] ?? 0,
      upTotal: json['upTotal'] ?? 0,
      dlTotal: json['dlTotal'] ?? 0,
    );
  }
  
  Map<String, dynamic> toJson() {
    return {
      'upSpeed': upSpeed,
      'dlSpeed': dlSpeed,
      'upTotal': upTotal,
      'dlTotal': dlTotal,
    };
  }
}

/// 服务器状态
class ServerState {
  final int freeSpaceOnDisk;
  
  const ServerState({
    required this.freeSpaceOnDisk,
  });
  
  factory ServerState.fromJson(Map<String, dynamic> json) {
    return ServerState(
      freeSpaceOnDisk: json['freeSpaceOnDisk'] ?? 0,
    );
  }
  
  Map<String, dynamic> toJson() {
    return {
      'freeSpaceOnDisk': freeSpaceOnDisk,
    };
  }
}

/// 下载任务状态
class DownloadTaskState {
  static const String error = 'error';
  static const String missingFiles = 'missingFiles';
  static const String uploading = 'uploading';
  static const String pausedUP = 'pausedUP';
  static const String queuedUP = 'queuedUP';
  static const String stalledUP = 'stalledUP';
  static const String checkingUP = 'checkingUP';
  static const String forcedUP = 'forcedUP';
  static const String allocating = 'allocating';
  static const String downloading = 'downloading';
  static const String metaDL = 'metaDL';
  static const String pausedDL = 'pausedDL';
  static const String queuedDL = 'queuedDL';
  static const String stalledDL = 'stalledDL';
  static const String checkingDL = 'checkingDL';
  static const String forcedDL = 'forcedDL';
  static const String stoppedDL = 'stoppedDL';
  static const String checkingResumeData = 'checkingResumeData';
  static const String moving = 'moving';
  static const String unknown = 'unknown';
  
  static bool isDownloading(String state) {
    return state == downloading || state == forcedDL || 
           state == metaDL || state == stalledDL;
  }
  
  static bool isPaused(String state) {
    return state == pausedDL || state == pausedUP;
  }
}

/// 下载任务
class DownloadTask {
  final String hash;
  final String name;
  final String state;
  final int size;
  final double progress;
  final int dlspeed;
  final int upspeed;
  final int eta;
  final String category;
  final List<String> tags;
  final int completionOn;
  final String contentPath;
  final int addedOn;
  final int amountLeft;
  final double ratio;
  final int timeActive;
  
  const DownloadTask({
    required this.hash,
    required this.name,
    required this.state,
    required this.size,
    required this.progress,
    required this.dlspeed,
    required this.upspeed,
    required this.eta,
    required this.category,
    required this.tags,
    required this.completionOn,
    required this.contentPath,
    required this.addedOn,
    required this.amountLeft,
    required this.ratio,
    required this.timeActive,
  });
  
  factory DownloadTask.fromJson(Map<String, dynamic> json) {
    return DownloadTask(
      hash: json['hash'] ?? '',
      name: json['name'] ?? '',
      state: json['state'] ?? DownloadTaskState.unknown,
      size: json['size'] is int ? json['size'] : int.tryParse('${json['size'] ?? 0}') ?? 0,
      progress: json['progress'] is double ? json['progress'] : double.tryParse('${json['progress'] ?? 0}') ?? 0,
      dlspeed: json['dlspeed'] is int ? json['dlspeed'] : int.tryParse('${json['dlspeed'] ?? 0}') ?? 0,
      upspeed: json['upspeed'] is int ? json['upspeed'] : int.tryParse('${json['upspeed'] ?? 0}') ?? 0,
      eta: json['eta'] is int ? json['eta'] : int.tryParse('${json['eta'] ?? 0}') ?? 0,
      category: json['category'] ?? '',
      tags: json['tags'] is String 
          ? (json['tags'] as String).split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList() 
          : (json['tags'] is List ? (json['tags'] as List).map((e) => e.toString()).toList() : <String>[]),
      completionOn: json['completionOn'] is int ? json['completionOn'] : int.tryParse('${json['completionOn'] ?? 0}') ?? 0,
      contentPath: json['contentPath'] ?? '',
      addedOn: json['addedOn'] is int ? json['addedOn'] : int.tryParse('${json['addedOn'] ?? 0}') ?? 0,
      amountLeft: json['amountLeft'] is int ? json['amountLeft'] : int.tryParse('${json['amountLeft'] ?? 0}') ?? 0,
      ratio: json['ratio'] is double ? json['ratio'] : double.tryParse('${json['ratio'] ?? 0}') ?? 0,
      timeActive: json['timeActive'] is int ? json['timeActive'] : int.tryParse('${json['timeActive'] ?? 0}') ?? 0,
    );
  }
  
  Map<String, dynamic> toJson() {
    return {
      'hash': hash,
      'name': name,
      'state': state,
      'size': size,
      'progress': progress,
      'dlspeed': dlspeed,
      'upspeed': upspeed,
      'eta': eta,
      'category': category,
      'tags': tags,
      'completionOn': completionOn,
      'contentPath': contentPath,
      'addedOn': addedOn,
      'amountLeft': amountLeft,
      'ratio': ratio,
      'timeActive': timeActive,
    };
  }
  
  bool get isDownloading => DownloadTaskState.isDownloading(state);
  bool get isPaused => DownloadTaskState.isPaused(state);
}

/// 添加任务参数
class AddTaskParams {
  final String url;
  final String? category;
  final List<String>? tags;
  final String? savePath;
  final bool? autoTMM;
  /// 是否添加后暂停（不立即开始），默认空表示遵循下载器默认行为
  final bool? startPaused;
  
  const AddTaskParams({
    required this.url,
    this.category,
    this.tags,
    this.savePath,
    this.autoTMM,
    this.startPaused,
  });
  
  factory AddTaskParams.fromJson(Map<String, dynamic> json) {
    return AddTaskParams(
      url: json['url'] ?? '',
      category: json['category'],
      tags: json['tags'] is List ? (json['tags'] as List).map((e) => e.toString()).toList() : null,
      savePath: json['savePath'],
      autoTMM: json['autoTMM'],
      startPaused: json['startPaused'] is bool ? json['startPaused'] : (json['startPaused']?.toString() == 'true' ? true : null),
    );
  }
  
  Map<String, dynamic> toJson() {
    return {
      'url': url,
      if (category != null) 'category': category,
      if (tags != null) 'tags': tags,
      if (savePath != null) 'savePath': savePath,
      if (autoTMM != null) 'autoTMM': autoTMM,
      if (startPaused != null) 'startPaused': startPaused,
    };
  }
}

/// 获取任务列表参数
class GetTasksParams {
  final String? filter;
  final String? category;
  final String? tag;
  final String? sort;
  final bool? reverse;
  final int? limit;
  final int? offset;
  
  const GetTasksParams({
    this.filter,
    this.category,
    this.tag,
    this.sort,
    this.reverse,
    this.limit,
    this.offset,
  });
  
  factory GetTasksParams.fromJson(Map<String, dynamic> json) {
    return GetTasksParams(
      filter: json['filter'],
      category: json['category'],
      tag: json['tag'],
      sort: json['sort'],
      reverse: json['reverse'],
      limit: json['limit'],
      offset: json['offset'],
    );
  }
  
  Map<String, dynamic> toJson() {
    return {
      if (filter != null) 'filter': filter,
      if (category != null) 'category': category,
      if (tag != null) 'tag': tag,
      if (sort != null) 'sort': sort,
      if (reverse != null) 'reverse': reverse,
      if (limit != null) 'limit': limit,
      if (offset != null) 'offset': offset,
    };
  }
}