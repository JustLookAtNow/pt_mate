import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pt_mate/widgets/app_drawer.dart';

void main() {
  for (final isFixedSidebar in [false, true]) {
    testWidgets('${isFixedSidebar ? '桌面侧栏' : '手机抽屉'}通过主页访问搜索，移除独立聚合导航', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AppDrawer(currentRoute: '/', isFixedSidebar: isFixedSidebar),
          ),
        ),
      );

      expect(find.text('聚合搜索'), findsNothing);
      expect(find.text('主页'), findsOneWidget);
      expect(find.text('下载管理'), findsOneWidget);
      expect(find.text('站点配置'), findsOneWidget);
      expect(find.text('设置'), findsOneWidget);
    });
  }
}
