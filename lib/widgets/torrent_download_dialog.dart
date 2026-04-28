import 'package:flutter/material.dart';
import '../services/storage/storage_service.dart';
import '../services/downloader/downloader_config.dart';
import '../services/downloader/downloader_service.dart';
import '../pages/downloader_settings_page.dart';

class TorrentDownloadDialog extends StatefulWidget {
  final String? torrentName;
  final String? downloadUrl;
  final int? itemCount; // 批量下载时的项目数量
  final bool? isGazelleSite;

  const TorrentDownloadDialog({
    super.key,
    this.torrentName,
    this.downloadUrl,
    this.itemCount,
    this.isGazelleSite,
  });

  @override
  State<TorrentDownloadDialog> createState() => _TorrentDownloadDialogState();
}

class _TorrentDownloadDialogState extends State<TorrentDownloadDialog> {
  List<DownloaderConfig> _clients = [];
  DownloaderConfig? _selectedClient;
  String? _selectedCategory;
  final List<String> _selectedTags = [];
  final _savePathCtrl = TextEditingController();

  List<String> _categories = [];
  List<String> _tags = [];
  List<String> _paths = [];
  bool _loading = false;
  String? _error;
  bool _startPaused = false; // 不立即开始（添加后暂停）
  bool _useToken = false; // Gazelle类型站点使用FL Token选项
  bool _downloadToLocal = false; // 是否下载到本地

  @override
  void initState() {
    super.initState();
    _loadClients();
  }

  @override
  void dispose() {
    _savePathCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadClients() async {
    try {
      final clientsData = await StorageService.instance.loadDownloaderConfigs();
      final defaultId = await StorageService.instance.loadDefaultDownloaderId();
      final startPaused = await StorageService.instance.loadDefaultDownloadStartPaused();

      final clients = clientsData.map((data) => DownloaderConfig.fromJson(data)).toList();

      if (mounted) {
        setState(() {
          _clients = clients;
          _selectedClient = clients.isNotEmpty
              ? clients.firstWhere(
                  (c) => c.id == defaultId,
                  orElse: () => clients.first,
                )
              : null;
          _startPaused = startPaused;
        });

        if (_selectedClient != null) {
          _loadCategoriesTagsAndPaths();
        }
      }
    } catch (e) {
      if (mounted) setState(() => _error = '加载下载器列表失败：$e');
    }
  }

  Future<void> _loadCategoriesTagsAndPaths() async {
    if (_selectedClient == null) return;

    setState(() => _loading = true);
    try {
      // 优先读取缓存
      final cachedCategories = await StorageService.instance.loadDownloaderCategories(
        _selectedClient!.id,
      );
      final cachedTags = await StorageService.instance.loadDownloaderTags(
        _selectedClient!.id,
      );
      final cachedPaths = await StorageService.instance.loadDownloaderPaths(
        _selectedClient!.id,
      );

      if (mounted) {
        setState(() {
          _categories = cachedCategories;
          _tags = cachedTags;
          _paths = cachedPaths;
        });
      }

      // 只有缓存为空时才刷新
      if (cachedCategories.isEmpty ||
          cachedTags.isEmpty ||
          cachedPaths.isEmpty) {
        await _refreshCategoriesTagsAndPaths();
      }
    } catch (e) {
      if (mounted) setState(() => _error = '加载分类标签路径失败：$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _refreshCategoriesTagsAndPaths() async {
    if (_selectedClient == null) return;

    try {
      String? password = await StorageService.instance.loadDownloaderPassword(
        _selectedClient!.id,
      );

      if (password == null || password.isEmpty) {
        password = await _promptPassword(_selectedClient!.name);
        if (password == null) return;
      }

      // 使用统一的下载器服务
      final categories = await DownloaderService.instance.getCategories(
        config: _selectedClient!,
        password: password,
      );
      final tags = await DownloaderService.instance.getTags(
        config: _selectedClient!,
        password: password,
      );
      final paths = await DownloaderService.instance.getPaths(
        config: _selectedClient!,
        password: password,
      );

      // 保存到缓存
      await StorageService.instance.saveDownloaderCategories(
        _selectedClient!.id,
        categories,
      );
      await StorageService.instance.saveDownloaderTags(_selectedClient!.id, tags);
      await StorageService.instance.saveDownloaderPaths(
        _selectedClient!.id,
        paths,
      );

      if (mounted) {
        setState(() {
          _categories = categories;
          _tags = tags;
          _paths = paths;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = '刷新分类标签路径失败：$e');
    }
  }

  Future<String?> _promptPassword(String clientName) async {
    return await PasswordPromptDialog.show(context, clientName);
  }

  Future<void> _onSubmit() async {
    // 本地下载模式：直接返回，不需要选择下载器
    if (_downloadToLocal) {
      if (!mounted) return;
      Navigator.pop(context, {
        'downloadToLocal': true,
        'clientConfig': null,
        'password': null,
        'category': null,
        'tags': null,
        'savePath': null,
        'autoTMM': null,
        'startPaused': null,
        'useToken': null,
      });
      return;
    }

    // 远程下载器模式：需要选择下载器
    if (_selectedClient == null) {
      setState(() => _error = '请选择下载器');
      return;
    }

    String? password = await StorageService.instance.loadDownloaderPassword(
      _selectedClient!.id,
    );
    if (password == null || password.isEmpty) {
      if (!mounted) return;
      password = await _promptPassword(_selectedClient!.name);
      if (password == null) return;
    }

    // 只有选择了分类才强制启用自动管理；未选择分类时不传该参数，遵循服务器默认
    final bool? autoTMM =
        (_selectedCategory != null && _selectedCategory!.isNotEmpty)
        ? true
        : null;

    if (!mounted) return;
    Navigator.pop(context, {
      'downloadToLocal': false,
      'clientConfig': _selectedClient!,
      'password': password,
      'category': _selectedCategory,
      'tags': _selectedTags.isEmpty ? null : _selectedTags,
      'savePath': _savePathCtrl.text.trim().isEmpty
          ? null
          : _savePathCtrl.text.trim(),
      'autoTMM': autoTMM,
      'startPaused': _startPaused,
      'useToken': _useToken,
    });
  }

  @override
  Widget build(BuildContext context) {
    final isBatchMode = widget.itemCount != null;
    final title = isBatchMode
        ? '批量下载设置 (${widget.itemCount}个项目)'
        : '下载种子';

    return AlertDialog(
      title: Text(title),
      scrollable: true,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      content: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: SizedBox(
          width: 400,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!isBatchMode && widget.torrentName != null) ...[
                  Text('种子：${widget.torrentName}', style: const TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                ],
                const SizedBox(height: 8),
                if (_error != null)
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(_error!, style: const TextStyle(color: Colors.red)),
                  )
                else if (_clients.isEmpty)
                  const Text('未配置下载器，请先添加下载器配置')
                else
                  _buildForm(),
              ],
            ),
          ),
        ),
      ),
      actions: [
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
        if (_downloadToLocal)
          FilledButton(
            onPressed: _onSubmit,
            child: Text(isBatchMode ? '批量下载到本地' : '下载到本地'),
          )
        else if (_clients.isNotEmpty && _selectedClient != null)
          FilledButton(
            onPressed: _onSubmit,
            child: Text(isBatchMode ? '开始批量下载' : '开始下载'),
          ),
      ],
    );
  }

  Widget _buildForm() {
    final isBatchMode = widget.itemCount != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 下载模式选择
        Text('下载方式', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: Theme.of(context).colorScheme.outline),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: () => setState(() => _downloadToLocal = false),
                  borderRadius: const BorderRadius.horizontal(
                    left: Radius.circular(8),
                  ),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: !_downloadToLocal
                          ? Theme.of(context).colorScheme.primaryContainer
                          : null,
                      borderRadius: const BorderRadius.horizontal(
                        left: Radius.circular(7),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.cloud_upload_outlined,
                          size: 20,
                          color: !_downloadToLocal
                              ? Theme.of(context).colorScheme.onPrimaryContainer
                              : Theme.of(context).colorScheme.onSurface,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '发送到下载器',
                          style: TextStyle(
                            color: !_downloadToLocal
                                ? Theme.of(context).colorScheme.onPrimaryContainer
                                : Theme.of(context).colorScheme.onSurface,
                            fontWeight: !_downloadToLocal
                                ? FontWeight.bold
                                : FontWeight.normal,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Container(
                width: 1,
                height: 40,
                color: Theme.of(context).colorScheme.outline,
              ),
              Expanded(
                child: InkWell(
                  onTap: () => setState(() => _downloadToLocal = true),
                  borderRadius: const BorderRadius.horizontal(
                    right: Radius.circular(8),
                  ),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: _downloadToLocal
                          ? Theme.of(context).colorScheme.primaryContainer
                          : null,
                      borderRadius: const BorderRadius.horizontal(
                        right: Radius.circular(7),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.save_outlined,
                          size: 20,
                          color: _downloadToLocal
                              ? Theme.of(context).colorScheme.onPrimaryContainer
                              : Theme.of(context).colorScheme.onSurface,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '下载到本地',
                          style: TextStyle(
                            color: _downloadToLocal
                                ? Theme.of(context).colorScheme.onPrimaryContainer
                                : Theme.of(context).colorScheme.onSurface,
                            fontWeight: _downloadToLocal
                                ? FontWeight.bold
                                : FontWeight.normal,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // 根据下载模式显示不同的内容
        if (_downloadToLocal) ...[
          // 本地下载模式：显示说明
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      size: 20,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '下载说明',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (isBatchMode) ...[
                  Text(
                    '将下载 ${widget.itemCount} 个种子文件到本地设备。',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '点击"批量下载到本地"后，需要选择一个文件夹来保存所有种子文件。',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ] else ...[
                  Text(
                    '将下载种子文件到本地设备。',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '点击"下载到本地"后，可以选择保存位置。',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ] else ...[
          // 远程下载器模式：显示下载器配置表单
          // 下载器选择
          Text('下载器', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          DropdownButtonFormField<DownloaderConfig>(
            initialValue: _selectedClient,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              isDense: true,
            ),
            selectedItemBuilder: (context) {
              return _clients.map((client) {
                final screenWidth = MediaQuery.of(context).size.width;
                // 响应式宽度：手机上限制最大宽度，大屏上基于对话框容器宽度计算
                final maxWidth = screenWidth > 600
                    ? 400.0 * 0.6  // 大屏上使用对话框容器宽度的60%
                    : 240.0;  // 小屏上限制240px

                return SizedBox(
                  width: maxWidth,
                  child: Text(
                    client is QbittorrentConfig
                        ? '${client.name} (${client.host}:${client.port})'
                        : client.name,
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                );
              }).toList();
            },
            items: _clients.map((client) {
              return DropdownMenuItem(
                value: client,
                child: Builder(
                  builder: (context) {
                    final screenWidth = MediaQuery.of(context).size.width;
                    // 响应式宽度：手机上限制最大宽度，大屏上允许更宽
                    final maxWidth = screenWidth > 600
                        ? screenWidth * 0.6  // 大屏上使用60%宽度
                        : 240.0;  // 小屏上限制200px

                    return SizedBox(
                      width: maxWidth,
                      child: Text(
                        client is QbittorrentConfig
                            ? '${client.name} (${client.host}:${client.port})'
                            : client.name,
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    );
                  },
                ),
              );
            }).toList(),
            onChanged: (client) {
              setState(() {
                _selectedClient = client;
                _selectedCategory = null;
                _selectedTags.clear();
              });
              if (client != null) {
                _loadCategoriesTagsAndPaths();
              }
            },
          ),
          const SizedBox(height: 16),

          // 分类选择
          Row(
            children: [
              Expanded(
                child: Text(
                  '分类（选择后使用分类路径）',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              if (_loading)
                const SizedBox(
                  height: 16,
                  width: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              if (!_loading)
                IconButton(
                  onPressed: _refreshCategoriesTagsAndPaths,
                  icon: const Icon(Icons.refresh, size: 20),
                  tooltip: '刷新',
                ),
            ],
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String?>(
            initialValue: _selectedCategory,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              isDense: true,
              hintText: '选择分类（可选）',
            ),
            isExpanded: true,
            items: [
              const DropdownMenuItem<String?>(
                value: null,
                child: Text('不使用分类'),
              ),
              ..._categories.map(
                (cat) => DropdownMenuItem<String?>(
                  value: cat,
                  child: Text(cat, overflow: TextOverflow.ellipsis),
                ),
              ),
            ],
            onChanged: (cat) => setState(() => _selectedCategory = cat),
          ),
          const SizedBox(height: 16),

          // 标签选择
          Text('标签（可选）', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          if (_tags.isNotEmpty)
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: _tags.map((tag) {
                final isSelected = _selectedTags.contains(tag);
                return FilterChip(
                  label: Text(tag),
                  selected: isSelected,
                  onSelected: (selected) {
                    setState(() {
                      if (selected) {
                        _selectedTags.add(tag);
                      } else {
                        _selectedTags.remove(tag);
                      }
                    });
                  },
                );
              }).toList(),
            )
          else
            const Text('暂无可用标签', style: TextStyle(color: Colors.grey)),
          // 保存路径
          const SizedBox(height: 16),
          Text('保存路径（可选）', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _savePathCtrl,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    hintText: '留空使用默认路径',
                    isDense: true,
                  ),
                ),
              ),
              if (_paths.isNotEmpty) ...[
                const SizedBox(width: 8),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.folder_open),
                  tooltip: '选择已有路径',
                  onSelected: (path) {
                    _savePathCtrl.text = path;
                  },
                  itemBuilder: (context) => _paths.map((path) {
                    return PopupMenuItem<String>(
                      value: path,
                      child: Text(
                        path,
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    );
                  }).toList(),
                ),
              ],
            ],
          ),

          const SizedBox(height: 16),
          // 不立即开始（添加后暂停）选项
          Row(
            children: [
              Expanded(
                child: Text('不立即开始（添加后暂停）',
                    style: Theme.of(context).textTheme.titleSmall),
              ),
              Switch(
                value: _startPaused,
                onChanged: (val) async {
                  setState(() => _startPaused = val);
                  // 保存用户偏好以便下次打开默认状态
                  await StorageService.instance.saveDefaultDownloadStartPaused(val);
                },
              ),
            ],
          ),

          // Gazelle类型站点 使用 Token 选项
          if (widget.isGazelleSite == true) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text('使用 FL Token',
                      style: Theme.of(context).textTheme.titleSmall),
                ),
                Switch(
                  value: _useToken,
                  onChanged: (val) {
                    setState(() => _useToken = val);
                  },
                ),
              ],
            ),
          ],
        ],
      ],
    );
  }
}