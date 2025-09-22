import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/app_models.dart';
import '../services/storage/storage_service.dart';
import '../services/api/api_service.dart';
import '../services/aggregate_search_service.dart';
import '../services/qbittorrent/qb_client.dart';
import '../providers/aggregate_search_provider.dart';
import '../widgets/responsive_layout.dart';
import '../widgets/qb_speed_indicator.dart';
import '../widgets/torrent_list_item.dart';
import '../widgets/torrent_download_dialog.dart';
import 'torrent_detail_page.dart';

class AggregateSearchPage extends StatefulWidget {
  const AggregateSearchPage({super.key});

  @override
  State<AggregateSearchPage> createState() => _AggregateSearchPageState();
}

class _AggregateSearchPageState extends State<AggregateSearchPage> {
  final TextEditingController _searchController = TextEditingController();
  
  @override
  void initState() {
    super.initState();
    _loadSearchConfigs();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadSearchConfigs() async {
    final provider = Provider.of<AggregateSearchProvider>(context, listen: false);
    
    try {
      final storage = Provider.of<StorageService>(context, listen: false);
      final settings = await storage.loadAggregateSearchSettings();

      if (mounted) {
        provider.setSearchConfigs(settings.searchConfigs
            .where((config) => config.isActive)
            .toList());
        provider.setLoading(false);
        provider.initializeDefaultStrategy();
      }
    } catch (e) {
      if (mounted) {
        provider.setLoading(false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(
          SnackBar(
            content: Text(
              '加载搜索配置失败: $e',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onErrorContainer,
              ),
            ),
            backgroundColor: Theme.of(context).colorScheme.errorContainer,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AggregateSearchProvider>(
      builder: (context, provider, child) {
        // 同步搜索框内容
        if (_searchController.text != provider.searchKeyword) {
          _searchController.text = provider.searchKeyword;
        }
        
        return ResponsiveLayout(
          currentRoute: '/aggregate_search',
          appBar: AppBar(
            title: const Text('聚合搜索'),
            backgroundColor: Theme.of(context).brightness == Brightness.light
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.surface,
            iconTheme: IconThemeData(
              color: Theme.of(context).brightness == Brightness.light
                  ? Theme.of(context).colorScheme.onPrimary
                  : Theme.of(context).colorScheme.onSurface,
            ),
            titleTextStyle: TextStyle(
              color: Theme.of(context).brightness == Brightness.light
                  ? Theme.of(context).colorScheme.onPrimary
                  : Theme.of(context).colorScheme.onSurface,
              fontSize: 20,
              fontWeight: FontWeight.w500,
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.settings),
                onPressed: () async {
                  await Navigator.pushNamed(context, '/aggregate_search_settings');
                  // 从设置页面返回后刷新配置
                  _loadSearchConfigs();
                },
                tooltip: '聚合搜索设置',
              ),
              const QbSpeedIndicator(),
            ],
          ),
          body: provider.loading
              ? const Center(child: CircularProgressIndicator())
              : Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 搜索区域
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // 紧凑的搜索控件行
                              Row(
                                children: [
                                  // 搜索策略选择
                                  Expanded(
                                    flex: 2,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 0,
                                      ),
                                      decoration: BoxDecoration(
                                        border: Border.all(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .primary
                                              .withValues(alpha: 0.3),
                                        ),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: DropdownButton<String>(
                                        value: provider.selectedStrategy.isEmpty ? null : provider.selectedStrategy,
                                        hint: const Text('选择搜索策略'),
                                        isExpanded: true,
                                        underline: const SizedBox(),
                                        items: provider.searchConfigs.map((config) {
                                          return DropdownMenuItem<String>(
                                            value: config.id,
                                            child: Row(
                                              children: [
                                                Icon(
                                                  config.isAllSitesType
                                                      ? Icons.public
                                                      : Icons.group,
                                                  size: 16,
                                                  color: Theme.of(context)
                                                      .colorScheme
                                                      .primary,
                                                ),
                                                const SizedBox(width: 8),
                                                Expanded(
                                                  child: Text(
                                                    config.name,
                                                    overflow: TextOverflow.ellipsis,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          );
                                        }).toList(),
                                        onChanged: (value) {
                                          if (value != null) {
                                            provider.setSelectedStrategy(value);
                                          }
                                        },
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  // 搜索输入框
                                  Expanded(
                                    flex: 3,
                                    child: TextField(
                                      controller: _searchController,
                                      decoration: InputDecoration(
                                        hintText: '输入搜索关键词',
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        contentPadding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 8,
                                        ),
                                        suffixIcon: IconButton(
                                          icon: const Icon(Icons.search),
                                          onPressed: () => _performSearch(_searchController.text),
                                        ),
                                      ),
                                      onSubmitted: _performSearch,
                                      onChanged: (value) {
                                        provider.setSearchKeyword(value);
                                      },
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  // 排序选择
                                  PopupMenuButton<String>(
                                    icon: Icon(
                                      Icons.sort,
                                      color: provider.sortBy != 'none'
                                          ? Theme.of(context).colorScheme.primary
                                          : null,
                                    ),
                                    tooltip: '排序方式',
                                    onSelected: (value) {
                                      provider.setSortBy(value);
                                      _resortCurrentResults();
                                    },
                                    itemBuilder: (context) => [
                                      PopupMenuItem(
                                        value: 'none',
                                        child: Container(
                                          decoration: BoxDecoration(
                                            color: provider.sortBy == 'none'
                                                ? Theme.of(context)
                                                    .colorScheme
                                                    .primaryContainer
                                                    .withValues(alpha: 0.3)
                                                : null,
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 4,
                                          ),
                                          child: Row(
                                            children: [
                                              Icon(
                                                Icons.clear,
                                                color: provider.sortBy == 'none'
                                                    ? Theme.of(
                                                        context,
                                                      ).colorScheme.secondary
                                                    : null,
                                              ),
                                              const SizedBox(width: 8),
                                              const Text('默认排序'),
                                            ],
                                          ),
                                        ),
                                      ),

                                      PopupMenuItem(
                                        value: 'size',
                                        child: Container(
                                          decoration: BoxDecoration(
                                            color: provider.sortBy == 'size'
                                                ? Theme.of(context)
                                                    .colorScheme
                                                    .primaryContainer
                                                    .withValues(alpha: 0.3)
                                                : null,
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 4,
                                          ),
                                          child: Row(
                                            children: [
                                              Icon(
                                                provider.sortAscending
                                                    ? Icons.arrow_upward
                                                    : Icons.arrow_downward,
                                                color: provider.sortBy == 'size'
                                                    ? Theme.of(
                                                        context,
                                                      ).colorScheme.secondary
                                                    : null,
                                              ),
                                              const SizedBox(width: 8),
                                              const Text('按大小排序'),
                                            ],
                                          ),
                                        ),
                                      ),

                                      PopupMenuItem(
                                        value: 'seeders',
                                        child: Container(
                                          decoration: BoxDecoration(
                                            color: provider.sortBy == 'seeders'
                                                ? Theme.of(context)
                                                    .colorScheme
                                                    .primaryContainer
                                                    .withValues(alpha: 0.3)
                                                : null,
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 4,
                                          ),
                                          child: Row(
                                            children: [
                                              Icon(
                                                provider.sortAscending
                                                    ? Icons.arrow_upward
                                                    : Icons.arrow_downward,
                                                color: provider.sortBy == 'seeders'
                                                    ? Theme.of(
                                                        context,
                                                      ).colorScheme.secondary
                                                    : null,
                                              ),
                                              const SizedBox(width: 8),
                                              const Text('按做种数排序'),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  // 排序方向切换
                                  if (provider.sortBy != 'none')
                                    IconButton(
                                      icon: Icon(
                                        provider.sortAscending
                                            ? Icons.keyboard_arrow_up
                                            : Icons.keyboard_arrow_down,
                                        color: Theme.of(context).colorScheme.primary,
                                      ),
                                      tooltip: provider.sortAscending ? '升序' : '降序',
                                      onPressed: () {
                                        provider.setSortAscending(!provider.sortAscending);
                                        _resortCurrentResults();
                                      },
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 16),

                      // 搜索进度指示器
                      if (provider.searching) ...[
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    ),
                                    const SizedBox(width: 12),
                                    Text(
                                      '正在搜索...',
                                      style: Theme.of(context).textTheme.titleSmall,
                                    ),
                                  ],
                                ),
                                if (provider.searchProgress != null) ...[
                                  const SizedBox(height: 8),
                                  LinearProgressIndicator(
                                    value: provider.searchProgress!.completedSites /
                                        provider.searchProgress!.totalSites,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${provider.searchProgress!.completedSites}/${provider.searchProgress!.totalSites} 个站点',
                                    style: Theme.of(context).textTheme.bodySmall,
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],

                      // 搜索结果
                      Expanded(
                        child: provider.searchResults.isEmpty && !provider.searching
                            ? Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.search,
                                      size: 64,
                                      color: Theme.of(context).colorScheme.outline,
                                    ),
                                    const SizedBox(height: 16),
                                    Text(
                                      '输入关键词开始搜索',
                                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                            color: Theme.of(context).colorScheme.outline,
                                          ),
                                    ),
                                  ],
                                ),
                              )
                            : ListView.builder(
                                itemCount: provider.searchResults.length,
                                itemBuilder: (context, index) {
                                  final item = provider.searchResults[index];
                                  return Card(
                                    margin: const EdgeInsets.only(bottom: 8),
                                    child: TorrentListItem(
                                      torrent: item.torrent,
                                      isSelected: false,
                                      isSelectionMode: false,
                                      isAggregateMode: true,
                                      siteName: item.siteName,
                                      onTap: () => _onTorrentTap(item),
                                      onDownload: () => _showDownloadDialog(item),
                                      onToggleCollection: null,
                                    ),
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                ),
        );
      },
    );
  }

  /// 应用排序到搜索结果
  List<AggregateSearchResultItem> _applySorting(List<AggregateSearchResultItem> items, String sortBy, bool sortAscending) {
    if (sortBy == 'none' || items.isEmpty) {
      return List.from(items);
    }

    final sortedItems = List<AggregateSearchResultItem>.from(items);
    
    switch (sortBy) {
      case 'size':
        // 按文件大小排序
        sortedItems.sort((a, b) {
          final comparison = a.torrent.sizeBytes.compareTo(b.torrent.sizeBytes);
          return sortAscending ? comparison : -comparison;
        });
        break;
      case 'seeders':
        // 按做种数排序
        sortedItems.sort((a, b) {
          final comparison = a.torrent.seeders.compareTo(b.torrent.seeders);
          return sortAscending ? comparison : -comparison;
        });
        break;
    }
    
    return sortedItems;
  }

  /// 重新排序当前搜索结果
  void _resortCurrentResults() {
    final provider = Provider.of<AggregateSearchProvider>(context, listen: false);
    if (provider.searchResults.isNotEmpty) {
      final sortedResults = _applySorting(provider.searchResults, provider.sortBy, provider.sortAscending);
      provider.setSearchResults(sortedResults);
    }
  }

  void _performSearch(String query) async {
    if (query.trim().isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(
        SnackBar(
          content: Text(
            '请输入搜索关键词',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onErrorContainer,
            ),
          ),
          backgroundColor: Theme.of(context).colorScheme.errorContainer,
        ),
      );
      return;
    }

    final provider = Provider.of<AggregateSearchProvider>(context, listen: false);
    
    if (provider.selectedStrategy.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(
        SnackBar(
          content: Text(
            '请选择搜索策略',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onErrorContainer,
            ),
          ),
          backgroundColor: Theme.of(context).colorScheme.errorContainer,
        ),
      );
      return;
    }

    provider.setSearching(true);
    provider.setSearchResults([]);
    provider.setSearchErrors({});
    provider.setSearchProgress(null);

    try {
      final result = await AggregateSearchService.instance.performAggregateSearch(
        keyword: query.trim(),
        configId: provider.selectedStrategy,
        maxResultsPerSite: 10,
        onProgress: (progress) {
          if (mounted) {
            provider.setSearchProgress(progress);
          }
        },
      );

      if (mounted) {
        final sortedResults = _applySorting(result.items, provider.sortBy, provider.sortAscending);
        provider.setSearchResults(sortedResults);
        provider.setSearchErrors(result.errors);
        provider.setSearching(false);
        provider.setSearchProgress(null);

        // 显示搜索结果摘要
        final message = '搜索完成：共找到 ${result.items.length} 条结果，'
            '成功搜索 ${result.successSites}/${result.totalSites} 个站点';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              message,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onPrimaryContainer,
              ),
            ),
            backgroundColor: Theme.of(context).colorScheme.primaryContainer,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        provider.setSearching(false);
        provider.setSearchProgress(null);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '搜索失败：$e',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onErrorContainer,
              ),
            ),
            backgroundColor: Theme.of(context).colorScheme.errorContainer,
          ),
        );
      }
    }
  }

  Future<void> _onTorrentTap(AggregateSearchResultItem item) async {
    try {
      // 1. 获取种子所属站点的配置
      final storage = Provider.of<StorageService>(context, listen: false);
      final allSites = await storage.loadSiteConfigs();
      final siteConfig = allSites.firstWhere(
        (site) => site.id == item.siteId,
        orElse: () => throw Exception('找不到站点配置: ${item.siteId}'),
      );
      
      // 2. 设置当前站点
      await ApiService.instance.setActiveSite(siteConfig);
      
      // 3. 获取qBittorrent客户端配置
       final qbClients = await storage.loadQbClients();
       
       // 4. 跳转到详情页面
       if (!mounted) return;
       Navigator.of(context).push(
         MaterialPageRoute(
           builder: (context) => TorrentDetailPage(
             torrentItem: item.torrent,
             siteFeatures: siteConfig.features,
             qbClients: qbClients,
           ),
         ),
       );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '打开详情失败: $e',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onErrorContainer,
              ),
            ),
            backgroundColor: Theme.of(context).colorScheme.errorContainer,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _showDownloadDialog(AggregateSearchResultItem item) async {
    try {
      // 1. 获取种子所属站点的配置
      final storage = Provider.of<StorageService>(context, listen: false);
      final allSites = await storage.loadSiteConfigs();
      final siteConfig = allSites.firstWhere(
        (site) => site.id == item.siteId,
        orElse: () => throw Exception('找不到站点配置: ${item.siteId}'),
      );
      
      await ApiService.instance.setActiveSite(siteConfig);
      
      // 2. 获取下载 URL
      final url = await ApiService.instance.genDlToken(
        id: item.torrent.id,
        url: item.torrent.downloadUrl,
      );

      // 3. 弹出对话框让用户选择下载器设置
      if (!mounted) return;
      final result = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (_) => TorrentDownloadDialog(
          torrentName: item.torrent.name,
          downloadUrl: url,
        ),
      );

      if (result == null) return; // 用户取消了

      // 4. 从对话框结果中获取设置
      final clientConfig = result['clientConfig'] as QbClientConfig;
      final password = result['password'] as String;
      final category = result['category'] as String?;
      final tags = result['tags'] as List<String>?;
      final savePath = result['savePath'] as String?;
      final autoTMM = result['autoTMM'] as bool?;

      // 5. 发送到 qBittorrent
      await _onTorrentDownload(item, clientConfig, password, url, category, tags, savePath, autoTMM);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '下载失败: $e',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onErrorContainer,
              ),
            ),
            backgroundColor: Theme.of(context).colorScheme.errorContainer,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _onTorrentDownload(
    AggregateSearchResultItem item,
    QbClientConfig clientConfig,
    String password,
    String url,
    String? category,
    List<String>? tags,
    String? savePath,
    bool? autoTMM,
  ) async {
    try {
      // 发送到 qBittorrent
      await QbService.instance.addTorrentByUrl(
        config: clientConfig,
        password: password,
        url: url,
        category: category,
        tags: tags,
        savePath: savePath,
        autoTMM: autoTMM,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '已成功发送"${item.torrent.name}"到 ${clientConfig.name}',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onPrimaryContainer,
              ),
            ),
            backgroundColor: Theme.of(context).colorScheme.primaryContainer,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '下载失败: $e',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onErrorContainer,
              ),
            ),
            backgroundColor: Theme.of(context).colorScheme.errorContainer,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }
}
