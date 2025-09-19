import 'package:flutter/material.dart';
import '../pages/downloader_settings_page.dart';
import '../pages/server_settings_page.dart';
import '../pages/settings_page.dart';
import '../pages/about_page.dart';
import '../app.dart';

class AppDrawer extends StatelessWidget {
  final VoidCallback? onSettingsChanged;
  final String? currentRoute;
  final bool isFixedSidebar;
  
  const AppDrawer({
    super.key,
    this.onSettingsChanged,
    this.currentRoute,
    this.isFixedSidebar = false,
  });

  @override
  Widget build(BuildContext context) {
    final drawerContent = Container(
      color: Theme.of(context).colorScheme.surface,
      child: ListView(
        padding: EdgeInsets.zero, // 移除默认的 padding，让 DrawerHeader 能够延伸到状态栏
        children: [
          // 只在非固定菜单模式下显示 header
          if (!isFixedSidebar)
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
          // 固定菜单模式下添加一些顶部间距
          if (isFixedSidebar)
            const SizedBox(height: 16),
          _DrawerItem(
            icon: Icons.home_outlined,
            title: '主页',
            isActive: currentRoute == '/home' || currentRoute == '/',
            onTap: () {
              if (!isFixedSidebar) {
                Navigator.of(context).pop();
              }
              // 如果不在主页，导航到主页
              if (currentRoute != '/home' && currentRoute != '/') {
                if (isFixedSidebar) {
                  Navigator.of(context).pushReplacement(
                    PageRouteBuilder(
                      pageBuilder: (context, animation1, animation2) => const HomePage(),
                      settings: const RouteSettings(name: '/'),
                      transitionDuration: Duration.zero,
                      reverseTransitionDuration: Duration.zero,
                    ),
                  );
                } else {
                  Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute(
                      builder: (_) => const HomePage(),
                      settings: const RouteSettings(name: '/'),
                    ),
                    (route) => false,
                  );
                }
              }
            },
          ),
          _DrawerItem(
            icon: Icons.download_outlined,
            title: '下载器设置',
            isActive: currentRoute == '/downloader_settings',
            onTap: () {
              if (!isFixedSidebar) {
                Navigator.of(context).pop();
              }
              if (currentRoute != '/downloader_settings') {
                if (isFixedSidebar) {
                  Navigator.of(context).pushReplacement(
                    PageRouteBuilder(
                      pageBuilder: (context, animation1, animation2) => const DownloaderSettingsPage(),
                      settings: const RouteSettings(name: '/downloader_settings'),
                      transitionDuration: Duration.zero,
                      reverseTransitionDuration: Duration.zero,
                    ),
                  );
                } else {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const DownloaderSettingsPage(),
                      settings: const RouteSettings(name: '/downloader_settings'),
                    ),
                  );
                }
              }
            },
          ),
          _DrawerItem(
            icon: Icons.dns,
            title: '服务器配置',
            isActive: currentRoute == '/server_settings',
            onTap: () {
              if (!isFixedSidebar) {
                Navigator.of(context).pop();
              }
              if (currentRoute != '/server_settings') {
                if (isFixedSidebar) {
                  Navigator.of(context).pushReplacement(
                    PageRouteBuilder(
                      pageBuilder: (context, animation1, animation2) => const ServerSettingsPage(),
                      settings: const RouteSettings(name: '/server_settings'),
                      transitionDuration: Duration.zero,
                      reverseTransitionDuration: Duration.zero,
                    ),
                  );
                } else {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const ServerSettingsPage(),
                      settings: const RouteSettings(name: '/server_settings'),
                    ),
                  );
                }
              }
            },
          ),
          _DrawerItem(
            icon: Icons.settings_outlined,
            title: '设置',
            isActive: currentRoute == '/settings',
            onTap: () async {
              if (!isFixedSidebar) {
                Navigator.of(context).pop();
              }
              if (currentRoute != '/settings') {
                if (isFixedSidebar) {
                  await Navigator.of(context).pushReplacement(
                    PageRouteBuilder(
                      pageBuilder: (context, animation1, animation2) => const SettingsPage(),
                      settings: const RouteSettings(name: '/settings'),
                      transitionDuration: Duration.zero,
                      reverseTransitionDuration: Duration.zero,
                    ),
                  );
                } else {
                  await Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const SettingsPage(),
                      settings: const RouteSettings(name: '/settings'),
                    ),
                  );
                  // 从设置页面返回后，重新加载分类配置
                  onSettingsChanged?.call();
                }
              }
            },
          ),
          _DrawerItem(
            icon: Icons.info_outline,
            title: '关于',
            isActive: currentRoute == '/about',
            onTap: () {
              if (!isFixedSidebar) {
                Navigator.of(context).pop();
              }
              if (currentRoute != '/about') {
                if (isFixedSidebar) {
                  Navigator.of(context).pushReplacement(
                    PageRouteBuilder(
                      pageBuilder: (context, animation1, animation2) => const AboutPage(),
                      settings: const RouteSettings(name: '/about'),
                      transitionDuration: Duration.zero,
                      reverseTransitionDuration: Duration.zero,
                    ),
                  );
                } else {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const AboutPage(),
                      settings: const RouteSettings(name: '/about'),
                    ),
                  );
                }
              }
            },
          ),
        ],
      ),
    );

    // 根据 isFixedSidebar 参数决定返回 Drawer 还是直接返回内容
    if (isFixedSidebar) {
      return drawerContent;
    } else {
      return Drawer(child: drawerContent);
    }
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