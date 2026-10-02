import 'package:flutter_test/flutter_test.dart';
import 'package:pt_mate/models/app_models.dart';
import 'package:pt_mate/services/settings/display_settings_manager.dart';
import 'package:pt_mate/services/storage/storage_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FailingTagStorage implements StorageService {
  final StorageService storage;

  _FailingTagStorage(this.storage);

  @override
  Future<bool> loadShowCoverImages() => storage.loadShowCoverImages();

  @override
  Future<void> loadVisibleTags() => storage.loadVisibleTags();

  @override
  List<String> get visibleTags => storage.visibleTags;

  @override
  Future<void> saveVisibleTags(List<String> tags) async {
    throw StateError('test preference write failure');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

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

  test('visible tags default to all tags and are read only', () async {
    final manager = DisplaySettingsManager(storage);
    addTearDown(manager.dispose);
    await Future<void>.delayed(Duration.zero);

    expect(manager.visibleTags, TagType.values.map((tag) => tag.name).toSet());
    expect(() => manager.visibleTags.clear(), throwsUnsupportedError);
  });

  for (final tags in <Set<String>>[
    {TagType.fourK.name, TagType.h265.name},
    {},
  ]) {
    test('loads persisted visible tags: $tags', () async {
      await storage.saveVisibleTags(tags.toList());
      storage.resetForTest();
      final manager = DisplaySettingsManager(storage);
      addTearDown(manager.dispose);
      await Future<void>.delayed(Duration.zero);

      expect(manager.isLoading, isFalse);
      expect(manager.visibleTags, tags);
    });
  }

  test('persists a snapshot of visible tags and notifies once', () async {
    final manager = DisplaySettingsManager(storage);
    addTearDown(manager.dispose);
    await Future<void>.delayed(Duration.zero);
    var notifyCount = 0;
    manager.addListener(() => notifyCount++);
    final tags = {TagType.fourK.name};

    final save = manager.setVisibleTags(tags);
    tags.add(TagType.h265.name);
    await save;

    expect(manager.visibleTags, {TagType.fourK.name});
    expect(storage.visibleTags, [TagType.fourK.name]);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList(StorageKeys.visibleTags), [TagType.fourK.name]);
    expect(notifyCount, 1);

    await manager.setVisibleTags({TagType.fourK.name});
    expect(notifyCount, 1);
  });

  test('failed save retains visible tags without notifying', () async {
    await storage.saveVisibleTags([TagType.fourK.name]);
    final manager = DisplaySettingsManager(_FailingTagStorage(storage));
    addTearDown(manager.dispose);
    await Future<void>.delayed(Duration.zero);
    var notifyCount = 0;
    manager.addListener(() => notifyCount++);

    await expectLater(manager.setVisibleTags({}), throwsStateError);

    expect(manager.visibleTags, {TagType.fourK.name});
    expect(storage.visibleTags, [TagType.fourK.name]);
    expect(notifyCount, 0);
  });
}
