import 'dart:async';
import 'package:flutter/material.dart';

import '../services/storage/storage_service.dart';
import '../services/downloader/downloader_service.dart';
import '../services/downloader/downloader_config.dart';
import '../services/downloader/downloader_models.dart';
import '../widgets/qb_speed_indicator.dart';
import '../widgets/responsive_layout.dart';
import '../utils/downloader_utils.dart';

class DownloaderSettingsPage extends StatefulWidget {
  const DownloaderSettingsPage({super.key});

  @override
  State<DownloaderSettingsPage> createState() => _DownloaderSettingsPageState();
}

class _DownloaderSettingsPageState extends State<DownloaderSettingsPage> {
  List<DownloaderConfig> _downloaderConfigs = [];
  String? _defaultId;
  bool _loading = true;
  String? _error;



  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final configMaps = await StorageService.instance.loadDownloaderConfigs();
      final configs = configMaps.map((configMap) => DownloaderConfig.fromJson(configMap)).toList();
      final defaultId = await StorageService.instance.loadDefaultDownloaderId();
      if (!mounted) return;
      setState(() {
        _downloaderConfigs = configs;
        _defaultId = defaultId;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '加载失败：$e';
        _loading = false;
      });
    }
  }

  Future<void> _addOrEdit({DownloaderConfig? existing}) async {
    final result = await showDialog<_DownloaderEditorResult>(
      context: context,
      builder: (_) => _DownloaderEditorDialog(existing: existing),
    );
    if (result == null) return;
    try {
      final updated = [..._downloaderConfigs];
      final idx = existing == null
          ? -1
          : updated.indexWhere((c) => c.id == existing.id);
      final cfg = DownloaderConfig.fromJson(result.config);
      if (idx >= 0) {
        updated[idx] = cfg;
      } else {
        updated.add(cfg);
      }
      await StorageService.instance.saveDownloaderConfigs(updated, defaultId: _defaultId);
      if (_defaultId == null && updated.isNotEmpty) {
        setState(() {
          _defaultId = cfg.id;
        });
      }
      if (result.password != null) {
        await StorageService.instance.saveDownloaderPassword(
          cfg.id,
          result.password!,
        );
      }
      
      // 通知配置变更
      DownloaderService.instance.notifyConfigChanged(cfg.id);
      
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '保存失败：$e',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onErrorContainer,
            ),
          ),
          backgroundColor: Theme.of(context).colorScheme.errorContainer,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _delete(DownloaderConfig config) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定要删除下载器"${config.name}"吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            style: TextButton.styleFrom(
              side: BorderSide(
                color: Theme.of(context).colorScheme.outline,
                width: 1.0,
              ),
            ),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      final list = _downloaderConfigs.where((e) => e.id != config.id).toList();
      await StorageService.instance.saveDownloaderConfigs(
        list,
        defaultId: _defaultId == config.id ? null : _defaultId,
      );
      await StorageService.instance.deleteDownloaderPassword(config.id);
      
      // 通知配置变更
      DownloaderService.instance.notifyConfigChanged(config.id);
      
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '删除失败：$e',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onErrorContainer,
            ),
          ),
          backgroundColor: Theme.of(context).colorScheme.errorContainer,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _setDefault(DownloaderConfig config) async {
    try {
      await StorageService.instance.saveDownloaderConfigs(
        _downloaderConfigs,
        defaultId: config.id,
      );
      
      // 通知配置变更
      DownloaderService.instance.notifyConfigChanged(config.id);
      
      setState(() {
        _defaultId = config.id;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '设置失败：$e',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onErrorContainer,
            ),
          ),
          backgroundColor: Theme.of(context).colorScheme.errorContainer,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _testDefault() async {
    if (_defaultId == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(
        content: Text(
          '请先设置默认下载器',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onErrorContainer,
          ),
        ),
        backgroundColor: Theme.of(context).colorScheme.errorContainer,
        behavior: SnackBarBehavior.floating,
      ));
      return;
    }
    final config = _downloaderConfigs.firstWhere((c) => c.id == _defaultId);
    await _test(config);
  }

  Future<void> _test(DownloaderConfig config) async {
    try {
      final pwd = await StorageService.instance.loadDownloaderPassword(config.id);
      if ((pwd ?? '').isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(
          content: Text(
            '请先保存密码',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onErrorContainer,
            ),
          ),
          backgroundColor: Theme.of(context).colorScheme.errorContainer,
          behavior: SnackBarBehavior.floating,
        ));
        return;
      }
      
      // 使用新的下载器服务进行测试
      await DownloaderService.instance.testConnection(
        config: config,
        password: pwd!,
      );
      
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(
                Icons.check_circle,
                color: Theme.of(context).colorScheme.onPrimaryContainer,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '连接成功',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                  ),
                ),
              ),
            ],
          ),
          backgroundColor: Theme.of(context).colorScheme.primaryContainer,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(
                Icons.error_outline,
                color: Theme.of(context).colorScheme.onErrorContainer,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '连接失败：$e',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onErrorContainer,
                  ),
                ),
              ),
            ],
          ),
          backgroundColor: Theme.of(context).colorScheme.errorContainer,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ResponsiveLayout(
      currentRoute: '/downloader_settings',
      appBar: AppBar(
        title: const Text('下载器设置'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            tooltip: '测试默认下载器',
            onPressed: _testDefault,
            icon: const Icon(Icons.wifi_tethering),
          ),
          const QbSpeedIndicator(),
        ],
        backgroundColor: Theme.of(context).brightness == Brightness.light
            ? Theme.of(context).colorScheme.primary
            : Theme.of(context).colorScheme.surface,
        iconTheme: IconThemeData(
          color: Theme.of(context).brightness == Brightness.light
              ? Theme.of(context).colorScheme.onPrimary
              : Theme.of(context).colorScheme.onSurface,
        ),
        titleTextStyle: TextStyle(
          color: Theme.of(context).brightness == Brightness.light
              ? Theme.of(context).colorScheme.onPrimary
              : Theme.of(context).colorScheme.onSurface,
          fontSize: 20,
          fontWeight: FontWeight.w500,
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      _error!,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),
                Expanded(
                  child: RadioGroup<String>(
                    groupValue: _defaultId,
                    onChanged: (String? value) {
                      if (value != null) {
                        final config = _downloaderConfigs.firstWhere(
                          (c) => c.id == value,
                        );
                        _setDefault(config);
                      }
                    },
                    child: ListView.builder(
                      padding: EdgeInsets.zero,
                      itemCount: _downloaderConfigs.length,
                      itemBuilder: (_, i) {
                        final c = _downloaderConfigs[i];
                        String subtitle = c.type.displayName;
                        if (c is QbittorrentConfig) {
                          subtitle = '${c.host}:${c.port} · ${c.username}';
                        } else if (c is TransmissionConfig) {
                          subtitle = '${c.host}:${c.port} · ${c.username}';
                        } else if (c is RuTorrentConfig) {
                          subtitle = '${c.host}:${c.port} · ${c.username}';
                        }
                        return ListTile(
                          dense: true,
                          visualDensity: const VisualDensity(
                            horizontal: -2,
                            vertical: -2,
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 2,
                            vertical: 2,
                          ),
                          minLeadingWidth: 0,
                          leading: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Radio<String>(value: c.id),
                              // const SizedBox(width: 8),
                              DownloaderUtils.getDownloaderIcon(c.type),
                            ],
                          ),
                          title: Text(c.name),
                          subtitle: Text(subtitle),
                          onTap: () => _addOrEdit(existing: c),
                          trailing: Wrap(
                            spacing: 1,
                            children: [
                              IconButton(
                                tooltip: '设置',
                                onPressed: () => _addOrEdit(existing: c),
                                icon: const Icon(Icons.settings),
                                iconSize: 20,
                                style: IconButton.styleFrom(
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                  padding: EdgeInsets.zero,
                                  visualDensity: const VisualDensity(
                                    horizontal: -2,
                                    vertical: -2,
                                  ),
                                ),
                              ),
                              IconButton(
                                tooltip: '删除',
                                onPressed: () => _delete(c),
                                icon: const Icon(Icons.delete_outline),
                                iconSize: 20,
                                style: IconButton.styleFrom(
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                  padding: EdgeInsets.zero,
                                  visualDensity: const VisualDensity(
                                    horizontal: -2,
                                    vertical: -2,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _addOrEdit(),
        icon: const Icon(Icons.add),
        label: const Text('新增下载器'),
      ),
    );
  }
}

// 公共密码提示对话框，供其他页面使用
class PasswordPromptDialog extends StatefulWidget {
  final String name;
  const PasswordPromptDialog({super.key, required this.name});

  @override
  State<PasswordPromptDialog> createState() => _PasswordPromptDialogState();

  // 静态方法，方便其他页面调用
  static Future<String?> show(BuildContext context, String clientName) async {
    return await showDialog<String>(
      context: context,
      builder: (_) => PasswordPromptDialog(name: clientName),
    );
  }
}

class _PasswordPromptDialogState extends State<PasswordPromptDialog> {
  final _pwdCtrl = TextEditingController();

  @override
  void dispose() {
    _pwdCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('输入"${widget.name}"密码'),
      content: TextField(
        controller: _pwdCtrl,
        obscureText: true,
        decoration: const InputDecoration(
          labelText: '密码',
          border: OutlineInputBorder(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          style: TextButton.styleFrom(
            side: BorderSide(
              color: Theme.of(context).colorScheme.outline,
              width: 1.0,
            ),
          ),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _pwdCtrl.text.trim()),
          child: const Text('确定'),
        ),
      ],
    );
  }
}

class _DownloaderEditorResult {
  final Map<String, dynamic> config;
  final String? password;
  _DownloaderEditorResult(this.config, this.password);
}

class _DownloaderEditorDialog extends StatefulWidget {
  final DownloaderConfig? existing;
  const _DownloaderEditorDialog({this.existing});

  @override
  State<_DownloaderEditorDialog> createState() => _DownloaderEditorDialogState();
}

class _DownloaderEditorDialogState extends State<_DownloaderEditorDialog> {
  final _nameCtrl = TextEditingController();
  final _hostCtrl = TextEditingController();
  final _portCtrl = TextEditingController(text: '8080');
  final _userCtrl = TextEditingController();
  final _pwdCtrl = TextEditingController();
  final _scrollController = ScrollController(); // 添加滚动控制器
  bool _testing = false;
  String? _testMsg;
  bool? _testOk;
  bool _useLocalRelay = false; // 本地中转选项状态
  bool _allowSelfSignedCert = false; // 允许自签名证书选项状态
  DownloaderType _selectedType = DownloaderType.qbittorrent; // 选择的下载器类型

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      _nameCtrl.text = e.name;
      _selectedType = e.type;
      _allowSelfSignedCert = e.allowSelfSignedCert;

      if (e is QbittorrentConfig) {
        _hostCtrl.text = e.host;
        _portCtrl.text = e.port.toString();
        _userCtrl.text = e.username;
        _useLocalRelay = e.useLocalRelay;
      } else if (e is TransmissionConfig) {
        _hostCtrl.text = e.host;
        _portCtrl.text = e.port.toString();
        _userCtrl.text = e.username;
        _useLocalRelay = e.useLocalRelay;
      } else if (e is RuTorrentConfig) {
        _hostCtrl.text = e.host;
        _portCtrl.text = e.port.toString();
        _userCtrl.text = e.username;
        _useLocalRelay = e.useLocalRelay;
      }
    } else {
      // 新建配置时，如果是 Transmission 或 ruTorrent 类型，默认开启本地中转
      if (_selectedType == DownloaderType.transmission ||
          _selectedType == DownloaderType.rutorrent) {
        _useLocalRelay = true;
      }
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _hostCtrl.dispose();
    _portCtrl.dispose();
    _userCtrl.dispose();
    _pwdCtrl.dispose();
    super.dispose();
  }



  Future<void> _onSubmit() async {
    final name = _nameCtrl.text.trim();
    final host = _hostCtrl.text.trim();
    final port = int.tryParse(_portCtrl.text.trim());
    final user = _userCtrl.text.trim();
    final pwd = _pwdCtrl.text.trim();
    if (name.isEmpty || host.isEmpty || port == null || user.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请完整填写名称、主机、端口、用户名')));
      return;
    }
    final id =
        widget.existing?.id ?? DateTime.now().millisecondsSinceEpoch.toString();
    final cfg = {
      'id': id,
      'name': name,
      'type': _selectedType.value, // 使用选择的类型
      'config': {
        'host': host,
        'port': port,
        'username': user,
        'useLocalRelay': _useLocalRelay, // 包含本地中转选项
        'allowSelfSignedCert': _allowSelfSignedCert, // 包含自签名证书选项
      },
    };
    
    // 如果密码为空且是编辑现有配置，则尝试从已保存的配置中读取密码
    if (pwd.isEmpty && widget.existing != null) {
      // 获取保存的密码
      final savedPassword = await StorageService.instance.loadDownloaderPassword(id);
      
      // 检查组件是否仍然挂载
      if (!mounted) return;
      
      // 返回结果，使用保存的密码或null
      Navigator.of(context).pop(_DownloaderEditorResult(cfg, savedPassword));
    } else {
      // 无需异步操作，直接返回结果
      Navigator.of(context).pop(_DownloaderEditorResult(cfg, pwd.isEmpty ? null : pwd));
    }
  }

  Future<void> _testConnection() async {
    // 保存当前上下文状态，避免异步操作后直接使用 context
    final name = _nameCtrl.text.trim();
    final host = _hostCtrl.text.trim();
    final port = int.tryParse(_portCtrl.text.trim());
    final user = _userCtrl.text.trim();
    final pwd = _pwdCtrl.text.trim();
    
    // 如果密码为空且是编辑现有配置，则尝试从已保存的配置中读取密码
    String? password = pwd;
    if (pwd.isEmpty && widget.existing != null) {
      final id = widget.existing!.id;
      try {
        password = await StorageService.instance.loadDownloaderPassword(id);
        // 检查组件是否仍然挂载
        if (!mounted) return;
      } catch (e) {
        // 处理密码加载失败的情况
        if (!mounted) return;
        setState(() {
          _testOk = false;
          _testMsg = '加载保存的密码失败';
        });
        return;
      }
    }

    if (name.isEmpty ||
        host.isEmpty ||
        port == null ||
        user.isEmpty ||
        (password?.isEmpty ?? true)) {
      if (!mounted) return;
      setState(() {
        _testOk = false;
        _testMsg = '请完整填写名称、主机、端口、用户名和密码后再测试';
      });
      return;
    }

    setState(() {
      _testing = true;
      _testMsg = null;
    });
    try {
      final cfg = {
        'id': widget.existing?.id ?? 'temp',
        'name': name,
        'type': _selectedType.value,
        'config': {
          'host': host,
          'port': port,
          'username': user,
          'useLocalRelay': _useLocalRelay, // 包含本地中转选项
          'allowSelfSignedCert': _allowSelfSignedCert, // 包含自签名证书选项
        },
      };

      final downloaderConfig = DownloaderConfig.fromJson(cfg);
      await DownloaderService.instance.testConnection(
        config: downloaderConfig,
        password: password!,
      );
      if (!mounted) return;
      setState(() {
        _testOk = true;
        _testMsg = '连接成功';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _testOk = false;
        _testMsg = '连接失败：$e';
      });
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Container(
        width: 420,
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.8,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 标题栏
            Container(
              padding: const EdgeInsets.all(24),
              decoration: const BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: Colors.grey, width: 0.5),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.existing == null ? '新增下载器' : '编辑下载器',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                ],
              ),
            ),
            // 内容区域
            Flexible(
              child: SingleChildScrollView(
                controller: _scrollController, // 使用滚动控制器
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: _nameCtrl,
                      decoration: const InputDecoration(
                        labelText: '名称',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    // 下载器类型选择
                    DropdownButtonFormField<DownloaderType>(
                      initialValue: _selectedType,
                      decoration: const InputDecoration(
                        labelText: '下载器类型',
                        border: OutlineInputBorder(),
                      ),
                      items: DownloaderType.values.map((type) {
                        return DropdownMenuItem<DownloaderType>(
                          value: type,
                          child: Row(
                            children: [
                              DownloaderUtils.getDownloaderIcon(type),
                              const SizedBox(width: 12),
                              Text(type.displayName),
                            ],
                          ),
                        );
                      }).toList(),
                      onChanged: (DownloaderType? newType) {
                        if (newType != null) {
                          setState(() {
                            _selectedType = newType;
                            // 当选择 Transmission 或 ruTorrent 时，自动开启本地中转
                            if (newType == DownloaderType.transmission ||
                                newType == DownloaderType.rutorrent) {
                              _useLocalRelay = true;
                            }
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _hostCtrl,
                      decoration: const InputDecoration(
                        labelText: '主机/IP（可含协议）',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _portCtrl,
                      decoration: const InputDecoration(
                        labelText: '端口',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _userCtrl,
                      decoration: const InputDecoration(
                        labelText: '用户名',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _pwdCtrl,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: '密码（仅用于保存/测试，不会明文入库）',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    // 本地中转选项
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '本地中转',
                                  style: Theme.of(context).textTheme.titleSmall,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _selectedType == DownloaderType.transmission
                                      ? 'Transmission 必须启用本地中转（种子文件需要先下载到本地）'
                                      : _selectedType == DownloaderType.rutorrent
                                      ? 'ruTorrent 必须启用本地中转（种子文件需要先下载到本地）'
                                      : '启用后先下载种子文件到本地，再提交给下载器',
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(color: Colors.grey.shade600),
                                ),
                              ],
                            ),
                          ),
                          Switch(
                            value: _useLocalRelay,
                            onChanged: (_selectedType == DownloaderType.transmission ||
                                    _selectedType == DownloaderType.rutorrent)
                                ? null // Transmission 和 ruTorrent 类型时禁用开关
                                : (value) {
                                    setState(() {
                                      _useLocalRelay = value;
                                    });
                                  },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    // 自签名证书选项
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      '允许自签名证书',
                                      style: Theme.of(context).textTheme.titleSmall,
                                    ),
                                    const SizedBox(width: 8),
                                    Icon(
                                      Icons.warning_amber_rounded,
                                      size: 18,
                                      color: Colors.orange.shade700,
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '警告：启用后将禁用 SSL/TLS 证书验证，可能导致中间人攻击风险。仅在使用自签名证书时启用。',
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(color: Colors.orange.shade700),
                                ),
                              ],
                            ),
                          ),
                          Switch(
                            value: _allowSelfSignedCert,
                            onChanged: (value) {
                              setState(() {
                                _allowSelfSignedCert = value;
                              });
                            },
                          ),
                        ],
                      ),
                    ),
                    if (_testMsg != null) ...[
                      Builder(builder: (context) {
                        // 当测试消息显示时，滚动到底部
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (_scrollController.hasClients) {
                            _scrollController.animateTo(
                              _scrollController.position.maxScrollExtent,
                              duration: const Duration(milliseconds: 300),
                              curve: Curves.easeOut,
                            );
                          }
                        });
                        return const SizedBox(height: 16);
                      }),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: _testOk == true
                              ? Theme.of(context).colorScheme.primaryContainer
                              : Theme.of(context).colorScheme.errorContainer,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: _testOk == true
                                ? Theme.of(context).colorScheme.primary
                                : Theme.of(context).colorScheme.error,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              _testOk == true
                                  ? Icons.check_circle
                                  : Icons.error_outline,
                              size: 18,
                              color: _testOk == true
                                  ? Theme.of(context).colorScheme.primary
                                  : Theme.of(context).colorScheme.error,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _testMsg!,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: _testOk == true
                                      ? Theme.of(
                                          context,
                                        ).colorScheme.onPrimaryContainer
                                      : Theme.of(
                                          context,
                                        ).colorScheme.onErrorContainer,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            // 按钮栏
            Container(
              padding: const EdgeInsets.all(12),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: Colors.grey, width: 0.5)),
              ),
              child: Column(
                children: [
                  // 测试按钮单独一排
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      OutlinedButton.icon(
                        onPressed: _testing ? null : _testConnection,
                        icon: _testing
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.wifi_tethering),
                        label: Text(_testing ? '测试中…' : '测试连接'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // 取消和保存按钮一排
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        style: TextButton.styleFrom(
                          side: BorderSide(
                            color: Theme.of(context).colorScheme.outline,
                            width: 1.0,
                          ),
                        ),
                        child: const Text('取消'),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: _onSubmit,
                        child: const Text('保存'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QbCategoriesTagsDialog extends StatefulWidget {
  final DownloaderConfig config;
  final String password;
  const _QbCategoriesTagsDialog({required this.config, required this.password});

  @override
  State<_QbCategoriesTagsDialog> createState() =>
      _QbCategoriesTagsDialogState();
}

class _QbCategoriesTagsDialogState extends State<_QbCategoriesTagsDialog> {
  List<String> _categories = [];
  List<String> _tags = [];
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadCacheThenRefresh();
  }

  Future<void> _loadCacheThenRefresh() async {
    // 先读取本地缓存，提升首屏体验
    final cachedCats = await StorageService.instance.loadDownloaderCategories(
      widget.config.id,
    );
    final cachedTags = await StorageService.instance.loadDownloaderTags(
      widget.config.id,
    );
    if (mounted) {
      setState(() {
        _categories = cachedCats;
        _tags = cachedTags;
      });
    }
    // 再尝试远程拉取
    await _refresh();
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final cats = await DownloaderService.instance.getCategories(
        config: widget.config,
        password: widget.password,
      );
      final tags = await DownloaderService.instance.getTags(
        config: widget.config,
        password: widget.password,
      );
      if (!mounted) return;
      setState(() {
        _categories = cats;
        _tags = tags;
        _error = null;
      });
      // 成功后写入本地缓存
      await StorageService.instance.saveDownloaderCategories(widget.config.id, cats);
      await StorageService.instance.saveDownloaderTags(widget.config.id, tags);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '拉取失败：$e';
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('分类与标签 - ${widget.config.name}'),
      content: SizedBox(
        width: 400,
        height: 300,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(_error!, style: const TextStyle(color: Colors.red)),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: _refresh,
                      child: const Text('重试'),
                    ),
                  ],
                ),
              )
            : DefaultTabController(
                length: 2,
                child: Column(
                  children: [
                    const TabBar(
                      tabs: [
                        Tab(text: '分类'),
                        Tab(text: '标签'),
                      ],
                    ),
                    Expanded(
                      child: TabBarView(
                        children: [_buildList(_categories), _buildList(_tags)],
                      ),
                    ),
                  ],
                ),
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('关闭'),
        ),
        if (!_loading && _error == null)
          TextButton(onPressed: _refresh, child: const Text('刷新')),
      ],
    );
  }

  Widget _buildList(List<String> items) {
    if (items.isEmpty) {
      return const Center(child: Text('暂无数据'));
    }
    return ListView.builder(
      itemCount: items.length,
      itemBuilder: (context, index) {
        return ListTile(title: Text(items[index]));
      },
    );
  }
}
