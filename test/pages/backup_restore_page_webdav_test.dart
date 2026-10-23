import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pt_mate/pages/backup_restore_page.dart';
import 'package:webdav_client/webdav_client.dart' as webdav;

import '../support/webdav_test_support.dart';

void main() {
  late WebDAVTestHarness harness;

  setUp(() {
    harness = WebDAVTestHarness();
  });
  tearDown(() => harness.tearDown());

  Future<void> openPage(WidgetTester tester) async {
    await harness.setUp();
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MaterialApp(home: BackupRestorePage()));
    await tester.pumpAndSettle();
  }

  Future<void> openConfig(WidgetTester tester) async {
    await openPage(tester);
    await tester.ensureVisible(find.byTooltip('配置WebDAV'));
    await tester.tap(find.byTooltip('配置WebDAV'));
    await tester.pumpAndSettle();
  }

  void expectVisibleError(WidgetTester tester, String message) {
    final error = find.textContaining(message);
    expect(error.hitTestable(), findsOneWidget);
    final viewport = tester.getRect(find.byType(SingleChildScrollView).last);
    final errorBounds = tester.getRect(error);
    expect(errorBounds.top, greaterThanOrEqualTo(viewport.top));
    expect(errorBounds.bottom, lessThanOrEqualTo(viewport.bottom + 1));
    expect(
      Scrollable.of(tester.element(error)).position.pixels,
      greaterThan(0),
    );
  }

  Future<void> waitForNotificationToDismiss(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
  }

  testWidgets('validation error scrolls into view with the keyboard open', (
    tester,
  ) async {
    await openConfig(tester);
    await tester.enterText(find.byType(TextField).first, '');
    tester.view.viewInsets = const FakeViewPadding(bottom: 260);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();

    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expectVisibleError(tester, '请填写所有必填字段');
    expect(tester.takeException(), isNull);
  });

  testWidgets('connection SSL error automatically scrolls into view', (
    tester,
  ) async {
    harness.client.onReadDir = (_) async => throw const HandshakeException();
    await openConfig(tester);
    tester.view.viewInsets = const FakeViewPadding(bottom: 260);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();

    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expectVisibleError(tester, webdavSSLMessage);
    expect(find.text('正在测试连接...'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('saving errors also scroll into view', (tester) async {
    await openConfig(tester);
    harness.failSecureWrites = true;
    tester.view.viewInsets = const FakeViewPadding(bottom: 260);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();

    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expectVisibleError(tester, '保存配置时发生错误');
    expect(tester.takeException(), isNull);
  });

  for (final succeeds in [true, false]) {
    testWidgets('closing a pending connection test is safe ($succeeds)', (
      tester,
    ) async {
      final pending = Completer<List<webdav.File>>();
      harness.client.onReadDir = (_) => pending.future;
      await openConfig(tester);
      await tester.enterText(find.byType(TextField).first, 'Changed');
      await tester.tap(find.text('保存'));
      await tester.pump();
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();

      if (succeeds) {
        pending.complete([]);
      } else {
        pending.completeError(const HandshakeException());
      }
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsNothing);
      expect((await harness.webdavService.loadConfig())!.name, 'Test');
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'upload errors remain on the page after the notification closes',
    (tester) async {
      harness.client.onWrite = (_) async => throw const HandshakeException();
      await openPage(tester);
      await tester.ensureVisible(find.text('上传备份'));
      await tester.tap(find.text('上传备份'));
      await tester.pumpAndSettle();
      await waitForNotificationToDismiss(tester);

      expect(find.textContaining(webdavSSLMessage), findsOneWidget);
      expect(find.text('备份已成功创建并上传到WebDAV'), findsNothing);
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '上传备份'))
            .onPressed,
        isNotNull,
      );
    },
  );

  testWidgets('save finishing during dialog dismissal does not pop the page', (
    tester,
  ) async {
    await openConfig(tester);
    final pendingWrite = Completer<void>();
    var writing = false;
    harness.beforeSecureWrite = () {
      writing = true;
      return pendingWrite.future;
    };
    addTearDown(() {
      if (!pendingWrite.isCompleted) pendingWrite.complete();
    });
    await tester.tap(find.text('保存'));
    await tester.pump();
    expect(writing, isTrue);
    await tester.tap(find.text('取消'));
    await tester.pump(const Duration(milliseconds: 16));

    pendingWrite.complete();
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(BackupRestorePage), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final empty in [false, true]) {
    testWidgets(
      'download distinguishes connection errors from empty lists ($empty)',
      (tester) async {
        if (!empty) {
          harness.client.onReadDir = (_) async =>
              throw const HandshakeException();
        }
        await openPage(tester);
        await tester.ensureVisible(find.text('下载备份'));
        await tester.tap(find.text('下载备份'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('确认恢复'));
        await tester.pumpAndSettle();
        await waitForNotificationToDismiss(tester);

        expect(
          find.textContaining(empty ? 'WebDAV上没有找到备份文件' : webdavSSLMessage),
          findsOneWidget,
        );
        if (!empty) {
          expect(find.text('WebDAV上没有找到备份文件'), findsNothing);
        }
      },
    );
  }

  testWidgets('cancelling backup selection clears progress', (tester) async {
    harness.client.files = [webdav.File(name: 'backup.json')];
    await openPage(tester);
    await tester.ensureVisible(find.text('下载备份'));
    await tester.tap(find.text('下载备份'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认恢复'));
    // 选择对话框出现后，背景仍显示进度动画，不能等待所有动画停止。
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('选择备份文件'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    expect(find.text('正在从WebDAV获取备份列表...'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('SSL failure after selecting a backup remains visible', (
    tester,
  ) async {
    harness.client.files = [webdav.File(name: 'backup.json')];
    harness.client.onRead = (_) async => throw const HandshakeException();
    await openPage(tester);
    await tester.ensureVisible(find.text('下载备份'));
    await tester.tap(find.text('下载备份'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认恢复'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('backup.json'));
    await tester.pumpAndSettle();
    await waitForNotificationToDismiss(tester);

    expect(find.textContaining(webdavSSLMessage), findsOneWidget);
    expect(find.text('WebDAV上没有找到备份文件'), findsNothing);
    expect(find.text('备份恢复成功'), findsNothing);
  });

  testWidgets('successful upload keeps its result after loading ends', (
    tester,
  ) async {
    await openPage(tester);
    await tester.ensureVisible(find.text('上传备份'));
    await tester.tap(find.text('上传备份'));
    await tester.pumpAndSettle();
    await waitForNotificationToDismiss(tester);

    expect(find.text('备份已成功创建并上传到WebDAV'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(harness.client.uploads, hasLength(1));
  });
}
