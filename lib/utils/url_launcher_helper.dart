import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:pt_mate/utils/notification_helper.dart';

class UrlLauncherHelper {
  /// 统一的浏览器唤起方法，支持跨平台，且在 Linux 桌面平台下具备 xdg-open 的强力命令行兜底。
  static Future<void> launchBrowser(BuildContext context, String urlString) async {
    try {
      final uri = Uri.parse(urlString);

      // 在 Linux 和 Windows 桌面平台上，url_launcher 底层可能由于平台原因失效，执行特定命令行进行强力兜底
      if (!kIsWeb && (defaultTargetPlatform == TargetPlatform.linux || defaultTargetPlatform == TargetPlatform.windows)) {
        final platformName = defaultTargetPlatform == TargetPlatform.linux ? 'Linux' : 'Windows';
        debugPrint('$platformName平台：尝试启动URL: $urlString');

        try {
          // 1. 尝试使用官方 url_launcher 启动
          await launchUrl(uri, mode: LaunchMode.externalApplication);
          debugPrint('$platformName平台：url_launcher 启动命令已执行');

          // 2. 如果是 Linux 平台，额外延迟执行 xdg-open 作为坚实备选
          if (defaultTargetPlatform == TargetPlatform.linux) {
            await Future.delayed(const Duration(milliseconds: 500));
            debugPrint('Linux平台：尝试备选方案 - 直接调用 xdg-open');
            final result = await Process.run('xdg-open', [urlString]);
            debugPrint('Linux平台：xdg-open 退出码: ${result.exitCode}');
            if (result.exitCode != 0) {
              debugPrint('Linux平台：xdg-open 错误输出: ${result.stderr}');
            } else {
              debugPrint('Linux平台：xdg-open 执行成功');
            }
          }
        } catch (processError) {
          debugPrint('$platformName平台：命令行唤起失败: $processError');
          rethrow;
        }
      } else {
        // 移动端、macOS 或 Web 平台，使用常规 url_launcher
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        } else {
          throw Exception('浏览器拒绝或无法打开此链接');
        }
      }
    } catch (e) {
      debugPrint('唤起浏览器失败：$e');
      if (context.mounted) {
        NotificationHelper.showError(context, '无法自动打开浏览器，请手动复制链接访问：$urlString');
      }
    }
  }
}
