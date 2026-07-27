import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart';

import '../models/app_models.dart';
import 'api/api_service.dart';
import 'storage/storage_service.dart';

class SiteHealthRefreshService {
  SiteHealthRefreshService._();

  static final SiteHealthRefreshService instance = SiteHealthRefreshService._();
  static final Logger _logger = Logger();
  static const Duration _refreshInterval = Duration(hours: 24);

  Future<Map<String, HealthStatus>?> refreshIfNeeded() async {
    final storage = StorageService.instance;
    try {
      return await storage.runWithCurrentSecureStorageOperation((epoch) async {
        if (!await _shouldRefresh()) {
          if (kDebugMode) {
            _logger.d('SiteHealthRefreshService: 未达到自动刷新间隔，跳过');
          }
          return null;
        }
        storage.requireSecureStorageOperationEpoch(epoch);
        return _refreshAllSitesInCurrentEpoch(
          force: true,
          persistLastRefreshTime: true,
          onStatus: null,
          epoch: epoch,
        );
      });
    } on SecureStorageUnavailableException {
      return null;
    }
  }

  Future<Map<String, HealthStatus>> refreshAllSites({
    bool force = false,
    bool persistLastRefreshTime = false,
    void Function(String siteId, HealthStatus status)? onStatus,
    int? expectedSecureStorageEpoch,
  }) {
    final storage = StorageService.instance;
    final expected = expectedSecureStorageEpoch;
    if (expected != null) {
      return storage.runWithSecureStorageOperationEpoch(
        expected,
        () => _refreshAllSitesInCurrentEpoch(
          force: force,
          persistLastRefreshTime: persistLastRefreshTime,
          onStatus: onStatus,
          epoch: expected,
        ),
      );
    }
    return storage.runWithCurrentSecureStorageOperation(
      (epoch) => _refreshAllSitesInCurrentEpoch(
        force: force,
        persistLastRefreshTime: persistLastRefreshTime,
        onStatus: onStatus,
        epoch: epoch,
      ),
    );
  }

  Future<Map<String, HealthStatus>> _refreshAllSitesInCurrentEpoch({
    required bool force,
    required bool persistLastRefreshTime,
    required void Function(String siteId, HealthStatus status)? onStatus,
    required int epoch,
  }) async {
    final storage = StorageService.instance;
    storage.requireSecureStorageOperationEpoch(epoch);
    if (!force && !await _shouldRefresh()) {
      storage.requireSecureStorageOperationEpoch(epoch);
      return <String, HealthStatus>{};
    }

    final allSites = await storage.loadSiteConfigs(includeApiKeys: true);
    storage.requireSecureStorageOperationEpoch(epoch);
    if (allSites.isEmpty) {
      if (persistLastRefreshTime) {
        storage.requireSecureStorageOperationEpoch(epoch);
        await storage.saveLastSiteHealthRefreshCheck(
          DateTime.now(),
          expectedSecureStorageEpoch: epoch,
        );
      }
      return <String, HealthStatus>{};
    }

    final settings = await StorageService.instance
        .loadAggregateSearchSettings();
    final maxConcurrency = settings.searchThreads <= 0
        ? 1
        : settings.searchThreads;
    final statuses = <String, HealthStatus>{};
    var index = 0;
    var active = 0;
    Object? refreshFailure;
    StackTrace? refreshFailureStack;
    late void Function() startNext;

    final completer = Completer<void>();

    void completeIfDone() {
      if (index >= allSites.length && active == 0 && !completer.isCompleted) {
        completer.complete();
      }
    }

    Future<void> runSite(SiteConfig site) async {
      try {
        final status = await checkSingleSite(
          site,
          expectedSecureStorageEpoch: epoch,
        );
        storage.requireSecureStorageOperationEpoch(epoch);
        statuses[site.id] = status;
        onStatus?.call(site.id, status);
      } catch (error, stackTrace) {
        refreshFailure ??= error;
        refreshFailureStack ??= stackTrace;
        index = allSites.length;
      } finally {
        active--;
        startNext();
        completeIfDone();
      }
    }

    startNext = () {
      if (!storage.isSecureStorageOperationEpochCurrent(epoch)) {
        refreshFailure ??= SecureStorageUnavailableException(
          storage.canAccessSensitiveStorage
              ? 'secure_storage_operation_invalidated'
              : storage.secureStorageFailureCode ?? 'secure_storage_not_ready',
        );
        refreshFailureStack ??= StackTrace.current;
        index = allSites.length;
      }

      while (active < maxConcurrency && index < allSites.length) {
        final site = allSites[index++];
        active++;
        unawaited(runSite(site));
      }
      completeIfDone();
    };

    startNext();
    await completer.future;

    if (refreshFailure != null) {
      Error.throwWithStackTrace(
        refreshFailure!,
        refreshFailureStack ?? StackTrace.current,
      );
    }
    storage.requireSecureStorageOperationEpoch(epoch);

    await storage.mergeHealthStatuses(
      statuses.map((siteId, status) => MapEntry(siteId, status.toJson())),
      expectedSecureStorageEpoch: epoch,
    );

    if (persistLastRefreshTime) {
      storage.requireSecureStorageOperationEpoch(epoch);
      await storage.saveLastSiteHealthRefreshCheck(
        DateTime.now(),
        expectedSecureStorageEpoch: epoch,
      );
    }

    if (kDebugMode) {
      _logger.i(
        'SiteHealthRefreshService: 站点健康状态刷新完成, count=${statuses.length}',
      );
    }

    return statuses;
  }

  Future<HealthStatus> refreshSingleSite(
    SiteConfig site, {
    bool recreateAdapter = false,
    int? expectedSecureStorageEpoch,
  }) {
    final storage = StorageService.instance;
    final expected = expectedSecureStorageEpoch;
    if (expected != null) {
      return storage.runWithSecureStorageOperationEpoch(
        expected,
        () => _refreshSingleSiteInCurrentEpoch(
          site,
          recreateAdapter: recreateAdapter,
          epoch: expected,
        ),
      );
    }
    return storage.runWithCurrentSecureStorageOperation(
      (epoch) => _refreshSingleSiteInCurrentEpoch(
        site,
        recreateAdapter: recreateAdapter,
        epoch: epoch,
      ),
    );
  }

  Future<HealthStatus> _refreshSingleSiteInCurrentEpoch(
    SiteConfig site, {
    required bool recreateAdapter,
    required int epoch,
  }) async {
    final storage = StorageService.instance;
    storage.requireSecureStorageOperationEpoch(epoch);
    if (recreateAdapter) {
      ApiService.instance.removeAdapter(site.id);
    }

    final status = await checkSingleSite(
      site,
      expectedSecureStorageEpoch: epoch,
    );
    storage.requireSecureStorageOperationEpoch(epoch);
    await storage.mergeHealthStatuses({
      site.id: status.toJson(),
    }, expectedSecureStorageEpoch: epoch);
    return status;
  }

  Future<HealthStatus> checkSingleSite(
    SiteConfig site, {
    int? expectedSecureStorageEpoch,
  }) {
    final storage = StorageService.instance;
    final expected = expectedSecureStorageEpoch;
    if (expected != null) {
      return storage.runWithSecureStorageOperationEpoch(
        expected,
        () => _checkSingleSiteInCurrentEpoch(site, expected),
      );
    }
    return storage.runWithCurrentSecureStorageOperation(
      (epoch) => _checkSingleSiteInCurrentEpoch(site, epoch),
    );
  }

  Future<HealthStatus> _checkSingleSiteInCurrentEpoch(
    SiteConfig site,
    int epoch,
  ) async {
    final storage = StorageService.instance;
    storage.requireSecureStorageOperationEpoch(epoch);
    if (!site.features.supportMemberProfile) {
      try {
        final adapter = await ApiService.instance.getAdapter(site);
        final ok = await adapter.testConnection();
        storage.requireSecureStorageOperationEpoch(epoch);
        if (!ok) {
          throw Exception('连接测试失败');
        }
        return HealthStatus(
          ok: true,
          notApplicable: true,
          message: '连接正常（不支持用户资料）',
          username: null,
          profile: null,
          updatedAt: DateTime.now(),
        );
      } on SecureStorageUnavailableException {
        rethrow;
      } catch (e) {
        return HealthStatus(
          ok: false,
          notApplicable: true,
          message: e.toString(),
          username: null,
          profile: null,
          updatedAt: DateTime.now(),
        );
      }
    }

    try {
      final adapter = await ApiService.instance.getAdapter(site);
      final profile = await adapter.fetchMemberProfile(apiKey: site.apiKey);
      storage.requireSecureStorageOperationEpoch(epoch);
      return HealthStatus(
        ok: true,
        message: '正常',
        username: profile.username,
        profile: profile,
        updatedAt: DateTime.now(),
      );
    } on SecureStorageUnavailableException {
      rethrow;
    } catch (e) {
      return HealthStatus(
        ok: false,
        message: e.toString(),
        username: null,
        profile: null,
        updatedAt: DateTime.now(),
      );
    }
  }

  Future<bool> _shouldRefresh() async {
    final lastCheck = await StorageService.instance
        .loadLastSiteHealthRefreshCheck();
    if (lastCheck == null) {
      return true;
    }

    return DateTime.now().difference(lastCheck) >= _refreshInterval;
  }
}
