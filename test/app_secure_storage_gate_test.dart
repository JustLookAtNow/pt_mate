import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pt_mate/app.dart';
import 'package:pt_mate/pages/server_settings_page.dart';
import 'package:pt_mate/services/storage/storage_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const secureStorageChannel = MethodChannel(
    'plugins.it_nomads.com/flutter_secure_storage',
  );
  final storage = StorageService.instance;

  setUp(() async {
    // A previous test may have started best-effort revision cleanup. Keep its
    // platform handler alive until it has finished before starting a new run.
    await storage.waitForPendingSecureStorageCleanup();
    SharedPreferences.setMockInitialValues({});
    storage.resetForTest();
    storage.overridePlatformForTest(TargetPlatform.iOS);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorageChannel, (call) async {
          if (call.method == 'read') {
            throw PlatformException(code: 'invalid_key');
          }
          return null;
        });

    try {
      await storage.initializeSecureStorage();
    } on SecureStorageUnavailableException {
      // 预检失败就是此测试要模拟的启动状态。
    }
  });

  tearDown(() async {
    await storage.waitForPendingSecureStorageCleanup();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorageChannel, null);
    storage.resetForTest();
  });

  testWidgets('app starts on the blocking page after preflight failure', (
    tester,
  ) async {
    await tester.pumpWidget(const MTeamApp());
    await tester.pump();

    expect(find.text('暂时无法读取安全存储'), findsOneWidget);
    expect(find.text('错误代码：invalid_key'), findsOneWidget);
    expect(find.text('进入备份恢复'), findsOneWidget);

    await tester.tap(find.text('进入备份恢复'));
    await _pumpUntilFound(tester, find.text('备份与恢复'));
    expect(find.text('备份与恢复'), findsOneWidget);
  });

  testWidgets('Linux KeyringLocked 使用明文 fallback 而不显示阻断页', (tester) async {
    storage.resetForTest();
    storage.overridePlatformForTest(TargetPlatform.linux);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorageChannel, (call) async {
          if (call.method == 'read') {
            throw PlatformException(
              code: 'KeyringLocked',
              message: 'KeyringLocked',
            );
          }
          return null;
        });

    await storage.initializeSecureStorage();
    await tester.pumpWidget(const MTeamApp());
    await _pumpUntilFound(tester, find.byType(ServerSettingsPage));

    expect(storage.canAccessSensitiveStorage, isTrue);
    expect(find.text('暂时无法读取安全存储'), findsNothing);
    expect(find.byType(ServerSettingsPage), findsOneWidget);
  });

  testWidgets('resume failure blocks the currently visible nested route', (
    tester,
  ) async {
    storage.resetForTest();
    storage.overridePlatformForTest(TargetPlatform.iOS);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorageChannel, (_) async => null);
    await storage.initializeSecureStorage();

    await tester.pumpWidget(const MTeamApp());
    await _pumpUntilFound(tester, find.byType(ServerSettingsPage));
    expect(find.byType(ServerSettingsPage), findsOneWidget);
    final appState = tester.state<MTeamAppState>(find.byType(MTeamApp));
    await _pumpUntilFutureCompletes(
      tester,
      appState.waitForAutomaticSyncForTest(),
    );

    var underlyingTapCount = 0;
    final underlyingFocus = FocusNode();
    addTearDown(underlyingFocus.dispose);
    final routeContext = tester.element(find.byType(ServerSettingsPage));
    Navigator.of(routeContext).push(
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          body: Center(
            child: FilledButton(
              focusNode: underlyingFocus,
              onPressed: () => underlyingTapCount++,
              child: const Text('underlying action'),
            ),
          ),
        ),
      ),
    );
    await _pumpUntilFound(tester, find.text('underlying action'));
    await tester.pump(const Duration(milliseconds: 350));
    underlyingFocus.requestFocus();
    await tester.pump();
    expect(underlyingFocus.hasFocus, isTrue);

    // Automatic restore and Cookie Cloud have been drained above. Startup
    // cleanup is generation-guarded and is covered independently by the
    // storage-service concurrency tests.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorageChannel, (call) async {
          if (call.method == 'read') {
            throw PlatformException(code: 'invalid_key');
          }
          return null;
        });
    await tester.runAsync(appState.recheckSecureStorageAfterResume);
    await tester.pump();

    expect(find.text('暂时无法读取安全存储'), findsOneWidget);
    expect(underlyingFocus.hasFocus, isFalse);
    final accessibleLabels = tester.semantics
        .simulatedAccessibilityTraversal()
        .map((node) => node.getSemanticsData().label);
    expect(accessibleLabels, isNot(contains('underlying action')));
    await tester.tap(find.text('underlying action'), warnIfMissed: false);
    await tester.pump();
    expect(underlyingTapCount, 0);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(underlyingTapCount, 0);
  });

  testWidgets(
    'healthy lifecycle resume does not flash gate or reload startup',
    (tester) async {
      storage.resetForTest();
      storage.overridePlatformForTest(TargetPlatform.iOS);
      var probeReads = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(secureStorageChannel, (call) async {
            if (call.method == 'read' &&
                call.arguments['key'] == '__ptmate_secure_storage_probe__') {
              probeReads++;
            }
            return null;
          });
      await storage.initializeSecureStorage();

      var webDavRuns = 0;
      var cookieCloudRuns = 0;
      final appState = AppState()
        ..overrideAutomaticSyncChecksForTest(
          webDav: () async => webDavRuns++,
          cookieCloud: () async => cookieCloudRuns++,
        );
      addTearDown(appState.dispose);

      await tester.pumpWidget(MTeamApp(appState: appState));
      await _pumpUntilFound(tester, find.byType(ServerSettingsPage));
      await _pumpUntilFutureCompletes(
        tester,
        appState.waitForAutomaticSyncForTest(),
      );
      final initialConfigVersion = appState.configVersion;
      expect((webDavRuns, cookieCloudRuns, probeReads), (1, 1, 1));

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      for (var index = 0; index < 100 && cookieCloudRuns < 2; index++) {
        await tester.pump(const Duration(milliseconds: 20));
        expect(find.text('暂时无法读取安全存储'), findsNothing);
      }

      expect((webDavRuns, cookieCloudRuns, probeReads), (1, 2, 2));
      expect(appState.configVersion, initialConfigVersion);
      expect(find.byType(ServerSettingsPage), findsOneWidget);
    },
  );

  testWidgets('successful explicit retry leaves the blocking page', (
    tester,
  ) async {
    await tester.pumpWidget(const MTeamApp());
    await tester.pump();
    expect(find.text('暂时无法读取安全存储'), findsOneWidget);

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorageChannel, (_) async => null);
    final appState = tester.state<MTeamAppState>(find.byType(MTeamApp));
    await tester.runAsync(appState.retrySecureStorageForTest);
    await _pumpUntilFound(tester, find.byType(ServerSettingsPage));
    await tester.runAsync(appState.waitForAutomaticSyncForTest);
    await tester.pump();

    expect(find.text('暂时无法读取安全存储'), findsNothing);
    expect(storage.secureStorageState, SecureStorageState.ready);
  });

  test('concurrent forced initialization shares one completion', () async {
    final appState = AppState();
    final first = _captureInitializationFailure(appState.loadInitial());
    final second = _captureInitializationFailure(
      appState.loadInitial(forceReload: true),
    );

    final failures = await Future.wait([
      first,
      second,
    ]).timeout(const Duration(seconds: 2));

    expect(failures, ['invalid_key', 'invalid_key']);
    appState.dispose();
  });
}

Future<void> _pumpUntilFound(
  WidgetTester tester,
  Finder finder, {
  int maxPumps = 100,
}) async {
  for (var index = 0; index < maxPumps; index++) {
    await tester.pump(const Duration(milliseconds: 20));
    if (finder.evaluate().isNotEmpty) return;
  }
  fail('Widget did not appear after $maxPumps bounded pumps: $finder');
}

Future<String?> _captureInitializationFailure(
  Future<void> initialization,
) async {
  try {
    await initialization;
    return null;
  } on SecureStorageUnavailableException catch (error) {
    return error.code;
  }
}

Future<void> _pumpUntilFutureCompletes(
  WidgetTester tester,
  Future<void> future, {
  int maxPumps = 100,
}) async {
  var completed = false;
  Object? failure;
  StackTrace? failureStackTrace;
  unawaited(
    future.then(
      (_) => completed = true,
      onError: (Object error, StackTrace stackTrace) {
        failure = error;
        failureStackTrace = stackTrace;
        completed = true;
      },
    ),
  );
  for (var index = 0; index < maxPumps && !completed; index++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
  if (!completed) {
    fail('Future did not complete after $maxPumps bounded pumps.');
  }
  if (failure != null) {
    Error.throwWithStackTrace(failure!, failureStackTrace!);
  }
}
