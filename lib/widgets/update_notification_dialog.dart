import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/app_update_downloader.dart';
import '../services/update_service.dart';
import 'package:pt_mate/utils/notification_helper.dart';

class UpdateNotificationDialog extends StatefulWidget {
  final UpdateCheckResult updateResult;

  const UpdateNotificationDialog({super.key, required this.updateResult});

  @override
  State<UpdateNotificationDialog> createState() =>
      _UpdateNotificationDialogState();

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

class _UpdateNotificationDialogState extends State<UpdateNotificationDialog> {
  bool _isUpdating = false;
  String? _progressMessage;

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
            if (widget.updateResult.latestVersion != null) ...[
              Text(
                '最新版本: ${widget.updateResult.latestVersion}',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
            ],
            if (widget.updateResult.releaseNotes != null &&
                widget.updateResult.releaseNotes!.isNotEmpty) ...[
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
                  data: widget.updateResult.releaseNotes!,
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
            if (_progressMessage != null) ...[
              const SizedBox(height: 12),
              Text(
                _progressMessage!,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isUpdating ? null : () => Navigator.of(context).pop(),
          style: TextButton.styleFrom(
            side: BorderSide(
              color: Theme.of(context).colorScheme.outline,
              width: 1.0,
            ),
          ),
          child: const Text('稍后提醒'),
        ),
        FilledButton(
          onPressed: _isUpdating ? null : _onPrimaryPressed,
          child: Text(_isUpdating ? '下载中...' : '立即更新'),
        ),
      ],
    );
  }

  Future<void> _onPrimaryPressed() async {
    if (AppUpdateDownloader.instance.supportsInAppUpdate) {
      await _startAndroidInAppUpdate();
      return;
    }

    Navigator.of(context).pop();
    await _openDownloadUrl(context);
  }

  Future<void> _startAndroidInAppUpdate() async {
    setState(() {
      _isUpdating = true;
      _progressMessage = '正在准备下载更新包...';
    });

    try {
      await AppUpdateDownloader.instance.startAndroidUpdate(
        updateResult: widget.updateResult,
        onProgress: (progress) {
          if (!mounted) return;
          setState(() {
            _progressMessage = progress.message;
          });
        },
      );

      if (!mounted) return;
      NotificationHelper.showSuccess(context, '安装界面已打开，请按系统提示完成更新');
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isUpdating = false;
      });
      NotificationHelper.showError(context, '应用内更新失败：$e');
    }
  }

  Future<void> _openDownloadUrl(BuildContext context) async {
    final fallbackUrl = AppUpdateDownloader.instance.resolveFallbackUrl(
      widget.updateResult,
    );
    if (fallbackUrl == null || fallbackUrl.isEmpty) {
      return;
    }
    await _launchUrl(context, fallbackUrl);
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
          NotificationHelper.showInfo(
            context,
            '无法直接打开链接，已复制到剪贴板，请手动粘贴到浏览器',
            duration: const Duration(seconds: 2),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        NotificationHelper.showError(context, '打开链接时出错: $e');
      }
    }
  }
}
