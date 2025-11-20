import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../models/app_models.dart';
// import '../site_config_service.dart';
import '../api/site_adapter.dart';
import '../api/nexusphp_web_adapter.dart';

class WebDebugService {
  WebDebugService._();
  static final WebDebugService instance = WebDebugService._();

  HttpServer? _server;
  List<String> _hostUrls = [];

  bool get isRunning => _server != null;
  List<String> get hostUrls => _hostUrls;
  String get hostUrl => _hostUrls.isNotEmpty ? _hostUrls.first : '';

  Future<bool> start({int port = 8833}) async {
    if (_server != null) return true;
    try {
      HttpServer server;
      try {
        server = await HttpServer.bind(InternetAddress.anyIPv4, port);
      } catch (_) {
        server = await HttpServer.bind(InternetAddress.anyIPv4, 0);
      }
      _server = server;

      final ips = await _pickLanIPv4();
      _hostUrls = ips.map((ip) => 'http://$ip:${server.port}/').toList();
      if (_hostUrls.isEmpty) {
        _hostUrls = ['http://127.0.0.1:${server.port}/'];
      }

      _serve(server);
      return true;
    } catch (_) {
      _server = null;
      _hostUrls = [];
      return false;
    }
  }

  Future<void> stop() async {
    final s = _server;
    _server = null;
    _hostUrls = [];
    await s?.close(force: true);
  }

  Future<List<String>> _pickLanIPv4() async {
    final ips = <String>[];
    try {
      final ifs = await NetworkInterface.list(type: InternetAddressType.IPv4);
      for (final ni in ifs) {
        for (final addr in ni.addresses) {
          if (!addr.isLoopback) {
            ips.add(addr.address);
          }
        }
      }
    } catch (_) {}
    return ips.isNotEmpty ? ips : ['127.0.0.1'];
  }

  void _serve(HttpServer server) {
    server.listen((HttpRequest req) async {
      req.response.headers.set('Access-Control-Allow-Origin', '*');
      req.response.headers.set('Access-Control-Allow-Methods', 'GET,POST');
      req.response.headers.set('Access-Control-Allow-Headers', 'Content-Type');
      if (req.method == 'OPTIONS') {
        req.response.statusCode = HttpStatus.noContent;
        await req.response.close();
        return;
      }
      try {
        if (req.method == 'GET' && req.uri.path == '/') {
          _handleIndex(req);
          return;
        }
        if (req.method == 'POST' && req.uri.path == '/test') {
          await _handleTest(req);
          return;
        }
        req.response.statusCode = HttpStatus.notFound;
        req.response.close();
      } catch (_) {
        _sendJson(req, {'error': 'internal error'});
      }
    });
  }

  void _handleIndex(HttpRequest req) {
    req.response.headers.set('Content-Type', 'text/html; charset=utf-8');
    req.response.write(_indexHtml);
    req.response.close();
  }

  Future<void> _handleTest(HttpRequest req) async {
    final bodyStr = await utf8.decodeStream(req);
    Map<String, dynamic> bodyJson = {};
    try {
      bodyJson = jsonDecode(bodyStr) as Map<String, dynamic>;
    } catch (_) {}

    final siteUrl = (bodyJson['siteUrl'] ?? '').toString().trim();
    final cookie = (bodyJson['cookie'] ?? '').toString().trim();
    final templateJsonStr = (bodyJson['templateJson'] ?? '').toString();

    try {
      if (templateJsonStr.isEmpty) {
        throw 'templateJson is empty';
      }

      SiteConfigTemplate tpl;
      try {
        final map = jsonDecode(templateJsonStr) as Map<String, dynamic>;
        map['primaryUrl'] = siteUrl;
        map['id'] = "templateSite";
        tpl = SiteConfigTemplate.fromJson(map);
      } catch (e) {
        throw 'Invalid templateJson: $e';
      }

      final config = tpl.toSiteConfig(
        selectedUrl: siteUrl,
        apiKey: null,
        passKey: null,
        cookie: cookie,
        userId: null,
        isActive: false,
      );

      final adapter = SiteAdapterFactory.createAdapter(config);
      await adapter.init(config);
      if (adapter is NexusPHPWebAdapter) {
        adapter.setCustomTemplate(tpl);
      }

      final profile = await adapter.fetchMemberProfile();
      final categories = await adapter.getSearchCategories();
      final search = await adapter.searchTorrents(
        keyword: 'a',
        pageNumber: 1,
        pageSize: 5,
      );

      final top3 = search.items
          .take(3)
          .map(
            (e) => {
              'id': e.id,
              'title': e.name,
              'smallDescr': e.smallDescr,
              'discount': e.discount.value,
              'discountText': e.discount.displayText,
              'discountEndTime': e.discountEndTime,
              'downloadUrl': e.downloadUrl,
              'seeders': e.seeders,
              'leechers': e.leechers,
              'sizeBytes': e.sizeBytes,
              'cover': e.cover,
              'createdDate': e.createdDate,
              'doubanRating': e.doubanRating,
              'imdbRating': e.imdbRating,
              'isTop': e.isTop,
              'downloadStatus': e.downloadStatus.toString().split('.').last,
              'collection': e.collection,
            },
          )
          .toList();

      _sendJson(req, {
        'profile': profile.toJson(),
        'categories': categories
            .map((c) => {'id': c.id, 'name': c.displayName})
            .toList(),
        'torrentsTop3': top3,
      });
    } catch (e) {
      _sendJson(req, {'error': e.toString()});
    }
  }

  void _sendJson(HttpRequest req, Map<String, dynamic> jsonObj) {
    req.response.headers.set('Content-Type', 'application/json; charset=utf-8');
    req.response.write(jsonEncode(jsonObj));
    req.response.close();
  }

  static const String _indexHtml = '''
<!DOCTYPE html>
<html lang="zh">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <title>PTMate Web 调试</title>
  <style>
    body { font-family: system-ui, sans-serif; padding: 16px; }
    label { display:block; margin-top:12px; }
    input, textarea { width:100%; padding:8px; margin-top:4px; }
    button { margin-top:16px; padding:8px 12px; }
    pre { background:#f6f8fa; padding:12px; overflow:auto; }
  </style>
  </head>
<body>
  <h2>PTMate Web 调试</h2>
  <label>站点地址
    <input id="siteUrl" placeholder="https://example.com" />
  </label>
  <label>Cookie
    <input id="cookie" placeholder="uid=...; pass=..." />
  </label>
  <label>详细配置（参考 assets/sites/ 下面的 <a href="https://github.com/JustLookAtNow/pt_mate/tree/master/assets/sites">json 文件</a>）
    <p>另有配置说明一份，参考 <a href="https://github.com/JustLookAtNow/pt_mate/blob/master/SITE_CONFIGURATION_GUIDE.md">配置说明</a></p>
    <textarea id="templateJson" rows="12" placeholder="{\n  ...\n}"></textarea>
  </label>
  <button id="testBtn">测试</button>
  <h3>返回结果</h3>
  <pre id="out"></pre>
  <script>
    const el = (id) => document.getElementById(id);
    el('testBtn').onclick = async () => {
      const payload = {
        siteUrl: el('siteUrl').value.trim(),
        cookie: el('cookie').value.trim(),
        templateJson: el('templateJson').value.trim(),
      };
      try {
        const res = await fetch('/test', {
          method:'POST',
          headers:{'Content-Type':'application/json'},
          body: JSON.stringify(payload)
        });
        const json = await res.json();
        el('out').textContent = JSON.stringify(json, null, 2);
      } catch (e) {
        el('out').textContent = '请求失败: ' + e;
      }
    };
  </script>
</body>
</html>
''';
}
