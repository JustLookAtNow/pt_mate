import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:pt_mate/utils/notification_helper.dart';

class WebLoginWidget extends StatefulWidget {
  final String baseUrl;
  final String? loginPath; // 自定义登录页面路径，默认为 /login.php
  final Function(String cookie) onCookieReceived;
  final VoidCallback? onCancel;

  const WebLoginWidget({
    super.key,
    required this.baseUrl,
    this.loginPath,
    required this.onCookieReceived,
    this.onCancel,
  });

  @override
  State<WebLoginWidget> createState() => _WebLoginWidgetState();
}

class _WebLoginWidgetState extends State<WebLoginWidget> {
  InAppWebViewController? _controller;
  bool _isLoading = true;
  bool _loginSuccess = false;
  String? _errorMessage;
  final Logger _logger = Logger();
  late final String _initialUrl; // 初始登录页URL

  @override
  void initState() {
    super.initState();
    // 构建初始登录页URL
    final baseUrl = widget.baseUrl.endsWith('/')
        ? widget.baseUrl.substring(0, widget.baseUrl.length - 1)
        : widget.baseUrl;
    _initialUrl = '$baseUrl${widget.loginPath ?? '/login.php'}';

    // 强制“洗大澡”：在启动时清除所有相关 Cookie
    _clearAllCookies();
  }

  Future<void> _clearAllCookies() async {
    try {
      if (kDebugMode) {
        _logger.i('正在清空旧 Cookie 以触发 Cloudflare 验证...');
      }
      final cookieManager = CookieManager.instance();
      await cookieManager.deleteAllCookies();
    } catch (e) {
      if (kDebugMode) _logger.e('清理 Cookie 失败: $e');
    }
  }

  Future<void> _checkLoginStatus(String url) async {
    if (kDebugMode) {
      _logger.d('检查登录状态, 当前页面URL: $url');
    }

    // 1. 基本路径检查：处于登录、注册或恢复页面时，直接跳过
    if (url == _initialUrl ||
        url.contains('/login.php') ||
        url.contains('/signup.php') ||
        url.contains('/recover.php') ||
        !url.contains(widget.baseUrl)) {
      return;
    }

    // 2. 深入核实内容 (解决 URL 变了但内容其实是登录表单的情况)
    try {
      if (_controller == null) return;

      final html = await _controller?.getHtml();
      if (html == null || html.isEmpty) return;

      // 检查页面标题
      final titleMatch = RegExp(
        r'<title>(.*?)<\/title>',
        caseSensitive: false,
      ).firstMatch(html);
      final title = titleMatch?.group(1) ?? "";

      // 如果标题包含登录字样，说明尚未成功
      if (title.contains('登錄') ||
          title.contains('Login') ||
          title.contains('Authentication')) {
        if (kDebugMode) {
          _logger.w('虽然 URL 已跳转，但页面标题显示仍处于登录状态: $title');
        }
        return;
      }

      // 检查典型的登录成功标志 (NexusPHP 特有)
      bool hasSuccessIndicator =
          html.contains('userdetails.php') ||
          html.contains('logout.php') ||
          html.contains('控制面板') ||
          html.contains('个人中心');

      if (!hasSuccessIndicator) {
        if (kDebugMode) {
          _logger.w('页面内容中未找到典型的登录成功标志元素 (userdetails/logout)');
        }
        // 对于某些特殊的站点，如果没有成功标志但标题已经变了，我们暂时持保留意见，不立即认定成功
        return;
      }

      if (kDebugMode) {
        _logger.i('检测到登录成功 (标题与内容核实通过)，正在最终提取并清洗 Cookie...');
      }

      // 成功后，最后提取一次
      await _extractCookie();
    } catch (e) {
      _logger.e('检查登录状态时发生异常: $e');
    }
  }

  // 辅助方法：清洗并除重 WebView 内部存储的 Cookie
  Future<void> _sanitizeWebViewCookies(WebUri url) async {
    try {
      final cookieManager = CookieManager.instance();
      final cookies = await cookieManager.getCookies(url: url);

      final Map<String, List<Cookie>> groups = {};
      for (var c in cookies) {
        groups.putIfAbsent(c.name, () => []).add(c);
      }

      bool hasCleaned = false;
      for (var entry in groups.entries) {
        if (entry.value.length > 1) {
          // 只保留最后一项，删除之前的重复项
          for (var i = 0; i < entry.value.length - 1; i++) {
            await cookieManager.deleteCookie(
              url: url,
              name: entry.key,
              domain: entry.value[i].domain,
              path: entry.value[i].path ?? '/',
            );
          }
          hasCleaned = true;
        }
      }
      if (hasCleaned && kDebugMode) {
        _logger.i('已完成同名 Cookie 清洗 (针对 Cloudflare 冗余项)');
      }
    } catch (e) {
      if (kDebugMode) _logger.e('清洗 Cookie 失败: $e');
    }
  }

  // 辅助方法：检查是否存在 Session Cookie
  Future<bool> _hasSessionCookie() async {
    try {
      final cookieManager = CookieManager.instance();
      final cookies = await cookieManager.getCookies(
        url: WebUri(widget.baseUrl),
      );
      // NexusPHP 常见的登录成功标志 Cookie
      return cookies.any(
        (c) =>
            c.name.contains('jwt') ||
            c.name.contains('pass') ||
            c.name.contains('uid') ||
            c.name == 'c_lang_folder', // 有些站只要有这个也就代表过了初步校验
      );
    } catch (e) {
      return false;
    }
  }

  Future<bool> _extractCookie({bool closeAfter = false}) async {
    try {
      if (kDebugMode) {
        _logger.i('开始提取cookie...');
      }

      if (_controller == null) {
        if (kDebugMode) {
          _logger.e('WebView控制器未初始化');
        }
        return false;
      }

      // 等待页面完全加载
      await Future.delayed(const Duration(milliseconds: 1000));

      // 使用flutter_inappwebview的CookieManager获取所有cookie
      final cookieManager = CookieManager.instance();
      final cookies = await cookieManager.getCookies(
        url: WebUri(widget.baseUrl),
      );

      if (kDebugMode) {
        _logger.i('通过CookieManager获取到 ${cookies.length} 个cookie');
      }

      if (cookies.isNotEmpty) {
        // 检查是否有c_lang_folder cookie，没有则添加，有则更新为chs
        bool hasLangFolder = false;
        final updatedCookies = <Cookie>[];

        for (final cookie in cookies) {
          if (cookie.name == 'c_lang_folder') {
            hasLangFolder = true;
            // 更新现有的c_lang_folder为chs
            updatedCookies.add(
              Cookie(
                name: 'c_lang_folder',
                value: 'chs',
                domain: cookie.domain,
                path: cookie.path,
              ),
            );
            if (kDebugMode) {
              _logger.i('更新c_lang_folder cookie为chs');
            }
          } else {
            updatedCookies.add(cookie);
          }
        }

        // 如果没有c_lang_folder，则添加
        if (!hasLangFolder) {
          final langCookie = Cookie(
            name: 'c_lang_folder',
            value: 'chs',
            domain: Uri.parse(widget.baseUrl).host,
            path: '/',
          );
          updatedCookies.add(langCookie);

          // // 设置到CookieManager
          // final cookieManager = CookieManager.instance();
          // await cookieManager.setCookie(
          //   url: WebUri(widget.baseUrl),
          //   name: 'c_lang_folder',
          //   value: 'chs',
          //   domain: Uri.parse(widget.baseUrl).host,
          //   path: '/',
          // );
          // if (kDebugMode) {
          //   _logger.i('添加c_lang_folder cookie为chs');
          // }
        }

        // 将cookie转换为 Map 进行去重
        // 解决某些站点（如带 Cloudflare）在不同域设置多个重复 name cookie 的问题
        final Map<String, String> cookieMap = {};
        for (final cookie in updatedCookies) {
          final name = cookie.name;
          final value = cookie.value.toString();

          if (cookieMap.containsKey(name) && kDebugMode) {
            _logger.w('检测到重复 Cookie [$name], 将使用新值覆盖旧值');
          }
          cookieMap[name] = value;
        }

        // 构建标准 Cookie 字符串
        final cookieStrings = cookieMap.entries
            .map((entry) => '${entry.key}=${entry.value}')
            .toList();
        final cookieString = cookieStrings.join('; ');

        if (kDebugMode) {
          _logger.d('导出 Cookie (去重后共 ${cookieMap.length} 个): $cookieString');
        }

        // 创建包含所有cookie信息的JSON
        final cookieData = {
          'cookies': cookieStrings,
          'cookieString': cookieString,
          'domain': widget.baseUrl,
          'count': updatedCookies.length,
        };

        final cookieJson = cookieData.toString();
        if (kDebugMode) {
          _logger.d('Cookie数据: $cookieJson');
        }

        widget.onCookieReceived(cookieString);
        if (mounted) {
          setState(() {
            _loginSuccess = true;
          });
          if (closeAfter) {
            NotificationHelper.showInfo(
              context,
              'Cookie 获取成功！',
              duration: const Duration(seconds: 3),
            );
            Navigator.of(context).pop();
          } else {
            NotificationHelper.showInfo(
              context,
              'Cookie 获取成功！如有二次验证请继续操作，完成后请手动关闭此页面',
              duration: const Duration(seconds: 5),
            );
          }
        }
        return true;
      }

      if (kDebugMode) {
        _logger.w('CookieManager未获取到cookie');
      }
      if (mounted) {
                NotificationHelper.showInfo(context, '无法获取cookie，请检查登录状态', duration: const Duration(seconds: 3));
      }
      return false;
    } catch (e) {
      if (kDebugMode) {
        _logger.e('提取cookie时出错: $e');
      }
      if (mounted) {
                NotificationHelper.showError(context, 'Cookie提取失败: $e');
      }
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_loginSuccess ? '登录成功 - 请手动关闭' : '网站登录'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          tooltip: '关闭',
          onPressed: () {
            widget.onCancel?.call();
            Navigator.of(context).pop();
          },
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              _controller?.reload();
            },
            tooltip: '刷新页面',
          ),
          IconButton(
            icon: const Icon(Icons.download),
            tooltip: '手动获取Cookie',
            onPressed: () {
              _extractCookie(closeAfter: true);
            },
          ),
        ],
      ),
      body: Column(
        children: [
          if (_isLoading) const LinearProgressIndicator(),
          if (_errorMessage != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              color: Colors.red.shade100,
              child: Text(
                _errorMessage!,
                style: TextStyle(color: Colors.red.shade800),
                textAlign: TextAlign.center,
              ),
            ),
          Expanded(
            child: _errorMessage != null
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.error_outline,
                          size: 64,
                          color: Colors.red.shade400,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          '页面加载失败',
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _errorMessage!,
                          style: Theme.of(context).textTheme.bodyMedium,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: () {
                            setState(() {
                              _errorMessage = null;
                            });
                            _controller?.reload();
                          },
                          child: const Text('重试'),
                        ),
                      ],
                    ),
                  )
                : InAppWebView(
                    initialUrlRequest: URLRequest(
                      url: WebUri(
                        '${widget.baseUrl.endsWith('/') ? widget.baseUrl.substring(0, widget.baseUrl.length - 1) : widget.baseUrl}${widget.loginPath ?? '/login.php'}',
                      ),
                    ),
                    initialSettings: InAppWebViewSettings(
                      javaScriptEnabled: true,
                      domStorageEnabled: true,
                      databaseEnabled: true,
                      // 因为 initState 里已经手动清了，这里保持 false 以便在登录过程中保持 session
                      clearCache: false,
                      clearSessionCache: false,
                      thirdPartyCookiesEnabled: true,
                      supportMultipleWindows: true, // 开启多窗口支持，有时挑战在弹窗中
                      // 彻底关闭拦截功能，减少指纹特征
                      useOnLoadResource: false,
                      useShouldOverrideUrlLoading: false,
                      useOnNavigationResponse: false,
                      useShouldInterceptRequest: false,

                      // 模拟纯净的手机 Chrome (Android 13)
                      userAgent:
                          'Mozilla/5.0 (Linux; Android 13; Pixel 7 Build/TQ3A.230705.001) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
                      preferredContentMode: UserPreferredContentMode.MOBILE,

                      // 允许混合内容
                      mixedContentMode:
                          MixedContentMode.MIXED_CONTENT_ALWAYS_ALLOW,

                      supportZoom: true,
                      forceDark: Theme.of(context).brightness == Brightness.dark
                          ? ForceDark.ON
                          : ForceDark.OFF,
                      algorithmicDarkeningAllowed:
                          Theme.of(context).brightness == Brightness.dark,
                    ),
                    onWebViewCreated: (controller) {
                      _controller = controller;
                    },
                    onLoadStart: (controller, url) async {
                      if (url != null) {
                        // 在请求发起前，清洗一次重复的 Cookie
                        await _sanitizeWebViewCookies(url);
                      }
                      if (mounted) {
                        setState(() {
                          _isLoading = true;
                          _errorMessage = null;
                        });
                      }
                    },
                    onLoadStop: (controller, url) async {
                      if (url == null) return;
                      if (mounted) {
                        setState(() => _isLoading = false);
                      }

                      // 处理同步延迟：如果在 index.php 但内容显示未登录，且已有 session，强制重载
                      if (url.toString().contains('index.php')) {
                        final html = await controller.getHtml() ?? "";
                        if (html.contains('登錄') || html.contains('login.php')) {
                          final hasSession = await _hasSessionCookie();
                          if (hasSession) {
                            debugPrint('🔄 同步 Session 中，即将自动重载...');
                            await controller.reload();
                            return;
                          }
                        }
                      }
                      _checkLoginStatus(url.toString());
                    },
                    onProgressChanged: (controller, progress) {
                      // debugPrint('WebView加载进度: $progress%'); // Removed verbose logging
                    },
                    onReceivedError: (controller, request, error) {
                      debugPrint(
                        'WebView错误: ${error.description}, URL: ${request.url}, isForMainFrame: ${request.isForMainFrame}',
                      );
                      // 只有主页面加载错误才显示错误信息，子资源错误忽略
                      if (request.isForMainFrame == true) {
                        setState(() {
                          _isLoading = false;
                          _errorMessage = '加载失败: ${error.description}';
                        });
                      } else {
                        // 子资源加载失败，只打印日志，不影响页面显示
                        debugPrint('子资源加载失败，忽略: ${request.url}');
                      }
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
