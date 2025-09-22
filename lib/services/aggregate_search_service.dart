import 'dart:async';

import '../models/app_models.dart';
import '../services/api/api_service.dart';
import '../services/storage/storage_service.dart';

/// 聚合搜索结果项
class AggregateSearchResultItem {
  final TorrentItem torrent;
  final String siteName;
  final String siteId;

  const AggregateSearchResultItem({
    required this.torrent,
    required this.siteName,
    required this.siteId,
  });
}

/// 聚合搜索结果
class AggregateSearchResult {
  final List<AggregateSearchResultItem> items;
  final Map<String, String> errors; // siteId -> error message
  final int totalSites;
  final int successSites;

  const AggregateSearchResult({
    required this.items,
    required this.errors,
    required this.totalSites,
    required this.successSites,
  });
}

/// 聚合搜索进度
class AggregateSearchProgress {
  final int totalSites;
  final int completedSites;
  final String? currentSite;
  final bool isCompleted;

  const AggregateSearchProgress({
    required this.totalSites,
    required this.completedSites,
    this.currentSite,
    this.isCompleted = false,
  });

  double get progress => totalSites > 0 ? completedSites / totalSites : 0.0;
}

/// 聚合搜索服务
class AggregateSearchService {
  static final AggregateSearchService _instance = AggregateSearchService._internal();
  factory AggregateSearchService() => _instance;
  AggregateSearchService._internal();

  static AggregateSearchService get instance => _instance;

  /// 执行聚合搜索
  Future<AggregateSearchResult> performAggregateSearch({
    required String keyword,
    required String configId,
    required Function(AggregateSearchProgress) onProgress,
    int maxResultsPerSite = 10,
  }) async {
    // 加载搜索配置
    final settings = await StorageService.instance.loadAggregateSearchSettings();
    final config = settings.searchConfigs.firstWhere(
      (c) => c.id == configId,
      orElse: () => throw ArgumentError('搜索配置不存在: $configId'),
    );

    // 获取要搜索的站点列表
    final allSites = await StorageService.instance.loadSiteConfigs();
    final activeSites = allSites.where((site) => site.isActive).toList();
    
    List<SiteConfig> targetSites;
    if (config.type == 'all') {
      targetSites = activeSites;
    } else {
      targetSites = activeSites
          .where((site) => config.enabledSiteIds.contains(site.id))
          .toList();
    }

    if (targetSites.isEmpty) {
      return const AggregateSearchResult(
        items: [],
        errors: {},
        totalSites: 0,
        successSites: 0,
      );
    }

    // 初始化进度
    onProgress(AggregateSearchProgress(
      totalSites: targetSites.length,
      completedSites: 0,
    ));

    // 并发搜索，但限制并发数量
    final maxConcurrency = settings.searchThreads;
    final results = <AggregateSearchResultItem>[];
    final errors = <String, String>{};
    int completedSites = 0;

    // 分批处理站点
    for (int i = 0; i < targetSites.length; i += maxConcurrency) {
      final batch = targetSites.skip(i).take(maxConcurrency).toList();
      
      // 并发搜索当前批次的站点
      final futures = batch.map((site) => _searchSingleSite(
        site: site,
        keyword: keyword,
        maxResults: maxResultsPerSite,
      ));

      final batchResults = await Future.wait(futures);
      
      // 处理批次结果
      for (int j = 0; j < batchResults.length; j++) {
        final site = batch[j];
        final result = batchResults[j];
        
        completedSites++;
        
        if (result.isSuccess) {
          final siteResults = result.data!.map((torrent) => 
            AggregateSearchResultItem(
              torrent: torrent,
              siteName: site.name,
              siteId: site.id,
            ),
          ).toList();
          results.addAll(siteResults);
        } else {
          errors[site.id] = result.error ?? '搜索失败';
        }

        // 更新进度
        onProgress(AggregateSearchProgress(
          totalSites: targetSites.length,
          completedSites: completedSites,
          currentSite: site.name,
        ));
      }
    }

    // 搜索完成
    onProgress(AggregateSearchProgress(
      totalSites: targetSites.length,
      completedSites: completedSites,
      isCompleted: true,
    ));

    return AggregateSearchResult(
      items: results,
      errors: errors,
      totalSites: targetSites.length,
      successSites: targetSites.length - errors.length,
    );
  }

  /// 搜索单个站点
  Future<SearchResult<List<TorrentItem>>> _searchSingleSite({
    required SiteConfig site,
    required String keyword,
    required int maxResults,
  }) async {
    try {
      // 检查站点是否支持搜索
      if (!site.features.supportTorrentSearch) {
        return SearchResult.error('站点不支持搜索功能');
      }

      // 设置当前站点
      await ApiService.instance.setActiveSite(site);

      // 执行搜索，限制结果数量
      final result = await ApiService.instance.searchTorrents(
        keyword: keyword.trim().isEmpty ? null : keyword.trim(),
        pageNumber: 1,
        pageSize: maxResults,
      );

      return SearchResult.success(result.items);
    } catch (e) {
      return SearchResult.error(e.toString());
    }
  }
}

/// 搜索结果包装类
class SearchResult<T> {
  final T? data;
  final String? error;
  final bool isSuccess;

  const SearchResult._({
    this.data,
    this.error,
    required this.isSuccess,
  });

  factory SearchResult.success(T data) => SearchResult._(
    data: data,
    isSuccess: true,
  );

  factory SearchResult.error(String error) => SearchResult._(
    error: error,
    isSuccess: false,
  );
}