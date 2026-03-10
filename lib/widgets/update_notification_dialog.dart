import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/android_install_permission_service.dart';
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
  final ScrollController _contentScrollController = ScrollController();

  bool _isUpdating = false;
  String? _progressMessage;
  double? _downloadProgress;

  @override
  void dispose() {
    _contentScrollController.dispose();
    super.dispose();
  }

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
        controller: _contentScrollController,
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
              if (_isUpdating) ...[
                LinearProgressIndicator(value: _downloadProgress),
                const SizedBox(height: 8),
              ],
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
      actionsAlignment: MainAxisAlignment.spaceBetween,
      actions: [
        TextButton(
          onPressed: _isUpdating ? null : _onNeverRemindPressed,
          style: TextButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.error,
            foregroundColor: Theme.of(context).colorScheme.onError,
          ),
          child: const Text('永不提醒'),
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
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
            const SizedBox(width: 8),
            FilledButton(
              onPressed: _isUpdating ? null : _onPrimaryPressed,
              child: Text(_isUpdating ? '下载中...' : '立即更新'),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _onNeverRemindPressed() async {
    await UpdateService.instance.setAutoUpdateDialogSuppressed(true);
    if (!mounted) return;
    Navigator.of(context).pop();
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
    final permissionGranted = await AndroidInstallPermissionService.instance
        .isInstallPermissionGranted();
    if (!permissionGranted) {
      final opened = await AndroidInstallPermissionService.instance
          .openInstallPermissionSettings();
      if (!mounted) return;
      NotificationHelper.showInfo(
        context,
        opened
            ? '请先在系统页面允许本应用安装未知应用，然后返回重新点击“立即更新”'
            : '无法打开系统安装授权页面，请手动在系统设置中允许本应用安装未知应用',
        duration: const Duration(seconds: 3),
      );
      return;
    }

    setState(() {
      _isUpdating = true;
      _progressMessage = '正在清理旧安装包...';
      _downloadProgress = null;
    });
    _scrollToBottom();

    try {
      await AndroidInstallPermissionService.instance.clearDownloadedApks();
      if (!mounted) return;

      setState(() {
        _progressMessage = '正在测速下载源...';
      });
      _scrollToBottom();

      await AppUpdateDownloader.instance.startAndroidUpdate(
        updateResult: widget.updateResult,
        onProgress: (progress) {
          if (!mounted) return;
          setState(() {
            _progressMessage = progress.message;
            _downloadProgress = progress.progress;
          });
          _scrollToBottom();
        },
      );

      if (!mounted) return;
      NotificationHelper.showSuccess(context, '安装界面已打开，请按系统提示完成更新');
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isUpdating = false;
        _downloadProgress = null;
      });
      _scrollToBottom();
      NotificationHelper.showError(context, '应用内更新失败：$e');
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_contentScrollController.hasClients) return;
      final position = _contentScrollController.position.maxScrollExtent;
      _contentScrollController.animateTo(
        position,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
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
