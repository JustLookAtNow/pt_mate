import 'package:dio/dio.dart';
import 'package:http_parser/http_parser.dart';

import '../../models/app_models.dart';

class QbTransferInfo {
  final int upSpeed;
  final int dlSpeed;
  final int upTotal;
  final int dlTotal;
  const QbTransferInfo({
    required this.upSpeed,
    required this.dlSpeed,
    required this.upTotal,
    required this.dlTotal,
  });
}

class QbServerState {
  final int freeSpaceOnDisk;
  const QbServerState({
    required this.freeSpaceOnDisk,
  });
}

class QbTorrentState {
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

class QbTorrent {
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
  
  const QbTorrent({
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
  
  factory QbTorrent.fromJson(Map<String, dynamic> json) {
    return QbTorrent(
      hash: json['hash'] ?? '',
      name: json['name'] ?? '',
      state: json['state'] ?? QbTorrentState.unknown,
      size: json['size'] is int ? json['size'] : int.tryParse('${json['size'] ?? 0}') ?? 0,
      progress: json['progress'] is double ? json['progress'] : double.tryParse('${json['progress'] ?? 0}') ?? 0,
      dlspeed: json['dlspeed'] is int ? json['dlspeed'] : int.tryParse('${json['dlspeed'] ?? 0}') ?? 0,
      upspeed: json['upspeed'] is int ? json['upspeed'] : int.tryParse('${json['upspeed'] ?? 0}') ?? 0,
      eta: json['eta'] is int ? json['eta'] : int.tryParse('${json['eta'] ?? 0}') ?? 0,
      category: json['category'] ?? '',
      tags: json['tags'] is String 
          ? (json['tags'] as String).split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList() 
          : <String>[],
      completionOn: json['completion_on'] is int ? json['completion_on'] : int.tryParse('${json['completion_on'] ?? 0}') ?? 0,
      contentPath: json['content_path'] ?? '',
      addedOn: json['added_on'] is int ? json['added_on'] : int.tryParse('${json['added_on'] ?? 0}') ?? 0,
      amountLeft: json['amount_left'] is int ? json['amount_left'] : int.tryParse('${json['amount_left'] ?? 0}') ?? 0,
      ratio: json['ratio'] is double ? json['ratio'] : double.tryParse('${json['ratio'] ?? 0}') ?? 0,
      timeActive: json['time_active'] is int ? json['time_active'] : int.tryParse('${json['time_active'] ?? 0}') ?? 0,
    );
  }
  
  bool get isDownloading => QbTorrentState.isDownloading(state);
  bool get isPaused => QbTorrentState.isPaused(state);
}

class QbService {
  QbService._();
  static final QbService instance = QbService._();

  // Cookie 缓存相关字段
  String? _cachedCookie;
  QbClientConfig? _cachedConfig;
  String? _cachedPassword;
  DateTime? _lastLoginTime;

  // Cookie 有效期（默认30分钟）
  static const Duration _cookieValidDuration = Duration(minutes: 30);

  String _buildBase(QbClientConfig c) {
    var h = c.host.trim();
    if (h.endsWith('/')) h = h.substring(0, h.length - 1);
    final hasScheme = h.startsWith('http://') || h.startsWith('https://');
    if (!hasScheme) {
      return 'http://$h:${c.port}';
    }
    try {
      final u = Uri.parse(h);
      if (u.hasPort) return h;
      return '$h:${c.port}';
    } catch (_) {
      return h;
    }
  }

  Dio _createDio(String base) {
    return Dio(
      BaseOptions(
        baseUrl: base,
        connectTimeout: const Duration(seconds: 8),
        receiveTimeout: const Duration(seconds: 12),
        sendTimeout: const Duration(seconds: 12),
        headers: {'User-Agent': 'MTeamApp/1.0 (Flutter; Dio)'},
        validateStatus: (code) => code != null && code >= 200 && code < 500,
      ),
    );
  }

  /// 清除缓存的 cookie
  void clearCache() {
    _cachedCookie = null;
    _cachedConfig = null;
    _cachedPassword = null;
    _lastLoginTime = null;
  }

  /// 检查缓存的 cookie 是否有效
  bool _isCacheValid(QbClientConfig config, String password) {
    if (_cachedCookie == null || 
        _cachedConfig == null || 
        _cachedPassword == null || 
        _lastLoginTime == null) {
      return false;
    }
    
    // 检查配置是否相同
    if (_cachedConfig!.host != config.host ||
        _cachedConfig!.port != config.port ||
        _cachedConfig!.username != config.username ||
        _cachedPassword != password) {
      return false;
    }
    
    // 检查时间是否过期
    final now = DateTime.now();
    if (now.difference(_lastLoginTime!) > _cookieValidDuration) {
      return false;
    }
    
    return true;
  }

  /// 获取有效的 cookie，如果缓存无效则重新登录
  Future<String> _getValidCookie(QbClientConfig config, String password) async {
    if (_isCacheValid(config, password)) {
      return _cachedCookie!;
    }
    
    // 缓存无效，重新登录
    final cookie = await _loginAndGetCookie(config, password);
    
    // 更新缓存
    _cachedCookie = cookie;
    _cachedConfig = config;
    _cachedPassword = password;
    _lastLoginTime = DateTime.now();
    
    return cookie;
  }

  /// 执行需要认证的 API 请求，自动处理 cookie 失效重试
  Future<Response<T>> _executeAuthenticatedRequest<T>(
    QbClientConfig config,
    String password,
    Future<Response<T>> Function(String cookie) request,
  ) async {
    try {
      final cookie = await _getValidCookie(config, password);
      return await request(cookie);
    } catch (e) {
      // 如果请求失败，可能是 cookie 失效，清除缓存并重试一次
      if (e is DioException && e.response?.statusCode == 403) {
        clearCache();
        final cookie = await _getValidCookie(config, password);
        return await request(cookie);
      }
      rethrow;
    }
  }

  Future<void> testConnection({
    required QbClientConfig config,
    required String password,
  }) async {
    final base = _buildBase(config);
    final dio = _createDio(base);
    try {
      final res = await dio.post(
        '/api/v2/auth/login',
        data: {'username': config.username, 'password': password},
        options: Options(
          contentType: Headers.formUrlEncodedContentType,
          followRedirects: false,
        ),
      );
      final sc = res.statusCode ?? 0;
      final body = (res.data ?? '').toString().toLowerCase();
      if (sc != 200 || !body.contains('ok')) {
        throw Exception('登录失败（HTTP $sc）');
      }
      // 可选：登录成功即可视为连通
    } on DioException catch (e) {
      final msg = e.response != null
          ? 'HTTP ${e.response?.statusCode}: ${e.response?.statusMessage ?? ''}'
          : (e.message ?? '网络错误');
      throw Exception('连接失败：$msg');
    }
  }

  Future<String> _loginAndGetCookie(
    QbClientConfig config,
    String password,
  ) async {
    final base = _buildBase(config);
    final dio = _createDio(base);
    final res = await dio.post(
      '/api/v2/auth/login',
      data: {'username': config.username, 'password': password},
      options: Options(
        contentType: Headers.formUrlEncodedContentType,
        followRedirects: false,
      ),
    );
    final sc = res.statusCode ?? 0;
    final body = (res.data ?? '').toString().toLowerCase();
    if (sc != 200 || !body.contains('ok')) {
      throw Exception('登录失败（HTTP $sc）');
    }
    final setCookie = res.headers.map['set-cookie']?.join('; ') ?? '';
    return setCookie;
  }

  Future<QbTransferInfo> fetchTransferInfo({
    required QbClientConfig config,
    required String password,
  }) async {
    final base = _buildBase(config);
    final dio = _createDio(base);
    
    final res = await _executeAuthenticatedRequest<Map<String, dynamic>>(
      config,
      password,
      (cookie) => dio.get(
        '/api/v2/transfer/info',
        options: Options(headers: cookie.isNotEmpty ? {'Cookie': cookie} : null),
      ),
    );
    
    if ((res.statusCode ?? 0) != 200) {
      throw Exception('获取传输信息失败（HTTP ${res.statusCode}）');
    }
    final data = res.data is Map
        ? (res.data as Map).cast<String, dynamic>()
        : <String, dynamic>{};
    final upSpeed = (data['up_info_speed'] ?? 0) is int
        ? data['up_info_speed'] as int
        : int.tryParse('${data['up_info_speed'] ?? 0}') ?? 0;
    final dlSpeed = (data['dl_info_speed'] ?? 0) is int
        ? data['dl_info_speed'] as int
        : int.tryParse('${data['dl_info_speed'] ?? 0}') ?? 0;
    final upTotal = (data['up_info_data'] ?? 0) is int
        ? data['up_info_data'] as int
        : int.tryParse('${data['up_info_data'] ?? 0}') ?? 0;
    final dlTotal = (data['dl_info_data'] ?? 0) is int
        ? data['dl_info_data'] as int
        : int.tryParse('${data['dl_info_data'] ?? 0}') ?? 0;
    return QbTransferInfo(
      upSpeed: upSpeed,
      dlSpeed: dlSpeed,
      upTotal: upTotal,
      dlTotal: dlTotal,
    );
  }

  Future<QbServerState> fetchServerState({
    required QbClientConfig config,
    required String password,
  }) async {
    final base = _buildBase(config);
    final dio = _createDio(base);
    
    final res = await _executeAuthenticatedRequest<Map<String, dynamic>>(
      config,
      password,
      (cookie) => dio.get(
        '/api/v2/sync/maindata',
        options: Options(headers: cookie.isNotEmpty ? {'Cookie': cookie} : null),
      ),
    );
    
    if ((res.statusCode ?? 0) != 200) {
      throw Exception('获取服务器状态失败（HTTP ${res.statusCode}）');
    }
    final data = res.data is Map
        ? (res.data as Map).cast<String, dynamic>()
        : <String, dynamic>{};
    final serverState = data['server_state'] as Map<String, dynamic>? ?? {};
    final freeSpaceOnDisk = (serverState['free_space_on_disk'] ?? 0) is int
        ? serverState['free_space_on_disk'] as int
        : int.tryParse('${serverState['free_space_on_disk'] ?? 0}') ?? 0;
    return QbServerState(
      freeSpaceOnDisk: freeSpaceOnDisk,
    );
  }

  Future<List<String>> fetchCategories({
    required QbClientConfig config,
    required String password,
  }) async {
    final base = _buildBase(config);
    final dio = _createDio(base);
    
    final res = await _executeAuthenticatedRequest<Map<String, dynamic>>(
      config,
      password,
      (cookie) => dio.get(
        '/api/v2/torrents/categories',
        options: Options(headers: cookie.isNotEmpty ? {'Cookie': cookie} : null),
      ),
    );
    
    if ((res.statusCode ?? 0) != 200) {
      throw Exception('获取分类失败（HTTP ${res.statusCode}）');
    }
    final data = res.data;
    if (data is Map) {
      final map = (data as Map).cast<String, dynamic>();
      return map.keys.toList()..sort();
    }
    return <String>[];
  }

  Future<List<String>> fetchTags({
    required QbClientConfig config,
    required String password,
  }) async {
    final base = _buildBase(config);
    final dio = _createDio(base);
    
    final res = await _executeAuthenticatedRequest(
      config,
      password,
      (cookie) => dio.get(
        '/api/v2/torrents/tags',
        options: Options(headers: cookie.isNotEmpty ? {'Cookie': cookie} : null),
      ),
    );
    
    if ((res.statusCode ?? 0) != 200) {
      throw Exception('获取标签失败（HTTP ${res.statusCode}）');
    }
    
    final data = res.data;
    if (data is List) {
      // 如果服务器直接返回 List<dynamic>，转换为 List<String>
      return data.map((e) => e.toString()).toList();
    } else if (data is String) {
      // 如果服务器返回字符串格式的数组，解析它
      if (data.trim().startsWith('[') && data.trim().endsWith(']')) {
        // 移除外层的 [] 并按逗号分割
        final content = data.trim().substring(1, data.trim().length - 1);
        if (content.trim().isEmpty) {
          return <String>[];
        }
        return content.split(',').map((tag) => tag.trim()).toList();
      } else {
        // 按换行符或逗号分割
        return data.split(RegExp(r'[\n,]')).map((tag) => tag.trim()).where((tag) => tag.isNotEmpty).toList();
      }
    }
    
    return <String>[];
  }
  
  /// 获取下载任务列表
  Future<List<QbTorrent>> fetchTorrents({
    required QbClientConfig config,
    required String password,
    String? filter,
    String? category,
    String? tag,
    String? sort,
    bool? reverse,
    int? limit,
    int? offset,
  }) async {
    final base = _buildBase(config);
    final dio = _createDio(base);
    
    final queryParams = <String, dynamic>{
      if (filter != null) 'filter': filter,
      if (category != null) 'category': category,
      if (tag != null) 'tag': tag,
      if (sort != null) 'sort': sort,
      if (reverse != null) 'reverse': reverse.toString(),
      if (limit != null) 'limit': limit.toString(),
      if (offset != null) 'offset': offset.toString(),
    };
    
    final res = await _executeAuthenticatedRequest<List<dynamic>>(
      config,
      password,
      (cookie) => dio.get(
        '/api/v2/torrents/info',
        queryParameters: queryParams,
        options: Options(headers: cookie.isNotEmpty ? {'Cookie': cookie} : null),
      ),
    );
    
    if ((res.statusCode ?? 0) != 200) {
      throw Exception('获取下载任务列表失败（HTTP ${res.statusCode}）');
    }
    
    final data = res.data;
    if (data is List) {
      return data
          .map((item) => item is Map 
              ? QbTorrent.fromJson((item).cast<String, dynamic>()) 
              : null)
          .where((item) => item != null)
          .cast<QbTorrent>()
          .toList();
    }
    
    return <QbTorrent>[];
  }

  // 新增：通过 URL 添加任务到 qBittorrent
  Future<void> addTorrentByUrl({
    required QbClientConfig config,
    required String password,
    required String url,
    String? category,
    List<String>? tags,
    String? savePath,
    bool? autoTMM,
  }) async {
    if (config.useLocalRelay) {
      // 使用本地中转：先下载种子文件，再提交给 qBittorrent
      await _addTorrentByLocalRelay(
        config: config,
        password: password,
        url: url,
        category: category,
        tags: tags,
        savePath: savePath,
        autoTMM: autoTMM,
      );
    } else {
      // 直接通过 URL 添加
      await _addTorrentByUrlDirect(
        config: config,
        password: password,
        url: url,
        category: category,
        tags: tags,
        savePath: savePath,
        autoTMM: autoTMM,
      );
    }
  }

  // 直接通过 URL 添加任务（原有逻辑）
  Future<void> _addTorrentByUrlDirect({
    required QbClientConfig config,
    required String password,
    required String url,
    String? category,
    List<String>? tags,
    String? savePath,
    bool? autoTMM,
  }) async {
    final base = _buildBase(config);
    final dio = _createDio(base);

    final form = FormData.fromMap({
      'urls': url,
      if (category != null && category.isNotEmpty) 'category': category,
      if (tags != null && tags.isNotEmpty) 'tags': tags.join(','),
      if (savePath != null && savePath.trim().isNotEmpty)
        'savepath': savePath.trim(),
      if (autoTMM != null) 'autoTMM': autoTMM ? 'true' : 'false',
    });

    final res = await _executeAuthenticatedRequest(
      config,
      password,
      (cookie) => dio.post(
        '/api/v2/torrents/add',
        data: form,
        options: Options(headers: cookie.isNotEmpty ? {'Cookie': cookie} : null),
      ),
    );

    if ((res.statusCode ?? 0) != 200) {
      throw Exception('发送任务失败（HTTP ${res.statusCode}）');
    }
  }

  // 本地中转：先下载种子文件，再提交给 qBittorrent
  Future<void> _addTorrentByLocalRelay({
    required QbClientConfig config,
    required String password,
    required String url,
    String? category,
    List<String>? tags,
    String? savePath,
    bool? autoTMM,
  }) async {
    final base = _buildBase(config);
    final dio = _createDio(base);

    // 1. 下载种子文件到本地
    final torrentData = await _downloadTorrentFile(url);
    
    // 2. 通过文件内容提交给 qBittorrent
    final form = FormData.fromMap({
      'torrents': MultipartFile.fromBytes(
        torrentData,
        filename: 'torrent_${DateTime.now().millisecondsSinceEpoch}.torrent',
        contentType: MediaType('application', 'x-bittorrent'),
      ),
      if (category != null && category.isNotEmpty) 'category': category,
      if (tags != null && tags.isNotEmpty) 'tags': tags.join(','),
      if (savePath != null && savePath.trim().isNotEmpty)
        'savepath': savePath.trim(),
      if (autoTMM != null) 'autoTMM': autoTMM ? 'true' : 'false',
    });

    final res = await _executeAuthenticatedRequest(
      config,
      password,
      (cookie) => dio.post(
        '/api/v2/torrents/add',
        data: form,
        options: Options(headers: cookie.isNotEmpty ? {'Cookie': cookie} : null),
      ),
    );

    if ((res.statusCode ?? 0) != 200) {
      throw Exception('发送任务失败（HTTP ${res.statusCode}）');
    }
  }

  // 下载种子文件
  Future<List<int>> _downloadTorrentFile(String url) async {
    final dio = Dio();
    
    try {
      final response = await dio.get<List<int>>(
        url,
        options: Options(
          responseType: ResponseType.bytes,
          headers: {
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
          },
        ),
      );
      
      if (response.statusCode != 200 || response.data == null) {
        throw Exception('下载种子文件失败（HTTP ${response.statusCode}）');
      }
      
      return response.data!;
    } catch (e) {
      throw Exception('下载种子文件失败：$e');
    }
  }
  
  /// 暂停下载任务
  Future<void> pauseTorrents({
    required QbClientConfig config,
    required String password,
    required List<String> hashes,
  }) async {
    if (hashes.isEmpty) return;
    
    final base = _buildBase(config);
    final dio = _createDio(base);
    
    final form = FormData.fromMap({
      'hashes': hashes.join('|'),
    });
    
    final res = await _executeAuthenticatedRequest(
      config,
      password,
      (cookie) => dio.post(
        '/api/v2/torrents/stop',
        data: form,
        options: Options(headers: cookie.isNotEmpty ? {'Cookie': cookie} : null),
      ),
    );
    
    if ((res.statusCode ?? 0) != 200) {
      throw Exception('暂停任务失败（HTTP ${res.statusCode}）');
    }
  }
  
  /// 恢复下载任务
  Future<void> resumeTorrents({
    required QbClientConfig config,
    required String password,
    required List<String> hashes,
  }) async {
    if (hashes.isEmpty) return;
    
    final base = _buildBase(config);
    final dio = _createDio(base);
    
    final form = FormData.fromMap({
      'hashes': hashes.join('|'),
    });
    
    final res = await _executeAuthenticatedRequest(
      config,
      password,
      (cookie) => dio.post(
        '/api/v2/torrents/start',
        data: form,
        options: Options(headers: cookie.isNotEmpty ? {'Cookie': cookie} : null),
      ),
    );
    
    if ((res.statusCode ?? 0) != 200) {
      throw Exception('恢复任务失败（HTTP ${res.statusCode}）');
    }
  }
  
  /// 删除下载任务
  Future<void> deleteTorrents({
    required QbClientConfig config,
    required String password,
    required List<String> hashes,
    bool deleteFiles = false,
  }) async {
    if (hashes.isEmpty) return;
    
    final base = _buildBase(config);
    final dio = _createDio(base);
    
    final form = FormData.fromMap({
      'hashes': hashes.join('|'),
      'deleteFiles': deleteFiles.toString(),
    });
    
    final res = await _executeAuthenticatedRequest(
      config,
      password,
      (cookie) => dio.post(
        '/api/v2/torrents/delete',
        data: form,
        options: Options(headers: cookie.isNotEmpty ? {'Cookie': cookie} : null),
      ),
    );
    
    if ((res.statusCode ?? 0) != 200) {
      throw Exception('删除任务失败（HTTP ${res.statusCode}）');
    }
  }

  /// 暂停单个任务的便捷方法
  Future<void> pauseTorrent({
    required QbClientConfig config,
    required String password,
    required String hash,
  }) async {
    await pauseTorrents(
      config: config,
      password: password,
      hashes: [hash],
    );
  }

  /// 恢复单个任务的便捷方法
  Future<void> resumeTorrent({
    required QbClientConfig config,
    required String password,
    required String hash,
  }) async {
    await resumeTorrents(
      config: config,
      password: password,
      hashes: [hash],
    );
  }

  /// 删除单个任务的便捷方法
  Future<void> deleteTorrent({
    required QbClientConfig config,
    required String password,
    required String hash,
    bool deleteFiles = false,
  }) async {
    await deleteTorrents(
      config: config,
      password: password,
      hashes: [hash],
      deleteFiles: deleteFiles,
    );
  }
}