import 'package:flutter/material.dart';
import '../pages/downloader_settings_page.dart';
import '../pages/server_settings_page.dart';
import '../pages/settings_page.dart';
import '../pages/about_page.dart';

class AppDrawer extends StatelessWidget {
  final VoidCallback? onSettingsChanged;
  final String? currentRoute;
  
  const AppDrawer({
    super.key,
    this.onSettingsChanged,
    this.currentRoute,
  });

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: SafeArea(
        child: ListView(
          children: [
            DrawerHeader(
              decoration: BoxDecoration(
                color: Theme.of(context).brightness == Brightness.light 
                    ? Theme.of(context).colorScheme.primary 
                    : Theme.of(context).colorScheme.surface,
              ),
              child: Align(
                alignment: Alignment.bottomLeft,
                child: Text(
                  'PT Mate',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).brightness == Brightness.light 
                        ? Theme.of(context).colorScheme.onPrimary 
                        : Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              ),
            ),
            _DrawerItem(
              icon: Icons.home_outlined,
              title: '主页',
              isActive: currentRoute == '/home' || currentRoute == '/',
              onTap: () {
                Navigator.of(context).pop();
                // 如果不在主页，导航到主页
                if (currentRoute != '/home' && currentRoute != '/') {
                  Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
                }
              },
            ),
            _DrawerItem(
              icon: Icons.download_outlined,
              title: '下载器设置',
              isActive: currentRoute == '/downloader_settings',
              onTap: () {
                Navigator.of(context).pop();
                if (currentRoute != '/downloader_settings') {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const DownloaderSettingsPage(),
                    ),
                  );
                }
              },
            ),
            _DrawerItem(
              icon: Icons.dns,
              title: '服务器配置',
              isActive: currentRoute == '/server_settings',
              onTap: () {
                Navigator.of(context).pop();
                if (currentRoute != '/server_settings') {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const ServerSettingsPage(),
                    ),
                  );
                }
              },
            ),
            _DrawerItem(
              icon: Icons.settings_outlined,
              title: '设置',
              isActive: currentRoute == '/settings',
              onTap: () async {
                Navigator.of(context).pop();
                if (currentRoute != '/settings') {
                  await Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const SettingsPage()),
                  );
                  // 从设置页面返回后，重新加载分类配置
                  onSettingsChanged?.call();
                }
              },
            ),
            _DrawerItem(
              icon: Icons.info_outline,
              title: '关于',
              isActive: currentRoute == '/about',
              onTap: () {
                Navigator.of(context).pop();
                if (currentRoute != '/about') {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const AboutPage()),
                  );
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _DrawerItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final bool isActive;
  final VoidCallback onTap;

  const _DrawerItem({
    required this.icon,
    required this.title,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: isActive 
            ? Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3)
            : null,
        borderRadius: BorderRadius.circular(8),
      ),
      child: ListTile(
        leading: Icon(
          icon,
          color: isActive 
              ? Theme.of(context).colorScheme.primary
              : Theme.of(context).colorScheme.primary,
        ),
        title: Text(
          title,
          style: TextStyle(
            fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
            color: isActive 
                ? Theme.of(context).colorScheme.onPrimaryContainer
                : null,
          ),
        ),
        onTap: onTap,
      ),
    );
  }
}