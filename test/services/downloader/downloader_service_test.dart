import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pt_mate/services/downloader/downloader_service.dart';
import 'package:pt_mate/services/downloader/downloader_config.dart';

import 'package:pt_mate/services/storage/storage_service.dart';

// Mock DownloaderService to override getVersion and avoid network calls
class MockDownloaderService extends DownloaderService {
  final String versionToReturn;
  final bool shouldThrow;

  MockDownloaderService({
    super.storageService,
    this.versionToReturn = '4.5.2',
    this.shouldThrow = false,
  }) : super.test();


  @override
  Future<String> getVersion({
    required DownloaderConfig config,
    required String password,
  }) async {
    if (shouldThrow) {
      throw Exception('Network error');
    }
    return versionToReturn;
  }
}

void main() {
  group('DownloaderService Tests', () {
    late StorageService storageService;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      storageService = StorageService.instance;
    });

    test('getUpdatedConfigAndSave should return existing config if version is present', () async {
      final config = QbittorrentConfig(
        id: 'test_id',
        name: 'Test QB',
        host: '127.0.0.1',
        port: 8080,
        username: 'admin',
        password: 'password',
        version: '4.5.0',
      );

      final service = MockDownloaderService(storageService: storageService);

      // Save initial config
      await storageService.saveDownloaderConfigs([config]);

      final result = await service.getUpdatedConfigAndSave(
        config: config,
        password: 'password',
      );

      expect(result.version, '4.5.0');

      // Verify no changes in storage
      final savedConfigs = await storageService.loadDownloaderConfigs();
      final savedConfig = DownloaderConfig.fromJson(savedConfigs.first);
      expect(savedConfig.version, '4.5.0');
    });

    test('getUpdatedConfigAndSave should fetch version and save if version is missing', () async {
      final config = QbittorrentConfig(
        id: 'test_id',
        name: 'Test QB',
        host: '127.0.0.1',
        port: 8080,
        username: 'admin',
        password: 'password',
        version: null,
      );

      final service = MockDownloaderService(
        storageService: storageService,
        versionToReturn: '4.5.2',
      );

      // Save initial config
      await storageService.saveDownloaderConfigs([config]);

      final result = await service.getUpdatedConfigAndSave(
        config: config,
        password: 'password',
      );

      expect(result.version, '4.5.2');

      // Verify changes in storage
      final savedConfigs = await storageService.loadDownloaderConfigs();
      final savedConfig = DownloaderConfig.fromJson(savedConfigs.first);
      expect(savedConfig.version, '4.5.2');
    });

    test('getUpdatedConfigAndSave should return original config and not save on error', () async {
      final config = QbittorrentConfig(
        id: 'test_id',
        name: 'Test QB',
        host: '127.0.0.1',
        port: 8080,
        username: 'admin',
        password: 'password',
        version: null,
      );

      final service = MockDownloaderService(
        storageService: storageService,
        shouldThrow: true,
      );

      // Save initial config
      await storageService.saveDownloaderConfigs([config]);

      final result = await service.getUpdatedConfigAndSave(
        config: config,
        password: 'password',
      );

      // Should return original config (null version)
      expect(result.version, null);

      // Verify no changes in storage
      final savedConfigs = await storageService.loadDownloaderConfigs();
      final savedConfig = DownloaderConfig.fromJson(savedConfigs.first);
      expect(savedConfig.version, null);
    });

    test('getUpdatedConfigAndSave should not save if autoSave is false', () async {
      final config = QbittorrentConfig(
        id: 'test_id',
        name: 'Test QB',
        host: '127.0.0.1',
        port: 8080,
        username: 'admin',
        password: 'password',
        version: null,
      );

      final service = MockDownloaderService(
        storageService: storageService,
        versionToReturn: '4.5.2',
      );

      // Save initial config
      await storageService.saveDownloaderConfigs([config]);

      final result = await service.getUpdatedConfigAndSave(
        config: config,
        password: 'password',
        autoSave: false,
      );

      // Returned config should have new version
      expect(result.version, '4.5.2');

      // But storage should still have old config (null version)
      final savedConfigs = await storageService.loadDownloaderConfigs();
      final savedConfig = DownloaderConfig.fromJson(savedConfigs.first);
      expect(savedConfig.version, null);
    });
  });
}
