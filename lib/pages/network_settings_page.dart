import 'dart:io';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:pt_mate/utils/notification_helper.dart';
import '../services/storage/storage_service.dart';
import '../services/network/proxy_service.dart';

class NetworkSettingsPage extends StatefulWidget {
  const NetworkSettingsPage({super.key});

  @override
  State<NetworkSettingsPage> createState() => _NetworkSettingsPageState();
}

class _NetworkSettingsPageState extends State<NetworkSettingsPage> {
  final _formKey = GlobalKey<FormState>();
  final _hostController = TextEditingController();
  final _portController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _bypassRulesController = TextEditingController();

  bool _proxyEnabled = false;
  bool _bypassLan = true;
  bool _isLoading = true;
  bool _isTesting = false;
  bool _obscurePassword = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _hostController.dispose();
    _portController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _bypassRulesController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    try {
      final storage = StorageService.instance;
      final enabled = await storage.loadProxyEnabled();
      final host = await storage.loadProxyHost();
      final port = await storage.loadProxyPort();
      final username = await storage.loadProxyUsername();
      final password = await storage.loadProxyPassword();
      final bypassLan = await storage.loadProxyBypassLan();
      final rules = await storage.loadProxyBypassRules();

      if (mounted) {
        setState(() {
          _proxyEnabled = enabled;
          _hostController.text = host;
          _portController.text = host.isEmpty ? '' : port.toString();
          _usernameController.text = username;
          _passwordController.text = password;
          _bypassLan = bypassLan;
          _bypassRulesController.text = rules.join('\n');
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        NotificationHelper.showError(context, '加载网络代理设置失败：$e');
      }
    }
  }

  Future<void> _testConnection() async {
    final host = _hostController.text.trim();
    final portStr = _portController.text.trim();

    if (host.isEmpty) {
      NotificationHelper.showError(context, '请先填写服务器地址');
      return;
    }
    if (portStr.isEmpty) {
      NotificationHelper.showError(context, '请先填写端口号');
      return;
    }

    final port = int.tryParse(portStr);
    if (port == null || port <= 0 || port > 65535) {
      NotificationHelper.showError(context, '请输入合法的端口号 (1-65535)');
      return;
    }

    setState(() {
      _isTesting = true;
    });

    try {
      final testDio = Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 5),
        receiveTimeout: const Duration(seconds: 5),
      ));

      final testUsername = _usernameController.text.trim();
      final testPassword = _passwordController.text;

      testDio.httpClientAdapter = IOHttpClientAdapter(
        createHttpClient: () {
          final client = HttpClient();
          client.findProxy = (uri) {
            return 'PROXY $host:$port';
          };
          if (testUsername.isNotEmpty && testPassword.isNotEmpty) {
            client.authenticateProxy = (h, p, s, r) {
              client.addProxyCredentials(
                h,
                p,
                r ?? '',
                HttpClientBasicCredentials(testUsername, testPassword),
              );
              return Future.value(true);
            };
          }
          client.badCertificateCallback = (cert, host, port) => true;
          return client;
        },
      );

      // 请求一个可靠的公网域名进行连通性测试 (例如 GitHub)
      final response = await testDio.get('https://github.com');
      if (response.statusCode == 200 ||
          response.statusCode == 301 ||
          response.statusCode == 302) {
        if (mounted) {
          NotificationHelper.showSuccess(context, '连接测试成功！可通过代理访问目标网络。');
        }
      } else {
        if (mounted) {
          NotificationHelper.showError(
              context, '连接测试异常：HTTP 状态码 ${response.statusCode}');
        }
      }
    } catch (e) {
      if (mounted) {
        NotificationHelper.showError(context, '连接测试失败：$e');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isTesting = false;
        });
      }
    }
  }

  Future<void> _saveSettings() async {
    if (_proxyEnabled) {
      if (!_formKey.currentState!.validate()) {
        return;
      }
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final storage = StorageService.instance;
      await storage.saveProxyEnabled(_proxyEnabled);
      await storage.saveProxyHost(_hostController.text.trim());
      
      final portVal = int.tryParse(_portController.text.trim()) ?? 7890;
      await storage.saveProxyPort(portVal);
      await storage.saveProxyUsername(_usernameController.text.trim());
      await storage.saveProxyPassword(_passwordController.text);
      await storage.saveProxyBypassLan(_bypassLan);

      // 解析多行白名单绕过规则
      final rules = _bypassRulesController.text
          .split('\n')
          .map((r) => r.trim())
          .where((r) => r.isNotEmpty)
          .toList();
      await storage.saveProxyBypassRules(rules);

      // 应用并更新全局 HttpOverrides
      await ProxyService.instance.applySettings();

      if (mounted) {
        NotificationHelper.showSuccess(context, '保存成功！');
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        NotificationHelper.showError(context, '保存网络代理设置失败：$e');
      }
    }
  }

  Widget _buildInfoCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          children: [
            Icon(
              Icons.info_outline,
              size: 32,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '网络代理配置说明',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '配置全局网络代理可帮助您解决部分 PT 站点因地区或运营商网络限制导致的直接访问超时或失败问题。仅支持标准 HTTP/HTTPS 代理。',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('网络代理设置')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('网络代理设置'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16.0),
          children: [
            _buildInfoCard(),
            const SizedBox(height: 16),
            Card(
              child: Column(
                children: [
                  SwitchListTile(
                    secondary: const Icon(Icons.network_ping),
                    title: const Text('启用网络代理'),
                    subtitle: const Text('对所有站点及 WebDAV 连接启用全局代理'),
                    value: _proxyEnabled,
                    onChanged: (val) {
                      setState(() {
                        _proxyEnabled = val;
                      });
                    },
                  ),
                ],
              ),
            ),
            if (_proxyEnabled) ...[
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        '代理服务器设置',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 3,
                            child: TextFormField(
                              controller: _hostController,
                              decoration: const InputDecoration(
                                labelText: '服务器地址',
                                hintText: '例如 127.0.0.1 或 proxy.com',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                              validator: (val) {
                                if (val == null || val.trim().isEmpty) {
                                  return '地址不能为空';
                                }
                                return null;
                              },
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 1,
                            child: TextFormField(
                              controller: _portController,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: '端口',
                                hintText: '7890',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                              validator: (val) {
                                if (val == null || val.trim().isEmpty) {
                                  return '端口不能为空';
                                }
                                final p = int.tryParse(val.trim());
                                if (p == null || p <= 0 || p > 65535) {
                                  return '非法端口';
                                }
                                return null;
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _usernameController,
                        decoration: const InputDecoration(
                          labelText: '用户名 (可选)',
                          hintText: '仅在代理需要身份验证时填写',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _passwordController,
                        obscureText: _obscurePassword,
                        decoration: InputDecoration(
                          labelText: '密码 (可选)',
                          hintText: '仅在代理需要身份验证时填写',
                          border: const OutlineInputBorder(),
                          isDense: true,
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscurePassword
                                  ? Icons.visibility_off
                                  : Icons.visibility,
                            ),
                            onPressed: () {
                              setState(() {
                                _obscurePassword = !_obscurePassword;
                              });
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Card(
                child: Column(
                  children: [
                    SwitchListTile(
                      secondary: const Icon(Icons.settings_ethernet),
                      title: const Text('绕过局域网段与自定义规则'),
                      subtitle: const Text('对局域网及以下白名单中的流量使用直连模式'),
                      value: _bypassLan,
                      onChanged: (val) {
                        setState(() {
                          _bypassLan = val;
                        });
                      },
                    ),
                    if (_bypassLan) ...[
                      const Divider(height: 1),
                      Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              '自定义绕过白名单 (每行一条规则)',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '默认已绕过 localhost, 127.0.0.1 极其余标准局域网 IP段。您可在下方输入自定义绕过域名或 IP (支持通配符 "*")：',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  ),
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: _bypassRulesController,
                              maxLines: 4,
                              decoration: const InputDecoration(
                                hintText: '例如:\n*.local\nmyvps-tracker.com\n10.20.*',
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
            const SizedBox(height: 24),
            Row(
              children: [
                if (_proxyEnabled) ...[
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _isTesting ? null : _testConnection,
                      icon: _isTesting
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                              ),
                            )
                          : const Icon(Icons.network_check),
                      label: const Text('测试连接'),
                    ),
                  ),
                  const SizedBox(width: 16),
                ],
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: TextButton.styleFrom(
                    side: BorderSide(
                      color: Theme.of(context).colorScheme.outline,
                      width: 1.0,
                    ),
                  ),
                  child: const Text('取消'),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: FilledButton(
                    onPressed: _isTesting ? null : _saveSettings,
                    child: const Text('保存配置'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
