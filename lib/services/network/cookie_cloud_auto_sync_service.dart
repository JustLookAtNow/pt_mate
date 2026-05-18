import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart';

import 'cookie_cloud_service.dart';
import '../storage/storage_service.dart';

class CookieCloudAutoSyncService {
  CookieCloudAutoSyncService._();

  static final CookieCloudAutoSyncService instance =
      CookieCloudAutoSyncService._();
  static final Logger _logger = Logger();

  bool _running = false;

  Future<void> syncIfNeeded({bool force = false}) async {
    if (_running) return;
    _running = true;
    try {
      final storage = StorageService.instance;
      final config = await storage.loadCookieCloudConfig();
      if (!config.autoSyncEnabled || !config.isConfigured) return;
      if (!force && config.lastSyncAt != null) {
        final dueAt = config.lastSyncAt!.add(
          Duration(minutes: config.syncIntervalMinutes),
        );
        if (DateTime.now().isBefore(dueAt)) return;
      }

      final service = CookieCloudService(storage: storage);
      final plan = await service.fetchSyncPlan(config);
      final updates = plan.updates.toSet();
      if (updates.isEmpty) {
        await storage.saveCookieCloudLastSync(
          syncedAt: DateTime.now(),
          summary: '没有可更新的站点',
        );
        return;
      }
      await service.applyPlan(
        plan,
        selectedUpdates: updates,
        selectedAdditions: <CookieCloudCandidate>{},
      );
    } catch (e, s) {
      if (kDebugMode) {
        _logger.w('Cookie Cloud 自动同步失败', error: e, stackTrace: s);
      }
    } finally {
      _running = false;
    }
  }
}
