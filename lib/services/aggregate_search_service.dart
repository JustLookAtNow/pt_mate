import 'dart:async';

import 'package:logger/logger.dart';

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
    int maxResultsPerSite = 30,
  }) async {
    // 加载搜索配置
    final settings = await StorageService.instance.loadAggregateSearchSettings();
    final config = settings.searchConfigs.firstWhere(
      (c) => c.id == configId,
      orElse: () => throw ArgumentError('搜索配置不存在: $configId'),
    );

    // 获取要搜索的站点列表（包含 API Key，避免 M-Team 等站点密钥为 null）
    final allSites = await StorageService.instance.loadSiteConfigs(includeApiKeys: true);
    final activeSites = allSites.where((site) => site.isActive).toList();
    final allSiteIds = activeSites.map((site) => site.id).toList();
    
    // 获取启用的站点对象列表
    final enabledSiteItems = config.getEnabledSites(allSiteIds);
    
    // 根据站点对象列表获取实际的站点配置
    List<SiteConfig> targetSites = [];
    Map<String, Map<String, dynamic>?> siteAdditionalParams = {};
    
    for (final siteItem in enabledSiteItems) {
      try {
        final siteConfig = activeSites.firstWhere(
          (site) => site.id == siteItem.id,
        );
        targetSites.add(siteConfig);
        siteAdditionalParams[siteItem.id] = siteItem.additionalParams;
      } catch (e) {
        // 站点不存在或未激活，跳过
        continue;
      }
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

    // 使用异步处理，让每个站点独立返回结果
    final maxConcurrency = settings.searchThreads;
    final results = <AggregateSearchResultItem>[];
    final errors = <String, String>{};
    int completedSites = 0;
    int activeTasks = 0;

    // 创建一个 Completer 来控制整个搜索流程的完成
    final completer = Completer<AggregateSearchResult>();
    
    // 处理单个站点搜索完成的回调
    void handleSiteComplete(SiteConfig site, SearchResult<List<TorrentItem>> result) {
      completedSites++;
      activeTasks--;
      
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

      // 检查是否所有站点都已完成
      if (completedSites >= targetSites.length) {
        // 搜索完成
        onProgress(AggregateSearchProgress(
          totalSites: targetSites.length,
          completedSites: completedSites,
          isCompleted: true,
        ));

        completer.complete(AggregateSearchResult(
          items: results,
          errors: errors,
          totalSites: targetSites.length,
          successSites: targetSites.length - errors.length,
        ));
      }
    }

    // 启动搜索任务，控制并发数量
    int siteIndex = 0;
    
    void startNextSite() {
      while (activeTasks < maxConcurrency && siteIndex < targetSites.length) {
        final site = targetSites[siteIndex];
        final additionalParams = siteAdditionalParams[site.id];
        siteIndex++;
        activeTasks++;

        // 异步启动单个站点搜索，不等待结果
        _searchSingleSite(
          site: site,
          keyword: keyword,
          maxResults: maxResultsPerSite,
          additionalParams: additionalParams,
        ).then((result) {
          handleSiteComplete(site, result);
          // 当前任务完成后，尝试启动下一个任务
          startNextSite();
        }).catchError((error) {
          // 处理异常情况
          handleSiteComplete(site, SearchResult.error(error.toString()));
          // 当前任务完成后，尝试启动下一个任务
          startNextSite();
        });
      }
    }

    // 开始启动搜索任务
    startNextSite();

    return completer.future;
  }

  /// 搜索单个站点
  Future<SearchResult<List<TorrentItem>>> _searchSingleSite({
    required SiteConfig site,
    required String keyword,
    required int maxResults,
    Map<String, dynamic>? additionalParams,
  }) async {
    final logger = Logger();
    try {
      logger.d(
        '开始搜索站点: ${site.name} (ID: ${site.id})\n关键字: "$keyword"\n最大结果数: $maxResults\n附加参数: $additionalParams',
      );
      // 检查站点是否支持搜索
      if (!site.features.supportTorrentSearch) {
        logger.w('站点 ${site.name} 不支持搜索功能');
        return SearchResult.error('站点不支持搜索功能');
      }

      // 转换分类参数
      Map<String, dynamic>? processedParams;
      if (additionalParams != null) {
        processedParams = Map<String, dynamic>.from(additionalParams);
        
        // 处理分类参数转换
        if (processedParams.containsKey('selectedCategories')) {
          final selectedCategoryIds = processedParams['selectedCategories'] as List<dynamic>?;
          if (selectedCategoryIds != null && selectedCategoryIds.isNotEmpty) {
            // 移除原始的selectedCategories
            processedParams.remove('selectedCategories');
            
            // 获取站点的分类配置
            final categories = site.searchCategories;
            
            // 将分类ID转换为对应的参数
            for (final categoryId in selectedCategoryIds) {
              final category = categories.firstWhere(
                (cat) => cat.id == categoryId,
                orElse: () => throw Exception('找不到分类配置: $categoryId'),
              );
              
              // 解析分类参数并合并到请求参数中
              final categoryParams = category.parseParameters();
              categoryParams.forEach((key, value) {
                processedParams![key] = value;
              });
            }
          }
        }
      }

      // 使用专用方法直接搜索指定站点，无需切换全局状态
      final result = await ApiService.instance.searchTorrentsWithSite(
        siteConfig: site,
        keyword: keyword.trim().isEmpty ? null : keyword.trim(),
        pageNumber: 1,
        pageSize: maxResults,
        additionalParams: processedParams, 
      );

      logger.d('站点 ${site.name} 搜索成功，返回 ${result.items.length} 条结果');
      return SearchResult.success(result.items);
    } catch (e) {
      logger.e('站点 ${site.name} 搜索失败', error: e);
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