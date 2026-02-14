import 'dart:io';
import 'package:flutter/material.dart';
import '../services/backup_service.dart';
import '../services/storage/storage_service.dart';
import '../services/webdav_service.dart';
import '../models/app_models.dart';

class BackupRestorePage extends StatefulWidget {
  const BackupRestorePage({super.key});

  @override
  State<BackupRestorePage> createState() => _BackupRestorePageState();
}

class _BackupRestorePageState extends State<BackupRestorePage> {
  late final BackupService _backupService;
  late final WebDAVService _webdavService;
  bool _isLoading = false;
  String? _statusMessage;
  bool _isError = false;

  // WebDAV相关状态
  WebDAVConfig? _selectedConfig;
  bool _isWebDAVLoading = false;
  String? _webdavStatusMessage;
  bool _isWebDAVError = false;

  @override
  void initState() {
    super.initState();
    _backupService = BackupService(StorageService.instance);
    _webdavService = WebDAVService.instance;
    _loadWebDAVConfigs();
  }

  // 加载WebDAV配置
  Future<void> _loadWebDAVConfigs() async {
    try {
      final currentConfig = await _webdavService.loadConfig();
      setState(() {
        _selectedConfig = currentConfig;
      });
    } catch (e) {
      _showWebDAVMessage('加载WebDAV配置失败: $e', isError: true);
    }
  }

  void _showMessage(String message, {bool isError = false}) {
    setState(() {
      _statusMessage = message;
      _isError = isError;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: TextStyle(
            color: isError
                ? Theme.of(context).colorScheme.onErrorContainer
                : Theme.of(context).colorScheme.onPrimaryContainer,
          ),
        ),
        backgroundColor: isError
            ? Theme.of(context).colorScheme.errorContainer
            : Theme.of(context).colorScheme.primaryContainer,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _showWebDAVMessage(String message, {bool isError = false}) {
    if (!mounted) return;

    setState(() {
      _webdavStatusMessage = message;
      _isWebDAVError = isError;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: TextStyle(
            color: isError
                ? Theme.of(context).colorScheme.onErrorContainer
                : Theme.of(context).colorScheme.onPrimaryContainer,
          ),
        ),
        backgroundColor: isError
            ? Theme.of(context).colorScheme.errorContainer
            : Theme.of(context).colorScheme.primaryContainer,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Future<void> _exportBackup() async {
    setState(() {
      _isLoading = true;
      _statusMessage = '正在创建备份...';
      _isError = false;
    });

    try {
      // 使用集成WebDAV的导出方法
      final filePath = await _backupService.exportBackupWithWebDAV();
      if (filePath != null) {
        // 检查是否有WebDAV配置
        final webdavConfig = await _webdavService.loadConfig();
        if (webdavConfig != null && webdavConfig.isEnabled) {
          _showMessage('备份已成功导出到: $filePath\n并已自动上传到WebDAV');
        } else {
          _showMessage('备份已成功导出到: $filePath');
        }
      } else {
        _showMessage('备份导出已取消', isError: false);
      }
    } catch (e) {
      _showMessage('备份导出失败: $e', isError: true);
    } finally {
      setState(() {
        _isLoading = false;
        _statusMessage = null;
      });
    }
  }

  Future<void> _importBackup() async {
    // 显示确认对话框
    final confirmed = await _showRestoreConfirmDialog();
    if (!confirmed) return;

    setState(() {
      _isLoading = true;
      _statusMessage = '正在导入备份...';
      _isError = false;
    });

    try {
      final backup = await _backupService.importBackup();
      if (backup != null) {
        setState(() {
          _statusMessage = '正在恢复数据...';
        });

        await _backupService.restoreBackup(backup);

        // 备份恢复完成，显示重启提示对话框
        if (mounted) {
          await _showRestartDialog();
        }
      } else {
        _showMessage('备份导入已取消', isError: false);
      }
    } catch (e) {
      _showMessage('备份恢复失败: $e', isError: true);
    } finally {
      setState(() {
        _isLoading = false;
        _statusMessage = null;
      });
    }
  }

  Future<bool> _showRestoreConfirmDialog() async {
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('确认恢复备份'),
            content: const Text(
              '恢复备份将会覆盖当前的所有应用数据，包括：\n\n'
              '• 站点配置\n'
              '• qBittorrent客户端配置\n'
              '• 用户偏好设置\n'
              '• 缓存数据\n\n'
              '此操作无法撤销，请确认是否继续？',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                style: TextButton.styleFrom(
                  side: BorderSide(
                    color: Theme.of(context).colorScheme.outline,
                    width: 1.0,
                  ),
                ),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('确认恢复'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _showRestartDialog() async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('备份恢复成功'),
        content: const Text(
          '备份已成功恢复！\n\n'
          '为确保所有数据正确生效，建议您重启应用。\n\n'
          '您可以选择立即重启或稍后手动重启应用。',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              _showMessage('备份恢复成功！请重启应用以确保数据生效。');
            },
            child: const Text('稍后重启'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(context).pop();
              // 退出应用，用户需要手动重启
              // 使用exit(0)来完全退出应用
              exit(0);
            },
            child: const Text('立即退出'),
          ),
        ],
      ),
    );
  }

  // WebDAV配置对话框
  Future<void> _showWebDAVConfigDialog() async {
    final TextEditingController nameController = TextEditingController();
    final TextEditingController serverUrlController = TextEditingController();
    final TextEditingController usernameController = TextEditingController();
    final TextEditingController passwordController = TextEditingController();
    final TextEditingController remotePathController = TextEditingController(
      text: '/PTMate',
    );

    if (_selectedConfig != null) {
      nameController.text = _selectedConfig!.name;
      serverUrlController.text = _selectedConfig!.serverUrl;
      usernameController.text = _selectedConfig!.username;
      // 从安全存储中获取密码
      final password = await _webdavService.getPassword(_selectedConfig!.id);
      passwordController.text = password ?? '';
      remotePathController.text = _selectedConfig!.remotePath;
    }
    if (!mounted) return;
    bool isLoading = false;
    String? errorMessage;

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: Text(_selectedConfig == null ? '添加WebDAV配置' : '编辑WebDAV配置'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(
                      labelText: '配置名称',
                      hintText: '例如：我的云盘',
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: serverUrlController,
                    decoration: const InputDecoration(
                      labelText: '服务器地址',
                      hintText: 'https://example.com/webdav',
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: usernameController,
                    decoration: const InputDecoration(labelText: '用户名'),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: passwordController,
                    decoration: const InputDecoration(labelText: '密码'),
                    obscureText: true,
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: remotePathController,
                    decoration: const InputDecoration(
                      labelText: '远程路径',
                      hintText: '/PTMate',
                    ),
                  ),
                  if (isLoading) ...[
                    const SizedBox(height: 16),
                    const Row(
                      children: [
                        SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        SizedBox(width: 8),
                        Text('正在测试连接...'),
                      ],
                    ),
                  ],
                  if (errorMessage != null) ...[
                    const SizedBox(height: 16),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.errorContainer,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.error_outline,
                            color: Theme.of(
                              context,
                            ).colorScheme.onErrorContainer,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              errorMessage!,
                              style: TextStyle(
                                color: Theme.of(
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
              if (_selectedConfig != null)
                TextButton(
                  onPressed: isLoading
                      ? null
                      : () async {
                          final navigator = Navigator.of(context);
                          final currentContext = context;
                          // 删除当前配置
                          await _webdavService.deleteConfig();
                          await _loadWebDAVConfigs();
                          if (mounted && currentContext.mounted) {
                            navigator.pop();
                            // 延迟显示消息，确保对话框完全关闭
                            Future.delayed(
                              const Duration(milliseconds: 100),
                              () {
                                if (mounted && currentContext.mounted) {
                                  _showWebDAVMessage('WebDAV配置已删除');
                                }
                              },
                            );
                          }
                        },
                  style: TextButton.styleFrom(
                    foregroundColor: Theme.of(context).colorScheme.error,
                    side: BorderSide(
                      color: Theme.of(context).colorScheme.error,
                      width: 1.0,
                    ),
                  ),
                  child: const Text('删除'),
                ),
              FilledButton(
                onPressed: isLoading
                    ? null
                    : () async {
                        setDialogState(() {
                          errorMessage = null;
                        });

                        if (nameController.text.isEmpty ||
                            serverUrlController.text.isEmpty ||
                            usernameController.text.isEmpty ||
                            passwordController.text.isEmpty) {
                          setDialogState(() {
                            errorMessage = '请填写所有必填字段';
                          });
                          return;
                        }

                        final config = WebDAVConfig(
                          id:
                              _selectedConfig?.id ??
                              DateTime.now().millisecondsSinceEpoch.toString(),
                          name: nameController.text,
                          serverUrl: serverUrlController.text,
                          username: usernameController.text,
                          remotePath: remotePathController.text,
                          isEnabled: true,
                          autoSync: false,
                          syncIntervalMinutes: 60,
                          lastSyncTime: null,
                          lastSyncStatus: WebDAVSyncStatus.idle,
                          lastSyncError: null,
                        );

                        try {
                          // 测试连接
                          setDialogState(() {
                            isLoading = true;
                          });

                          final testResult = await _webdavService
                              .testConnection(config, passwordController.text);

                          if (testResult.success) {
                            await _webdavService.saveConfig(
                              config,
                              password: passwordController.text,
                            );
                            await _loadWebDAVConfigs();
                            final currentContext = context;
                            if (mounted && currentContext.mounted) {
                              Navigator.of(currentContext).pop();
                              // 延迟显示消息，确保对话框完全关闭
                              Future.delayed(
                                const Duration(milliseconds: 100),
                                () {
                                  if (mounted && currentContext.mounted) {
                                    _showWebDAVMessage('WebDAV配置保存成功');
                                  }
                                },
                              );
                            }
                          } else {
                            setDialogState(() {
                              errorMessage =
                                  testResult.errorMessage ?? '连接测试失败，请检查配置';
                            });
                          }
                        } catch (e) {
                          setDialogState(() {
                            errorMessage = '保存配置时发生错误: $e';
                          });
                        } finally {
                          setDialogState(() {
                            isLoading = false;
                          });
                        }
                      },
                child: const Text('保存'),
              ),
            ],
          );
        },
      ),
    );
  }

  // 上传备份到WebDAV

  // 上传备份到WebDAV
  Future<void> _uploadBackupToWebDAV() async {
    if (_selectedConfig == null) {
      _showWebDAVMessage('请先配置WebDAV', isError: true);
      return;
    }

    setState(() {
      _isWebDAVLoading = true;
      _webdavStatusMessage = '正在创建并上传备份...';
      _isWebDAVError = false;
    });

    try {
      // 使用集成的导出和上传方法
      final filePath = await _backupService.exportBackupWithWebDAV();
      if (filePath == null) {
        _showWebDAVMessage('备份创建已取消', isError: false);
        return;
      }

      _showWebDAVMessage('备份已成功创建并上传到WebDAV');
    } catch (e) {
      _showWebDAVMessage('备份上传失败: $e', isError: true);
    } finally {
      setState(() {
        _isWebDAVLoading = false;
        _webdavStatusMessage = null;
      });
    }
  }

  // 从WebDAV下载备份
  Future<void> _downloadBackupFromWebDAV() async {
    if (_selectedConfig == null) {
      _showWebDAVMessage('请先配置WebDAV', isError: true);
      return;
    }

    // 显示确认对话框
    final confirmed = await _showRestoreConfirmDialog();
    if (!confirmed) return;

    setState(() {
      _isWebDAVLoading = true;
      _webdavStatusMessage = '正在从WebDAV获取备份列表...';
      _isWebDAVError = false;
    });

    try {
      final backupFiles = await _backupService.listWebDAVBackups();
      if (backupFiles.isEmpty) {
        _showWebDAVMessage('WebDAV上没有找到备份文件', isError: true);
        return;
      }

      // 显示备份文件选择对话框
      final selectedFile = await _showBackupFileSelectionDialog(backupFiles);
      if (selectedFile == null) return;

      setState(() {
        _webdavStatusMessage = '正在从WebDAV下载并恢复备份...';
      });

      // 下载并恢复备份
      final backupData = await _backupService.downloadWebDAVBackup(selectedFile);
      if (backupData == null) {
        _showWebDAVMessage('下载备份文件失败', isError: true);
        return;
      }
      
      final result = await _backupService.restoreBackup(backupData);

      if (result.success) {
        if (mounted) {
          await _showRestartDialog();
        }
      } else {
        _showWebDAVMessage(result.message, isError: true);
      }
    } catch (e) {
      _showWebDAVMessage('从WebDAV恢复备份失败: $e', isError: true);
    } finally {
      setState(() {
        _isWebDAVLoading = false;
        _webdavStatusMessage = null;
      });
    }
  }

  // 显示备份文件选择对话框
  Future<String?> _showBackupFileSelectionDialog(
    List<Map<String, dynamic>> backupFiles,
  ) async {
    return await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('选择备份文件'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: backupFiles.length,
            itemBuilder: (context, index) {
              final backup = backupFiles[index];
              final fileName = backup['name'] as String; // 只显示文件名
              final fullPath = backup['path'] as String; // 完整路径用于返回
              final modifiedTime = backup['modifiedTime'] as DateTime?;

              return ListTile(
                leading: const Icon(Icons.backup),
                title: Text(fileName),
                subtitle: Text(
                  modifiedTime != null
                      ? '修改时间: ${modifiedTime.toString().substring(0, 19)}'
                      : '点击选择此备份',
                ),
                onTap: () => Navigator.of(context).pop(fullPath), // 返回完整路径
              );
            },
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
        ],
      ),
    );
  }

  Widget _buildInfoCard({
    required IconData icon,
    required String title,
    required String description,
    Color? iconColor,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          children: [
            Icon(
              icon,
              size: 32,
              color: iconColor ?? Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    description,
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('备份与恢复'),
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
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 功能说明
            _buildInfoCard(
              icon: Icons.info_outline,
              title: '备份与恢复功能',
              description: '安全地备份和恢复您的应用数据，包括站点配置、客户端设置和用户偏好。',
            ),

            const SizedBox(height: 24),

            // 导出备份部分
            Text(
              '导出备份',
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),

            _buildInfoCard(
              icon: Icons.backup,
              title: '创建备份文件',
              description: '将当前的应用数据导出为备份文件，可用于数据迁移或恢复。',
              iconColor: Colors.blue,
            ),

            const SizedBox(height: 16),

            FilledButton.icon(
              onPressed: _isLoading ? null : _exportBackup,
              icon: const Icon(Icons.file_download),
              label: const Text('导出备份'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),

            const SizedBox(height: 32),

            // 导入备份部分
            Text(
              '导入备份',
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),

            _buildInfoCard(
              icon: Icons.restore,
              title: '恢复备份数据',
              description: '从备份文件恢复应用数据。注意：此操作将覆盖当前所有数据。',
              iconColor: Colors.orange,
            ),

            const SizedBox(height: 16),

            FilledButton.icon(
              onPressed: _isLoading ? null : _importBackup,
              icon: const Icon(Icons.file_upload),
              label: const Text('导入备份'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),

            const SizedBox(height: 32),

            // WebDAV云同步部分
            Text(
              'WebDAV云同步',
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),

            _buildInfoCard(
              icon: Icons.cloud_sync,
              title: 'WebDAV云备份',
              description: '通过WebDAV协议将备份同步到云端，支持自动备份和多设备同步。',
              iconColor: Colors.green,
            ),

            const SizedBox(height: 16),

            // WebDAV配置状态
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          _selectedConfig != null && _selectedConfig!.isEnabled
                              ? Icons.cloud_done
                              : Icons.cloud_off,
                          color:
                              _selectedConfig != null &&
                                  _selectedConfig!.isEnabled
                              ? Colors.green
                              : Colors.grey,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _selectedConfig != null && _selectedConfig!.isEnabled
                              ? '已配置: ${_selectedConfig!.name}'
                              : '未配置WebDAV',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        const Spacer(),
                        IconButton(
                          onPressed: _showWebDAVConfigDialog,
                          icon: const Icon(Icons.settings),
                          tooltip: '配置WebDAV',
                        ),
                      ],
                    ),
                    if (_selectedConfig != null &&
                        _selectedConfig!.isEnabled) ...[
                      const SizedBox(height: 8),
                      Text(
                        '服务器: ${_selectedConfig!.serverUrl}',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      Text(
                        '远程路径: ${_selectedConfig!.remotePath}',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // WebDAV操作按钮
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed:
                        (_isWebDAVLoading ||
                            _selectedConfig == null ||
                            !_selectedConfig!.isEnabled)
                        ? null
                        : _uploadBackupToWebDAV,
                    icon: const Icon(Icons.cloud_upload),
                    label: const Text('上传备份'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: FilledButton.icon(
                    onPressed:
                        (_isWebDAVLoading ||
                            _selectedConfig == null ||
                            !_selectedConfig!.isEnabled)
                        ? null
                        : _downloadBackupFromWebDAV,
                    icon: const Icon(Icons.cloud_download),
                    label: const Text('下载备份'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ],
            ),

            // WebDAV状态显示
            if (_webdavStatusMessage != null) ...[
              const SizedBox(height: 16),
              Card(
                color: _isWebDAVError
                    ? Theme.of(context).colorScheme.errorContainer
                    : Theme.of(context).colorScheme.primaryContainer,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    children: [
                      if (_isWebDAVLoading)
                        const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      else
                        Icon(
                          _isWebDAVError ? Icons.error : Icons.check_circle,
                          color: _isWebDAVError
                              ? Theme.of(context).colorScheme.onErrorContainer
                              : Theme.of(
                                  context,
                                ).colorScheme.onPrimaryContainer,
                        ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _webdavStatusMessage!,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: _isWebDAVError
                                    ? Theme.of(
                                        context,
                                      ).colorScheme.onErrorContainer
                                    : Theme.of(
                                        context,
                                      ).colorScheme.onPrimaryContainer,
                              ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],

            const SizedBox(height: 32),

            // 注意事项
            Card(
              color: Colors.orange.withValues(alpha: 0.1),
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: Colors.orange.withValues(alpha: 0.2)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.warning,
                          color: Colors.orange,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '重要提示',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(
                                color:
                                    Theme.of(context).brightness ==
                                        Brightness.light
                                    ? Colors.orange.shade900
                                    : Colors.orange.shade200,
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '• 备份文件包含敏感信息（如API密钥），请妥善保管\n'
                      '• 恢复备份会覆盖当前所有数据，建议先导出当前备份\n'
                      '• 备份文件支持版本兼容，新版本可以读取旧版本备份\n'
                      '• 建议定期创建备份以防数据丢失',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).brightness == Brightness.light
                            ? Colors.orange.shade900
                            : Colors.orange.shade200,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // 状态显示
            if (_statusMessage != null) ...[
              const SizedBox(height: 24),
              Card(
                color: _isError
                    ? Theme.of(context).colorScheme.errorContainer
                    : Theme.of(context).colorScheme.primaryContainer,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    children: [
                      if (_isLoading)
                        const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      else
                        Icon(
                          _isError ? Icons.error : Icons.check_circle,
                          color: _isError
                              ? Theme.of(context).colorScheme.onErrorContainer
                              : Theme.of(
                                  context,
                                ).colorScheme.onPrimaryContainer,
                        ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _statusMessage!,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: _isError
                                    ? Theme.of(
                                        context,
                                      ).colorScheme.onErrorContainer
                                    : Theme.of(
                                        context,
                                      ).colorScheme.onPrimaryContainer,
                              ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
