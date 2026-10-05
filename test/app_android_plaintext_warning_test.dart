import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pt_mate/app.dart';
import 'package:pt_mate/services/storage/android_secure_storage_profile_resolver.dart';
import 'package:pt_mate/services/storage/storage_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const profileChannel = MethodChannel('pt_mate/secure_storage_profile');
  final storage = StorageService.instance;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    storage.resetForTest();
    storage.overridePlatformForTest(TargetPlatform.android);
    storage.overrideAndroidSecureStorageProfileForTest(
      AndroidSecureStorageProfile.plaintext,
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(profileChannel, (_) async => null);
    await storage.initializeSecureStorage();
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(profileChannel, null);
    storage.resetForTest();
  });

  testWidgets('首次进入应用时显示可关闭的 Android 明文存储警告', (tester) async {
    await tester.pumpWidget(const MTeamApp());
    await tester.pump();

    expect(find.textContaining('此 Android 设备不支持 OAEP+GCM'), findsOneWidget);
    expect(find.text('我已知晓'), findsOneWidget);

    await tester.tap(find.text('我已知晓'));
    await tester.pump();
    expect(find.textContaining('此 Android 设备不支持 OAEP+GCM'), findsNothing);
  });
}
