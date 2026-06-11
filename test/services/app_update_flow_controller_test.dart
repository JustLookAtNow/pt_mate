import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pt_mate/services/app_update_downloader.dart';
import 'package:pt_mate/services/app_update_flow_controller.dart';
import 'package:pt_mate/services/app_update_notification_service.dart';
import 'package:pt_mate/services/update_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  UpdateCheckResult updateResult() => UpdateCheckResult(
    hasUpdate: true,
    latestVersion: '2.27.0',
    androidDownloadUrl: 'https://example.com/app.apk',
  );

  test(
    'keeps running when the dialog would be dismissed to background',
    () async {
      final releaseDownload = Completer<void>();
      var startCount = 0;
      final controller = AppUpdateFlowController(
        notificationService: _FakeNotificationService(),
        clearDownloadedApks: () async => 0,
        startAndroidUpdate:
            ({
              required UpdateCheckResult updateResult,
              required ValueChanged<AppUpdateProgress> onProgress,
              AppUpdateCancelToken? cancelToken,
            }) async {
              startCount++;
              onProgress(
                const AppUpdateProgress(message: '正在下载更新包 10%', progress: 0.1),
              );
              await releaseDownload.future;
            },
      );

      final startFuture = controller.start(updateResult());
      await _pumpEventQueue();

      expect(controller.state.status, AppUpdateFlowStatus.downloading);
      expect(controller.state.isRunning, isTrue);
      expect(controller.currentUpdateResult?.latestVersion, '2.27.0');
      expect(startCount, 1);

      releaseDownload.complete();
      await startFuture;

      expect(controller.state.status, AppUpdateFlowStatus.installing);
    },
  );

  test('cancel stops the active download and enters canceled state', () async {
    final releaseDownload = Completer<void>();
    AppUpdateCancelToken? capturedToken;
    final controller = AppUpdateFlowController(
      notificationService: _FakeNotificationService(),
      clearDownloadedApks: () async => 0,
      startAndroidUpdate:
          ({
            required UpdateCheckResult updateResult,
            required ValueChanged<AppUpdateProgress> onProgress,
            AppUpdateCancelToken? cancelToken,
          }) async {
            capturedToken = cancelToken;
            onProgress(
              const AppUpdateProgress(message: '正在下载更新包 20%', progress: 0.2),
            );
            await releaseDownload.future;
            cancelToken?.throwIfCanceled();
          },
    );

    final startFuture = controller.start(updateResult());
    await _pumpEventQueue();

    controller.cancel();
    releaseDownload.complete();
    await startFuture;

    expect(capturedToken?.isCanceled, isTrue);
    expect(controller.state.status, AppUpdateFlowStatus.canceled);
  });

  test('notification cancel action uses the same cancel flow', () async {
    final releaseDownload = Completer<void>();
    final notificationService = _FakeNotificationService();
    final controller = AppUpdateFlowController(
      notificationService: notificationService,
      clearDownloadedApks: () async => 0,
      startAndroidUpdate:
          ({
            required UpdateCheckResult updateResult,
            required ValueChanged<AppUpdateProgress> onProgress,
            AppUpdateCancelToken? cancelToken,
          }) async {
            onProgress(
              const AppUpdateProgress(message: '正在下载更新包 30%', progress: 0.3),
            );
            await releaseDownload.future;
            cancelToken?.throwIfCanceled();
          },
    );

    final startFuture = controller.start(updateResult());
    await _pumpEventQueue();

    notificationService.triggerCancel();
    releaseDownload.complete();
    await startFuture;

    expect(controller.state.status, AppUpdateFlowStatus.canceled);
  });

  test('does not start a second download while one is running', () async {
    final releaseDownload = Completer<void>();
    var startCount = 0;
    final controller = AppUpdateFlowController(
      notificationService: _FakeNotificationService(),
      clearDownloadedApks: () async => 0,
      startAndroidUpdate:
          ({
            required UpdateCheckResult updateResult,
            required ValueChanged<AppUpdateProgress> onProgress,
            AppUpdateCancelToken? cancelToken,
          }) async {
            startCount++;
            onProgress(
              const AppUpdateProgress(message: '正在下载更新包 10%', progress: 0.1),
            );
            await releaseDownload.future;
          },
    );

    final firstStart = controller.start(updateResult());
    await _pumpEventQueue();
    final secondStart = controller.start(updateResult());
    await secondStart;

    expect(startCount, 1);

    releaseDownload.complete();
    await firstStart;
  });

  test('notification failure does not stop the download', () async {
    final controller = AppUpdateFlowController(
      notificationService: _ThrowingNotificationService(),
      clearDownloadedApks: () async => 0,
      startAndroidUpdate:
          ({
            required UpdateCheckResult updateResult,
            required ValueChanged<AppUpdateProgress> onProgress,
            AppUpdateCancelToken? cancelToken,
          }) async {
            onProgress(
              const AppUpdateProgress(
                message: '下载完成，正在打开安装界面...',
                progress: 1,
                isFinal: true,
              ),
            );
          },
    );

    await controller.start(updateResult());

    expect(controller.state.status, AppUpdateFlowStatus.installing);
  });
}

Future<void> _pumpEventQueue() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

class _FakeNotificationService extends AppUpdateNotificationService {
  VoidCallback? onCancelRequested;
  final shownMessages = <String>[];

  @override
  Future<void> initialize({VoidCallback? onCancelRequested}) async {
    this.onCancelRequested = onCancelRequested;
  }

  @override
  Future<void> showPreparing(String message) async {
    shownMessages.add(message);
  }

  @override
  Future<void> showProgress({
    required String message,
    required double? progress,
  }) async {
    shownMessages.add(message);
  }

  @override
  Future<void> showInstalling(String message) async {
    shownMessages.add(message);
  }

  @override
  Future<void> showCanceled() async {
    shownMessages.add('canceled');
  }

  @override
  Future<void> showFailed(String message) async {
    shownMessages.add(message);
  }

  void triggerCancel() {
    onCancelRequested?.call();
  }
}

class _ThrowingNotificationService extends _FakeNotificationService {
  @override
  Future<void> initialize({VoidCallback? onCancelRequested}) async {
    throw StateError('notifications unavailable');
  }

  @override
  Future<void> showPreparing(String message) async {
    throw StateError('notifications unavailable');
  }

  @override
  Future<void> showProgress({
    required String message,
    required double? progress,
  }) async {
    throw StateError('notifications unavailable');
  }

  @override
  Future<void> showInstalling(String message) async {
    throw StateError('notifications unavailable');
  }
}
