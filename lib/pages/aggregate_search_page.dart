import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../widgets/responsive_layout.dart';
import '../widgets/qb_speed_indicator.dart';
import '../widgets/torrent_list_item.dart';
import '../models/app_models.dart';
import '../services/storage/storage_service.dart';
import '../services/aggregate_search_service.dart';
import '../widgets/torrent_download_dialog.dart';
import '../services/qbittorrent/qb_client.dart';
import '../pages/torrent_detail_page.dart';
import '../services/api/api_service.dart';

class AggregateSearchPage extends StatefulWidget {
  const AggregateSearchPage({super.key});

  @override
  State<AggregateSearchPage> createState() => _AggregateSearchPageState();
}

class _AggregateSearchPageState extends State<AggregateSearchPage> {
  final TextEditingController _searchController = TextEditingController();
  String _selectedStrategy = '';
  String _sortBy = 'none';
  bool _sortAscending = false;
  List<AggregateSearchConfig> _searchConfigs = [];
  bool _loading = true;
  
  // 搜索相关状态
  bool _searching = false;
  List<AggregateSearchResultItem> _searchResults = [];
  Map<String, String> _searchErrors = {};
  AggregateSearchProgress? _searchProgress;

  @override
  void initState() {
    super.initState();
    _loadSearchConfigs();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 当页面重新显示时刷新配置
    _loadSearchConfigs();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadSearchConfigs() async {
    try {
      final storage = Provider.of<StorageService>(context, listen: false);
      final settings = await storage.loadAggregateSearchSettings();

      if (mounted) {
        setState(() {
          _searchConfigs = settings.searchConfigs
              .where((config) => config.isActive)
              .toList();
          _loading = false;

          // 设置默认选中的策略
          if (_searchConfigs.isNotEmpty && _selectedStrategy.isEmpty) {
            // 优先选择"所有站点"配置
            final allSitesConfig = _searchConfigs.firstWhere(
              (config) => config.isAllSitesType,
              orElse: () => _searchConfigs.first,
            );
            _selectedStrategy = allSitesConfig.id;
          }

          // 如果当前选中的策略不在激活列表中，重新选择
          if (!_searchConfigs.any((config) => config.id == _selectedStrategy)) {
            _selectedStrategy = _searchConfigs.isNotEmpty
                ? _searchConfigs.first.id
                : '';
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('加载搜索配置失败: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
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
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 搜索区域
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
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
                                    vertical: 8,
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
                                    value: _selectedStrategy,
                                    isExpanded: true,
                                    underline: const SizedBox(),
                                    isDense: true,
                                    items: _searchConfigs.map((config) {
                                      return DropdownMenuItem<String>(
                                        value: config.id,
                                        child: Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                config.name,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                            Text(
                                              config.type == 'all'
                                                  ? '(全部)'
                                                  : '(${config.enabledSiteIds.length})',
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: Theme.of(
                                                  context,
                                                ).colorScheme.onSurfaceVariant,
                                              ),
                                            ),
                                          ],
                                        ),
                                      );
                                    }).toList(),
                                    onChanged: (value) {
                                      if (value != null) {
                                        setState(() {
                                          _selectedStrategy = value;
                                        });
                                      }
                                    },
                                  ),
                                ),
                              ),
                              const SizedBox(width: 4),

                              // 搜索框
                              Expanded(
                                flex: 2,
                                child: TextField(
                                  controller: _searchController,
                                  textInputAction: TextInputAction.search,
                                  decoration: InputDecoration(
                                    hintText: '输入关键词',
                                    border: OutlineInputBorder(
                                      borderRadius: const BorderRadius.all(
                                        Radius.circular(25),
                                      ),
                                      borderSide: BorderSide(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .primary
                                            .withValues(alpha: 0.3),
                                      ),
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: const BorderRadius.all(
                                        Radius.circular(25),
                                      ),
                                      borderSide: BorderSide(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .primary
                                            .withValues(alpha: 0.3),
                                      ),
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderRadius: const BorderRadius.all(
                                        Radius.circular(25),
                                      ),
                                      borderSide: BorderSide(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.primary,
                                      ),
                                    ),
                                    isDense: true,
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 12,
                                    ),
                                  ),
                                  onSubmitted: _performSearch,
                                ),
                              ),

                              // 排序选择
                              PopupMenuButton<String>(
                                onSelected: (value) {
                                  setState(() {
                                    if (_sortBy == value) {
                                      _sortAscending = !_sortAscending;
                                    } else {
                                      _sortBy = value;
                                      _sortAscending = false;
                                    }
                                  });
                                },
                                icon: Icon(
                                  Icons.sort,
                                  color: _sortBy == 'none'
                                      ? null
                                      : Theme.of(context).colorScheme.secondary,
                                ),
                                tooltip: '排序',
                                itemBuilder: (context) => [
                                  PopupMenuItem(
                                    value: 'none',
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: _sortBy == 'none'
                                            ? Theme.of(context)
                                                  .colorScheme
                                                  .primary
                                                  .withValues(alpha: 0.1)
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
                                            color: _sortBy == 'none'
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
                                    value: 'time',
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: _sortBy == 'time'
                                            ? Theme.of(context)
                                                  .colorScheme
                                                  .primary
                                                  .withValues(alpha: 0.1)
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
                                            _sortBy == 'time' && _sortAscending
                                                ? Icons.arrow_upward
                                                : Icons.arrow_downward,
                                            color: _sortBy == 'time'
                                                ? Theme.of(
                                                    context,
                                                  ).colorScheme.secondary
                                                : null,
                                          ),
                                          const SizedBox(width: 8),
                                          const Text('按时间排序'),
                                        ],
                                      ),
                                    ),
                                  ),
                                  PopupMenuItem(
                                    value: 'size',
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: _sortBy == 'size'
                                            ? Theme.of(context)
                                                  .colorScheme
                                                  .primary
                                                  .withValues(alpha: 0.1)
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
                                            _sortBy == 'size' && _sortAscending
                                                ? Icons.arrow_upward
                                                : Icons.arrow_downward,
                                            color: _sortBy == 'size'
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
                                        color: _sortBy == 'seeders'
                                            ? Theme.of(context)
                                                  .colorScheme
                                                  .primary
                                                  .withValues(alpha: 0.1)
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
                                            _sortBy == 'seeders' &&
                                                    _sortAscending
                                                ? Icons.arrow_upward
                                                : Icons.arrow_downward,
                                            color: _sortBy == 'seeders'
                                                ? Theme.of(
                                                    context,
                                                  ).colorScheme.secondary
                                                : null,
                                          ),
                                          const SizedBox(width: 8),
                                          const Text('按做种排序'),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // 搜索结果区域
                  Expanded(
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  '搜索结果',
                                  style: Theme.of(context).textTheme.titleMedium,
                                ),
                                if (_searchResults.isNotEmpty)
                                  Text(
                                    '共 ${_searchResults.length} 条结果',
                                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                      color: Theme.of(context).colorScheme.outline,
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            
                            // 搜索进度指示器
                            if (_searching) ...[
                              if (_searchProgress != null) ...[
                                LinearProgressIndicator(
                                  value: _searchProgress!.progress,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  _searchProgress!.currentSite != null
                                      ? '正在搜索: ${_searchProgress!.currentSite} (${_searchProgress!.completedSites}/${_searchProgress!.totalSites})'
                                      : '正在搜索... (${_searchProgress!.completedSites}/${_searchProgress!.totalSites})',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ] else ...[
                                const LinearProgressIndicator(),
                                const SizedBox(height: 8),
                                const Text('正在准备搜索...'),
                              ],
                              const SizedBox(height: 16),
                            ],
                            
                            // 搜索错误信息
                            if (_searchErrors.isNotEmpty && !_searching) ...[
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Theme.of(context).colorScheme.errorContainer,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '部分站点搜索失败:',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w500,
                                        color: Theme.of(context).colorScheme.onErrorContainer,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    ..._searchErrors.entries.map((entry) => Text(
                                      '• ${entry.key}: ${entry.value}',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Theme.of(context).colorScheme.onErrorContainer,
                                      ),
                                    )),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 16),
                            ],
                            
                            // 搜索结果列表
                            Expanded(
                              child: _searchResults.isEmpty && !_searching
                                  ? Center(
                                      child: Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Icon(
                                            Icons.search_off,
                                            size: 64,
                                            color: Theme.of(context).colorScheme.outline,
                                          ),
                                          const SizedBox(height: 16),
                                          Text(
                                            '暂无搜索结果',
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodyLarge
                                                ?.copyWith(
                                                  color: Theme.of(context).colorScheme.outline,
                                                ),
                                          ),
                                          const SizedBox(height: 8),
                                          Text(
                                            '请输入关键词并选择搜索策略开始搜索',
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodyMedium
                                                ?.copyWith(
                                                  color: Theme.of(context).colorScheme.outline,
                                                ),
                                          ),
                                        ],
                                      ),
                                    )
                                  : ListView.builder(
                                      itemCount: _searchResults.length,
                                      itemBuilder: (context, index) {
                                        final item = _searchResults[index];
                                        return TorrentListItem(
                                          torrent: item.torrent,
                                          isSelected: false,
                                          isSelectionMode: false,
                                          isAggregateMode: true,
                                          siteName: item.siteName,
                                          onTap: () => _onTorrentTap(item),
                                          onDownload: () => _onTorrentDownload(item),
                                          // 聚合搜索模式下不支持收藏功能
                                          onToggleCollection: null,
                                        );
                                      },
                                    ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  void _performSearch(String query) async {
    if (query.trim().isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请输入搜索关键词')));
      return;
    }

    if (_selectedStrategy.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请选择搜索策略')));
      return;
    }

    setState(() {
      _searching = true;
      _searchResults.clear();
      _searchErrors.clear();
      _searchProgress = null;
    });

    try {
      final result = await AggregateSearchService.instance.performAggregateSearch(
        keyword: query.trim(),
        configId: _selectedStrategy,
        maxResultsPerSite: 5,
        onProgress: (progress) {
          if (mounted) {
            setState(() {
              _searchProgress = progress;
            });
          }
        },
      );

      if (mounted) {
        setState(() {
          _searchResults = result.items;
          _searchErrors = result.errors;
          _searching = false;
          _searchProgress = null;
        });

        // 显示搜索结果摘要
        final message = '搜索完成：共找到 ${result.items.length} 条结果，'
            '成功搜索 ${result.successSites}/${result.totalSites} 个站点';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message)),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _searching = false;
          _searchProgress = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('搜索失败：$e')),
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
            content: Text('打开详情失败: $e'),
            backgroundColor: Theme.of(context).colorScheme.errorContainer,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _onTorrentDownload(AggregateSearchResultItem item) async {
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
            content: Text('已成功发送"${item.torrent.name}"到 ${clientConfig.name}'),
            backgroundColor: Theme.of(context).colorScheme.primaryContainer,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('下载失败: $e'),
            backgroundColor: Theme.of(context).colorScheme.errorContainer,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }
}
