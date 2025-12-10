import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import '../../models/app_models.dart';
import '../api/nexusphp_web_adapter.dart';
import 'downloader_client.dart';
import 'downloader_config.dart';
import 'downloader_models.dart';

/// qBittorrent下载器客户端实现
class QbittorrentClient implements DownloaderClient {
  final QbittorrentConfig config;
  final String password;

  // HTTP客户端和会话管理
  late final Dio _dio;
  String? _sessionId;

  // 缓存的版本信息，避免重复调用 API
  String? _cachedVersion;

  // 配置更新回调
  final Function(QbittorrentConfig)? _onConfigUpdated;

  QbittorrentClient({
    required this.config,
    required this.password,
    Function(QbittorrentConfig)? onConfigUpdated,
  }) : _onConfigUpdated = onConfigUpdated {
    _dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 30),
        headers: {'User-Agent': 'PT Mate'},
        followRedirects: true,
        maxRedirects: 5,
      ),
    );
  }

  /// 获取基础URL
  String get _baseUrl => _buildBase(config);

  /// 构建基础URL，处理各种格式的主机地址
  String _buildBase(QbittorrentConfig c) {
    var urlStr = c.host.trim();
    // 补全协议
    if (!urlStr.startsWith(RegExp(r'https?://'))) {
      urlStr = 'http://$urlStr';
    }

    try {
      final uri = Uri.parse(urlStr);
      // 优先使用配置中的端口，如果配置为0且URL中包含端口则使用URL中的端口
      final port = (c.port > 0) ? c.port : (uri.hasPort ? uri.port : null);

      // 构建新的URI，保留原有的path
      final newUri = uri.replace(port: port);
      var result = newUri.toString();

      // 移除末尾的斜杠，因为API路径通常以斜杠开头
      if (result.endsWith('/')) {
        result = result.substring(0, result.length - 1);
      }
      return result;
    } catch (e) {
      return urlStr;
    }
  }

  /// 获取API路径前缀（根据版本决定）
  String get _apiPrefix {
    if (config.version != null && config.version!.isNotEmpty) {
      // 解析版本号，判断是否支持新API路径
      final versionParts = config.version!.split('.');
      if (versionParts.isNotEmpty) {
        final majorVersion = int.tryParse(versionParts[0]) ?? 0;
        final minorVersion = versionParts.length > 1
            ? int.tryParse(versionParts[1]) ?? 0
            : 0;

        // qBittorrent 4.1+ 使用 /api/v2/ 路径
        if (majorVersion > 4 || (majorVersion == 4 && minorVersion >= 1)) {
          return '/api/v2';
        }
      }
    }
    // 默认使用新版本路径，如果失败会自动降级
    return '/api/v2';
  }

  /// 执行HTTP请求
  Future<Response> _request(
    String method,
    String endpoint, {
    Map<String, String>? headers,
    Map<String, dynamic>? body,
    bool requireAuth = true,
  }) async {
    final url = '$_baseUrl$_apiPrefix$endpoint';

    // 如果需要认证且没有会话，先登录
    if (requireAuth && _sessionId == null) {
      await _login();
    }

    final requestHeaders = <String, String>{...?headers};

    // 添加会话Cookie
    if (_sessionId != null) {
      requestHeaders['Cookie'] = 'SID=$_sessionId';
    }

    try {
      Response response;

      switch (method.toUpperCase()) {
        case 'GET':
          response = await _dio.get(
            url,
            queryParameters: body,
            options: Options(headers: requestHeaders),
          );
          break;
        case 'POST':
          if (body != null) {
            // /torrents/add 使用 multipart/form-data 提交
            if (endpoint.contains('/torrents/add')) {
              final formData = FormData.fromMap(body);
              response = await _dio.post(
                url,
                data: formData,
                options: Options(
                  headers: requestHeaders,
                  contentType: 'multipart/form-data',
                ),
              );
            } else {
              // 其他接口保持 application/x-www-form-urlencoded
              response = await _dio.post(
                url,
                data: body,
                options: Options(
                  headers: {
                    ...requestHeaders,
                    'Content-Type': 'application/x-www-form-urlencoded',
                  },
                ),
              );
            }
          } else {
            response = await _dio.post(
              url,
              options: Options(headers: requestHeaders),
            );
          }
          break;
        default:
          throw UnsupportedError('HTTP method $method not supported');
      }

      return response;
    } on DioException catch (e) {
      // 检查响应状态
      if (e.response?.statusCode == 403) {
        // 会话可能已过期，清除会话并重试一次
        if (_sessionId != null) {
          _sessionId = null;
          return _request(
            method,
            endpoint,
            headers: headers,
            body: body,
            requireAuth: requireAuth,
          );
        }
        throw Exception('Authentication failed');
      }

      if (e.response?.statusCode != null && e.response!.statusCode! >= 400) {
        throw HttpException(
          'HTTP ${e.response!.statusCode}: ${e.response!.data}',
        );
      }

      throw Exception('Request failed: ${e.message}');
    }
  }

  /// 登录获取会话
  Future<void> _login() async {
    try {
      final response = await _dio.post(
        '$_baseUrl$_apiPrefix/auth/login',
        data:
            'username=${Uri.encodeComponent(config.username)}&password=${Uri.encodeComponent(password)}',
        options: Options(
          headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        ),
      );

      if (response.statusCode == 200 && response.data == 'Ok.') {
        // 从响应头中提取会话ID
        final cookies = response.headers['set-cookie'];
        if (cookies != null && cookies.isNotEmpty) {
          final sidMatch = RegExp(r'SID=([^;]+)').firstMatch(cookies.first);
          if (sidMatch != null) {
            _sessionId = sidMatch.group(1);
            return;
          }
        }
        throw Exception('Failed to extract session ID from login response');
      } else {
        throw Exception('Login failed: ${response.data}');
      }
    } on DioException catch (e) {
      throw Exception('Login failed: ${e.message}');
    }
  }

  @override
  Future<void> testConnection() async {
    try {
      await _login();
      // 尝试获取版本信息来验证连接
      await getVersion();
    } catch (e) {
      throw Exception('Connection test failed: $e');
    }
  }

  @override
  Future<TransferInfo> getTransferInfo() async {
    final response = await _request('GET', '/transfer/info');
    final data = response.data as Map<String, dynamic>;
    return TransferInfo(
      upSpeed: data['up_info_speed'] ?? 0,
      dlSpeed: data['dl_info_speed'] ?? 0,
      upTotal: data['up_info_data'] ?? 0,
      dlTotal: data['dl_info_data'] ?? 0,
    );
  }

  @override
  Future<ServerState> getServerState() async {
    final response = await _request('GET', '/sync/maindata');
    final data = response.data as Map<String, dynamic>;

    // 从 server_state 字段中获取服务器状态信息
    final serverState = data['server_state'] as Map<String, dynamic>? ?? {};
    final freeSpaceOnDisk = (serverState['free_space_on_disk'] ?? 0) is int
        ? serverState['free_space_on_disk'] as int
        : int.tryParse('${serverState['free_space_on_disk'] ?? 0}') ?? 0;

    return ServerState(freeSpaceOnDisk: freeSpaceOnDisk);
  }

  @override
  Future<List<DownloadTask>> getTasks([GetTasksParams? params]) async {
    final queryParams = <String, dynamic>{};

    if (params != null) {
      if (params.filter != null) queryParams['filter'] = params.filter;
      if (params.category != null) queryParams['category'] = params.category;
      if (params.tag != null) queryParams['tag'] = params.tag;
      if (params.sort != null) queryParams['sort'] = params.sort;
      if (params.reverse != null) queryParams['reverse'] = params.reverse;
      if (params.limit != null) queryParams['limit'] = params.limit;
      if (params.offset != null) queryParams['offset'] = params.offset;
    }

    final response = await _request('GET', '/torrents/info', body: queryParams);
    final List<dynamic> data = response.data as List<dynamic>;

    return data.map((torrent) => _convertToDownloadTask(torrent)).toList();
  }

  @override
  Future<void> addTask(AddTaskParams params, {SiteConfig? siteConfig}) async {
    final body = <String, dynamic>{};

    // 本地中转支持：当启用且为种子URL时，先在本地下载种子并以文件上传
    // 如果URL以 ## 开头，强制使用本地中转
    var url = params.url;
    var forceRelay = false;
    if (url.startsWith('##')) {
      url = url.substring(2);
      forceRelay = true;
    }


    final useRelay = config.useLocalRelay || forceRelay;
    if (!useRelay) {
      body['urls'] = url;
    } else {
      final torrentData = await _downloadTorrentFile(
        url,
        siteConfig: siteConfig,
      );
      body['torrents'] = MultipartFile.fromBytes(
        torrentData,
        filename: 'ptmate.torrent',
      );
    }

    if (params.category != null) body['category'] = params.category;
    if (params.tags != null && params.tags!.isNotEmpty) {
      body['tags'] = params.tags!.join(',');
    }
    if (params.savePath != null) body['savepath'] = params.savePath;
    if (params.autoTMM != null) body['autoTMM'] = params.autoTMM;
    // qBittorrent: 使用 'stopped' 字段控制是否添加后暂停
    if (params.startPaused != null) {
      body['stopped'] = params.startPaused.toString();
      body['stopCondition'] = 'None';
    }

    await _request('POST', '/torrents/add', body: body);
  }

  /// 下载种子文件并返回字节数据（用于本地中转）
  Future<List<int>> _downloadTorrentFile(
    String url, {
    SiteConfig? siteConfig,
  }) async {
    List<int> result;

    // 如果是NexusPHPWeb站点，使用适配器下载
    if (siteConfig?.siteType == SiteType.nexusphpweb) {
      try {
        final adapter = NexusPHPWebAdapter();
        await adapter.init(siteConfig!);
        result = await adapter.downloadTorrent(url);
      } catch (e) {
        // 如果适配器下载失败，尝试降级到普通下载（虽然可能因为缺Cookie失败）
        // 或者直接抛出异常
        throw Exception('NexusPHPWebAdapter下载失败: $e');
      }
    } else {
      try {
        final response = await _dio.get<List<int>>(
          url,
          options: Options(
            responseType: ResponseType.bytes,
            followRedirects: true,
            maxRedirects: 5,
            validateStatus: (status) => status != null && status < 400,
          ),
        );

        if (response.data != null) {
          result = response.data!;
        } else {
          throw Exception('Failed to download torrent file: empty response');
        }
      } on DioException catch (e) {
        if (e.response?.statusCode == 401) {
          throw Exception(
            'Authentication failed when downloading torrent file',
          );
        }

        if (e.response?.statusCode != null && e.response!.statusCode! >= 400) {
          throw HttpException(
            'HTTP ${e.response!.statusCode} when downloading torrent file: ${e.response!.data}',
          );
        }

        throw Exception('Failed to download torrent file: ${e.message}');
      } catch (e) {
        throw Exception('Failed to download torrent file: $e');
      }
    }

    // DEBUG: 保存文件以供检查
    if (kDebugMode) {
      try {
        final debugFile = File('/tmp/debug_ptmate.torrent');
        await debugFile.writeAsBytes(result);
        // ignore: avoid_print
        print(
          'DEBUG: Torrent file saved to ${debugFile.path}, size: ${result.length} bytes',
        );

        if (result.isNotEmpty) {
          // 打印前100个字符，检查是否为HTML
          final prefix = String.fromCharCodes(result.take(100).toList());
          // ignore: avoid_print
          print('DEBUG: File content prefix: $prefix');
        }
      } catch (e) {
        // ignore: avoid_print
        print('DEBUG: Failed to save debug file: $e');
      }
    }

    return result;
  }

  /// 根据版本获取暂停任务的 API 路径
  String _getPauseApiPath(String? version) {
    if (version == null) return '/torrents/pause'; // 默认使用 4.x 的路径

    // 移除版本号前的 'v' 前缀（如果存在）
    String cleanVersion = version.toLowerCase().startsWith('v')
        ? version.substring(1)
        : version;

    // 解析版本号，判断是 4.x 还是 5.x
    final versionParts = cleanVersion.split('.');
    if (versionParts.isNotEmpty) {
      final majorVersion = int.tryParse(versionParts[0]);
      if (majorVersion != null && majorVersion >= 5) {
        return '/torrents/stop'; // 5.x 使用 stop
      }
    }
    return '/torrents/pause'; // 4.x 使用 pause
  }

  /// 根据版本获取恢复任务的 API 路径
  String _getResumeApiPath(String? version) {
    if (version == null) return '/torrents/resume'; // 默认使用 4.x 的路径

    // 移除版本号前的 'v' 前缀（如果存在）
    String cleanVersion = version.toLowerCase().startsWith('v')
        ? version.substring(1)
        : version;

    // 解析版本号，判断是 4.x 还是 5.x
    final versionParts = cleanVersion.split('.');
    if (versionParts.isNotEmpty) {
      final majorVersion = int.tryParse(versionParts[0]);
      if (majorVersion != null && majorVersion >= 5) {
        return '/torrents/start'; // 5.x 使用 start
      }
    }
    return '/torrents/resume'; // 4.x 使用 resume
  }

  @override
  Future<void> pauseTasks(List<String> hashes) async {
    // 获取版本信息来决定使用哪个 API
    String? version = _cachedVersion ?? config.version;
    if (version == null || version.isEmpty) {
      try {
        version = await getVersion(); // 这会自动缓存版本信息
      } catch (e) {
        // 如果获取版本失败，使用默认路径
        version = null;
      }
    }

    final apiPath = _getPauseApiPath(version);
    await _request('POST', apiPath, body: {'hashes': hashes.join('|')});
  }

  @override
  Future<void> resumeTasks(List<String> hashes) async {
    // 获取版本信息来决定使用哪个 API
    String? version = _cachedVersion ?? config.version;
    if (version == null || version.isEmpty) {
      try {
        version = await getVersion(); // 这会自动缓存版本信息
      } catch (e) {
        // 如果获取版本失败，使用默认路径
        version = null;
      }
    }

    final apiPath = _getResumeApiPath(version);
    await _request('POST', apiPath, body: {'hashes': hashes.join('|')});
  }

  @override
  Future<void> deleteTasks(
    List<String> hashes, {
    bool deleteFiles = false,
  }) async {
    await _request(
      'POST',
      '/torrents/delete',
      body: {'hashes': hashes.join('|'), 'deleteFiles': deleteFiles.toString()},
    );
  }

  @override
  Future<List<String>> getCategories() async {
    final response = await _request('GET', '/torrents/categories');
    final Map<String, dynamic> data = response.data as Map<String, dynamic>;
    return data.keys.toList();
  }

  @override
  Future<List<String>> getTags() async {
    final response = await _request('GET', '/torrents/tags');
    final List<dynamic> data = response.data as List<dynamic>;
    return data.cast<String>();
  }

  @override
  Future<String> getVersion() async {
    // 如果已经缓存了版本信息，直接返回
    if (_cachedVersion != null) {
      return _cachedVersion!;
    }

    final response = await _request('GET', '/app/version');
    final version = response.data.replaceAll('"', ''); // 移除可能的引号

    // 缓存版本信息
    _cachedVersion = version;

    // 如果配置中没有版本信息且有回调，触发配置更新
    if ((config.version == null || config.version?.isEmpty == true)) {
      final callback = _onConfigUpdated;
      if (callback != null) {
        final updatedConfig = config.copyWith(version: version);
        callback(updatedConfig);
      }
    }

    return version;
  }

  @override
  Future<List<String>> getPaths() async {
    // 获取所有种子的信息，包括保存路径
    final response = await _request('GET', '/torrents/info');
    final List<dynamic> data = response.data as List<dynamic>;

    final Set<String> allPaths = {};

    for (final torrent in data) {
      final savePath = torrent['save_path'] as String?;
      if (savePath != null && savePath.isNotEmpty) {
        allPaths.add(savePath);
      }
    }

    final paths = allPaths.toList();
    paths.sort(); // 按字母顺序排序
    return paths;
  }

  @override
  Future<void> pauseTask(String hash) async {
    await pauseTasks([hash]);
  }

  @override
  Future<void> resumeTask(String hash) async {
    await resumeTasks([hash]);
  }

  @override
  Future<void> deleteTask(String hash, {bool deleteFiles = false}) async {
    await deleteTasks([hash], deleteFiles: deleteFiles);
  }

  /// 将qBittorrent API响应转换为DownloadTask
  DownloadTask _convertToDownloadTask(Map<String, dynamic> torrent) {
    return DownloadTask(
      hash: torrent['hash'] ?? '',
      name: torrent['name'] ?? '',
      state: torrent['state'] ?? '',
      size: torrent['size'] ?? 0,
      progress: (torrent['progress'] ?? 0.0).toDouble(),
      dlspeed: torrent['dlspeed'] ?? 0,
      upspeed: torrent['upspeed'] ?? 0,
      eta: torrent['eta'] ?? 0,
      category: torrent['category'] ?? '',
      tags:
          torrent['tags']
              ?.toString()
              .split(',')
              .where((tag) => tag.isNotEmpty)
              .toList() ??
          [],
      completionOn: torrent['completion_on'] ?? 0,
      contentPath: torrent['content_path'] ?? '',
      addedOn: torrent['added_on'] ?? 0,
      amountLeft: torrent['amount_left'] ?? 0,
      ratio: (torrent['ratio'] ?? 0.0).toDouble(),
      timeActive: torrent['time_active'] ?? 0,
      uploaded: torrent['uploaded'] ?? 0,
    );
  }

  /// 获取包含版本信息的配置
  /// 如果当前配置中没有版本信息，会自动获取并返回更新后的配置
  Future<QbittorrentConfig> getUpdatedConfig() async {
    // 如果配置中已有版本信息且与缓存一致，直接返回
    if (config.version != null && config.version!.isNotEmpty) {
      return config;
    }

    try {
      // 获取版本信息（会自动缓存）
      final version = await getVersion();

      // 创建包含版本信息的新配置
      return config.copyWith(version: version);
    } catch (e) {
      // 如果获取版本失败，返回原配置
      return config;
    }
  }

  /// 确保配置中有版本信息，如果没有则自动获取
  /// 返回更新后的配置（如果版本信息被更新）
  Future<QbittorrentConfig> ensureVersionInfo({
    Function(QbittorrentConfig)? onVersionUpdated,
  }) async {
    // 如果配置中已有版本信息，直接返回
    if (config.version != null && config.version!.isNotEmpty) {
      return config;
    }

    try {
      // 获取版本信息
      final version = await getVersion();

      // 创建包含版本信息的新配置
      final updatedConfig = config.copyWith(version: version);

      // 如果提供了回调，通知调用者配置已更新
      onVersionUpdated?.call(updatedConfig);

      return updatedConfig;
    } catch (e) {
      // 如果获取版本失败，返回原配置（使用默认的 API 路径）
      return config;
    }
  }

  /// 暂停单个任务（带版本更新回调）
  Future<void> pauseTaskWithVersionUpdate(
    String hash, {
    Function(QbittorrentConfig)? onConfigUpdated,
  }) async {
    await pauseTask(hash);

    // 如果需要更新配置，确保版本信息
    if (onConfigUpdated != null) {
      final updatedConfig = await ensureVersionInfo();
      if (updatedConfig != config) {
        onConfigUpdated(updatedConfig);
      }
    }
  }

  /// 恢复单个任务（带版本更新回调）
  Future<void> resumeTaskWithVersionUpdate(
    String hash, {
    Function(QbittorrentConfig)? onConfigUpdated,
  }) async {
    await resumeTask(hash);

    // 如果需要更新配置，确保版本信息
    if (onConfigUpdated != null) {
      final updatedConfig = await ensureVersionInfo();
      if (updatedConfig != config) {
        onConfigUpdated(updatedConfig);
      }
    }
  }

  /// 释放资源
  void dispose() {
    _dio.close();
  }
}
