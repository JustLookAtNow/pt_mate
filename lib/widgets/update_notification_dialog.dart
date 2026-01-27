import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/update_service.dart';

class UpdateNotificationDialog extends StatelessWidget {
  final UpdateCheckResult updateResult;

  const UpdateNotificationDialog({super.key, required this.updateResult});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          Icon(
            Icons.system_update,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: 8),
          const Text('发现新版本'),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (updateResult.latestVersion != null) ...[
              Text(
                '最新版本: ${updateResult.latestVersion}',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
            ],
            if (updateResult.releaseNotes != null &&
                updateResult.releaseNotes!.isNotEmpty) ...[
              Text(
                '更新内容:',
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Container(
                width: double.maxFinite,
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: MarkdownBody(
                  data: updateResult.releaseNotes!,
                  styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)),
                  onTapLink: (text, href, title) {
                    if (href == null) return;
                    _launchUrl(context, href);
                  },
                ),
              ),
            ] else ...[
              Text(
                '建议更新到最新版本以获得更好的体验和最新功能。',
                style: Theme.of(context).textTheme.bodyMedium,
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
          child: const Text('稍后提醒'),
        ),
        FilledButton(
          onPressed: () async {
            Navigator.of(context).pop();
            await _openDownloadUrl(context);
          },
          child: const Text('立即更新'),
        ),
      ],
    );
  }

  Future<void> _openDownloadUrl(BuildContext context) async {
    if (updateResult.downloadUrl == null || updateResult.downloadUrl!.isEmpty) {
      // 如果没有下载链接，打开GitHub releases页面
      const String defaultUrl =
          'https://github.com/JustLookAtNow/pt_mate/releases';
      await _launchUrl(context, defaultUrl);
      return;
    }

    await _launchUrl(context, updateResult.downloadUrl!);
  }

  Future<void> _launchUrl(BuildContext context, String url) async {
    try {
      final Uri uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        // 降级处理：复制URL到剪贴板
        await Clipboard.setData(ClipboardData(text: url.toString()));
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '无法直接打开链接，已复制到剪贴板，请手动粘贴到浏览器',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                ),
              ),
              duration: const Duration(seconds: 2),
              backgroundColor: Theme.of(context).colorScheme.primaryContainer,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        _showErrorSnackBar(context, '打开链接时出错: $e');
      }
    }
  }

  void _showErrorSnackBar(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onErrorContainer,
          ),
        ),
        backgroundColor: Theme.of(context).colorScheme.errorContainer,
        behavior: SnackBarBehavior.floating,
        action: SnackBarAction(
          label: '确定',
          textColor: Theme.of(context).colorScheme.onErrorContainer,
          onPressed: () {
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
          },
        ),
      ),
    );
  }

  /// 显示更新通知对话框
  static Future<void> show(
    BuildContext context,
    UpdateCheckResult updateResult,
  ) async {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return UpdateNotificationDialog(updateResult: updateResult);
      },
    );
  }
}
