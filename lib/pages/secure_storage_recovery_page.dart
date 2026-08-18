import 'package:flutter/material.dart';

class SecureStorageRecoveryPage extends StatelessWidget {
  const SecureStorageRecoveryPage({
    super.key,
    required this.onRetry,
    required this.onOpenBackupRestore,
    this.onDiscardLegacyData,
    this.failureCode,
    this.isRetrying = false,
  });

  final Future<void> Function() onRetry;
  final VoidCallback onOpenBackupRestore;

  /// Invoked only after the user explicitly confirms that they want to discard
  /// legacy encrypted data without restoring a backup.
  final Future<void> Function()? onDiscardLegacyData;
  final String? failureCode;
  final bool isRetrying;

  bool get _requiresLegacyBackupRestore =>
      failureCode == 'legacy_secure_storage_backup_restore_required';

  Future<void> _confirmDiscardLegacyData(BuildContext context) async {
    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('确认放弃旧安全数据'),
            content: const Text(
              '这会永久删除旧版安全存储中的 Cookie、API Key 和密码，且无法恢复。\n\n'
              '只有在您确认没有可用备份时才继续。',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('取消'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(dialogContext).colorScheme.error,
                  foregroundColor: Theme.of(dialogContext).colorScheme.onError,
                ),
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('放弃旧数据'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || onDiscardLegacyData == null) return;

    try {
      await onDiscardLegacyData!();
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('无法重置旧安全数据，请重试或恢复备份。')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('安全存储需要处理')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.shield_outlined,
                        size: 64,
                        color: theme.colorScheme.error,
                      ),
                      const SizedBox(height: 20),
                      Text(
                        _requiresLegacyBackupRestore
                            ? '需要恢复旧版安全存储数据'
                            : '暂时无法读取安全存储',
                        style: theme.textTheme.headlineSmall,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _requiresLegacyBackupRestore
                            ? '此版本无法直接读取旧版安全存储。请先选择并解析一份有效备份；确认后，应用才会清理旧数据并恢复备份。'
                            : '为避免把读取异常误判为配置为空，站点初始化、自动同步、健康检查和备份上传已暂停。应用不会自动清空或重建安全存储。',
                        style: theme.textTheme.bodyLarge,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        _requiresLegacyBackupRestore
                            ? '备份文件包含 Cookie、API Key 和密码等敏感信息。请妥善保管，并在恢复成功后删除备份文件。'
                            : '如果重试仍失败，请先在系统中清除应用数据或重装，使安全存储回到全新状态，再进入备份恢复；这里不会原地重建或覆盖现有密钥。',
                        style: theme.textTheme.bodyMedium,
                        textAlign: TextAlign.center,
                      ),
                      if (failureCode != null && failureCode!.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        SelectableText(
                          '错误代码：$failureCode',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                      const SizedBox(height: 24),
                      if (!_requiresLegacyBackupRestore)
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: isRetrying ? null : () => onRetry(),
                            icon: isRetrying
                                ? const SizedBox.square(
                                    dimension: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.refresh),
                            label: Text(isRetrying ? '正在重试…' : '重试'),
                          ),
                        ),
                      if (!_requiresLegacyBackupRestore)
                        const SizedBox(height: 12),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: isRetrying ? null : onOpenBackupRestore,
                          icon: const Icon(Icons.restore),
                          label: Text(
                            _requiresLegacyBackupRestore
                                ? '选择有效备份并恢复'
                                : '进入备份恢复',
                          ),
                        ),
                      ),
                      if (_requiresLegacyBackupRestore) ...[
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: TextButton.icon(
                            onPressed: isRetrying || onDiscardLegacyData == null
                                ? null
                                : () => _confirmDiscardLegacyData(context),
                            icon: const Icon(Icons.delete_forever_outlined),
                            label: const Text('没有备份，放弃旧数据'),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
