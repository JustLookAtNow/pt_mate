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

  /// ruTorrent官方的base64负载上限（php/rtorrent.php RTORRENT_PACKET_LIMIT）
  /// base64编码后达到该长度时，load.raw会超出rTorrent的XML-RPC包大小限制；
  /// 官方此时改为写服务器临时文件再按路径加载，该回退依赖服务器文件系统，
  /// 客户端只能改走 /php/addtorrent.php 上传由服务端处理
  static const int rtorrentPacketLimit = 1572864;

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
    Dio? dio, // 供测试注入
  }) : _onConfigUpdated = onConfigUpdated {
    if (dio != null) {
      _dio = dio;
      return;
    }
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
  /// [acceptRedirect] 为true时不跟随重定向，且3xx不视为错误
  /// （addtorrent.php以302的Location参数返回结果）
  Future<Response> _request(
    String method,
    String endpoint, {
    Map<String, String>? headers,
    dynamic body,
    bool useAuth = true,
    bool acceptRedirect = false,
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
              followRedirects: acceptRedirect ? false : null,
              validateStatus: acceptRedirect
                  ? (status) => status != null && status < 400
                  : null,
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

  /// 构建单个方法调用的XML-RPC请求
  /// 参数支持字符串和二进制数据（List&lt;int&gt;，编码为base64）
  String _buildMethodCallXML(String method, List<dynamic> params) {
    final builder = XmlBuilder();
    builder.processing('xml', 'version="1.0" encoding="UTF-8"');
    builder.element(
      'methodCall',
      nest: () {
        builder.element('methodName', nest: method);
        builder.element(
          'params',
          nest: () {
            for (final param in params) {
              builder.element(
                'param',
                nest: () {
                  builder.element(
                    'value',
                    nest: () {
                      if (param is List<int>) {
                        builder.element('base64', nest: base64Encode(param));
                      } else {
                        builder.element('string', nest: param.toString());
                      }
                    },
                  );
                },
              );
            }
          },
        );
      },
    );

    return builder.buildDocument().toXmlString();
  }

  /// 检查XML-RPC响应中的fault，出错时抛出异常
  void _checkXmlRpcFault(String xmlString) {
    final XmlDocument document;
    try {
      document = XmlDocument.parse(xmlString);
    } catch (_) {
      // 响应不是合法XML（如网关返回的HTML错误页），不在此处判定失败
      return;
    }
    if (document.findAllElements('fault').isNotEmpty) {
      String message = 'Unknown XML-RPC fault';
      for (final member in document.findAllElements('member')) {
        final name = member.getElement('name')?.innerText;
        if (name == 'faultString') {
          message =
              member.getElement('value')?.innerText.trim() ?? message;
          break;
        }
      }
      throw Exception('XML-RPC fault: $message');
    }
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

    // 列表接口不包含添加/完成时间，需单独从custom字段获取
    final timeCustoms = await _fetchTimeCustoms();

    final tasks = <DownloadTask>[];

    for (final entry in torrents.entries) {
      final hash = entry.key;
      final torrentData = entry.value as List<dynamic>;
      final times = timeCustoms[hash.toUpperCase()];

      tasks.add(
        _convertToDownloadTask(
          hash,
          torrentData,
          addTime: times?.$1 ?? 0,
          completedTime: times?.$2 ?? 0,
        ),
      );
    }

    return tasks;
  }

  /// 获取所有种子的添加时间与完成时间
  /// ruTorrent将其存储在custom字段addtime/seedingtime中，mode=list不返回
  /// 返回 hash(大写) -> (addtime, seedingtime)，字段未设置时为0
  Future<Map<String, (int, int)>> _fetchTimeCustoms() async {
    try {
      final xml = _buildMethodCallXML('d.multicall2', [
        '',
        'main',
        'd.hash=',
        'd.custom=addtime',
        'd.custom=seedingtime',
      ]);

      final response = await _request(
        'POST',
        '/plugins/httprpc/action.php',
        headers: {'Content-Type': 'application/xml'},
        body: xml,
      );

      final document = XmlDocument.parse(response.data.toString());
      final result = <String, (int, int)>{};

      final dataElements = document.findAllElements('data');
      if (dataElements.isEmpty) return result;

      // 外层data的每个value对应一个种子：[hash, addtime, seedingtime]
      for (final value in dataElements.first.childElements.where(
        (e) => e.name.local == 'value',
      )) {
        final strings = value.findAllElements('string').toList();
        if (strings.isEmpty) continue;

        final hash = strings[0].innerText.trim();
        final addTime = strings.length > 1
            ? (int.tryParse(strings[1].innerText.trim()) ?? 0)
            : 0;
        final completedTime = strings.length > 2
            ? (int.tryParse(strings[2].innerText.trim()) ?? 0)
            : 0;

        if (hash.isNotEmpty) {
          result[hash.toUpperCase()] = (addTime, completedTime);
        }
      }

      return result;
    } catch (_) {
      // 获取失败时不影响任务列表本身
      return {};
    }
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

    final savePath = params.savePath?.trim() ?? '';
    if (savePath.isNotEmpty) {
      _validateSavePath(savePath);
    }

    // 附加命令：记录添加时间（ruTorrent约定的custom字段）、保存路径与标签
    // label需URL编码，与ruTorrent存储格式一致
    final commands = <String>[
      'd.custom.set=addtime,${DateTime.now().millisecondsSinceEpoch ~/ 1000}',
    ];
    if (savePath.isNotEmpty) {
      commands.add('d.directory.set="$savePath"');
    }
    if (params.category != null && params.category!.isNotEmpty) {
      commands.add('d.custom1.set=${Uri.encodeComponent(params.category!)}');
    }

    final startPaused = params.startPaused == true;

    String xml;
    if (url.startsWith('magnet:') && !useRelay) {
      // Magnet链接：由rTorrent直接加载
      final method = startPaused ? 'load.normal' : 'load.start';
      xml = _buildMethodCallXML(method, ['', url, ...commands]);
    } else {
      // 种子文件：先下载到本地
      final torrentData = await downloadTorrentFileCommon(
        _dio,
        url,
        siteConfig: siteConfig,
      );

      // 与ruTorrent官方相同的判断：base64编码后达到包大小上限的种子
      // 无法经load.raw提交，改走addtorrent.php由服务端落盘后加载
      final base64Length = ((torrentData.length + 2) ~/ 3) * 4;
      if (base64Length >= rtorrentPacketLimit) {
        await _addTorrentFileViaWeb(torrentData, params);
        return;
      }

      final method = startPaused ? 'load.raw' : 'load.raw_start';
      xml = _buildMethodCallXML(method, ['', torrentData, ...commands]);
    }

    // 官方sendTorrent/sendMagnet设置保存路径前会先在服务端execute mkdir -p，
    // 避免目录不存在时rTorrent开始写入才失败；~与相对路径由服务端配置解析，
    // 客户端无法复刻，仅对绝对路径创建
    if (savePath.startsWith('/')) {
      await _ensureRemoteDirectory(savePath);
    }

    final response = await _request(
      'POST',
      '/plugins/httprpc/action.php',
      headers: {'Content-Type': 'application/xml'},
      body: xml,
    );

    _checkXmlRpcFault(response.data.toString());
  }

  /// 校验保存路径，对应官方addtorrent.php经correctDirectory()的拒绝行为
  /// 官方基于服务器配置解析路径归属，客户端无法复刻，
  /// 此处拦截会破坏rTorrent命令引用的非法字符
  void _validateSavePath(String path) {
    if (path.contains('"') || path.codeUnits.any((c) => c < 0x20)) {
      throw Exception('ruTorrent: invalid save path (FailedDirectory)');
    }
  }

  /// 在服务端创建保存目录，等价于官方sendTorrent中的execute mkdir -p
  /// （官方经方法表把execute映射为execute2并前置空target，
  /// execute2在rTorrent 0.9.4至当前master均可用）
  /// 官方multicall中mkdir失败不阻断load，此处保持一致
  Future<void> _ensureRemoteDirectory(String directory) async {
    try {
      final xml = _buildMethodCallXML('execute2', [
        '',
        'mkdir',
        '-p',
        directory,
      ]);
      await _request(
        'POST',
        '/plugins/httprpc/action.php',
        headers: {'Content-Type': 'application/xml'},
        body: xml,
      );
    } catch (_) {
      // 目录创建失败不阻断添加，写入问题由rTorrent自身报告
    }
  }

  /// 通过 /php/addtorrent.php 以multipart上传种子文件（大文件专用）
  /// addtime由ruTorrent的seedingtime插件注册的inserted_new事件自动写入，
  /// 无需在此设置
  Future<void> _addTorrentFileViaWeb(
    List<int> torrentData,
    AddTaskParams params,
  ) async {
    final form = <String, dynamic>{
      'torrent_file': MultipartFile.fromBytes(
        torrentData,
        filename: 'pt_mate.torrent',
      ),
      'json': '1',
    };
    if (params.savePath != null && params.savePath!.isNotEmpty) {
      form['dir_edit'] = params.savePath!;
    }
    if (params.category != null && params.category!.isNotEmpty) {
      // 服务端会自行URL编码后存入custom1
      form['label'] = params.category!;
    }
    if (params.startPaused == true) {
      form['torrents_start_stopped'] = '1';
    }

    final response = await _request(
      'POST',
      '/php/addtorrent.php',
      body: FormData.fromMap(form),
      acceptRedirect: true,
    );

    final result = _parseAddTorrentResult(response);
    if (result != 'Success') {
      throw Exception(
        'ruTorrent addtorrent.php failed: '
        '${result ?? 'unexpected response (HTTP ${response.statusCode})'}',
      );
    }
  }

  /// 解析addtorrent.php的结果
  /// 正常返回302，结果在Location头的result[]参数中；
  /// 若反向代理等中间层已跟随重定向，则按JSON响应解析
  String? _parseAddTorrentResult(Response response) {
    if (response.statusCode == 302) {
      final location = response.headers.value('location') ?? '';
      return RegExp(r'result\[\]=(\w+)').firstMatch(location)?.group(1);
    }
    try {
      final data = response.data;
      final map = data is Map ? data : jsonDecode(data.toString());
      return map['result']?.toString();
    } catch (_) {
      return null;
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
  /// [addTime]/[completedTime] 来自custom字段，未设置时为0
  DownloadTask _convertToDownloadTask(
    String infoHash,
    List<dynamic> rawTorrent, {
    int addTime = 0,
    int completedTime = 0,
  }) {
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
      completionOn: completedTime,
      contentPath: savePath,
      // addtime未设置时回退到种子文件创建时间
      addedOn: addTime > 0 ? addTime : created,
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
