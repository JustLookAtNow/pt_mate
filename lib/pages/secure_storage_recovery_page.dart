import 'package:flutter/material.dart';

class SecureStorageRecoveryPage extends StatelessWidget {
  const SecureStorageRecoveryPage({
    super.key,
    required this.onRetry,
    required this.onOpenBackupRestore,
    this.failureCode,
    this.isRetrying = false,
  });

  final Future<void> Function() onRetry;
  final VoidCallback onOpenBackupRestore;
  final String? failureCode;
  final bool isRetrying;

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
                        '暂时无法读取安全存储',
                        style: theme.textTheme.headlineSmall,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        '为避免把读取异常误判为配置为空，站点初始化、自动同步、健康检查和备份上传已暂停。应用不会自动清空或重建安全存储。',
                        style: theme.textTheme.bodyLarge,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        '如果重试仍失败，请先在系统中清除应用数据或重装，使安全存储回到全新状态，再进入备份恢复；这里不会原地重建或覆盖现有密钥。',
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
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: isRetrying ? null : onOpenBackupRestore,
                          icon: const Icon(Icons.restore),
                          label: const Text('进入备份恢复'),
                        ),
                      ),
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
