import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pt_mate/services/app_update_flow_controller.dart';
import 'package:pt_mate/services/app_update_notification_service.dart';
import 'package:pt_mate/services/update_service.dart';
import 'package:pt_mate/widgets/update_notification_dialog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('shows the initial update actions before download starts', (
    tester,
  ) async {
    final controller = _buildController();

    await _pumpOpenDialog(tester, controller);

    expect(find.text('永不提醒'), findsOneWidget);
    expect(find.text('稍后提醒'), findsOneWidget);
    expect(find.text('立即更新'), findsOneWidget);
    expect(find.text('后台'), findsNothing);
    expect(find.text('取消'), findsNothing);
  });

  testWidgets('shows background and cancel actions while download is running', (
    tester,
  ) async {
    final controller = _buildController()
      ..setStateForTest(
        const AppUpdateFlowState(
          status: AppUpdateFlowStatus.downloading,
          message: '正在下载更新包 10%',
          progress: 0.1,
        ),
      );

    await _pumpOpenDialog(tester, controller);

    expect(find.text('永不提醒'), findsNothing);
    expect(find.text('稍后提醒'), findsNothing);
    expect(find.text('立即更新'), findsNothing);
    expect(find.text('后台'), findsOneWidget);
    expect(find.text('取消'), findsOneWidget);
  });
}

AppUpdateFlowController _buildController() {
  return AppUpdateFlowController(
    notificationService: _FakeNotificationService(),
    clearDownloadedApks: () async => 0,
    startAndroidUpdate:
        ({required updateResult, required onProgress, cancelToken}) async {},
  );
}

Future<void> _pumpOpenDialog(
  WidgetTester tester,
  AppUpdateFlowController controller,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) {
            return TextButton(
              onPressed: () {
                showDialog<void>(
                  context: context,
                  barrierDismissible: false,
                  builder: (_) => UpdateNotificationDialog(
                    updateResult: UpdateCheckResult(
                      hasUpdate: true,
                      latestVersion: '2.27.0',
                      releaseNotes: '更新内容',
                      androidDownloadUrl: 'https://example.com/app.apk',
                    ),
                    flowController: controller,
                  ),
                );
              },
              child: const Text('open'),
            );
          },
        ),
      ),
    ),
  );

  await tester.tap(find.text('open'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 250));
}

class _FakeNotificationService extends AppUpdateNotificationService {}
