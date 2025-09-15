import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

class NexusPhpWebLogin extends StatefulWidget {
  final String baseUrl;
  final Function(String cookie) onCookieReceived;
  final VoidCallback? onCancel;

  const NexusPhpWebLogin({
    super.key,
    required this.baseUrl,
    required this.onCookieReceived,
    this.onCancel,
  });

  @override
  State<NexusPhpWebLogin> createState() => _NexusPhpWebLoginState();
}

class _NexusPhpWebLoginState extends State<NexusPhpWebLogin> {
  InAppWebViewController? _controller;
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
  }

  Future<void> _checkLoginStatus(String url) async {
    debugPrint('当前页面URL: $url'); // 调试信息

    // 检查是否已经登录成功（通常登录成功后会跳转到首页或其他页面）
    if (url.contains('/index.php') ||
        url.contains('/torrents.php') ||
        url.contains('/usercp.php') ||
        url.contains('/browse.php') ||
        url.contains('/upload.php') ||
        (!url.contains('/login.php') &&
            !url.contains('/signup.php') &&
            !url.contains('/recover.php') &&
            url.contains(widget.baseUrl))) {
      debugPrint('检测到登录成功，开始获取cookie'); // 调试信息
      // 获取cookie
      await _extractCookie();
    }
  }

  Future<void> _extractCookie() async {
    try {
      debugPrint('开始提取cookie...');

      if (_controller == null) {
        debugPrint('WebView控制器未初始化');
        return;
      }

      // 等待页面完全加载
      await Future.delayed(const Duration(milliseconds: 1000));

      // 使用flutter_inappwebview的CookieManager获取所有cookie
      final cookieManager = CookieManager.instance();
      final cookies = await cookieManager.getCookies(
        url: WebUri(widget.baseUrl),
      );

      debugPrint('通过CookieManager获取到 ${cookies.length} 个cookie');

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
            debugPrint('更新c_lang_folder cookie为chs');
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

          // 设置到CookieManager
          final cookieManager = CookieManager.instance();
          await cookieManager.setCookie(
            url: WebUri(widget.baseUrl),
            name: 'c_lang_folder',
            value: 'chs',
            domain: Uri.parse(widget.baseUrl).host,
            path: '/',
          );
          debugPrint('添加c_lang_folder cookie为chs');
        }

        // 将cookie转换为标准格式
        final cookieStrings = updatedCookies
            .map((cookie) => '${cookie.name}=${cookie.value}')
            .toList();
        final cookieString = cookieStrings.join('; ');

        debugPrint('获取到的cookie: $cookieString');

        // 创建包含所有cookie信息的JSON
        final cookieData = {
          'cookies': cookieStrings,
          'cookieString': cookieString,
          'domain': widget.baseUrl,
          'count': updatedCookies.length,
        };

        final cookieJson = cookieData.toString();
        debugPrint('Cookie数据: $cookieJson');

        widget.onCookieReceived(cookieString);
        if (mounted) {
          Navigator.of(context).pop();
        }
        return;
      }

      debugPrint('CookieManager未获取到cookie');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('无法获取cookie，请检查登录状态'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      debugPrint('提取cookie时出错: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Cookie提取失败: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('网站登录'),
        leading: IconButton(
          icon: const Icon(Icons.close),
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
              _extractCookie();
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
                        '${widget.baseUrl.endsWith('/') ? widget.baseUrl.substring(0, widget.baseUrl.length - 1) : widget.baseUrl}/login.php',
                      ),
                    ),
                    initialSettings: InAppWebViewSettings(
                      javaScriptEnabled: true,
                      domStorageEnabled: true,
                      databaseEnabled: true,
                      clearCache: false,
                      thirdPartyCookiesEnabled: true,
                      supportMultipleWindows: false,
                      useOnDownloadStart: false,
                      useOnLoadResource: false,
                      useShouldOverrideUrlLoading: false,
                    ),
                    onWebViewCreated: (controller) {
                      _controller = controller;
                      debugPrint('InAppWebView创建完成');
                    },
                    onLoadStart: (controller, url) {
                      debugPrint('开始加载页面: $url');
                      setState(() {
                        _isLoading = true;
                        _errorMessage = null;
                      });
                    },
                    onLoadStop: (controller, url) {
                      debugPrint('页面加载完成: $url');
                      setState(() {
                        _isLoading = false;
                      });
                      if (url != null) {
                        _checkLoginStatus(url.toString());
                      }
                    },
                    onProgressChanged: (controller, progress) {
                      debugPrint('WebView加载进度: $progress%');
                    },
                    onReceivedError: (controller, request, error) {
                      debugPrint('WebView错误: ${error.description}, URL: ${request.url}, isForMainFrame: ${request.isForMainFrame}');
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
