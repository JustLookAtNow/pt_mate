import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart';

import 'cookie_cloud_service.dart';
import '../storage/storage_service.dart';

class CookieCloudAutoSyncService {
  CookieCloudAutoSyncService._({
    StorageService? storage,
    CookieCloudService Function(StorageService storage)? serviceFactory,
  }) : _storage = storage ?? StorageService.instance,
       _serviceFactory =
           serviceFactory ??
           ((storage) => CookieCloudService(storage: storage));

  @visibleForTesting
  CookieCloudAutoSyncService.forTest({
    required StorageService storage,
    required CookieCloudService cookieCloudService,
  }) : this._(storage: storage, serviceFactory: (_) => cookieCloudService);

  static final CookieCloudAutoSyncService instance =
      CookieCloudAutoSyncService._();
  static final Logger _logger = Logger();

  final StorageService _storage;
  final CookieCloudService Function(StorageService storage) _serviceFactory;

  bool _running = false;

  Future<void> syncIfNeeded({bool force = false}) async {
    final storage = _storage;
    if (_running) return;
    _running = true;
    try {
      await storage.runWithCurrentSecureStorageOperation((epoch) async {
        final config = await storage.loadCookieCloudConfig();
        if (!config.autoSyncEnabled || !config.isConfigured) return;
        if (!force && config.lastSyncAt != null) {
          final dueAt = config.lastSyncAt!.add(
            Duration(minutes: config.syncIntervalMinutes),
          );
          if (DateTime.now().isBefore(dueAt)) return;
        }

        final service = _serviceFactory(storage);
        final plan = await service.fetchSyncPlan(config);
        storage.requireSecureStorageOperationEpoch(epoch);
        final updates = plan.updates.toSet();
        if (updates.isEmpty) {
          await storage.saveCookieCloudLastSync(
            syncedAt: DateTime.now(),
            summary: '没有可更新的站点',
            expectedSecureStorageEpoch: epoch,
          );
          return;
        }
        storage.requireSecureStorageOperationEpoch(epoch);
        await service.applyPlan(
          plan,
          selectedUpdates: updates,
          selectedAdditions: <CookieCloudCandidate>{},
        );
      });
    } on SecureStorageUnavailableException {
      return;
    } catch (e, s) {
      if (kDebugMode) {
        _logger.w('Cookie Cloud 自动同步失败', error: e, stackTrace: s);
      }
    } finally {
      _running = false;
    }
  }
}
