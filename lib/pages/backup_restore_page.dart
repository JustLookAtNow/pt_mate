import 'dart:io';
import 'package:flutter/material.dart';
import '../services/backup_service.dart';
import '../services/storage/storage_service.dart';

class BackupRestorePage extends StatefulWidget {
  const BackupRestorePage({super.key});

  @override
  State<BackupRestorePage> createState() => _BackupRestorePageState();
}

class _BackupRestorePageState extends State<BackupRestorePage> {
  late final BackupService _backupService;
  bool _isLoading = false;
  String? _statusMessage;
  bool _isError = false;

  @override
  void initState() {
    super.initState();
    _backupService = BackupService(StorageService.instance);
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

  Future<void> _exportBackup() async {
    setState(() {
      _isLoading = true;
      _statusMessage = '正在创建备份...';
      _isError = false;
    });

    try {
      final filePath = await _backupService.exportBackup();
      if (filePath != null) {
        _showMessage('备份已成功导出到: $filePath');
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

            // 注意事项
            Card(
              color: Theme.of(context).colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.warning,
                          color: Theme.of(context).colorScheme.onErrorContainer,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '重要提示',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onErrorContainer,
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
                        color: Theme.of(context).colorScheme.onErrorContainer,
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
