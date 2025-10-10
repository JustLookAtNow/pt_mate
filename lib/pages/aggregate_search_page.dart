import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/app_models.dart';
import '../services/storage/storage_service.dart';
import '../services/api/api_service.dart';
import '../services/aggregate_search_service.dart';
import '../services/downloader/downloader_config.dart';
import '../services/downloader/downloader_factory.dart';
import '../services/downloader/downloader_models.dart';
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
  
  // 选择模式相关状态
  bool _isSelectionMode = false;
  final Set<String> _selectedItems = <String>{};
  
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
                                      isSelected: _selectedItems.contains(item.torrent.id),
                                      isSelectionMode: _isSelectionMode,
                                      isAggregateMode: true,
                                      siteName: item.siteName,
                                      onTap: _isSelectionMode
                                          ? () => _onToggleSelection(item)
                                          : () => _onTorrentTap(item),
                                      onLongPress: () => _onLongPress(item),
                                      onDownload: () => _showDownloadDialog(item),
                                      onToggleCollection: () => _onToggleCollection(item),
                                    ),
                                  );
                                },
                              ),
                      ),

                      // 选择模式下的操作栏
                      if (_isSelectionMode) ...[
                        const SizedBox(height: 8),
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Row(
                              children: [
                                Text(
                                  '已选择 ${_selectedItems.length} 项',
                                  style: Theme.of(context).textTheme.titleSmall,
                                ),
                                const Spacer(),
                                TextButton(
                                  onPressed: _onCancelSelection,
                                  style: TextButton.styleFrom(
                                    side: BorderSide(
                                      color: Theme.of(context).colorScheme.outline,
                                      width: 1.0,
                                    ),
                                  ),
                                  child: const Text('取消'),
                                ),
                                const SizedBox(width: 8),
                                ElevatedButton.icon(
                                  onPressed: _selectedItems.isEmpty ? null : _onBatchDownload,
                                  icon: const Icon(Icons.download),
                                  label: const Text('批量下载'),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
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
      
      // 2. 获取下载器客户端配置
        final downloaderConfigs = await storage.loadDownloaderConfigs();
        final qbClients = downloaderConfigs.map((configMap) {
          final config = DownloaderConfig.fromJson(configMap);
          if (config is QbittorrentConfig) {
            return config;
          }
          throw Exception('不支持的下载器类型: ${config.type}');
        }).toList();
       
       // 4. 跳转到详情页面
       if (!mounted) return;
       Navigator.of(context).push(
         MaterialPageRoute(
           builder: (context) => TorrentDetailPage(
                            torrentItem: item.torrent,
                            siteFeatures: siteConfig.features,
                            qbClients: qbClients,
                            siteConfig: siteConfig, // 传入站点配置
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
      
      // 2. 获取下载 URL
      final url = await ApiService.instance.genDlToken(
        id: item.torrent.id,
        url: item.torrent.downloadUrl,
        siteConfig: siteConfig, // 传入站点配置
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
      final clientConfig = result['clientConfig'] as DownloaderConfig;
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
    DownloaderConfig clientConfig,
    String password,
    String url,
    String? category,
    List<String>? tags,
    String? savePath,
    bool? autoTMM,
  ) async {
    try {
      // 直接使用下载器配置
      final client = DownloaderFactory.createClient(
        config: clientConfig,
        password: password,
      );
      
      // 发送到下载器
       await client.addTask(AddTaskParams(
         url: url,
         category: category,
         tags: tags,
         savePath: savePath,
         autoTMM: autoTMM,
       ));

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

  // 长按触发选中模式
  void _onLongPress(AggregateSearchResultItem item) {
    if (!_isSelectionMode && mounted) {
      // 使用 Flutter 内置的触觉反馈，提供原生的震动体验
      HapticFeedback.mediumImpact();
      setState(() {
        _isSelectionMode = true;
        _selectedItems.add(item.torrent.id);
      });
    }
  }

  // 切换选中状态
  void _onToggleSelection(AggregateSearchResultItem item) {
    if (mounted) {
      setState(() {
        if (_selectedItems.contains(item.torrent.id)) {
          _selectedItems.remove(item.torrent.id);
          if (_selectedItems.isEmpty) {
            _isSelectionMode = false;
          }
        } else {
          _selectedItems.add(item.torrent.id);
        }
      });
    }
  }

  // 批量下载
  Future<void> _onBatchDownload() async {
    if (_selectedItems.isEmpty) return;

    final provider = Provider.of<AggregateSearchProvider>(context, listen: false);
    final selectedItems = provider.searchResults
        .where((item) => _selectedItems.contains(item.torrent.id))
        .toList();

    // 显示批量下载设置对话框
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) =>
          TorrentDownloadDialog(itemCount: selectedItems.length),
    );

    if (result == null) return; // 用户取消了

    _onCancelSelection(); // 取消选择模式

    // 显示开始下载的提示
    if (mounted) {
      final clientConfig = result['clientConfig'] as QbClientConfig;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '开始批量下载${selectedItems.length}个项目到${clientConfig.name}...',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onPrimaryContainer,
            ),
          ),
          backgroundColor: Theme.of(context).colorScheme.primaryContainer,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }

    // 异步处理下载
    _performBatchDownload(
      selectedItems,
      result['clientConfig'] as DownloaderConfig,
      result['password'] as String,
      result['category'] as String?,
      result['tags'] as List<String>? ?? [],
      result['savePath'] as String?,
      result['autoTMM'] as bool?,
    );
  }

  Future<void> _performBatchDownload(
    List<AggregateSearchResultItem> items,
    DownloaderConfig clientConfig,
    String password,
    String? category,
    List<String> tags,
    String? savePath,
    bool? autoTMM,
  ) async {
    int successCount = 0;
    int failureCount = 0;

    for (final item in items) {
      try {
        // 1. 获取种子所属站点的配置
        final storage = Provider.of<StorageService>(context, listen: false);
        final allSites = await storage.loadSiteConfigs();
        final siteConfig = allSites.firstWhere(
          (site) => site.id == item.siteId,
          orElse: () => throw Exception('找不到站点配置: ${item.siteId}'),
        );

        // 2. 获取下载 URL
        final url = await ApiService.instance.genDlToken(
          id: item.torrent.id,
          url: item.torrent.downloadUrl,
          siteConfig: siteConfig,
        );

        // 3. 发送到下载器
        final client = DownloaderFactory.createClient(
          config: clientConfig,
          password: password,
        );
        await client.addTask(AddTaskParams(
          url: url,
          category: category,
          tags: tags.isEmpty ? null : tags,
          savePath: savePath,
          autoTMM: autoTMM,
        ));

        successCount++;

        // 添加延迟避免请求过快
        await Future.delayed(const Duration(milliseconds: 500));
      } catch (e) {
        failureCount++;
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '下载失败: ${item.torrent.name}, 错误: $e',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onErrorContainer,
                ),
              ),
              backgroundColor: Theme.of(context).colorScheme.errorContainer,
              duration: const Duration(seconds: 2),
            ),
          );
        }
      }
    }

    // 显示最终结果
    if (mounted) {
      final message = failureCount == 0
          ? '批量下载完成，成功$successCount个项目'
          : '批量下载完成，成功$successCount个，失败$failureCount个';

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            message,
            style: TextStyle(
              color: failureCount == 0
                  ? Theme.of(context).colorScheme.onPrimaryContainer
                  : Theme.of(context).colorScheme.onErrorContainer,
            ),
          ),
          backgroundColor: failureCount == 0
              ? Theme.of(context).colorScheme.primaryContainer
              : Theme.of(context).colorScheme.errorContainer,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  // 取消选中模式
  void _onCancelSelection() {
    if (mounted) {
      setState(() {
        _isSelectionMode = false;
        _selectedItems.clear();
      });
    }
  }

  // 收藏/取消收藏功能
  Future<void> _onToggleCollection(AggregateSearchResultItem item) async {
    final newCollectionState = !item.torrent.collection;

    // 立即更新UI状态
    if (mounted) {
      setState(() {
        item.torrent.collection = newCollectionState;
      });
    }

    // 异步后台请求
    try {
      // 调用收藏API
      await ApiService.instance.toggleCollection(
        id: item.torrent.id,
        make: newCollectionState,
      );

      // 显示成功提示
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              newCollectionState ? '已收藏' : '已取消收藏',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onPrimaryContainer,
              ),
            ),
            backgroundColor: Theme.of(context).colorScheme.primaryContainer,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 1),
          ),
        );
      }
    } catch (e) {
      // 请求失败，恢复原状态
      if (mounted) {
        setState(() {
          item.torrent.collection = !newCollectionState;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '收藏操作失败：$e',
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
