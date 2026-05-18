import 'dart:io';
import '../storage/storage_service.dart';

class ProxyService {
  ProxyService._();
  static final ProxyService instance = ProxyService._();

  // 内存中缓存最新的代理配置参数
  bool isProxyEnabled = false;
  String proxyHost = '';
  int proxyPort = 7890;
  String proxyUsername = '';
  String proxyPassword = '';
  bool bypassLan = true;
  List<String> bypassRules = [];

  /// 在应用启动时初始化并应用代理设置
  Future<void> init() async {
    // 全局只注入一次 AppHttpOverrides
    HttpOverrides.global = AppHttpOverrides();
    await applySettings();
  }

  /// 从存储中读取最新配置并更新到内存，使代理设置能够即时对所有请求生效
  Future<void> applySettings() async {
    final storage = StorageService.instance;
    isProxyEnabled = await storage.loadProxyEnabled();
    proxyHost = await storage.loadProxyHost();
    proxyPort = await storage.loadProxyPort();
    proxyUsername = await storage.loadProxyUsername();
    proxyPassword = await storage.loadProxyPassword();
    bypassLan = await storage.loadProxyBypassLan();
    bypassRules = await storage.loadProxyBypassRules();
  }
}

class AppHttpOverrides extends HttpOverrides {
  AppHttpOverrides();

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context);

    client.findProxy = (uri) {
      final service = ProxyService.instance;
      
      // 1. 若未开启代理或配置为空，直接直连
      if (!service.isProxyEnabled || service.proxyHost.isEmpty || service.proxyPort <= 0) {
        return 'DIRECT';
      }

      // 2. 若开启了绕过机制
      if (service.bypassLan) {
        final hostLower = uri.host.toLowerCase();
        
        // 默认局域网及本地回环直连
        if (hostLower == 'localhost' ||
            hostLower == '127.0.0.1' ||
            hostLower.startsWith('192.168.') ||
            hostLower.startsWith('10.') ||
            hostLower.startsWith('172.16.') ||
            hostLower.startsWith('172.17.') ||
            hostLower.startsWith('172.18.') ||
            hostLower.startsWith('172.19.') ||
            hostLower.startsWith('172.20.') ||
            hostLower.startsWith('172.21.') ||
            hostLower.startsWith('172.22.') ||
            hostLower.startsWith('172.23.') ||
            hostLower.startsWith('172.24.') ||
            hostLower.startsWith('172.25.') ||
            hostLower.startsWith('172.26.') ||
            hostLower.startsWith('172.27.') ||
            hostLower.startsWith('172.28.') ||
            hostLower.startsWith('172.29.') ||
            hostLower.startsWith('172.30.') ||
            hostLower.startsWith('172.31.')) {
          return 'DIRECT';
        }

        // 自定义规则白名单直连
        for (final rule in service.bypassRules) {
          if (_matchesRule(uri.host, rule)) {
            return 'DIRECT';
          }
        }
      }
      
      return 'PROXY ${service.proxyHost}:${service.proxyPort}';
    };

    client.authenticateProxy = (h, p, s, r) {
      final service = ProxyService.instance;
      if (service.isProxyEnabled &&
          service.proxyUsername.isNotEmpty &&
          service.proxyPassword.isNotEmpty) {
        client.addProxyCredentials(
          h,
          p,
          r ?? '',
          HttpClientBasicCredentials(service.proxyUsername, service.proxyPassword),
        );
        return Future.value(true);
      }
      return Future.value(false);
    };

    return client;
  }

  /// 匹配规则助手：支持精确匹配和通配符模糊匹配
  bool _matchesRule(String host, String rule) {
    final cleanRule = rule.trim().toLowerCase();
    final cleanHost = host.toLowerCase();

    if (cleanRule.isEmpty) return false;

    // 通配符模糊匹配，如将 *.local 转换为正则 ^.*\.local$
    if (cleanRule.contains('*')) {
      final cleanPattern = cleanRule.replaceAll('.', '\\.').replaceAll('*', '.*');
      final pattern = '^$cleanPattern\$';
      try {
        final regex = RegExp(pattern);
        return regex.hasMatch(cleanHost);
      } catch (_) {
        // 正则报错时，退化为简单的后缀判定
        return cleanHost.endsWith(cleanRule.replaceAll('*', ''));
      }
    }

    return cleanHost == cleanRule;
  }
}
