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
  Future<TorrentSwipeMode> loadTorrentSwipeMode() =>
      storage.loadTorrentSwipeMode();

  @override
  Future<void> loadVisibleTags() => storage.loadVisibleTags();

  @override
  List<String> get visibleTags => storage.visibleTags;

  @override
  Future<void> saveVisibleTags(List<String> tags) async {
    throw StateError('test preference write failure');
  }

  @override
  Future<void> saveTorrentSwipeMode(TorrentSwipeMode mode) async {
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

  test(
    'swipe mode defaults to buttons and tolerates invalid local values',
    () async {
      final prefs = await SharedPreferences.getInstance();
      for (final value in <Object?>[null, 'unknown', true]) {
        if (value is String) {
          await prefs.setString(StorageKeys.torrentSwipeMode, value);
        }
        if (value is bool) {
          await prefs.setBool(StorageKeys.torrentSwipeMode, value);
        }
        final manager = DisplaySettingsManager(storage);
        addTearDown(manager.dispose);
        await Future<void>.delayed(Duration.zero);
        expect(manager.torrentSwipeMode, TorrentSwipeMode.revealButtons);
        expect(manager.isLoading, isFalse);
      }
    },
  );

  test(
    'swipe mode persists, notifies once and loads into a new manager',
    () async {
      final manager = DisplaySettingsManager(storage);
      addTearDown(manager.dispose);
      await Future<void>.delayed(Duration.zero);
      var notifications = 0;
      manager.addListener(() => notifications++);
      await manager.setTorrentSwipeMode(TorrentSwipeMode.swipeActions);
      await manager.setTorrentSwipeMode(TorrentSwipeMode.swipeActions);
      expect(manager.torrentSwipeMode, TorrentSwipeMode.swipeActions);
      expect(notifications, 1);
      final restored = DisplaySettingsManager(storage);
      addTearDown(restored.dispose);
      await Future<void>.delayed(Duration.zero);
      expect(restored.torrentSwipeMode, TorrentSwipeMode.swipeActions);
    },
  );

  test('failed swipe mode save retains value without notifying', () async {
    final manager = DisplaySettingsManager(_FailingTagStorage(storage));
    addTearDown(manager.dispose);
    await Future<void>.delayed(Duration.zero);
    var notifications = 0;
    manager.addListener(() => notifications++);
    await expectLater(
      manager.setTorrentSwipeMode(TorrentSwipeMode.swipeActions),
      throwsStateError,
    );
    expect(manager.torrentSwipeMode, TorrentSwipeMode.revealButtons);
    expect(
      await storage.loadTorrentSwipeMode(),
      TorrentSwipeMode.revealButtons,
    );
    expect(notifications, 0);
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
