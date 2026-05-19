import 'package:flutter_test/flutter_test.dart';
import 'package:pt_mate/services/settings/display_settings_manager.dart';
import 'package:pt_mate/services/storage/storage_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late StorageService storage;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    storage = StorageService.instance;
    storage.resetForTest();
  });

  test('loads show cover preference from storage', () async {
    await storage.saveShowCoverImages(false);

    final manager = DisplaySettingsManager(storage);
    await Future<void>.delayed(Duration.zero);

    expect(manager.isLoading, isFalse);
    expect(manager.showCoverImages, isFalse);
  });

  test('persists show cover preference and notifies listeners', () async {
    final manager = DisplaySettingsManager(storage);
    await Future<void>.delayed(Duration.zero);

    var notifyCount = 0;
    manager.addListener(() => notifyCount++);

    await manager.setShowCoverImages(false);

    expect(manager.showCoverImages, isFalse);
    expect(await storage.loadShowCoverImages(), isFalse);
    expect(notifyCount, 1);
  });
}
