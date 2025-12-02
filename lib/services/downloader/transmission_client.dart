import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'downloader_client.dart';
import 'downloader_config.dart';
import 'downloader_models.dart';

/// Transmission下载器客户端实现
class TransmissionClient implements DownloaderClient {
  final TransmissionConfig config;
  final String password;
  
  // HTTP客户端和会话管理
  late final Dio _dio;
  String? _sessionId;
  
  // 缓存的版本信息，避免重复调用 API
  String? _cachedVersion;
  
  // 配置更新回调
  final Function(TransmissionConfig)? _onConfigUpdated;
  
  TransmissionClient({
    required this.config,
    required this.password,
    Function(TransmissionConfig)? onConfigUpdated,
  }) : _onConfigUpdated = onConfigUpdated {
    _dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 30),
      headers: {
        'User-Agent': 'PT Mate',
        'Content-Type': 'application/json',
      },
        followRedirects: true,
        maxRedirects: 5,
    ));
  }
  
  /// 获取基础URL
  String get _baseUrl => _buildBase(config);
  
  /// 构建基础URL，处理各种格式的主机地址
  String _buildBase(TransmissionConfig c) { 
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
  
  /// 获取RPC路径
  String get _rpcPath => '/transmission/rpc';
  
  /// 执行RPC请求
  Future<Map<String, dynamic>> _rpcRequest(
    String method, {
    Map<String, dynamic>? arguments,
  }) async {
    final url = '$_baseUrl$_rpcPath';
    
    final requestBody = {
      'method': method,
      if (arguments != null) 'arguments': arguments,
    };
    
    final requestHeaders = <String, String>{
      'Content-Type': 'application/json',
    };
    
    // 添加认证信息
    if (config.username.isNotEmpty) {
      final credentials = base64Encode(utf8.encode('${config.username}:$password'));
      requestHeaders['Authorization'] = 'Basic $credentials';
    }
    
    // 添加会话ID（如果有）
    if (_sessionId != null) {
      requestHeaders['X-Transmission-Session-Id'] = _sessionId!;
    }
    
    try {
      final response = await _dio.post(
        url,
        data: jsonEncode(requestBody),
        options: Options(headers: requestHeaders),
      );
      
      if (response.statusCode == 200) {
        final responseData = response.data as Map<String, dynamic>;
        
        // 检查响应结果
        final result = responseData['result'] as String?;
        if (result == 'success') {
          return responseData['arguments'] as Map<String, dynamic>? ?? {};
        } else {
          throw Exception('RPC request failed: $result');
        }
      } else {
        throw HttpException('HTTP ${response.statusCode}: ${response.data}');
      }
    } on DioException catch (e) {
      // 检查是否需要会话ID
      if (e.response?.statusCode == 409) {
        // 从响应头中提取会话ID
        final sessionId = e.response?.headers.value('X-Transmission-Session-Id');
        if (sessionId != null) {
          _sessionId = sessionId;
          // 重试请求
          return _rpcRequest(method, arguments: arguments);
        }
      }
      
      if (e.response?.statusCode == 401) {
        throw Exception('Authentication failed');
      }
      
      if (e.response?.statusCode != null && e.response!.statusCode! >= 400) {
        throw HttpException('HTTP ${e.response!.statusCode}: ${e.response!.data}');
      }
      
      throw Exception('Request failed: ${e.message}');
    }
  }
  
  /// 下载种子文件并返回字节数据
  Future<List<int>> _downloadTorrentFile(String url) async {
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
        return response.data!;
      } else {
        throw Exception('Failed to download torrent file: empty response');
      }
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        throw Exception('Authentication failed when downloading torrent file');
      }
      
      if (e.response?.statusCode != null && e.response!.statusCode! >= 400) {
        throw HttpException('HTTP ${e.response!.statusCode} when downloading torrent file: ${e.response!.data}');
      }
      
      throw Exception('Failed to download torrent file: ${e.message}');
    } catch (e) {
      throw Exception('Failed to download torrent file: $e');
    }
  }
  
  @override
  Future<void> testConnection() async {
    try {
      // 尝试获取会话统计信息来验证连接
      await _rpcRequest('session-stats');
    } catch (e) {
      throw Exception('Connection test failed: $e');
    }
  }
  
  @override
  Future<TransferInfo> getTransferInfo() async {
    final response = await _rpcRequest('session-stats');
    
    return TransferInfo(
      upSpeed: response['uploadSpeed'] ?? 0,
      dlSpeed: response['downloadSpeed'] ?? 0,
      upTotal: response['cumulative-stats']?['uploadedBytes'] ?? 0,
      dlTotal: response['cumulative-stats']?['downloadedBytes'] ?? 0,
    );
  }
  
  @override
  Future<ServerState> getServerState() async {
    final response = await _rpcRequest('session-get');
    
    // Transmission 的可用空间信息在 download-dir-free-space 字段中
    final freeSpace = response['download-dir-free-space'] ?? 0;
    
    return ServerState(
      freeSpaceOnDisk: freeSpace is int ? freeSpace : int.tryParse('$freeSpace') ?? 0,
    );
  }
  
  @override
  Future<List<DownloadTask>> getTasks([GetTasksParams? params]) async {
    final arguments = <String, dynamic>{
      'fields': [
        'id',
        'name',
        'status',
        'totalSize',
        'percentDone',
        'rateDownload',
        'rateUpload',
        'eta',
        'labels',
        'downloadDir',
        'addedDate',
        'leftUntilDone',
        'uploadRatio',
        'activityDate',
        'hashString',
      ],
    };
    
    // 如果有过滤参数，可以在这里处理
    // Transmission 的过滤通常在客户端进行
    
    final response = await _rpcRequest('torrent-get', arguments: arguments);
    final List<dynamic> torrents = response['torrents'] as List<dynamic>? ?? [];
    
    return torrents.map((torrent) => _convertToDownloadTask(torrent)).toList();
  }
  
  @override
  Future<void> addTask(AddTaskParams params) async {
    final arguments = <String, dynamic>{};
    
    // Transmission 不支持通过 URL 下载种子文件，只支持磁力链接
    // 对于种子文件，必须先下载并转换为 base64 格式
    var url = params.url;
    if (url.startsWith('##')) {
      url = url.substring(2);
    }

    if (url.startsWith('magnet:')) {
      // 磁力链接可以直接传递
      arguments['filename'] = url;
    } else {
      // 种子文件 URL，需要下载并转换为 base64
      final torrentData = await _downloadTorrentFile(url);
      arguments['metainfo'] = base64Encode(torrentData);
    }
    
    if (params.savePath != null) {
      arguments['download-dir'] = params.savePath;
    }
    
    // Transmission 使用 labels 而不是 category 和 tags
    final labels = <String>[];
    if (params.category != null && params.category!.isNotEmpty) {
      labels.add(params.category!);
    }
    if (params.tags != null && params.tags!.isNotEmpty) {
      labels.addAll(params.tags!);
    }
    if (labels.isNotEmpty) {
      arguments['labels'] = labels;
    }
    
    // 设置任务自动开始或暂停
    // 当 startPaused 为 true 时，添加后暂停；默认行为为自动开始
    arguments['paused'] = params.startPaused == true;
    
    await _rpcRequest('torrent-add', arguments: arguments);
  }
  
  @override
  Future<void> pauseTasks(List<String> hashes) async {
    final ids = await _hashesToIds(hashes);
    if (ids.isNotEmpty) {
      await _rpcRequest('torrent-stop', arguments: {'ids': ids});
    }
  }
  
  @override
  Future<void> resumeTasks(List<String> hashes) async {
    final ids = await _hashesToIds(hashes);
    if (ids.isNotEmpty) {
      await _rpcRequest('torrent-start', arguments: {'ids': ids});
    }
  }
  
  @override
  Future<void> deleteTasks(List<String> hashes, {bool deleteFiles = false}) async {
    final ids = await _hashesToIds(hashes);
    if (ids.isNotEmpty) {
      await _rpcRequest('torrent-remove', arguments: {
        'ids': ids,
        'delete-local-data': deleteFiles,
      });
    }
  }
  
  @override
  Future<List<String>> getCategories() async {
    // Transmission 没有分类概念，返回空列表
    // 可以考虑从 labels 中提取分类信息
    return [];
  }
  
  @override
  Future<List<String>> getTags() async {
    // 获取所有种子的标签
    final response = await _rpcRequest('torrent-get', arguments: {
      'fields': ['labels'],
    });
    
    final List<dynamic> torrents = response['torrents'] as List<dynamic>? ?? [];
    final Set<String> allLabels = {};
    
    for (final torrent in torrents) {
      final labels = torrent['labels'] as List<dynamic>? ?? [];
      allLabels.addAll(labels.map((label) => label.toString()));
    }
    
    return allLabels.toList();
  }
  
  @override
  Future<String> getVersion() async {
    // 如果已经缓存了版本信息，直接返回
    if (_cachedVersion != null) {
      return _cachedVersion!;
    }
    
    final response = await _rpcRequest('session-get');
    final version = response['version'] as String? ?? 'Unknown';
    
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
    // 获取所有种子的下载路径
    final response = await _rpcRequest('torrent-get', arguments: {
      'fields': ['downloadDir'],
    });
    
    final List<dynamic> torrents = response['torrents'] as List<dynamic>? ?? [];
    final Set<String> allPaths = {};
    
    for (final torrent in torrents) {
      final downloadDir = torrent['downloadDir'] as String?;
      if (downloadDir != null && downloadDir.isNotEmpty) {
        allPaths.add(downloadDir);
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
  
  /// 将哈希值转换为Transmission的ID
  /// 
  /// Transmission 使用数字ID而不是哈希值来标识种子
  Future<List<int>> _hashesToIds(List<String> hashes) async {
    if (hashes.isEmpty) return [];
    
    final response = await _rpcRequest('torrent-get', arguments: {
      'fields': ['id', 'hashString'],
    });
    
    final List<dynamic> torrents = response['torrents'] as List<dynamic>? ?? [];
    final List<int> ids = [];
    
    for (final torrent in torrents) {
      final hash = torrent['hashString'] as String?;
      final id = torrent['id'] as int?;
      
      if (hash != null && id != null && hashes.contains(hash)) {
        ids.add(id);
      }
    }
    
    return ids;
  }
  
  /// 将Transmission API响应转换为DownloadTask
  DownloadTask _convertToDownloadTask(Map<String, dynamic> torrent) {
    // Transmission 状态映射
    final status = torrent['status'] as int? ?? 0;
    String state;
    switch (status) {
      case 0: // TR_STATUS_STOPPED
        state = DownloadTaskState.pausedDL;
        break;
      case 1: // TR_STATUS_CHECK_WAIT
        state = DownloadTaskState.queuedDL;
        break;
      case 2: // TR_STATUS_CHECK
        state = DownloadTaskState.checkingDL;
        break;
      case 3: // TR_STATUS_DOWNLOAD_WAIT
        state = DownloadTaskState.queuedDL;
        break;
      case 4: // TR_STATUS_DOWNLOAD
        state = DownloadTaskState.downloading;
        break;
      case 5: // TR_STATUS_SEED_WAIT
        state = DownloadTaskState.queuedUP;
        break;
      case 6: // TR_STATUS_SEED
        state = DownloadTaskState.uploading;
        break;
      default:
        state = DownloadTaskState.unknown;
    }
    
    final percentDone = (torrent['percentDone'] as num? ?? 0).toDouble();
    final totalSize = torrent['totalSize'] as int? ?? 0;
    final leftUntilDone = torrent['leftUntilDone'] as int? ?? 0;
    final labels = torrent['labels'] as List<dynamic>? ?? [];
    
    return DownloadTask(
      hash: torrent['hashString'] ?? '',
      name: torrent['name'] ?? '',
      state: state,
      size: totalSize,
      progress: percentDone,
      dlspeed: torrent['rateDownload'] ?? 0,
      upspeed: torrent['rateUpload'] ?? 0,
      eta: torrent['eta'] ?? 0,
      category: '', // Transmission 没有分类概念
      tags: labels.map((label) => label.toString()).toList(),
      completionOn: 0, // Transmission API 中没有直接的完成时间字段
      contentPath: torrent['downloadDir'] ?? '',
      addedOn: torrent['addedDate'] ?? 0,
      amountLeft: leftUntilDone,
      ratio: (torrent['uploadRatio'] as num? ?? 0).toDouble(),
      timeActive: (torrent['activityDate'] as int? ?? 0) - (torrent['addedDate'] as int? ?? 0),
    );
  }
  
  /// 获取包含版本信息的配置
  /// 如果当前配置中没有版本信息，会自动获取并返回更新后的配置
  Future<TransmissionConfig> getUpdatedConfig() async {
    // 如果配置中已有版本信息，直接返回
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
  
  /// 释放资源
  void dispose() {
    _dio.close();
  }
}