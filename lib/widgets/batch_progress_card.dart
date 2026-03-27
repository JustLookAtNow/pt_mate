import 'package:flutter/material.dart';

import '../models/batch_operation_models.dart';

class BatchProgressCard<T> extends StatelessWidget {
  final BatchProgressState<T> progress;
  final ValueChanged<T>? onRetryItem;
  final VoidCallback? onRetryAll;
  final VoidCallback? onClose;
  final EdgeInsetsGeometry? margin;

  const BatchProgressCard({
    super.key,
    required this.progress,
    this.onRetryItem,
    this.onRetryAll,
    this.onClose,
    this.margin,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: margin,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    progress.titleLabel,
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                if (progress.isRunning)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else if (onClose != null)
                  IconButton(
                    onPressed: onClose,
                    icon: const Icon(Icons.close, size: 18),
                    tooltip: '关闭',
                    visualDensity: VisualDensity.compact,
                    splashRadius: 18,
                  ),
              ],
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(value: progress.progress),
            const SizedBox(height: 8),
            Text(
              '成功 ${progress.successCount}  失败 ${progress.failureCount}',
              style: theme.textTheme.bodySmall,
            ),
            if (progress.currentItemName != null) ...[
              const SizedBox(height: 4),
              Text(
                '当前处理：${progress.currentItemName}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall,
              ),
            ],
            if (!progress.isRunning && progress.failedItems.isNotEmpty) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.tonal(
                  onPressed: onRetryAll,
                  child: const Text('重试失败项'),
                ),
              ),
            ],
            if (progress.failedItems.isNotEmpty) ...[
              const SizedBox(height: 8),
              ...progress.failedItems.map((failure) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              failure.itemName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodyMedium,
                            ),
                            Text(
                              failure.errorMessage,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.error,
                              ),
                            ),
                          ],
                        ),
                      ),
                      TextButton(
                        onPressed: progress.isRunning || onRetryItem == null
                            ? null
                            : () => onRetryItem!(failure.item),
                        child: const Text('重试'),
                      ),
                    ],
                  ),
                );
              }),
            ],
          ],
        ),
      ),
    );
  }
}
