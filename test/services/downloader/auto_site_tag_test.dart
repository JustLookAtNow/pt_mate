import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pt_mate/models/app_models.dart';
import 'package:pt_mate/services/downloader/downloader_client.dart';
import 'package:pt_mate/services/downloader/downloader_config.dart';
import 'package:pt_mate/services/downloader/downloader_models.dart';
import 'package:pt_mate/services/downloader/downloader_service.dart';
import 'package:pt_mate/services/storage/storage_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _RecordingClient implements DownloaderClient {
  final List<AddTaskParams> requests = [];
  final List<SiteConfig?> sites = [];
  bool timeoutOnce = false;

  @override
  Future<void> addTask(AddTaskParams params, {SiteConfig? siteConfig}) async {
    requests.add(params);
    sites.add(siteConfig);
    if (timeoutOnce) {
      timeoutOnce = false;
      throw TimeoutException('test timeout');
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _RecordingService extends DownloaderService {
  _RecordingService(this.client) : super.test();

  final _RecordingClient client;

  @override
  DownloaderClient getClient({
    required DownloaderConfig config,
    required String password,
  }) => client;
}

class _UnmockedHttpOverrides extends HttpOverrides {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const site = SiteConfig(
    id: 'mteam',
    name: 'M-Team',
    baseUrl: 'https://example.com',
  );
  const config = QbittorrentConfig(
    id: 'test-qb',
    name: 'qBittorrent',
    host: 'localhost',
    port: 8080,
    username: '',
    password: '',
  );
  const params = AddTaskParams(
    url: 'magnet:?xt=urn:btih:test',
    category: '电影',
    tags: ['手选标签'],
    savePath: '/downloads/movies',
    autoTMM: false,
    startPaused: true,
  );

  final storage = StorageService.instance;
  late _RecordingClient client;
  late _RecordingService service;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    storage.resetForTest();
    client = _RecordingClient();
    service = _RecordingService(client);
  });

  tearDown(() => DownloaderService.instance.clearCache());

  Future<void> submit({
    SiteConfig? source = site,
    AddTaskParams options = params,
    DownloaderConfig downloader = config,
  }) => service.addTask(
    config: downloader,
    password: '',
    params: options,
    siteConfig: source,
  );

  test('默认关闭，显式关闭后也保持原始任务参数', () async {
    await submit();
    expect(client.requests.single, same(params));
    await storage.saveAutoAddSiteTag(true);
    await storage.saveAutoAddSiteTag(false);
    await submit();
    expect(client.requests.last, same(params));
  });

  test('追加站点标签且保留所有其他参数和调用方列表', () async {
    await storage.saveAutoAddSiteTag(true);
    await submit();
    final result = client.requests.single;
    expect(result.tags, ['手选标签', '站点/M-Team']);
    expect(params.tags, ['手选标签']);
    expect(result.toJson(), {...params.toJson(), 'tags': result.tags});
    expect(client.sites.single, same(site));
  });

  test('没有手选标签时也能自动添加，已有站点标签时不重复', () async {
    await storage.saveAutoAddSiteTag(true);
    await submit(options: const AddTaskParams(url: 'magnet:?xt=test'));
    expect(client.requests.last.tags, ['站点/M-Team']);
    await submit(options: params.copyWith(tags: ['站点/M-Team', '手选标签']));
    expect(client.requests.last.tags, ['站点/M-Team', '手选标签']);
  });

  test('缺少站点或名称为空时跳过，名称首尾空白被去除', () async {
    await storage.saveAutoAddSiteTag(true);
    await submit(source: null);
    await submit(source: site.copyWith(name: '   '));
    expect(client.requests, everyElement(same(params)));
    await submit(source: site.copyWith(name: ' M-Team '));
    expect(client.requests.last.tags, ['手选标签', '站点/M-Team']);
  });

  test('ruTorrent 忽略开关，分类和手选参数保持原样', () async {
    await storage.saveAutoAddSiteTag(true);
    await submit(
      downloader: const RuTorrentConfig(
        id: 'test-ru',
        name: 'ruTorrent',
        host: 'localhost',
        port: 80,
        username: '',
        password: '',
      ),
    );
    expect(client.requests.single, same(params));
    expect(DownloaderType.rutorrent.supportsTags, isFalse);
    expect(DownloaderType.qbittorrent.supportsTags, isTrue);
    expect(DownloaderType.transmission.supportsTags, isTrue);
  });

  test('批量提交按各自来源添加标签，不将站点标签写入默认标签', () async {
    await storage.saveAutoAddSiteTag(true);
    await storage.saveDefaultDownloadTags(params.tags!);
    await submit();
    await submit(
      source: site.copyWith(id: 'other', name: 'Other Site'),
    );
    expect(client.requests[0].tags, ['手选标签', '站点/M-Team']);
    expect(client.requests[1].tags, ['手选标签', '站点/Other Site']);
    expect(await storage.loadDefaultDownloadTags(), params.tags);
  });

  test('超时重试仍使用同一份参数，不重复追加标签', () async {
    await storage.saveAutoAddSiteTag(true);
    client.timeoutOnce = true;
    await submit();
    expect(client.requests, hasLength(2));
    expect(client.requests[0], same(client.requests[1]));
    expect(client.requests.last.tags, ['手选标签', '站点/M-Team']);
  });

  for (final type in [
    DownloaderType.qbittorrent,
    DownloaderType.transmission,
  ]) {
    test('${type.displayName} 实际添加请求携带站点标签', () async {
      await storage.saveAutoAddSiteTag(true);
      await HttpOverrides.runZoned(() async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        final requests = <Map<String, dynamic>>[];
        final subscription = server.listen((request) async {
          final body = await utf8.decoder.bind(request).join();
          if (request.uri.path.endsWith('/auth/login')) {
            request.response.headers.add('set-cookie', 'SID=test; Path=/');
            request.response.write('Ok.');
          } else if (type == DownloaderType.transmission) {
            final rpc = jsonDecode(body) as Map<String, dynamic>;
            requests.add(rpc);
            request.response.headers.contentType = ContentType.json;
            request.response.write(
              jsonEncode({'result': 'success', 'arguments': {}}),
            );
          } else {
            final fields = <String, dynamic>{};
            for (final match in RegExp(
              r'name="([^"]+)"\r\n\r\n([^\r]*)',
            ).allMatches(body)) {
              fields[match.group(1)!] = match.group(2)!;
            }
            requests.add(fields);
            request.response.write('Ok.');
          }
          await request.response.close();
        });
        try {
          final downloader = type == DownloaderType.qbittorrent
              ? config.copyWith(port: server.port)
              : TransmissionConfig(
                  id: 'test-transmission',
                  name: 'Transmission',
                  host: '127.0.0.1',
                  port: server.port,
                  username: '',
                  password: '',
                );
          await DownloaderService.test().addTask(
            config: downloader,
            password: '',
            params: params,
            siteConfig: site,
          );
          final request = requests.single;
          if (type == DownloaderType.qbittorrent) {
            expect(request['tags'], '手选标签,站点/M-Team');
            expect(request['category'], '电影');
            expect(request['savepath'], '/downloads/movies');
            expect(request['stopped'], 'true');
          } else {
            expect(request['method'], 'torrent-add');
            final arguments = request['arguments'] as Map<String, dynamic>;
            expect(arguments['labels'], ['电影', '手选标签', '站点/M-Team']);
            expect(arguments['download-dir'], '/downloads/movies');
            expect(arguments['paused'], isTrue);
          }
        } finally {
          await subscription.cancel();
          await server.close(force: true);
        }
      }, createHttpClient: _UnmockedHttpOverrides().createHttpClient);
    });
  }
}
