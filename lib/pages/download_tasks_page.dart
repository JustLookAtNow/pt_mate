import 'package:flutter/material.dart';
import 'dart:async';
import '../services/storage/storage_service.dart';
import '../services/downloader/downloader_config.dart';
import '../services/downloader/downloader_factory.dart';
import '../services/downloader/downloader_models.dart';
import '../utils/format.dart';

import '../widgets/responsive_layout.dart';
import '../widgets/qb_speed_indicator.dart';
import 'downloader_settings_page.dart';

class DownloadTasksPage extends StatefulWidget {
  const DownloadTasksPage({super.key});

  @override
  State<DownloadTasksPage> createState() => _DownloadTasksPageState();
}

class _DownloadTasksPageState extends State<DownloadTasksPage> {
  Timer? _refreshTimer;
  
  // 状态变量
  bool _isLoading = true;
 String? _errorMessage;
  List<DownloadTask> _tasks = [];
  DownloaderConfig? _downloaderConfig;
  String? _password;
  


  @override
  void initState() {
    super.initState();
    _loadQbConfig();
    _startAutoRefresh();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
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
  Future<void> _loadQbConfig() async {
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
      final client = DownloaderFactory.createClient(
        config: _downloaderConfig!,
        password: _password!,
      );
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
                                '未配置qBittorrent',
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
      final client = DownloaderFactory.createClient(
        config: _downloaderConfig!,
        password: _password!,
      );
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
      final client = DownloaderFactory.createClient(
        config: _downloaderConfig!,
        password: _password!,
      );
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
      final client = DownloaderFactory.createClient(
        config: _downloaderConfig!,
        password: _password!,
      );
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

  Widget _buildAllTasksList() {
    // 过滤只显示这三种状态的任务
    final filteredTasks = _tasks.where((task) => 
      task.state == DownloadTaskState.downloading || 
      task.state == DownloadTaskState.pausedDL ||
      task.state == DownloadTaskState.stalledDL ||
      task.state == DownloadTaskState.stoppedDL 
    ).toList();
    
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
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 第一排：名称（粗体）和控制按钮
            Row(
              children: [
                Expanded(
                  child: Text(
                    task.name,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  icon: Icon(
                    isPaused ? Icons.play_arrow : Icons.pause,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  constraints: const BoxConstraints(
                    minWidth: 36,
                    minHeight: 36,
                  ),
                  padding: EdgeInsets.zero,
                  onPressed: () {
                    if (isPaused) {
                      _resumeTask(task.hash);
                    } else {
                      _pauseTask(task.hash);
                    }
                  },
                ),
                IconButton(
                  icon: const Icon(
                    Icons.delete,
                    color: Colors.red,
                  ),
                  constraints: const BoxConstraints(
                    minWidth: 36,
                    minHeight: 36,
                  ),
                  padding: EdgeInsets.zero,
                  onPressed: () {
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
                            style: TextButton.styleFrom(
                              side: BorderSide(
                                color: Theme.of(context).colorScheme.outline,
                                width: 1.0,
                              ),
                            ),
                            child: const Text('仅任务'),
                          ),
                          TextButton(
                            onPressed: () {
                              Navigator.of(context).pop();
                              _deleteTask(task.hash, true);
                            },
                            style: TextButton.styleFrom(
                              side: BorderSide(
                                color: Theme.of(context).colorScheme.error,
                                width: 1.0,
                              ),
                            ),
                            child: Text('同时删除文件',
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ],
            ),
            
            // 第二排：分类和标签
            if (task.category.isNotEmpty || task.tags.isNotEmpty)
              Row(
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
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.onPrimaryContainer,
                        ),
                      ),
                    ),
                  if (task.category.isNotEmpty && task.tags.isNotEmpty)
                    const SizedBox(width: 8),
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
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.onSecondaryContainer,
                        ),
                      ),
                    ),
                  )),
                ],
              ),
            
            const SizedBox(height: 4),
            
            // 第三排：大小和速度
            Row(
              children: [
                Text(
                  '大小: ${FormatUtil.formatFileSize(task.size)}',
                  style: const TextStyle(fontSize: 12),
                ),
                const SizedBox(width: 16),
                if (isDownloading) ...[                  
                  Text(
                    '↓ ${FormatUtil.formatSpeed(task.dlspeed)}',
                    style: const TextStyle(fontSize: 12),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '↑ ${FormatUtil.formatSpeed(task.upspeed)}',
                    style: const TextStyle(fontSize: 12),
                  ),
                  const Spacer(),
                  Text(
                    '剩余: ${FormatUtil.formatEta(task.eta)}',
                    style: const TextStyle(fontSize: 12),
                  ),
                ],
              ],
            ),
            
            const SizedBox(height: 4),
            
            // 第四排：进度条
            Row(
              children: [
                Expanded(
                  child: LinearProgressIndicator(
                    value: task.progress,
                    backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      isDownloading 
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).colorScheme.secondary,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${(task.progress * 100).toStringAsFixed(1)}%',
                  style: const TextStyle(fontSize: 12),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}