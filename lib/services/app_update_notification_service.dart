import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class AppUpdateNotificationService {
  AppUpdateNotificationService({FlutterLocalNotificationsPlugin? plugin})
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  static final AppUpdateNotificationService instance =
      AppUpdateNotificationService();

  static const int notificationId = 26001;
  static const String cancelActionId = 'cancel_app_update';
  static const String _channelId = 'app_update_download_v2';
  static const String _channelName = '应用更新下载';
  static const String _channelDescription = '显示应用更新包下载进度';

  final FlutterLocalNotificationsPlugin _plugin;
  bool _initialized = false;
  bool _available = true;
  VoidCallback? _onCancelRequested;

  Future<void> initialize({VoidCallback? onCancelRequested}) async {
    _onCancelRequested = onCancelRequested ?? _onCancelRequested;
    if (_initialized || !_available) return;

    try {
      const androidSettings = AndroidInitializationSettings('ic_stat_update');
      const settings = InitializationSettings(android: androidSettings);
      await _plugin.initialize(
        settings: settings,
        onDidReceiveNotificationResponse: (response) {
          if (response.actionId == cancelActionId) {
            _onCancelRequested?.call();
          }
        },
      );

      final android = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      await android?.requestNotificationsPermission();
      _initialized = true;
    } catch (_) {
      _available = false;
    }
  }

  Future<void> showPreparing(String message) async {
    await _show(
      title: '正在下载更新',
      body: message,
      progress: null,
      indeterminate: true,
      ongoing: true,
      withCancelAction: true,
    );
  }

  Future<void> showProgress({
    required String message,
    required double? progress,
  }) async {
    await _show(
      title: '正在下载更新',
      body: message,
      progress: progress,
      indeterminate: progress == null,
      ongoing: true,
      withCancelAction: true,
    );
  }

  Future<void> showInstalling(String message) async {
    await _show(
      title: '更新包下载完成',
      body: message,
      progress: 1,
      indeterminate: false,
      ongoing: false,
      withCancelAction: false,
    );
  }

  Future<void> showCanceled() async {
    await _show(
      title: '更新下载已取消',
      body: '可稍后重新检查更新',
      progress: null,
      indeterminate: false,
      ongoing: false,
      withCancelAction: false,
    );
  }

  Future<void> showFailed(String message) async {
    await _show(
      title: '更新下载失败',
      body: message,
      progress: null,
      indeterminate: false,
      ongoing: false,
      withCancelAction: false,
    );
  }

  Future<void> _show({
    required String title,
    required String body,
    required double? progress,
    required bool indeterminate,
    required bool ongoing,
    required bool withCancelAction,
  }) async {
    await initialize();
    if (!_available) return;

    final normalizedProgress = progress == null
        ? 0
        : (progress.clamp(0, 1) * 100).round();
    final details = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDescription,
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
      playSound: false,
      enableVibration: false,
      onlyAlertOnce: true,
      showProgress: indeterminate || progress != null,
      maxProgress: 100,
      progress: normalizedProgress,
      indeterminate: indeterminate,
      ongoing: ongoing,
      autoCancel: !ongoing,
      actions: withCancelAction
          ? const [
              AndroidNotificationAction(
                cancelActionId,
                '取消',
                showsUserInterface: true,
                cancelNotification: false,
              ),
            ]
          : null,
    );

    try {
      await _plugin.show(
        id: notificationId,
        title: title,
        body: body,
        notificationDetails: NotificationDetails(android: details),
      );
    } catch (_) {
      if (withCancelAction) {
        await _show(
          title: title,
          body: body,
          progress: progress,
          indeterminate: indeterminate,
          ongoing: ongoing,
          withCancelAction: false,
        );
        return;
      }
      _available = false;
    }
  }
}
