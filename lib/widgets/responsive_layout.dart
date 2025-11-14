import 'package:flutter/material.dart';
import 'app_drawer.dart';

class ResponsiveLayout extends StatelessWidget {
  final Widget body;
  final PreferredSizeWidget? appBar;
  final String? currentRoute;
  final VoidCallback? onSettingsChanged;
  final Widget? floatingActionButton;
  final FloatingActionButtonLocation? floatingActionButtonLocation;

  const ResponsiveLayout({
    super.key,
    required this.body,
    this.appBar,
    this.currentRoute,
    this.onSettingsChanged,
    this.floatingActionButton,
    this.floatingActionButtonLocation,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // 判断是否为大屏设备（宽度大于 768px）
        final isLargeScreen = constraints.maxWidth > 600;
        
        if (isLargeScreen) {
          // 大屏设备：使用固定侧边栏布局
          return Scaffold(
            appBar: appBar != null ? _buildAppBarForLargeScreen(context) : null,
            floatingActionButton: floatingActionButton,
            floatingActionButtonLocation: floatingActionButtonLocation,
            body: SafeArea(
              top: true,
              bottom: true,
              child: Row(
                children: [
                  // 固定侧边栏
                  SizedBox(
                    width: 240,
                    child: AppDrawer(
                      currentRoute: currentRoute,
                      onSettingsChanged: onSettingsChanged,
                      isFixedSidebar: true,
                    ),
                  ),
                  // 主内容区域
                  Expanded(child: body),
                ],
              ),
            ),
          );
        } else {
          // 小屏设备：使用传统的 Drawer 布局
          return Scaffold(
            appBar: appBar,
            drawer: AppDrawer(
              currentRoute: currentRoute,
              onSettingsChanged: onSettingsChanged,
              isFixedSidebar: false,
            ),
            floatingActionButton: floatingActionButton,
            floatingActionButtonLocation: floatingActionButtonLocation,
            body: SafeArea(top: true, bottom: true, child: body),
          );
        }
      },
    );
  }

  PreferredSizeWidget _buildAppBarForLargeScreen(BuildContext context) {
    if (appBar is AppBar) {
      final originalAppBar = appBar as AppBar;
      return AppBar(
        title: originalAppBar.title,
        actions: originalAppBar.actions,
        backgroundColor: originalAppBar.backgroundColor,
        iconTheme: originalAppBar.iconTheme,
        titleTextStyle: originalAppBar.titleTextStyle,
        // 大屏设备不需要菜单按钮，因为侧边栏是固定显示的
        automaticallyImplyLeading: false,
      );
    }
    return appBar!;
  }
}