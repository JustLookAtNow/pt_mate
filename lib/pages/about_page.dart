import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../widgets/qb_speed_indicator.dart';

class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('关于'),
        actions: const [QbSpeedIndicator()],
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('M-Team Flutter 客户端（非官方）'),
            const SizedBox(height: 16),
            InkWell(
              onTap: () async {
                try {
                  final Uri url = Uri.parse('https://github.com/JustLookAtNow/flutter_application_m_team');
                  if (await canLaunchUrl(url)) {
                    await launchUrl(url, mode: LaunchMode.externalApplication);
                  } else {
                    // 降级处理：复制URL到剪贴板
                    await Clipboard.setData(ClipboardData(text: url.toString()));
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('无法直接打开链接，已复制到剪贴板，请手动粘贴到浏览器'),
                          duration: Duration(seconds: 2),
                        ),
                      );
                    }
                  }
                } catch (e) {
                  // 捕获任何异常并显示错误信息
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('操作失败: $e'),
                        duration: const Duration(seconds: 2),
                      ),
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
          ],
        ),
      ),
    );
  }
}