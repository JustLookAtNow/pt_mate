import 'dart:async';

import 'package:flutter/foundation.dart';

import 'android_install_permission_service.dart';
import 'app_update_downloader.dart';
import 'app_update_notification_service.dart';
import 'update_service.dart';

enum AppUpdateFlowStatus {
  idle,
  preparing,
  probing,
  downloading,
  installing,
  canceled,
  failed,
}

@immutable
class AppUpdateFlowState {
  final AppUpdateFlowStatus status;
  final String? message;
  final double? progress;
  final Object? error;

  const AppUpdateFlowState({
    required this.status,
    this.message,
    this.progress,
    this.error,
  });

  const AppUpdateFlowState.idle()
    : status = AppUpdateFlowStatus.idle,
      message = null,
      progress = null,
      error = null;

  bool get isRunning =>
      status == AppUpdateFlowStatus.preparing ||
      status == AppUpdateFlowStatus.probing ||
      status == AppUpdateFlowStatus.downloading;

  bool get canCancel => isRunning;
}

typedef StartAndroidUpdate =
    Future<void> Function({
      required UpdateCheckResult updateResult,
      required ValueChanged<AppUpdateProgress> onProgress,
      AppUpdateCancelToken? cancelToken,
    });

class AppUpdateFlowController extends ChangeNotifier {
  AppUpdateFlowController({
    StartAndroidUpdate? startAndroidUpdate,
    Future<int> Function()? clearDownloadedApks,
    AppUpdateNotificationService? notificationService,
  }) : _startAndroidUpdate =
           startAndroidUpdate ??
           AppUpdateDownloader.instance.startAndroidUpdate,
       _clearDownloadedApks =
           clearDownloadedApks ??
           AndroidInstallPermissionService.instance.clearDownloadedApks,
       _notificationService =
           notificationService ?? AppUpdateNotificationService.instance;

  static final AppUpdateFlowController instance = AppUpdateFlowController();

  final StartAndroidUpdate _startAndroidUpdate;
  final Future<int> Function() _clearDownloadedApks;
  final AppUpdateNotificationService _notificationService;

  AppUpdateFlowState _state = const AppUpdateFlowState.idle();
  AppUpdateCancelToken? _cancelToken;
  UpdateCheckResult? _currentUpdateResult;
  int _runId = 0;

  AppUpdateFlowState get state => _state;
  UpdateCheckResult? get currentUpdateResult => _currentUpdateResult;

  Future<void> start(UpdateCheckResult updateResult) async {
    if (_state.isRunning) return;

    final runId = ++_runId;
    final cancelToken = AppUpdateCancelToken();
    _cancelToken = cancelToken;
    _currentUpdateResult = updateResult;

    _setState(
      runId,
      const AppUpdateFlowState(
        status: AppUpdateFlowStatus.preparing,
        message: '正在清理旧安装包...',
      ),
    );
    await _runNotification(
      () => _notificationService.initialize(onCancelRequested: cancel),
    );
    _notifyInBackground(
      () => _notificationService.showPreparing('正在清理旧安装包...'),
    );

    try {
      await _clearDownloadedApks();
      cancelToken.throwIfCanceled();

      _setState(
        runId,
        const AppUpdateFlowState(
          status: AppUpdateFlowStatus.probing,
          message: '正在测速下载源...',
        ),
      );
      _notifyInBackground(
        () => _notificationService.showPreparing('正在测速下载源...'),
      );

      await _startAndroidUpdate(
        updateResult: updateResult,
        cancelToken: cancelToken,
        onProgress: (progress) {
          if (cancelToken.isCanceled) return;

          final nextStatus = _statusForProgress(progress);
          final nextState = AppUpdateFlowState(
            status: nextStatus,
            message: progress.message,
            progress: progress.progress,
          );
          _setState(runId, nextState);

          if (nextStatus == AppUpdateFlowStatus.installing) {
            _notifyInBackground(
              () => _notificationService.showInstalling(progress.message),
            );
          } else {
            _notifyInBackground(
              () => _notificationService.showProgress(
                message: progress.message,
                progress: progress.progress,
              ),
            );
          }
        },
      );

      if (cancelToken.isCanceled) {
        throw const AppUpdateCanceledException();
      }

      if (_state.status != AppUpdateFlowStatus.installing) {
        _setState(
          runId,
          const AppUpdateFlowState(
            status: AppUpdateFlowStatus.installing,
            message: '下载完成，正在打开安装界面...',
            progress: 1,
          ),
        );
        _notifyInBackground(
          () => _notificationService.showInstalling('下载完成，正在打开安装界面...'),
        );
      }
    } on AppUpdateCanceledException {
      _setCanceled(runId);
    } catch (e) {
      if (cancelToken.isCanceled) {
        _setCanceled(runId);
      } else {
        _setState(
          runId,
          AppUpdateFlowState(
            status: AppUpdateFlowStatus.failed,
            message: '应用内更新失败：$e',
            error: e,
          ),
        );
        _notifyInBackground(
          () => _notificationService.showFailed(e.toString()),
        );
      }
    } finally {
      if (identical(_cancelToken, cancelToken)) {
        _cancelToken = null;
      }
    }
  }

  void cancel() {
    final cancelToken = _cancelToken;
    if (cancelToken == null || !state.canCancel) return;

    cancelToken.cancel();
    _setCanceled(_runId);
  }

  void resetIfFinished() {
    if (_state.isRunning) return;
    _currentUpdateResult = null;
    _state = const AppUpdateFlowState.idle();
    notifyListeners();
  }

  @visibleForTesting
  void setStateForTest(AppUpdateFlowState state) {
    _state = state;
    notifyListeners();
  }

  AppUpdateFlowStatus _statusForProgress(AppUpdateProgress progress) {
    if (progress.isFinal) {
      return AppUpdateFlowStatus.installing;
    }
    if (progress.progress != null) {
      return AppUpdateFlowStatus.downloading;
    }

    final message = progress.message;
    if (message.contains('下载更新包') ||
        message.contains('正在使用') ||
        message.contains('正在切换到')) {
      return AppUpdateFlowStatus.downloading;
    }
    return AppUpdateFlowStatus.probing;
  }

  void _setCanceled(int runId) {
    if (runId != _runId || _state.status == AppUpdateFlowStatus.canceled) {
      return;
    }

    _setState(
      runId,
      const AppUpdateFlowState(
        status: AppUpdateFlowStatus.canceled,
        message: '更新下载已取消',
      ),
    );
    _notifyInBackground(_notificationService.showCanceled);
  }

  void _setState(int runId, AppUpdateFlowState state) {
    if (runId != _runId) return;
    _state = state;
    notifyListeners();
  }

  void _notifyInBackground(Future<void> Function() action) {
    unawaited(_runNotification(action));
  }

  Future<void> _runNotification(Future<void> Function() action) async {
    try {
      await action();
    } catch (_) {
      // Notification availability must not affect the update download flow.
    }
  }
}
