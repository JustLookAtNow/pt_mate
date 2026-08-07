import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pt_mate/services/downloader/downloader_config.dart';
import 'package:pt_mate/services/downloader/downloader_models.dart';
import 'package:pt_mate/services/downloader/rutorrent_client.dart';

/// 构造 mode=list 返回的种子数组（索引与 httprpc 插件一致，共30项）
List<String> buildRawTorrent({
  String isOpen = '1',
  String isHashChecking = '0',
  String getState = '1',
  String name = 'Test.Torrent',
  String size = '2000',
  String completedChunks = '50',
  String sizeChunks = '100',
  String downloaded = '1000',
  String uploaded = '500',
  String ratio = '500',
  String upSpeed = '10',
  String dlSpeed = '20',
  String label = '',
  String hashing = '0',
  String hashedChunks = '0',
  String basePath = '/downloads/Test.Torrent',
  String created = '1600000000',
  String isActive = '1',
  String message = '',
}) {
  return [
    isOpen, // 0 is_open
    isHashChecking, // 1 is_hash_checking
    '1', // 2 is_hash_checked
    getState, // 3 state
    name, // 4 name
    size, // 5 size_bytes
    completedChunks, // 6 completed_chunks
    sizeChunks, // 7 size_chunks
    downloaded, // 8 bytes_done
    uploaded, // 9 up.total
    ratio, // 10 ratio
    upSpeed, // 11 up.rate
    dlSpeed, // 12 down.rate
    '1024', // 13 chunk_size
    label, // 14 custom1
    '0', // 15 peers_accounted
    '0', // 16 peers_not_connected
    '0', // 17 peers_connected
    '0', // 18 peers_complete
    '0', // 19 left_bytes
    '0', // 20 priority
    '0', // 21 state_changed
    '0', // 22 skip.total
    hashing, // 23 hashing
    hashedChunks, // 24 chunks_hashed
    basePath, // 25 base_path
    created, // 26 creation_date
    '', // 27 tracker_focus
    isActive, // 28 is_active
    message, // 29 message
  ];
}

class _FakeHttpClientAdapter implements HttpClientAdapter {
  /// mode=list 返回的种子表
  Map<String, List<String>> torrents = {};

  /// hash(大写) -> [addtime, seedingtime]
  Map<String, List<String>> timeCustoms = {};

  /// 记录发往 httprpc 的 XML-RPC 请求体
  final List<String> xmlRequests = [];

  /// 模拟 custom 字段查询失败
  bool failTimeCustoms = false;

  /// load 命令返回 fault
  bool faultOnLoad = false;

  /// 种子文件下载内容
  List<int> torrentFileBytes = [1, 2, 3, 4];

  /// 记录发往 addtorrent.php 的表单请求体
  final List<String> uploadRequests = [];

  /// addtorrent.php 通过302 Location返回的result[]值
  String addTorrentResult = 'Success';

  /// 模拟中间层已跟随重定向：addtorrent.php 直接返回200+JSON
  bool addTorrentRespondJson = false;

  Future<String> _readBody(Stream<Uint8List>? stream) async {
    if (stream == null) return '';
    final bytes = <int>[];
    await for (final chunk in stream) {
      bytes.addAll(chunk);
    }
    return utf8.decode(bytes);
  }

  String _multicallResponse() {
    final rows = timeCustoms.entries
        .map(
          (e) =>
              '<value><array><data>'
              '<value><string>${e.key}</string></value>'
              '<value><string>${e.value[0]}</string></value>'
              '<value><string>${e.value[1]}</string></value>'
              '</data></array></value>',
        )
        .join();
    return '<?xml version="1.0" encoding="UTF-8"?>'
        '<methodResponse><params><param><value><array><data>'
        '$rows'
        '</data></array></value></param></params></methodResponse>';
  }

  static const _successResponse =
      '<?xml version="1.0" encoding="UTF-8"?>'
      '<methodResponse><params><param><value><i4>0</i4></value></param>'
      '</params></methodResponse>';

  static const _faultResponse =
      '<?xml version="1.0" encoding="UTF-8"?>'
      '<methodResponse><fault><value><struct>'
      '<member><name>faultCode</name><value><i4>-501</i4></value></member>'
      '<member><name>faultString</name>'
      '<value><string>Could not create download</string></value></member>'
      '</struct></value></fault></methodResponse>';

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final path = options.path;

    if (path.endsWith('/test.torrent')) {
      return ResponseBody.fromBytes(
        Uint8List.fromList(torrentFileBytes),
        200,
        headers: {
          Headers.contentTypeHeader: ['application/x-bittorrent'],
        },
      );
    }

    if (path.endsWith('/plugins/httprpc/action.php')) {
      final body = await _readBody(requestStream);

      if (body.contains('mode=list')) {
        return ResponseBody.fromString(
          jsonEncode({'t': torrents}),
          200,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          },
        );
      }

      if (body.contains('d.multicall2')) {
        if (failTimeCustoms) {
          return ResponseBody.fromString('Internal Server Error', 500);
        }
        return ResponseBody.fromString(
          _multicallResponse(),
          200,
          headers: {
            Headers.contentTypeHeader: ['text/xml'],
          },
        );
      }

      if (body.contains('load.')) {
        xmlRequests.add(body);
        return ResponseBody.fromString(
          faultOnLoad ? _faultResponse : _successResponse,
          200,
          headers: {
            Headers.contentTypeHeader: ['text/xml'],
          },
        );
      }
    }

    if (path.endsWith('/php/addtorrent.php')) {
      final bytes = <int>[];
      if (requestStream != null) {
        await for (final chunk in requestStream) {
          bytes.addAll(chunk);
        }
      }
      uploadRequests.add(utf8.decode(bytes, allowMalformed: true));

      if (addTorrentRespondJson) {
        return ResponseBody.fromString(
          jsonEncode({'result': addTorrentResult}),
          200,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          },
        );
      }
      // 官方行为：无条件302，结果在Location的result[]参数中
      return ResponseBody.fromString(
        '',
        302,
        headers: {
          'location': [
            '//localhost/php/addtorrent.php?result[]=$addTorrentResult&json=1',
          ],
        },
      );
    }

    throw UnsupportedError('Unexpected request: ${options.method} $path');
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  group('RuTorrentClient', () {
    RuTorrentClient buildClient(
      _FakeHttpClientAdapter adapter, {
      bool useLocalRelay = true,
    }) {
      final dio = Dio()..httpClientAdapter = adapter;
      return RuTorrentClient(
        config: RuTorrentConfig(
          id: 'rt-1',
          name: 'rt',
          host: 'http://localhost',
          port: 80,
          username: 'admin',
          password: '',
          useLocalRelay: useLocalRelay,
        ),
        password: 'secret',
        dio: dio,
      );
    }

    test('getTasks maps downloading state and progress', () async {
      final adapter = _FakeHttpClientAdapter()
        ..torrents = {
          'AAAA0000AAAA0000AAAA0000AAAA0000AAAA0000': buildRawTorrent(
            label: Uri.encodeComponent('电影'),
          ),
        };

      final tasks = await buildClient(adapter).getTasks();

      expect(tasks.length, 1);
      final task = tasks.first;
      expect(task.hash, 'aaaa0000aaaa0000aaaa0000aaaa0000aaaa0000');
      expect(task.state, DownloadTaskState.downloading);
      expect(task.progress, closeTo(0.5, 0.001));
      expect(task.dlspeed, 20);
      expect(task.upspeed, 10);
      expect(task.category, '电影');
      // basePath 末段与名称相同时取父目录
      expect(task.contentPath, '/downloads');
    });

    test('getTasks uses addtime custom for addedOn', () async {
      const hash = 'AAAA0000AAAA0000AAAA0000AAAA0000AAAA0000';
      final adapter = _FakeHttpClientAdapter()
        ..torrents = {hash: buildRawTorrent(created: '1600000000')}
        ..timeCustoms = {
          hash: ['1700000000', '1710000000'],
        };

      final tasks = await buildClient(adapter).getTasks();

      expect(tasks.first.addedOn, 1700000000);
      expect(tasks.first.completionOn, 1710000000);
    });

    test('getTasks falls back to creation date without addtime', () async {
      const hash = 'BBBB0000BBBB0000BBBB0000BBBB0000BBBB0000';
      final adapter = _FakeHttpClientAdapter()
        ..torrents = {hash: buildRawTorrent(created: '1600000000')}
        ..timeCustoms = {
          hash: ['', ''],
        };

      final tasks = await buildClient(adapter).getTasks();

      expect(tasks.first.addedOn, 1600000000);
      expect(tasks.first.completionOn, 0);
    });

    test('getTasks survives time-custom fetch failure', () async {
      const hash = 'CCCC0000CCCC0000CCCC0000CCCC0000CCCC0000';
      final adapter = _FakeHttpClientAdapter()
        ..torrents = {hash: buildRawTorrent(created: '1600000000')}
        ..failTimeCustoms = true;

      final tasks = await buildClient(adapter).getTasks();

      expect(tasks.length, 1);
      expect(tasks.first.addedOn, 1600000000);
    });

    test('getTasks maps paused and stopped states', () async {
      final adapter = _FakeHttpClientAdapter()
        ..torrents = {
          'D000000000000000000000000000000000000001': buildRawTorrent(
            getState: '0',
          ),
          'D000000000000000000000000000000000000002': buildRawTorrent(
            isOpen: '0',
          ),
          'D000000000000000000000000000000000000003': buildRawTorrent(
            completedChunks: '100',
          ),
        };

      final tasks = await buildClient(adapter).getTasks();
      final byHash = {for (final t in tasks) t.hash.toUpperCase(): t};

      expect(
        byHash['D000000000000000000000000000000000000001']!.state,
        DownloadTaskState.pausedDL,
      );
      expect(
        byHash['D000000000000000000000000000000000000002']!.state,
        DownloadTaskState.unknown,
      );
      expect(
        byHash['D000000000000000000000000000000000000003']!.state,
        DownloadTaskState.uploading,
      );
    });

    test('addTask magnet with savePath uses addtorrent.php', () async {
      final adapter = _FakeHttpClientAdapter();
      final client = buildClient(adapter, useLocalRelay: false);

      await client.addTask(
        AddTaskParams(
          url: 'magnet:?xt=urn:btih:abcdef0123456789',
          savePath: '/data',
          category: '电影',
          startPaused: true,
        ),
      );

      expect(adapter.xmlRequests, isEmpty);
      final body = adapter.uploadRequests.single;
      expect(body, contains('name="url"'));
      expect(body, contains('magnet:?xt=urn:btih:abcdef0123456789'));
      expect(body, contains('name="dir_edit"'));
      expect(body, contains('/data'));
      expect(body, contains('name="label"'));
      expect(body, contains('电影'));
      expect(body, contains('name="torrents_start_stopped"'));
      expect(body, contains('name="addition[]"'));
      expect(body, contains('d.custom.set=addtime,'));
    });

    test('addTask magnet with startPaused uses load.normal', () async {
      final adapter = _FakeHttpClientAdapter();
      final client = buildClient(adapter, useLocalRelay: false);

      await client.addTask(
        AddTaskParams(url: 'magnet:?xt=urn:btih:abcdef', startPaused: true),
      );

      expect(
        adapter.xmlRequests.single,
        contains('<methodName>load.normal</methodName>'),
      );
    });

    test(
      'addTask torrent url downloads file and uses load.raw_start',
      () async {
        final adapter = _FakeHttpClientAdapter()
          ..torrentFileBytes = [1, 2, 3, 4];
        final client = buildClient(adapter);

        await client.addTask(
          AddTaskParams(url: 'https://example.com/test.torrent'),
        );

        final xml = adapter.xmlRequests.single;
        expect(xml, contains('<methodName>load.raw_start</methodName>'));
        expect(xml, contains('<base64>${base64Encode([1, 2, 3, 4])}</base64>'));
      },
    );

    test(
      'addTask small torrent with savePath uses addtorrent.php multipart',
      () async {
        final adapter = _FakeHttpClientAdapter()
          ..torrentFileBytes = [1, 2, 3, 4];
        final client = buildClient(adapter);

        await client.addTask(
          AddTaskParams(
            url: 'https://example.com/test.torrent',
            savePath: '/data/new',
          ),
        );

        expect(adapter.xmlRequests, isEmpty);
        final body = adapter.uploadRequests.single;
        expect(body, contains('name="torrent_file"'));
        expect(body, contains('name="dir_edit"'));
        expect(body, contains('/data/new'));
        expect(body, contains('name="addition[]"'));
        expect(body, contains('d.custom.set=addtime,'));
      },
    );

    test('addTask propagates FailedDirectory from addtorrent.php', () async {
      final adapter = _FakeHttpClientAdapter()
        ..addTorrentResult = 'FailedDirectory';
      final client = buildClient(adapter, useLocalRelay: false);

      expect(
        () => client.addTask(
          AddTaskParams(url: 'magnet:?xt=urn:btih:abc', savePath: '/invalid'),
        ),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('FailedDirectory'),
          ),
        ),
      );
    });

    // ruTorrent官方上限RTORRENT_PACKET_LIMIT=1572864按base64后长度比较：
    // 原始1179645字节 -> base64 1572860（未达上限，走load.raw）
    // 原始1179646字节 -> base64 1572864（达到上限，走addtorrent.php）
    test(
      'addTask torrent at packet limit boundary stays on load.raw',
      () async {
        final adapter = _FakeHttpClientAdapter()
          ..torrentFileBytes = List.filled(1179645, 0);
        final client = buildClient(adapter);

        await client.addTask(
          AddTaskParams(url: 'https://example.com/test.torrent'),
        );

        expect(adapter.uploadRequests, isEmpty);
        expect(adapter.xmlRequests.single, contains('load.raw_start'));
      },
    );

    test(
      'addTask large torrent falls back to addtorrent.php multipart',
      () async {
        final adapter = _FakeHttpClientAdapter()
          ..torrentFileBytes = List.filled(1179646, 0);
        final client = buildClient(adapter);

        await client.addTask(
          AddTaskParams(
            url: 'https://example.com/test.torrent',
            category: '电影',
            startPaused: true,
          ),
        );

        // 未经XML-RPC提交，且302被视为成功
        expect(adapter.xmlRequests, isEmpty);
        final body = adapter.uploadRequests.single;
        expect(body, contains('name="torrent_file"'));
        expect(body, contains('name="json"'));
        expect(body, isNot(contains('name="dir_edit"')));
        expect(body, contains('name="label"'));
        expect(body, contains('电影'));
        expect(body, contains('name="torrents_start_stopped"'));
        expect(body, contains('name="addition[]"'));
        expect(body, contains('d.custom.set=addtime,'));
      },
    );

    test('addTask large torrent omits optional fields when unset', () async {
      final adapter = _FakeHttpClientAdapter()
        ..torrentFileBytes = List.filled(1179646, 0);
      final client = buildClient(adapter);

      await client.addTask(
        AddTaskParams(url: 'https://example.com/test.torrent'),
      );

      final body = adapter.uploadRequests.single;
      expect(body, isNot(contains('name="dir_edit"')));
      expect(body, isNot(contains('name="label"')));
      expect(body, isNot(contains('name="torrents_start_stopped"')));
      expect(body, contains('name="addition[]"'));
      expect(body, contains('d.custom.set=addtime,'));
    });

    test('addTask throws when addtorrent.php reports failure', () async {
      final adapter = _FakeHttpClientAdapter()
        ..torrentFileBytes = List.filled(1179646, 0)
        ..addTorrentResult = 'FailedFile';
      final client = buildClient(adapter);

      expect(
        () => client.addTask(
          AddTaskParams(url: 'https://example.com/test.torrent'),
        ),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('FailedFile'),
          ),
        ),
      );
    });

    test(
      'addTask accepts JSON result when redirect already followed',
      () async {
        final adapter = _FakeHttpClientAdapter()
          ..torrentFileBytes = List.filled(1179646, 0)
          ..addTorrentRespondJson = true;
        final client = buildClient(adapter);

        await client.addTask(
          AddTaskParams(url: 'https://example.com/test.torrent'),
        );

        expect(adapter.uploadRequests, hasLength(1));
      },
    );

    test('addTask throws on XML-RPC fault', () async {
      final adapter = _FakeHttpClientAdapter()..faultOnLoad = true;
      final client = buildClient(adapter, useLocalRelay: false);

      expect(
        () => client.addTask(AddTaskParams(url: 'magnet:?xt=urn:btih:abc')),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('Could not create download'),
          ),
        ),
      );
    });
  });
}
