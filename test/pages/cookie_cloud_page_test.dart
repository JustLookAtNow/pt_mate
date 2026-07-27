import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pt_mate/pages/cookie_cloud_page.dart';
import 'package:pt_mate/services/storage/storage_service.dart';

void main() {
  testWidgets('clear config button clears Cookie Cloud configuration', (
    tester,
  ) async {
    var config = CookieCloudConfig(
      url: 'https://cookiecloud.example.com',
      uuid: 'uuid-1',
      password: 'password-1',
      autoSyncEnabled: true,
      lastSyncAt: DateTime(2026),
      lastSyncSummary: '更新 1 个站点，新增 0 个站点',
    );
    final saveRequests = <CookieCloudConfig>[];

    await tester.pumpWidget(
      MaterialApp(
        home: CookieCloudPage(
          loadConfig: () async => config,
          saveConfig: (value) async {
            saveRequests.add(value);
            config = value;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('https://cookiecloud.example.com'), findsWidgets);
    expect(find.text('清空配置'), findsOneWidget);

    await tester.tap(find.text('清空配置'));
    await tester.pumpAndSettle();
    expect(find.text('清空 Cookie Cloud 配置'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, '清空'));
    await tester.pumpAndSettle();

    expect(saveRequests, hasLength(1));
    expect(saveRequests.single, same(config));
    expect(config.url, isEmpty);
    expect(config.uuid, isEmpty);
    expect(config.password, isEmpty);
    expect(config.autoSyncEnabled, isFalse);
    expect(config.lastSyncAt, isNull);
    expect(config.lastSyncSummary, isEmpty);
    final editableTexts = tester.widgetList<EditableText>(
      find.byType(EditableText),
    );
    expect(
      editableTexts.any(
        (widget) => widget.controller.text == 'https://cookiecloud.example.com',
      ),
      isFalse,
    );

    // Advance fake time so the success notification completes its normal
    // auto-dismiss lifecycle without introducing a real-time delay.
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
  });
}
