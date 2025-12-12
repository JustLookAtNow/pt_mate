import 'package:flutter/material.dart';
import 'dart:async';
import '../services/storage/storage_service.dart';
import '../services/downloader/downloader_config.dart';
import '../services/downloader/downloader_service.dart';
import '../services/downloader/downloader_models.dart';
import '../utils/format.dart';

import '../widgets/responsive_layout.dart';
import '../widgets/qb_speed_indicator.dart';
import 'downloader_settings_page.dart';

enum SortField {
  name,
  dlSpeed,
  upSpeed,
  addedOn,
  completionOn,
  ratio,
  size,
  progress
}

class DownloadTasksPage extends StatefulWidget {
  const DownloadTasksPage({super.key});

  @override
  State<DownloadTasksPage> createState() => _DownloadTasksPageState();
}

class _DownloadTasksPageState extends State<DownloadTasksPage> {
  Timer? _refreshTimer;
  StreamSubscription<String>? _configChangeSubscription;

  // 状态变量
  bool _isLoading = true;
  String? _errorMessage;
  List<DownloadTask> _tasks = [];
  DownloaderConfig? _downloaderConfig;
  String? _password;
  bool _showAllTasks = false; // 控制是否显示全部任务
  String _searchQuery = ''; // 搜索关键词
  final TextEditingController _searchController = TextEditingController();

  // 排序状态
  SortField _sortField = SortField.addedOn;
  bool _sortAscending = false;

  @override
  void initState() {
    super.initState();
    _loadDownloaderConfig();
    _startAutoRefresh();

    // 监听配置变更
    _configChangeSubscription = DownloaderService.instance.configChangeStream.listen((configId) {
      // 当配置发生变更时，重置 client 并重新加载配置
      _resetClient();
      _loadDownloaderConfig();
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _configChangeSubscription?.cancel();
    _searchController.dispose();
    _resetClient(); // 清理 client 实例
    super.dispose();
  }

  // 启动自动刷新
  void _startAutoRefresh() {
    _refreshTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      if (_downloaderConfig != null && _password != null && mounted) {
        _loadTasks(silent: true); // 使用静默模式
      }
    });
  }

  // 加载下载器配置
  Future<void> _loadDownloaderConfig() async {
    try {
      final defId = await StorageService.instance.loadDefaultDownloaderId();
      if (defId == null) {
        setState(() {
          _isLoading = false;
          _downloaderConfig = null;
          _password = null;
          _errorMessage = '未配置下载器';
        });
        return;
      }

      final configs = await StorageService.instance.loadDownloaderConfigs();
      final configMap = configs.firstWhere(
        (e) => e['id'] == defId,
        orElse: () => configs.isNotEmpty ? configs.first : throw Exception('未找到默认下载器'),
      );

      final config = DownloaderConfig.fromJson(configMap);
      final password = await StorageService.instance.loadDownloaderPassword(config.id);
      if ((password ?? '').isEmpty) {
        setState(() {
          _isLoading = false;
          _downloaderConfig = config;
          _password = null;
          _errorMessage = '未保存密码';
        });
        return;
      }

      setState(() {
        _downloaderConfig = config;
        _password = password;
      });

      // 配置更改时重置 client
      _resetClient();

      await _loadTasks();
    } catch (e) {
      setState(() {
        _isLoading = false;
        _downloaderConfig = null;
        _password = null;
        _errorMessage = '加载配置失败: $e';
      });
    }
  }

  // 获取或创建 client 实例
  dynamic _getClient() {
    if (_downloaderConfig == null || _password == null) {
      return null;
    }

    // 使用 DownloaderService 的缓存机制（包含配置更新回调）
    return DownloaderService.instance.getClient(
      config: _downloaderConfig!,
      password: _password!,
    );
  }

  /// 重置客户端
  void _resetClient() {
    // 清除 DownloaderService 中的缓存
    if (_downloaderConfig != null) {
      DownloaderService.instance.clearConfigCache(_downloaderConfig!.id);
    }
  }

  // 加载下载任务
  Future<void> _loadTasks({bool silent = false}) async {
    if (_downloaderConfig == null || _password == null) return;

    if (!silent) {
      setState(() {
        _isLoading = true;
        _errorMessage = '';
      });
    }

    try {
      final client = _getClient();
      if (client == null) return;

      final tasks = await client.getTasks();

      setState(() {
        _tasks = tasks;
        if (!silent) _isLoading = false;
        _errorMessage = null; // 清除错误信息
      });
    } catch (e) {
      // 静默模式下不更新错误状态，避免干扰用户
      if (!silent) {
        setState(() {
          _isLoading = false;
          _errorMessage = '加载任务失败: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ResponsiveLayout(
      currentRoute: '/download_tasks',
      appBar: AppBar(
        title: const Text('下载管理'),
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
        actions: const [QbSpeedIndicator()],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                if (_errorMessage != null && _errorMessage!.isNotEmpty)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    color: _downloaderConfig == null
                        ? Theme.of(context).colorScheme.primaryContainer
                        : Theme.of(context).colorScheme.errorContainer,
                    child: _downloaderConfig == null
                        ? Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                '未配置下载器',
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(width: 12),
                              TextButton(
                                onPressed: () {
                                  Navigator.of(context).push(MaterialPageRoute(
                                    builder: (_) => const DownloaderSettingsPage(),
                                    settings: const RouteSettings(name: '/downloader_settings'),
                                  ));
                                },
                                style: TextButton.styleFrom(
                                  side: BorderSide(
                                    color: Theme.of(context).colorScheme.outline,
                                    width: 1.0,
                                  ),
                                ),
                                child: const Text('去配置'),
                              ),
                            ],
                          )
                        : Text(
                            _errorMessage!,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.onErrorContainer,
                              fontSize: 14,
                            ),
                            textAlign: TextAlign.center,
                          ),
                  ),
                // 搜索和过滤UI
                _buildSearchAndFilterBar(),
                Expanded(
                  child: _buildAllTasksList(),
                ),
              ],
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          _loadTasks();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('刷新任务列表',
              style:TextStyle(
                color: Theme.of(context).colorScheme.onPrimaryContainer,
              )),

              backgroundColor: Theme.of(context).colorScheme.primaryContainer,
              behavior: SnackBarBehavior.floating,
            ),
          );
        },
        child: const Icon(Icons.refresh),
      ),
    );
  }

  // 暂停任务
  Future<void> _pauseTask(String hash) async {
    if (_downloaderConfig == null || _password == null) return;

    try {
      final client = _getClient();
      if (client == null) return;

      await client.pauseTask(hash);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '已暂停',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onPrimaryContainer,
            ),
          ),
          backgroundColor: Theme.of(context).colorScheme.primaryContainer,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '暂停失败: $e',
            style: TextStyle(color: Theme.of(context).colorScheme.onErrorContainer),
          ),
          backgroundColor: Theme.of(context).colorScheme.errorContainer,
        ),
      );
    }
  }

  // 恢复任务
  Future<void> _resumeTask(String hash) async {
    if (_downloaderConfig == null || _password == null) return;

    try {
      final client = _getClient();
      if (client == null) return;

      await client.resumeTask(hash);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '已启动',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onPrimaryContainer,
            ),
          ),
          backgroundColor: Theme.of(context).colorScheme.primaryContainer,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '恢复失败: $e',
            style: TextStyle(color: Theme.of(context).colorScheme.onErrorContainer),
          ),
          backgroundColor: Theme.of(context).colorScheme.errorContainer,
        ),
      );
    }
  }



  // 删除任务
  Future<void> _deleteTask(String hash, bool deleteFiles) async {
    if (_downloaderConfig == null || _password == null) return;

    try {
      final client = _getClient();
      if (client == null) return;

      await client.deleteTask(hash, deleteFiles: deleteFiles);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            deleteFiles ? '已删除任务和文件' : '已删除任务',
            style: TextStyle(color: Theme.of(context).colorScheme.onPrimaryContainer),
          ),
          backgroundColor: Theme.of(context).colorScheme.primaryContainer,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '删除任务失败: $e',
            style: TextStyle(color: Theme.of(context).colorScheme.onErrorContainer),
          ),
          backgroundColor: Theme.of(context).colorScheme.errorContainer,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  // 构建搜索和过滤UI
  Widget _buildSearchAndFilterBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        children: [
          Row(
            children: [
              // 搜索框
              Expanded(
                child: SizedBox(
                  height: 40,
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: '搜索...',
                      prefixIcon: const Icon(Icons.search, size: 20),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 16),
                              onPressed: () {
                                _searchController.clear();
                                setState(() {
                                  _searchQuery = '';
                                });
                              },
                            )
                          : null,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide: BorderSide.none,
                      ),
                      filled: true,
                      fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                      isDense: true,
                    ),
                    style: const TextStyle(fontSize: 14),
                    onChanged: (value) {
                      setState(() {
                        _searchQuery = value;
                      });
                    },
                  ),
                ),
              ),
              const SizedBox(width: 8),

              // 排序按钮
              PopupMenuButton<SortField>(
                icon: const Icon(Icons.sort),
                tooltip: '排序方式',
                initialValue: _sortField,
                onSelected: (SortField value) {
                  setState(() {
                    _sortField = value;
                  });
                },
                itemBuilder: (BuildContext context) => <PopupMenuEntry<SortField>>[
                  const PopupMenuItem<SortField>(
                    value: SortField.addedOn,
                    child: Text('添加时间'),
                  ),
                  const PopupMenuItem<SortField>(
                    value: SortField.completionOn,
                    child: Text('完成时间'),
                  ),
                  const PopupMenuItem<SortField>(
                    value: SortField.dlSpeed,
                    child: Text('下载速度'),
                  ),
                  const PopupMenuItem<SortField>(
                    value: SortField.upSpeed,
                    child: Text('上传速度'),
                  ),
                  const PopupMenuItem<SortField>(
                    value: SortField.ratio,
                    child: Text('分享率'),
                  ),
                  const PopupMenuItem<SortField>(
                    value: SortField.size,
                    child: Text('大小'),
                  ),
                  const PopupMenuItem<SortField>(
                    value: SortField.progress,
                    child: Text('进度'),
                  ),
                  const PopupMenuItem<SortField>(
                    value: SortField.name,
                    child: Text('名称'),
                  ),
                ],
              ),

              // 排序方向
              IconButton(
                icon: Icon(_sortAscending ? Icons.arrow_upward : Icons.arrow_downward),
                tooltip: _sortAscending ? '升序' : '降序',
                onPressed: () {
                  setState(() {
                    _sortAscending = !_sortAscending;
                  });
                },
              ),

              // 过滤切换
              IconButton(
                icon: Icon(_showAllTasks ? Icons.filter_alt_off : Icons.filter_alt),
                tooltip: _showAllTasks ? '显示全部' : '仅显示活跃',
                onPressed: () {
                  setState(() {
                    _showAllTasks = !_showAllTasks;
                  });
                },
              ),
            ],
          ),
        ],
      ),
    );
  }



  Widget _buildAllTasksList() {
    // 首先根据状态过滤任务
    List<DownloadTask> statusFilteredTasks = _showAllTasks
        ? _tasks // 显示全部任务
        : _tasks
              .where(
                (task) =>
                    task.state == DownloadTaskState.downloading ||
                    task.state == DownloadTaskState.uploading ||
                    task.state == DownloadTaskState.pausedDL ||
                    task.state == DownloadTaskState.stalledDL ||
                    task.state == DownloadTaskState.stoppedDL
              )
              .toList(); // 只显示活跃状态的任务

    // 然后根据搜索关键词过滤任务名称
    final filteredTasks = _searchQuery.isEmpty
        ? statusFilteredTasks
        : statusFilteredTasks
              .where((task) => task.name.toLowerCase().contains(_searchQuery.toLowerCase()))
              .toList();

    // 排序
    filteredTasks.sort((a, b) {
      int cmp;
      switch (_sortField) {
        case SortField.name:
          cmp = a.name.compareTo(b.name);
          break;
        case SortField.dlSpeed:
          cmp = a.dlspeed.compareTo(b.dlspeed);
          break;
        case SortField.upSpeed:
          cmp = a.upspeed.compareTo(b.upspeed);
          break;
        case SortField.addedOn:
          cmp = a.addedOn.compareTo(b.addedOn);
          break;
        case SortField.completionOn:
          cmp = a.completionOn.compareTo(b.completionOn);
          break;
        case SortField.ratio:
          cmp = a.ratio.compareTo(b.ratio);
          break;
        case SortField.size:
          cmp = a.size.compareTo(b.size);
          break;
        case SortField.progress:
          cmp = a.progress.compareTo(b.progress);
          break;
      }
      return _sortAscending ? cmp : -cmp;
    });
    
    if (filteredTasks.isEmpty) {
      return const Center(
        child: Text('没有下载任务'),
      );
    }
    
    return RefreshIndicator(
      onRefresh: _loadTasks,
      child: ListView.builder(
        itemCount: filteredTasks.length,
        padding: const EdgeInsets.all(16),
        itemBuilder: (context, index) {
          final task = filteredTasks[index];
          return _buildTaskCard(task);
        },
      ),
    );
  }

  // 确认删除
  void _confirmDelete(DownloadTask task) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除任务'),
        content: const Text('是否同时删除文件？'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              _deleteTask(task.hash, false);
            },
            child: const Text('仅任务'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              _deleteTask(task.hash, true);
            },
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('同时删除文件'),
          ),
        ],
      ),
    );
  }

  Widget _buildTaskCard(DownloadTask task) {
    final bool isDownloading =
      task.state == DownloadTaskState.downloading ||
      task.state == DownloadTaskState.stalledDL ||
      task.state == DownloadTaskState.metaDL ||
      task.state == DownloadTaskState.forcedDL ||
      task.state == DownloadTaskState.queuedDL ||
      task.state == DownloadTaskState.checkingDL ||
      task.state == DownloadTaskState.allocating ||
      task.state == DownloadTaskState.checkingResumeData;
    final bool isPaused =
      task.state == DownloadTaskState.pausedDL ||
      task.state == DownloadTaskState.pausedUP ||
      task.state == DownloadTaskState.queuedUP ||
      task.state == DownloadTaskState.error ||
      task.state == DownloadTaskState.stoppedDL ||
      task.state == DownloadTaskState.missingFiles;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 0, vertical: 4),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant.withOpacity(0.5)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Row: Title and Actions
            Row(
              children: [
                // Title and Info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        task.name,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      // Category and Tags
                      if (task.category.isNotEmpty || task.tags.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Row(
                            children: [
                              if (task.category.isNotEmpty)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Theme.of(context).colorScheme.primaryContainer,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    task.category,
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                                    ),
                                  ),
                                ),
                              if (task.category.isNotEmpty && task.tags.isNotEmpty)
                                const SizedBox(width: 6),
                              ...task.tags.map((tag) => Padding(
                                padding: const EdgeInsets.only(right: 4),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Theme.of(context).colorScheme.secondaryContainer,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    tag,
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: Theme.of(context).colorScheme.onSecondaryContainer,
                                    ),
                                  ),
                                ),
                              )),
                            ],
                          ),
                        ),
                      // Status Info Row 1: Static Info
                      Row(
                        children: [
                          // Size
                          Text(
                            FormatUtil.formatFileSize(task.size),
                            style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.secondary),
                          ),
                          const SizedBox(width: 8),
                          // Uploaded
                          Icon(Icons.upload_file, size: 12, color: Theme.of(context).colorScheme.secondary),
                          const SizedBox(width: 2),
                          Text(
                            FormatUtil.formatFileSize(task.uploaded),
                            style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.secondary),
                          ),
                          const SizedBox(width: 8),
                          // Ratio
                          Icon(Icons.compare_arrows, size: 12, color: Theme.of(context).colorScheme.secondary),
                          const SizedBox(width: 2),
                          Text(
                            task.ratio.toStringAsFixed(2),
                            style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.secondary),
                          ),
                        ],
                      ),

                      // Status Info Row 2: Dynamic Info (Speed & ETA)
                      if (task.dlspeed > 0 || task.upspeed > 0 || (isDownloading && task.eta > 0 && task.eta < 8640000))
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Row(
                            children: [
                              // DL Speed
                              if (task.dlspeed > 0) ...[
                                 const Icon(Icons.download, size: 12, color: Colors.green),
                                 const SizedBox(width: 2),
                                 Text(
                                   FormatUtil.formatSpeed(task.dlspeed),
                                   style: const TextStyle(fontSize: 11, color: Colors.green),
                                 ),
                                 const SizedBox(width: 8),
                              ],
                              // UP Speed
                              if (task.upspeed > 0) ...[
                                 const Icon(Icons.upload, size: 12, color: Colors.blue),
                                 const SizedBox(width: 2),
                                 Text(
                                   FormatUtil.formatSpeed(task.upspeed),
                                   style: const TextStyle(fontSize: 11, color: Colors.blue),
                                 ),
                                 const SizedBox(width: 8),
                              ],
                              // ETA
                              if (isDownloading && task.eta > 0 && task.eta < 8640000) ...[
                                 Icon(Icons.timer, size: 12, color: Theme.of(context).colorScheme.secondary),
                                 const SizedBox(width: 2),
                                 Text(
                                   FormatUtil.formatEta(task.eta),
                                   style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.secondary),
                                 ),
                              ],
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                // Actions
                IconButton(
                  icon: Icon(
                    isPaused ? Icons.play_arrow_rounded : Icons.pause_rounded,
                    size: 20,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  padding: EdgeInsets.zero,
                  onPressed: () => isPaused ? _resumeTask(task.hash) : _pauseTask(task.hash),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 20, color: Colors.red),
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  padding: EdgeInsets.zero,
                  onPressed: () => _confirmDelete(task),
                ),
              ],
            ),

            const SizedBox(height: 6),

            // Progress Bar
            Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(
                      value: task.progress,
                      minHeight: 4,
                      backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        isDownloading
                            ? Theme.of(context).colorScheme.primary
                            : (task.progress >= 1.0 ? Colors.green : Theme.of(context).colorScheme.secondary),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${(task.progress * 100).toStringAsFixed(1)}%',
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}