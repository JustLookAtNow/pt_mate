import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pt_mate/services/site_health_refresh_service.dart';
import 'package:pt_mate/services/storage/storage_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const MethodChannel channel = MethodChannel(
    'plugins.it_nomads.com/flutter_secure_storage',
  );

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    StorageService.instance.resetForTest();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
          return null;
        });
  });

  test('未达到刷新间隔时跳过自动刷新', () async {
    await StorageService.instance.saveLastSiteHealthRefreshCheck(
      DateTime.now(),
    );

    final result = await SiteHealthRefreshService.instance.refreshIfNeeded();

    expect(result, isNull);
  });

  test('首次自动刷新在无站点时也会记录刷新时间', () async {
    final result = await SiteHealthRefreshService.instance.refreshIfNeeded();

    expect(result, isEmpty);
    expect(
      await StorageService.instance.loadLastSiteHealthRefreshCheck(),
      isNotNull,
    );
  });
}
