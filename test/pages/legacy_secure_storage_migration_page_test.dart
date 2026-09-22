import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pt_mate/pages/legacy_secure_storage_migration_page.dart';
import 'package:pt_mate/services/backup_service.dart';
import 'package:pt_mate/services/storage/android_secure_storage_profile_resolver.dart';

void main() {
  final backup = BackupData(
    version: '1.4.0',
    timestamp: DateTime.utc(2026, 9, 22),
    appVersion: '2.30.0',
    data: const <String, dynamic>{},
  );

  LegacyMigrationPreparation preparation(LegacyAndroidMigrationTarget target) =>
      LegacyMigrationPreparation(
        exportedBackup: LegacyMigrationBackupExport(
          path: '/tmp/migration-backup.json',
          backup: backup,
        ),
        target: target,
      );

  Future<void> pumpPage(
    WidgetTester tester, {
    required Future<LegacyMigrationPreparation?> Function(
      ValueChanged<String> onProgress,
    )
    prepareMigration,
    Future<void> Function(LegacyMigrationPreparation preparation)?
    performMigration,
    VoidCallback? onOpenBackupRestore,
    String failureCode = 'legacy_secure_storage_backup_restore_required',
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: LegacySecureStorageMigrationPage(
          failureCode: failureCode,
          onOpenBackupRestore: onOpenBackupRestore ?? () {},
          onMigrationCompleted: () async {},
          onDiscardLegacyData: () async {},
          prepareMigration: prepareMigration,
          performMigration: performMigration,
        ),
      ),
    );
  }

  testWidgets(
    'cancelled export never enables or starts destructive migration',
    (tester) async {
      var migrated = false;
      await pumpPage(
        tester,
        prepareMigration: (_) async => null,
        performMigration: (_) async => migrated = true,
      );

      await tester.tap(find.text('第一步：校验并导出本地备份'));
      await tester.pumpAndSettle();

      expect(find.text('已取消导出，旧数据未做任何修改。'), findsOneWidget);
      expect(migrated, isFalse);
      final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, '第二步：确认并升级安全存储'),
      );
      expect(button.onPressed, isNull);
    },
  );

  testWidgets('failed backup validation leaves migration disabled', (
    tester,
  ) async {
    var migrated = false;
    await pumpPage(
      tester,
      prepareMigration: (_) async => throw StateError('incomplete snapshot'),
      performMigration: (_) async => migrated = true,
    );

    await tester.tap(find.text('第一步：校验并导出本地备份'));
    await tester.pumpAndSettle();

    expect(find.textContaining('incomplete snapshot'), findsOneWidget);
    expect(migrated, isFalse);
  });

  testWidgets('OAEP capable device confirms encrypted migration target', (
    tester,
  ) async {
    LegacyAndroidMigrationTarget? migratedTarget;
    await pumpPage(
      tester,
      prepareMigration: (_) async =>
          preparation(LegacyAndroidMigrationTarget.oaepGcm),
      performMigration: (value) async => migratedTarget = value.target,
    );

    await tester.tap(find.text('第一步：校验并导出本地备份'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('第二步：确认并升级安全存储'));
    await tester.pumpAndSettle();

    expect(find.text('确认升级安全存储'), findsOneWidget);
    expect(find.textContaining('OAEP+GCM'), findsOneWidget);
    await tester.tap(find.text('确认迁移'));
    await tester.pumpAndSettle();
    expect(migratedTarget, LegacyAndroidMigrationTarget.oaepGcm);
    expect(find.textContaining('请从设备中删除该文件'), findsOneWidget);
    await tester.tap(find.text('我会删除备份'));
    await tester.pumpAndSettle();
  });

  testWidgets(
    'plaintext target shows risk and requires a second confirmation',
    (tester) async {
      var migrationCount = 0;
      await pumpPage(
        tester,
        prepareMigration: (_) async =>
            preparation(LegacyAndroidMigrationTarget.plaintext),
        performMigration: (_) async => migrationCount++,
      );

      await tester.tap(find.text('第一步：校验并导出本地备份'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('第二步：确认并迁移到明文存储'));
      await tester.pumpAndSettle();

      expect(find.text('确认改用明文存储'), findsOneWidget);
      expect(find.textContaining('Cookie、API Key 和密码将以明文保存'), findsOneWidget);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(migrationCount, 0);

      await tester.tap(find.text('第二步：确认并迁移到明文存储'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('确认迁移'));
      await tester.pumpAndSettle();
      expect(migrationCount, 1);
      await tester.tap(find.text('我会删除备份'));
      await tester.pumpAndSettle();
    },
  );

  testWidgets('pending migration requires selecting the exported backup', (
    tester,
  ) async {
    var opened = false;
    await pumpPage(
      tester,
      failureCode: 'legacy_secure_storage_migration_resume_required',
      prepareMigration: (_) async => null,
      onOpenBackupRestore: () => opened = true,
    );

    expect(find.text('需要从迁移备份继续恢复'), findsOneWidget);
    await tester.tap(find.text('选择迁移备份并继续'));
    expect(opened, isTrue);
  });
}
