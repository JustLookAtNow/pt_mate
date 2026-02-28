import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:pt_mate/models/app_models.dart';
import 'package:pt_mate/utils/format.dart';
import 'package:xml/xml.dart';

import 'downloader_client.dart';
import 'downloader_config.dart';
import 'downloader_models.dart';
import 'torrent_file_downloader_mixin.dart';

/// ruTorrent下载器客户端实现
class RuTorrentClient
    with TorrentFileDownloaderMixin
    implements DownloaderClient {
  final RuTorrentConfig config;
  final String password;

  // HTTP客户端
  late final Dio _dio;

  // 缓存的版本信息
  String? _cachedVersion;

  // 配置更新回调
  final Function(RuTorrentConfig)? _onConfigUpdated;

  RuTorrentClient({
    required this.config,
    required this.password,
    Function(RuTorrentConfig)? onConfigUpdated,
  }) : _onConfigUpdated = onConfigUpdated {
    _dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 60),
        headers: {
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/143.0.0.0 Safari/537.36',
        },
        followRedirects: true,
        maxRedirects: 5,
      ),
    );

    // 仅在用户明确允许时才禁用证书验证
    if (config.allowSelfSignedCert) {
      _dio.httpClientAdapter = IOHttpClientAdapter(
        createHttpClient: () {
          final HttpClient client = HttpClient()
            ..badCertificateCallback =
                (X509Certificate cert, String host, int port) => true;
          return client;
        },
      );
    }
  }

  /// 获取基础URL
  String get _baseUrl => _buildBase(config);

  /// 构建基础URL
  String _buildBase(RuTorrentConfig c) {
    var urlStr = c.host.trim();
    // 补全协议
    if (!urlStr.startsWith(RegExp(r'https?://'))) {
      urlStr = 'http://$urlStr';
    }

    try {
      final uri = Uri.parse(urlStr);
      // 优先使用配置中的端口
      final port = (c.port > 0) ? c.port : (uri.hasPort ? uri.port : null);

      // 构建新的URI
      final newUri = uri.replace(port: port);
      var result = newUri.toString();

      // 移除末尾的斜杠
      if (result.endsWith('/')) {
        result = result.substring(0, result.length - 1);
      }
      return result;
    } catch (e) {
      return urlStr;
    }
  }

  /// 执行HTTP请求
  Future<Response> _request(
    String method,
    String endpoint, {
    Map<String, String>? headers,
    dynamic body,
    bool useAuth = true,
  }) async {
    final url = '$_baseUrl$endpoint';

    final requestHeaders = <String, String>{...?headers};

    // 添加Basic Auth
    if (useAuth) {
      final credentials = base64Encode(
        utf8.encode('${config.username}:$password'),
      );
      requestHeaders['Authorization'] = 'Basic $credentials';
    }

    try {
      Response response;

      switch (method.toUpperCase()) {
        case 'GET':
          response = await _dio.get(
            url,
            queryParameters: body is Map<String, dynamic> ? body : null,
            options: Options(headers: requestHeaders),
          );
          break;
        case 'POST':
          // 如果 body 是 Map 且没有指定 Content-Type，使用 form-urlencoded
          if (body is Map<String, dynamic> &&
              !requestHeaders.containsKey('Content-Type')) {
            requestHeaders['Content-Type'] =
                'application/x-www-form-urlencoded';
          }

          response = await _dio.post(
            url,
            data: body,
            options: Options(
              headers: requestHeaders,
              contentType: requestHeaders['Content-Type'],
            ),
          );
          break;
        default:
          throw UnsupportedError('HTTP method $method not supported');
      }

      return response;
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
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

  /// 构建XML-RPC请求
  String _buildRequestXML(List<List<dynamic>> calls) {
    final builder = XmlBuilder();
    builder.processing('xml', 'version="1.0" encoding="UTF-8"');
    builder.element(
      'methodCall',
      nest: () {
        builder.element('methodName', nest: 'system.multicall');
        builder.element(
          'params',
          nest: () {
            builder.element(
              'param',
              nest: () {
                builder.element(
                  'value',
                  nest: () {
                    builder.element(
                      'array',
                      nest: () {
                        builder.element(
                          'data',
                          nest: () {
                            for (final call in calls) {
                              final method = call[0] as String;
                              final params = call.length > 1
                                  ? call[1] as List
                                  : <String>[];

                              builder.element(
                                'value',
                                nest: () {
                                  builder.element(
                                    'struct',
                                    nest: () {
                                      builder.element(
                                        'member',
                                        nest: () {
                                          builder.element(
                                            'name',
                                            nest: 'methodName',
                                          );
                                          builder.element(
                                            'value',
                                            nest: () {
                                              builder.element(
                                                'string',
                                                nest: method,
                                              );
                                            },
                                          );
                                        },
                                      );
                                      builder.element(
                                        'member',
                                        nest: () {
                                          builder.element(
                                            'name',
                                            nest: 'params',
                                          );
                                          builder.element(
                                            'value',
                                            nest: () {
                                              builder.element(
                                                'array',
                                                nest: () {
                                                  builder.element(
                                                    'data',
                                                    nest: () {
                                                      for (final param
                                                          in params) {
                                                        builder.element(
                                                          'value',
                                                          nest: () {
                                                            builder.element(
                                                              'string',
                                                              nest: param
                                                                  .toString(),
                                                            );
                                                          },
                                                        );
                                                      }
                                                    },
                                                  );
                                                },
                                              );
                                            },
                                          );
                                        },
                                      );
                                    },
                                  );
                                },
                              );
                            }
                          },
                        );
                      },
                    );
                  },
                );
              },
            );
          },
        );
      },
    );

    return builder.buildDocument().toXmlString();
  }

  /// 解析XML-RPC响应
  List<String> _parseResponseXML(String xmlString) {
    final document = XmlDocument.parse(xmlString);
    final values = document.findAllElements('value');

    // 查找符合路径的值
    final results = <String>[];
    for (final value in values) {
      // 检查是否是数据值节点（包含文本内容）
      final textNodes = value.children.whereType<XmlText>();
      if (textNodes.isNotEmpty) {
        results.add(textNodes.first.value);
      }
    }

    return results;
  }

  /// 安全地将字符串转为整数
  int _iv(String? val) {
    return FormatUtil.parseInt(val) ?? 0;
  }



  @override
  Future<void> testConnection() async {
    try {
      // 使用 getsettings.php 测试连接
      final response = await _request('GET', '/php/getsettings.php');

      if (response.statusCode == 200 && response.data is Map) {
        // 连接成功
        return;
      } else {
        throw Exception('Invalid response from server');
      }
    } catch (e) {
      throw Exception('Connection test failed: $e');
    }
  }

  @override
  Future<String> getVersion() async {
    // 如果已经缓存了版本信息，直接返回
    if (_cachedVersion != null) {
      return _cachedVersion!;
    }

    try {
      // 使用 XML-RPC 获取版本信息
      final xml = _buildRequestXML([
        ['system.client_version'],
        ['system.api_version'],
      ]);

      final response = await _request(
        'POST',
        '/plugins/httprpc/action.php',
        headers: {'Content-Type': 'application/xml'},
        body: xml,
      );

      final versions = _parseResponseXML(response.data);
      final version = versions.isNotEmpty ? versions[0] : 'Unknown';

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
    } catch (e) {
      return 'Unknown';
    }
  }

  @override
  Future<TransferInfo> getTransferInfo() async {
    // 获取总传输量
    final ttlResponse = await _request(
      'POST',
      '/plugins/httprpc/action.php',
      body: {'mode': 'ttl'},
    );

    final List<dynamic> ttlData = ttlResponse.data as List<dynamic>;
    final upTotal = ttlData.isNotEmpty ? _iv(ttlData[0].toString()) : 0;
    final dlTotal = ttlData.length > 1 ? _iv(ttlData[1].toString()) : 0;

    // 获取种子列表以计算实时速度
    final listResponse = await _request(
      'POST',
      '/plugins/httprpc/action.php',
      body: {'mode': 'list'},
    );

    final Map<String, dynamic> data = listResponse.data as Map<String, dynamic>;
    final Map<String, dynamic> torrents =
        data['t'] as Map<String, dynamic>? ?? {};

    // 累加所有种子的上传和下载速度
    int totalUpSpeed = 0;
    int totalDlSpeed = 0;

    for (final entry in torrents.entries) {
      final torrentData = entry.value as List<dynamic>;
      if (torrentData.length > 12) {
        totalUpSpeed += _iv(
          torrentData[11].toString(),
        ); // upload_speed at index 11
        totalDlSpeed += _iv(
          torrentData[12].toString(),
        ); // download_speed at index 12
      }
    }

    return TransferInfo(
      upTotal: upTotal,
      dlTotal: dlTotal,
      upSpeed: totalUpSpeed,
      dlSpeed: totalDlSpeed,
    );
  }

  @override
  Future<ServerState> getServerState() async {
    try {
      // 尝试从 diskspace 插件获取空间信息
      final response = await _request('GET', '/plugins/diskspace/action.php');

      final Map<String, dynamic> data = response.data as Map<String, dynamic>;
      final freeSpace = data['free'] ?? 0;

      return ServerState(
        freeSpaceOnDisk: freeSpace is int
            ? freeSpace
            : FormatUtil.parseInt(freeSpace) ?? 0,
      );
    } catch (e) {
      // 如果 diskspace 插件不可用，尝试从种子列表中获取（取第一个种子的 free_diskspace）
      try {
        final listResponse = await _request(
          'POST',
          '/plugins/httprpc/action.php',
          body: {'mode': 'list'},
        );

        final Map<String, dynamic> data =
            listResponse.data as Map<String, dynamic>;
        final Map<String, dynamic> torrents =
            data['t'] as Map<String, dynamic>? ?? {};

        // 从第一个种子获取磁盘空间（所有种子的该值应该相同）
        if (torrents.isNotEmpty) {
          final firstTorrent = torrents.values.first as List<dynamic>;
          if (firstTorrent.length > 31) {
            final freeSpace = _iv(firstTorrent[31].toString());
            return ServerState(freeSpaceOnDisk: freeSpace);
          }
        }
      } catch (_) {
        // 忽略错误
      }

      // 如果都失败，返回0
      return const ServerState(freeSpaceOnDisk: 0);
    }
  }

  @override
  Future<List<DownloadTask>> getTasks([GetTasksParams? params]) async {
    final response = await _request(
      'POST',
      '/plugins/httprpc/action.php',
      body: {'mode': 'list'},
    );

    final Map<String, dynamic> data = response.data as Map<String, dynamic>;
    final Map<String, dynamic> torrents =
        data['t'] as Map<String, dynamic>? ?? {};

    final tasks = <DownloadTask>[];

    for (final entry in torrents.entries) {
      final hash = entry.key;
      final torrentData = entry.value as List<dynamic>;

      tasks.add(_convertToDownloadTask(hash, torrentData));
    }

    return tasks;
  }

  @override
  Future<void> addTask(AddTaskParams params, {SiteConfig? siteConfig}) async {
    var url = params.url;
    var forceRelay = false;
    if (url.startsWith('##')) {
      url = url.substring(2);
      forceRelay = true;
    }

    final useRelay = config.useLocalRelay || forceRelay;

    if (url.startsWith('magnet:') && !useRelay) {
      // Magnet链接，使用URLSearchParams
      final body = <String, dynamic>{'url': url, 'json': '1'};

      if (params.savePath != null) {
        body['dir_edit'] = params.savePath;
      }
      if (params.startPaused == true) {
        body['torrents_start_stopped'] = '1';
      }
      if (params.category != null && params.category!.isNotEmpty) {
        body['label'] = params.category;
      }

      final formData = FormData.fromMap(body);
      await _request('POST', '/php/addtorrent.php', body: formData);
    } else {
      // 种子文件，需要先下载
      final torrentData = await downloadTorrentFileCommon(
        _dio,
        url,
        siteConfig: siteConfig,
      );

      final body = <String, dynamic>{
        'torrent_file': MultipartFile.fromBytes(
          torrentData,
          filename: 'ptmate.torrent',
        ),
        'json': '1',
      };

      if (params.savePath != null) {
        body['dir_edit'] = params.savePath;
      }
      if (params.startPaused == true) {
        body['torrents_start_stopped'] = '1';
      }
      if (params.category != null && params.category!.isNotEmpty) {
        body['label'] = params.category;
      }

      final formData = FormData.fromMap(body);
      await _request('POST', '/php/addtorrent.php', body: formData);
    }
  }

  @override
  Future<void> pauseTasks(List<String> hashes) async {
    for (final hash in hashes) {
      final hashUpper = hash.toUpperCase();
      await _request(
        'POST',
        '/plugins/httprpc/action.php',
        body: {'mode': 'pause', 'hash': hashUpper},
      );
    }
  }

  @override
  Future<void> resumeTasks(List<String> hashes) async {
    for (final hash in hashes) {
      final hashUpper = hash.toUpperCase();
      await _request(
        'POST',
        '/plugins/httprpc/action.php',
        body: {'mode': 'start', 'hash': hashUpper},
      );
    }
  }

  @override
  Future<void> deleteTasks(
    List<String> hashes, {
    bool deleteFiles = false,
  }) async {
    for (final hash in hashes) {
      final hashUpper = hash.toUpperCase();

      if (!deleteFiles) {
        // 仅删除种子
        await _request(
          'POST',
          '/plugins/httprpc/action.php',
          body: {'mode': 'remove', 'hash': hashUpper},
        );
      } else {
        // 删除种子和数据
        final xml = _buildRequestXML([
          [
            'd.custom5.set',
            [hashUpper, '1'],
          ],
          [
            'd.delete_tied',
            [hashUpper],
          ],
          [
            'd.erase',
            [hashUpper],
          ],
        ]);

        await _request(
          'POST',
          '/plugins/httprpc/action.php',
          headers: {'Content-Type': 'application/xml'},
          body: xml,
        );
      }
    }
  }

  @override
  Future<List<String>> getCategories() async {
    // ruTorrent 没有分类概念，返回空列表
    return [];
  }

  @override
  Future<List<String>> getTags() async {
    // 从所有种子中提取标签
    final tasks = await getTasks();
    final Set<String> allLabels = {};

    for (final task in tasks) {
      if (task.category.isNotEmpty) {
        allLabels.add(task.category);
      }
    }

    return allLabels.toList();
  }

  @override
  Future<List<String>> getPaths() async {
    final tasks = await getTasks();
    final Set<String> allPaths = {};

    for (final task in tasks) {
      if (task.contentPath.isNotEmpty) {
        allPaths.add(task.contentPath);
      }
    }

    final paths = allPaths.toList();
    paths.sort();
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

  /// 将ruTorrent API响应转换为DownloadTask
  DownloadTask _convertToDownloadTask(
    String infoHash,
    List<dynamic> rawTorrent,
  ) {
    // 解析各字段
    final isOpen = _iv(rawTorrent[0].toString());
    final isHashChecking = _iv(rawTorrent[1].toString());
    final getState = _iv(rawTorrent[3].toString());
    final torrentName = rawTorrent[4].toString();
    final torrentSize = _iv(rawTorrent[5].toString());
    final getCompletedChunks = _iv(rawTorrent[6].toString());
    final getSizeChunks = _iv(rawTorrent[7].toString());
    final torrentDownloaded = _iv(rawTorrent[8].toString());
    final torrentUploaded = _iv(rawTorrent[9].toString());
    final ratio = _iv(rawTorrent[10].toString());
    final uploadSpeed = _iv(rawTorrent[11].toString());
    final downloadSpeed = _iv(rawTorrent[12].toString());
    final torrentLabel = Uri.decodeComponent(rawTorrent[14].toString());
    final basePath = rawTorrent[25].toString();
    final created = _iv(rawTorrent[26].toString());
    final isActive = _iv(rawTorrent[28].toString());
    final torrentMsg = rawTorrent[29].toString();
    final getHashing = _iv(rawTorrent[23].toString());
    final getHashedChunks = _iv(rawTorrent[24].toString());

    // 计算进度
    final chunksProcessing = isHashChecking == 0
        ? getCompletedChunks
        : getHashedChunks;
    final progress = getSizeChunks > 0
        ? (chunksProcessing / getSizeChunks * 1000).floor()
        : 0;
    final isCompleted = progress >= 1000;

    // 判断状态
    String state;
    if (isOpen != 0) {
      if (getState == 0 || isActive == 0) {
        state = DownloadTaskState.pausedDL;
      } else {
        state = isCompleted
            ? DownloadTaskState.uploading
            : DownloadTaskState.downloading;
      }
    } else if (getHashing != 0) {
      state = DownloadTaskState.queuedDL;
    } else if (isHashChecking != 0) {
      state = DownloadTaskState.checkingDL;
    } else if (torrentMsg.isNotEmpty &&
        torrentMsg != 'Tracker: [Tried all trackers.]') {
      state = DownloadTaskState.error;
    } else {
      state = DownloadTaskState.unknown;
    }

    // 计算保存路径
    final basePathPos = basePath.lastIndexOf('/');
    final savePath =
        basePathPos >= 0 && basePath.substring(basePathPos + 1) == torrentName
        ? basePath.substring(0, basePathPos)
        : basePath;

    return DownloadTask(
      hash: infoHash.toLowerCase(),
      name: torrentName,
      state: state,
      size: torrentSize,
      progress: progress / 1000.0, // 转换为 0-1 之间的小数
      dlspeed: downloadSpeed,
      upspeed: uploadSpeed,
      eta: 0, // ruTorrent API 中没有直接的 ETA 字段
      category: torrentLabel,
      tags: torrentLabel.isNotEmpty ? [torrentLabel] : [],
      completionOn: 0,
      contentPath: savePath,
      addedOn: created,
      amountLeft: torrentSize - torrentDownloaded,
      ratio: ratio / 1000.0, // 转换为实际比率
      timeActive: 0,
      uploaded: torrentUploaded,
    );
  }

  /// 释放资源
  void dispose() {
    _dio.close();
  }
}
