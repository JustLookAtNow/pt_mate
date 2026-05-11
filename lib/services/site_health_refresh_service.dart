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
    if (!await _shouldRefresh()) {
      if (kDebugMode) {
        _logger.d('SiteHealthRefreshService: 未达到自动刷新间隔，跳过');
      }
      return null;
    }

    return refreshAllSites(force: true, persistLastRefreshTime: true);
  }

  Future<Map<String, HealthStatus>> refreshAllSites({
    bool force = false,
    bool persistLastRefreshTime = false,
    void Function(String siteId, HealthStatus status)? onStatus,
  }) async {
    if (!force && !await _shouldRefresh()) {
      return <String, HealthStatus>{};
    }

    final allSites = await StorageService.instance.loadSiteConfigs(
      includeApiKeys: true,
    );
    if (allSites.isEmpty) {
      if (persistLastRefreshTime) {
        await StorageService.instance.saveLastSiteHealthRefreshCheck(
          DateTime.now(),
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

    final completer = Completer<void>();

    void completeIfDone() {
      if (index >= allSites.length && active == 0 && !completer.isCompleted) {
        completer.complete();
      }
    }

    void startNext() {
      while (active < maxConcurrency && index < allSites.length) {
        final site = allSites[index++];
        active++;

        checkSingleSite(site)
            .then((status) {
              statuses[site.id] = status;
              onStatus?.call(site.id, status);
            })
            .whenComplete(() {
              active--;
              startNext();
              completeIfDone();
            });
      }
      completeIfDone();
    }

    startNext();
    await completer.future;

    await StorageService.instance.mergeHealthStatuses(
      statuses.map((siteId, status) => MapEntry(siteId, status.toJson())),
    );

    if (persistLastRefreshTime) {
      await StorageService.instance.saveLastSiteHealthRefreshCheck(
        DateTime.now(),
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
  }) async {
    if (recreateAdapter) {
      ApiService.instance.removeAdapter(site.id);
    }

    final status = await checkSingleSite(site);
    await StorageService.instance.mergeHealthStatuses({
      site.id: status.toJson(),
    });
    return status;
  }

  Future<HealthStatus> checkSingleSite(SiteConfig site) async {
    if (!site.features.supportMemberProfile) {
      try {
        final adapter = await ApiService.instance.getAdapter(site);
        final ok = await adapter.testConnection();
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
      return HealthStatus(
        ok: true,
        message: '正常',
        username: profile.username,
        profile: profile,
        updatedAt: DateTime.now(),
      );
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
