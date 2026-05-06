import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pt_mate/utils/notification_helper.dart';

void main() {
  testWidgets('长文本通知使用固定圆角并限制最大行数', (tester) async {
    await tester.pumpWidget(const _NotificationTestApp());

    await tester.tap(find.byKey(const Key('show_long')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.byKey(const Key('notification_helper_toast')), findsOneWidget);

    final material = tester.widget<Material>(
      find.byKey(const Key('notification_helper_toast')),
    );
    final shape = material.shape! as RoundedRectangleBorder;
    expect(
      shape.borderRadius,
      equals(const BorderRadius.all(Radius.circular(18))),
    );

    final text = tester.widget<Text>(
      find.byKey(const Key('notification_helper_message')),
    );
    expect(text.maxLines, 4);
    expect(text.overflow, TextOverflow.ellipsis);
    expect(tester.takeException(), isNull);

    await _cleanupNotification(tester);
  });

  testWidgets('通知会自动消失', (tester) async {
    await tester.pumpWidget(const _NotificationTestApp());

    await tester.tap(find.byKey(const Key('show_short')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.text('短通知'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.text('短通知'), findsNothing);

    await _cleanupNotification(tester);
  });

  testWidgets('通知显示期间不会阻塞底部 FAB 点击', (tester) async {
    await tester.pumpWidget(const _NotificationTestApp());

    await tester.tap(find.byKey(const Key('show_short')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    await tester.tap(find.byKey(const Key('fab')));
    await tester.pump();

    expect(find.text('fab taps: 1'), findsOneWidget);

    await _cleanupNotification(tester);
  });

  testWidgets('新通知会替换旧通知', (tester) async {
    await tester.pumpWidget(const _NotificationTestApp());

    await tester.tap(find.byKey(const Key('show_first')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('第一条通知'), findsOneWidget);

    await tester.tap(find.byKey(const Key('show_second')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.text('第一条通知'), findsNothing);
    expect(find.text('第二条通知'), findsOneWidget);

    await _cleanupNotification(tester);
  });
}

Future<void> _cleanupNotification(WidgetTester tester) async {
  NotificationHelper.resetForTest();
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
}

class _NotificationTestApp extends StatefulWidget {
  const _NotificationTestApp();

  @override
  State<_NotificationTestApp> createState() => _NotificationTestAppState();
}

class _NotificationTestAppState extends State<_NotificationTestApp> {
  static const _longMessage =
      '这是一条很长很长的通知消息，用来验证顶部通知在多行场景下不会出现文字越界，同时圆角仍然保持稳定，不会变成左右两端的半圆胶囊样式。';

  int _fabTaps = 0;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: SafeArea(
          child: Builder(
            builder: (context) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ElevatedButton(
                    key: const Key('show_short'),
                    onPressed: () {
                      NotificationHelper.showInfo(
                        context,
                        '短通知',
                        duration: const Duration(milliseconds: 500),
                      );
                    },
                    child: const Text('show_short'),
                  ),
                  ElevatedButton(
                    key: const Key('show_long'),
                    onPressed: () {
                      NotificationHelper.showInfo(
                        context,
                        _longMessage,
                        duration: const Duration(seconds: 2),
                      );
                    },
                    child: const Text('show_long'),
                  ),
                  ElevatedButton(
                    key: const Key('show_first'),
                    onPressed: () {
                      NotificationHelper.showInfo(
                        context,
                        '第一条通知',
                        duration: const Duration(seconds: 2),
                      );
                    },
                    child: const Text('show_first'),
                  ),
                  ElevatedButton(
                    key: const Key('show_second'),
                    onPressed: () {
                      NotificationHelper.showError(
                        context,
                        '第二条通知',
                        duration: const Duration(seconds: 2),
                      );
                    },
                    child: const Text('show_second'),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text('fab taps: $_fabTaps'),
                  ),
                ],
              );
            },
          ),
        ),
        floatingActionButton: FloatingActionButton(
          key: const Key('fab'),
          onPressed: () {
            setState(() {
              _fabTaps++;
            });
          },
          child: const Icon(Icons.add),
        ),
      ),
    );
  }
}
