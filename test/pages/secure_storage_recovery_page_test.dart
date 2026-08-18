import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pt_mate/pages/secure_storage_recovery_page.dart';

void main() {
  testWidgets('shows a blocking explanation and exposes recovery actions', (
    tester,
  ) async {
    var retryCount = 0;
    var openBackupCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: SecureStorageRecoveryPage(
          failureCode: 'invalid_key',
          onRetry: () async {
            retryCount++;
          },
          onOpenBackupRestore: () {
            openBackupCount++;
          },
        ),
      ),
    );

    expect(find.text('暂时无法读取安全存储'), findsOneWidget);
    expect(find.text('错误代码：invalid_key'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
    expect(find.text('进入备份恢复'), findsOneWidget);

    await tester.tap(find.text('重试'));
    await tester.pump();
    expect(retryCount, 1);

    await tester.tap(find.text('进入备份恢复'));
    await tester.pump();
    expect(openBackupCount, 1);
  });

  testWidgets('disables recovery actions while retrying', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SecureStorageRecoveryPage(
          isRetrying: true,
          onRetry: () async {},
          onOpenBackupRestore: () {},
        ),
      ),
    );

    final filledButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '正在重试…'),
    );
    final outlinedButton = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, '进入备份恢复'),
    );
    expect(filledButton.onPressed, isNull);
    expect(outlinedButton.onPressed, isNull);
  });

  testWidgets('legacy recovery requires a backup or an explicit discard', (
    tester,
  ) async {
    var openBackupCount = 0;
    var discardCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: SecureStorageRecoveryPage(
          failureCode: 'legacy_secure_storage_backup_restore_required',
          onRetry: () async {},
          onOpenBackupRestore: () => openBackupCount++,
          onDiscardLegacyData: () async => discardCount++,
        ),
      ),
    );

    expect(find.text('需要恢复旧版安全存储数据'), findsOneWidget);
    expect(find.text('选择有效备份并恢复'), findsOneWidget);
    expect(find.text('没有备份，放弃旧数据'), findsOneWidget);
    expect(find.text('重试'), findsNothing);

    await tester.tap(find.text('选择有效备份并恢复'));
    await tester.pump();
    expect(openBackupCount, 1);

    await tester.tap(find.text('没有备份，放弃旧数据'));
    await tester.pumpAndSettle();
    expect(find.text('确认放弃旧安全数据'), findsOneWidget);
    await tester.tap(find.text('放弃旧数据'));
    await tester.pumpAndSettle();
    expect(discardCount, 1);
  });
}
