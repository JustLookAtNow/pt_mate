import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../services/update_service.dart';
import '../widgets/update_notification_dialog.dart';

import '../widgets/qb_speed_indicator.dart';
import '../widgets/responsive_layout.dart';
import 'package:pt_mate/utils/notification_helper.dart';

class AboutPage extends StatefulWidget {
  const AboutPage({super.key});

  @override
  State<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<AboutPage> {
  String _version = '';

  @override
  void initState() {
    super.initState();
    _loadPackageInfo();
    // 进入关于页时自动检查一次更新（静默，无更新不提示）
    _checkUpdateOnEnter();
  }

  Future<void> _loadPackageInfo() async {
    final packageInfo = await PackageInfo.fromPlatform();
    setState(() {
      _version = 'v${packageInfo.version}';
    });
  }

  @override
  Widget build(BuildContext context) {
    return ResponsiveLayout(
      currentRoute: '/about',
      appBar: AppBar(
        title: const Text('关于'),
        actions: const [QbSpeedIndicator()],
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
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('PT Mate（PT伴侣）'),
            const SizedBox(height: 8),
            Text(
              _version,
              style: const TextStyle(
                fontSize: 16,
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 16),
            InkWell(
              onTap: () async {
                try {
                  final Uri url = Uri.parse('https://github.com/JustLookAtNow/pt_mate');
                  if (await canLaunchUrl(url)) {
                    await launchUrl(url, mode: LaunchMode.externalApplication);
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
                  // 捕获任何异常并显示错误信息
                  if (context.mounted) {
                    NotificationHelper.showError(
                      context,
                      '操作失败: $e',
                      duration: const Duration(seconds: 2),
                    );
                  }
                }
              },
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'https://github.com/JustLookAtNow',
                    style: TextStyle(
                      color: Colors.blue,
                      // decoration: TextDecoration.underline,
                    ),
                    overflow: TextOverflow.visible,
                    softWrap: true,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _onCheckUpdatePressed,
              icon: const Icon(Icons.system_update),
              label: const Text('检查更新'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _checkUpdateOnEnter() async {
    try {
      final result = await UpdateService.instance.manualCheckForUpdates();
      if (!mounted || result == null) return;
      if (result.hasUpdate) {
        await UpdateNotificationDialog.show(context, result);
      }
    } catch (e) {
      // 静默失败，不影响用户浏览关于页
    }
  }

  Future<void> _onCheckUpdatePressed() async {
    try {
      final result = await UpdateService.instance.manualCheckForUpdates();
      if (!mounted) return;
      if (result == null) {
        NotificationHelper.showError(context, '检查更新失败，请稍后重试');
        return;
      }
      if (result.hasUpdate) {
        await UpdateNotificationDialog.show(context, result);
      } else {
        NotificationHelper.showInfo(context, '当前已是最新版本');
      }
    } catch (e) {
      if (!mounted) return;
      NotificationHelper.showError(context, '检查更新时发生错误：$e');
    }
  }
}