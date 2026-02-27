import 'package:flutter/material.dart';
import 'dart:async';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:flutter/rendering.dart';
import 'dart:math' as math;
import '../models/app_models.dart';
import '../services/storage/storage_service.dart';
import '../services/api/api_service.dart';
import '../services/aggregate_search_service.dart';
import '../services/downloader/downloader_config.dart';
import '../services/downloader/downloader_service.dart';
import '../services/downloader/downloader_models.dart';

import '../providers/aggregate_search_provider.dart';
import '../widgets/responsive_layout.dart';
import '../widgets/qb_speed_indicator.dart';
import '../widgets/torrent_list_item.dart';
import '../widgets/torrent_download_dialog.dart';
import '../widgets/tag_filter_bar.dart';
import 'torrent_detail_page.dart';
import 'package:pt_mate/utils/notification_helper.dart';

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

  // 拖动与多选增强功能
  bool _isDraggingSelection = false;
  int? _dragStartIndex;
  int? _lastSelectedIndex;
  Set<String> _preDragSelectedItems = <String>{};
  final GlobalKey _listKey = GlobalKey();

  final ScrollController _listController = ScrollController();
  final ScrollController _errorListController = ScrollController();

  // String? _overlaySiteName; // Moved to _AggregateSearchScrollbar
  // double _overlayOpacity = 0.0; // Moved to _AggregateSearchScrollbar
  // Timer? _overlayTimer; // Moved to _AggregateSearchScrollbar
  final Map<String, Color> _siteColors = {};
  bool _isFastScrolling = false;
  bool _showErrorWidget = true;

  // 头部隐藏动画相关
  double _headerProgress = 1.0; // 1.0=完全显示, 0.0=完全隐藏
  double _lastScrollOffset = 0.0;
  final double _maxHideDistance = 200.0; // 滚动多少距离完全隐藏
  
  // 封面图片显示设置（用户偏好）
  bool _showCoverSetting = true; // 默认自动显示

  Color _colorForSite(String siteId) {
    if (_siteColors.containsKey(siteId)) return _siteColors[siteId]!;
    Color color;
    try {
      final storage = Provider.of<StorageService>(context, listen: false);
      final sites = storage.siteConfigsCache ?? [];
      final site = sites.firstWhere(
        (s) => s.id == siteId,
        orElse: () => const SiteConfig(id: '', name: '', baseUrl: ''),
      );
      if (site.siteColor != null) {
        color = Color(site.siteColor!);
      } else {
        final primaries = Colors.primaries;
        color = primaries[(siteId.hashCode.abs()) % primaries.length];
      }
    } catch (_) {
      final primaries = Colors.primaries;
      color = primaries[(siteId.hashCode.abs()) % primaries.length];
    }
    _siteColors[siteId] = color;
    return color;
  }

  @override
  void initState() {
    super.initState();
    _loadSearchConfigs();
    _listController.addListener(() {
      if (!_listController.hasClients) return;
      
      final currentOffset = _listController.offset;
      final delta = currentOffset - _lastScrollOffset;

      // 计算头部显示进度
      double newProgress = _headerProgress;

      // 快速滚动时强制隐藏头部
      if (_isFastScrolling) {
        newProgress = 0.0;
      } else {
        if (delta > 0) {
          // 向下滚动:隐藏
          newProgress = (_headerProgress - delta / _maxHideDistance).clamp(
            0.0,
            1.0,
          );
        } else if (delta < 0) {
          // 向上滚动:显示
          newProgress = (_headerProgress + (-delta) / _maxHideDistance).clamp(
            0.0,
            1.0,
          );
        }
      }

      if (newProgress != _headerProgress) {
        setState(() {
          _headerProgress = newProgress;
        });
      }
      _lastScrollOffset = currentOffset;
      
      // 一旦开始滑动，就隐藏错误提示
      if (_showErrorWidget && _listController.offset > 0) {
        setState(() {
          _showErrorWidget = false;
        });
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _listController.dispose();
    _errorListController.dispose();
    // _overlayTimer?.cancel(); // Moved to _AggregateSearchScrollbar
    super.dispose();
  }

  Future<void> _loadSearchConfigs() async {
    final provider = Provider.of<AggregateSearchProvider>(
      context,
      listen: false,
    );

    try {
      final storage = Provider.of<StorageService>(context, listen: false);
      final settings = await storage.loadAggregateSearchSettings();

      if (mounted) {
        provider.setSearchConfigs(
          settings.searchConfigs.where((config) => config.isActive).toList(),
        );
        provider.setLoading(false);
        provider.initializeDefaultStrategy();
        
        // 加载封面图片显示设置
        final showCoverSetting = await storage.loadShowCoverImages();
        if (mounted) {
          setState(() => _showCoverSetting = showCoverSetting);
        }
      }
    } catch (e) {
      if (mounted) {
        provider.setLoading(false);
        NotificationHelper.showError(context, '加载搜索配置失败: $e');
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
            actions: [const QbSpeedIndicator()],
          ),
          body: provider.loading
              ? const Center(child: CircularProgressIndicator())
              : Padding(
                  padding: const EdgeInsets.all(4.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 搜索区域 - 带滚动隐藏动画
                      ClipRect(
                        child: Align(
                          alignment: Alignment.bottomCenter,
                          heightFactor: _headerProgress,
                          child: Opacity(
                            opacity: _headerProgress,
                            child: Card(
                              child: Padding(
                                padding: const EdgeInsets.all(2.0),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // 紧凑的搜索控件行
                                    Row(
                                      children: [
                                        // 搜索策略选择
                                        Expanded(
                                          flex: 1,
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
                                              borderRadius:
                                                  BorderRadius.circular(25),
                                            ),
                                            child: DropdownButton<String>(
                                              value:
                                                  provider
                                                      .selectedStrategy
                                                      .isEmpty
                                                  ? null
                                                  : provider.selectedStrategy,
                                              hint: const Text('选择搜索策略'),
                                              isExpanded: true,
                                              underline: const SizedBox(),
                                              icon: const SizedBox.shrink(),
                                              items: provider.searchConfigs.map(
                                                (config) {
                                                  return DropdownMenuItem<
                                                    String
                                                  >(
                                                    value: config.id,
                                                    child: Row(
                                                      children: [
                                                        Icon(
                                                          config.isAllSitesType
                                                              ? Icons.public
                                                              : Icons.group,
                                                          size: 16,
                                                          color: Theme.of(
                                                            context,
                                                          ).colorScheme.primary,
                                                        ),
                                                        const SizedBox(
                                                          width: 8,
                                                        ),
                                                        Expanded(
                                                          child: Text(
                                                            config.name,
                                                            overflow:
                                                                TextOverflow
                                                                    .ellipsis,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  );
                                                },
                                              ).toList(),
                                              onChanged: (value) {
                                                if (value != null) {
                                                  provider.setSelectedStrategy(
                                                    value,
                                                  );
                                                }
                                              },
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 4),
                                        // 搜索输入框
                                        Expanded(
                                          flex: 3,
                                          child: TextField(
                                            controller: _searchController,
                                            decoration: InputDecoration(
                                              hintText: '输入搜索关键词',
                                              border: OutlineInputBorder(
                                                borderRadius:
                                                    const BorderRadius.all(
                                                      Radius.circular(25),
                                                    ),
                                                borderSide: BorderSide(
                                                  color: Theme.of(context)
                                                      .colorScheme
                                                      .primary
                                                      .withValues(alpha: 0.3),
                                                ),
                                              ),
                                              contentPadding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 12,
                                                    vertical: 8,
                                                  ),
                                              suffixIcon: IconButton(
                                                icon: const Icon(Icons.search),
                                                tooltip: '搜索',
                                                onPressed: () => _performSearch(
                                                  _searchController.text,
                                                ),
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
                                                ? Theme.of(
                                                    context,
                                                  ).colorScheme.secondary
                                                : null,
                                          ),
                                          tooltip: '排序',
                                          onSelected: (value) {
                                            // 与 app.dart 的行为保持一致：
                                            // 选择相同的排序类型时切换升降序；选择新的类型时默认降序
                                            if (value == provider.sortBy) {
                                              provider.setSortAscending(
                                                !provider.sortAscending,
                                              );
                                            } else {
                                              provider.setSortBy(value);
                                              provider.setSortAscending(false);
                                            }
                                            _resortCurrentResults();
                                          },
                                          itemBuilder: (context) => [
                                            PopupMenuItem(
                                              value: 'none',
                                              child: Container(
                                                decoration: BoxDecoration(
                                                  color:
                                                      provider.sortBy == 'none'
                                                      ? Theme.of(context)
                                                            .colorScheme
                                                            .primary
                                                            .withValues(
                                                              alpha: 0.1,
                                                            )
                                                      : null,
                                                  borderRadius:
                                                      BorderRadius.circular(4),
                                                ),
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 8,
                                                      vertical: 4,
                                                    ),
                                                child: Row(
                                                  children: [
                                                    Icon(
                                                      Icons.clear,
                                                      color:
                                                          provider.sortBy ==
                                                              'none'
                                                          ? Theme.of(context)
                                                                .colorScheme
                                                                .secondary
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
                                                  color:
                                                      provider.sortBy == 'size'
                                                      ? Theme.of(context)
                                                            .colorScheme
                                                            .primary
                                                            .withValues(
                                                              alpha: 0.1,
                                                            )
                                                      : null,
                                                  borderRadius:
                                                      BorderRadius.circular(4),
                                                ),
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 8,
                                                      vertical: 4,
                                                    ),
                                                child: Row(
                                                  children: [
                                                    Icon(
                                                      provider.sortBy ==
                                                                  'size' &&
                                                              provider
                                                                  .sortAscending
                                                          ? Icons.arrow_upward
                                                          : Icons
                                                                .arrow_downward,
                                                      color:
                                                          provider.sortBy ==
                                                              'size'
                                                          ? Theme.of(context)
                                                                .colorScheme
                                                                .secondary
                                                          : null,
                                                    ),
                                                    const SizedBox(width: 8),
                                                    const Text('按大小排序'),
                                                  ],
                                                ),
                                              ),
                                            ),

                                            PopupMenuItem(
                                              value: 'upload',
                                              child: Container(
                                                decoration: BoxDecoration(
                                                  color:
                                                      provider.sortBy ==
                                                          'upload'
                                                      ? Theme.of(context)
                                                            .colorScheme
                                                            .primary
                                                            .withValues(
                                                              alpha: 0.1,
                                                            )
                                                      : null,
                                                  borderRadius:
                                                      BorderRadius.circular(4),
                                                ),
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 8,
                                                      vertical: 4,
                                                    ),
                                                child: Row(
                                                  children: [
                                                    Icon(
                                                      provider.sortBy ==
                                                                  'upload' &&
                                                              provider
                                                                  .sortAscending
                                                          ? Icons.arrow_upward
                                                          : Icons
                                                                .arrow_downward,
                                                      color:
                                                          provider.sortBy ==
                                                              'upload'
                                                          ? Theme.of(context)
                                                                .colorScheme
                                                                .secondary
                                                          : null,
                                                    ),
                                                    const SizedBox(width: 8),
                                                    const Text('按上传量排序'),
                                                  ],
                                                ),
                                              ),
                                            ),

                                            PopupMenuItem(
                                              value: 'download',
                                              child: Container(
                                                decoration: BoxDecoration(
                                                  color:
                                                      provider.sortBy ==
                                                          'download'
                                                      ? Theme.of(context)
                                                            .colorScheme
                                                            .primary
                                                            .withValues(
                                                              alpha: 0.1,
                                                            )
                                                      : null,
                                                  borderRadius:
                                                      BorderRadius.circular(4),
                                                ),
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 8,
                                                      vertical: 4,
                                                    ),
                                                child: Row(
                                                  children: [
                                                    Icon(
                                                      provider.sortBy ==
                                                                  'download' &&
                                                              provider
                                                                  .sortAscending
                                                          ? Icons.arrow_upward
                                                          : Icons
                                                                .arrow_downward,
                                                      color:
                                                          provider.sortBy ==
                                                              'download'
                                                          ? Theme.of(context)
                                                                .colorScheme
                                                                .secondary
                                                          : null,
                                                    ),
                                                    const SizedBox(width: 8),
                                                    const Text('按下载量排序'),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                    // 标签筛选栏
                                    TagFilterBar(
                                      includedTags: provider.includedTags,
                                      excludedTags: provider.excludedTags,
                                      onIncludedChanged:
                                          provider.setIncludedTags,
                                      onExcludedChanged:
                                          provider.setExcludedTags,
                                      padding: const EdgeInsets.fromLTRB(
                                        8.0,
                                        8.0,
                                        8.0,
                                        4.0,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
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
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Text(
                                      '正在搜索...',
                                      style: Theme.of(
                                        context,
                                      ).textTheme.titleSmall,
                                    ),
                                    const Spacer(),
                                    TextButton.icon(
                                      onPressed: () {
                                        provider.cancelSearch();
                                      },
                                      icon: const Icon(Icons.stop, size: 16),
                                      label: const Text('停止'),
                                      style: TextButton.styleFrom(
                                        side: BorderSide(
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.outline,
                                          width: 1.0,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                if (provider.searchProgress != null) ...[
                                  const SizedBox(height: 8),
                                  LinearProgressIndicator(
                                    value:
                                        provider.searchProgress!.totalSites > 0
                                        ? provider
                                                  .searchProgress!
                                                  .completedSites /
                                              provider
                                                  .searchProgress!
                                                  .totalSites
                                        : 0.0,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${provider.searchProgress!.completedSites}/${provider.searchProgress!.totalSites} 个站点',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodySmall,
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],

                      // 搜索结果
                      if (provider.searchErrors.isNotEmpty &&
                          _showErrorWidget) ...[
                        FutureBuilder<List<SiteConfig>>(
                          future: Provider.of<StorageService>(
                            context,
                            listen: false,
                          ).loadSiteConfigs(),
                          builder: (context, snapshot) {
                            if (snapshot.connectionState ==
                                ConnectionState.waiting) {
                              return const SizedBox(); // or a loading indicator
                            }
                            if (snapshot.hasError) {
                              return const SizedBox(); // or an error message
                            }
                            final sites = snapshot.data ?? [];
                            return Card(
                              color: Theme.of(
                                context,
                              ).colorScheme.errorContainer,
                              child: ExpansionTile(
                                title: Text(
                                  '部分站点搜索失败',
                                  style: Theme.of(context).textTheme.titleSmall
                                      ?.copyWith(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.onErrorContainer,
                                      ),
                                ),
                                iconColor: Theme.of(
                                  context,
                                ).colorScheme.onErrorContainer,
                                collapsedIconColor: Theme.of(
                                  context,
                                ).colorScheme.onErrorContainer,
                                tilePadding: const EdgeInsets.symmetric(
                                  horizontal: 16.0,
                                  vertical: 2.0,
                                ),
                                childrenPadding: const EdgeInsets.fromLTRB(
                                  16.0,
                                  0,
                                  16.0,
                                  16.0,
                                ),
                                children: [
                                  Container(
                                    constraints: const BoxConstraints(
                                      maxHeight: 240,
                                    ),
                                    child: Scrollbar(
                                      thumbVisibility: true,
                                      controller: _errorListController,
                                      child: ListView.separated(
                                        controller: _errorListController,
                                        shrinkWrap: true,
                                        padding: EdgeInsets.zero,
                                        itemCount: provider.searchErrors.length,
                                        separatorBuilder: (context, index) =>
                                            Divider(
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .onErrorContainer
                                                  .withValues(alpha: 0.2),
                                              height: 1,
                                            ),
                                        itemBuilder: (context, index) {
                                          final entry = provider
                                              .searchErrors
                                              .entries
                                              .elementAt(index);
                                          final siteName = sites
                                              .firstWhere(
                                                (site) => site.id == entry.key,
                                                orElse: () => SiteConfig(
                                                  id: '',
                                                  name: '未知站点',
                                                  baseUrl: '',
                                                ),
                                              )
                                              .name;
                                          return Padding(
                                            padding: const EdgeInsets.fromLTRB(
                                              8.0,
                                              0,
                                              8.0,
                                              8.0,
                                            ),
                                            child: Align(
                                              alignment: Alignment.centerLeft,
                                              child: Text(
                                                '$siteName: ${entry.value}',
                                                textAlign: TextAlign.left,
                                                style: TextStyle(
                                                  color: Theme.of(context)
                                                      .colorScheme
                                                      .onErrorContainer,
                                                ),
                                              ),
                                            ),
                                          );
                                        },
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 16),
                      ],
                      Expanded(
                        child:
                            provider.searchResults.isEmpty &&
                                !provider.searching
                            ? Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.search,
                                      size: 64,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.outline,
                                    ),
                                    const SizedBox(height: 16),
                                    Text(
                                      '输入关键词开始搜索',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyLarge
                                          ?.copyWith(
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.outline,
                                          ),
                                    ),
                                  ],
                                ),
                              )
                            : Stack(
                                children: [
                                  ScrollConfiguration(
                                    behavior: ScrollConfiguration.of(
                                      context,
                                    ).copyWith(scrollbars: false),
                                    child: Listener(
                                      onPointerMove: _onPointerMove,
                                      onPointerUp: _onPointerUp,
                                      child: ListView.builder(
                                        key: _listKey,
                                        controller: _listController,
                                        itemCount:
                                            provider.filteredResults.length,
                                        itemBuilder: (context, index) {
                                          final item =
                                              provider.filteredResults[index];
                                          // final Color siteColor = _colorForSite(item.siteId);
                                          return Container(
                                            key: ValueKey(item.torrent.id),
                                            padding: EdgeInsets.zero,
                                            child: MetaData(
                                              metaData: index,
                                              behavior:
                                                  HitTestBehavior.translucent,
                                              child: RepaintBoundary(
                                                child: TorrentListItem(
                                                  torrent: item.torrent,
                                                  isSelected: _selectedItems
                                                      .contains(
                                                        item.torrent.id,
                                                      ),
                                                  isSelectionMode:
                                                      _isSelectionMode,
                                                  isAggregateMode: true,
                                                  siteName: item.siteName,
                                                  showCoverSetting:
                                                      _showCoverSetting,
                                                  suspendImageLoading:
                                                      _isFastScrolling,
                                                  onTap: _isSelectionMode
                                                      ? () =>
                                                            _onToggleSelection(
                                                              item,
                                                              index,
                                                            )
                                                      : () =>
                                                            _onTorrentTap(item),
                                                  onLongPress: () =>
                                                      _onLongPress(item, index),
                                                  onDownload: () =>
                                                      _showDownloadDialog(item),
                                                  onToggleCollection: () =>
                                                      _onToggleCollection(item),
                                                ),
                                              ),
                                            ),
                                          );
                                        },
                                      ),
                                    ),
                                  ),
                                  if (provider.filteredResults.isNotEmpty)
                                    Positioned.fill(
                                      child: LayoutBuilder(
                                        builder: (context, constraints) {
                                          final totalHeight =
                                              constraints.maxHeight;
                                          final results =
                                              provider.filteredResults;
                                          final counts = <String, int>{};
                                          final names = <String, String>{};
                                          for (
                                            var i = 0;
                                            i < results.length;
                                            i++
                                          ) {
                                            final id = results[i].siteId;
                                            counts[id] = (counts[id] ?? 0) + 1;
                                            names[id] = results[i].siteName;
                                          }
                                          final siteIds = counts.keys.toList();
                                          final totalCount = results.length;
                                          double acc = 0;
                                          final sections = <_SiteSection>[];
                                          final firstIndex = <String, int>{};
                                          for (
                                            var i = 0;
                                            i < results.length;
                                            i++
                                          ) {
                                            final id = results[i].siteId;
                                            firstIndex[id] ??= i;
                                          }
                                          for (final id in siteIds) {
                                            final ratio =
                                                (counts[id]! / totalCount);
                                            final extent = totalHeight * ratio;
                                            sections.add(
                                              _SiteSection(
                                                siteId: id,
                                                siteName: names[id] ?? id,
                                                color: _colorForSite(id),
                                                start: acc,
                                                extent: extent,
                                                firstIndex: firstIndex[id] ?? 0,
                                              ),
                                            );
                                            acc += extent;
                                          }
                                          return _AggregateSearchScrollbar(
                                            controller: _listController,
                                                sections: sections,
                                            onFastScrollingChanged:
                                                _setFastScrolling,
                                          );
                                        },
                                      ),
                                    ),

                                ],
                              ),
                      ),

                      // 选择模式下的操作栏
                      if (_isSelectionMode) ...[
                        const SizedBox(height: 8),
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12.0,
                              vertical: 12.0,
                            ),
                            child: Row(
                              children: [
                                Text(
                                  '已选择 ${_selectedItems.length} 项',
                                  style: Theme.of(context).textTheme.titleSmall
                                      ?.copyWith(fontSize: 13),
                                ),
                                const Spacer(),
                                TextButton(
                                  onPressed: _onCancelSelection,
                                  style: TextButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                    ),
                                    textStyle: const TextStyle(fontSize: 12),
                                    side: BorderSide(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.outline,
                                      width: 1.0,
                                    ),
                                  ),
                                  child: const Text('取消'),
                                ),
                                const SizedBox(width: 6),
                                // 全选按钮
                                TextButton(
                                  onPressed: () {
                                    if (_selectedItems.length ==
                                        provider.filteredResults.length) {
                                      setState(() => _selectedItems.clear());
                                    } else {
                                      setState(() {
                                        _selectedItems.addAll(
                                          provider.filteredResults.map(
                                            (e) => e.torrent.id,
                                          ),
                                        );
                                      });
                                    }
                                  },
                                  style: TextButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                    ),
                                    textStyle: const TextStyle(fontSize: 12),
                                    side: BorderSide(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.outline,
                                      width: 1.0,
                                    ),
                                  ),
                                  child: Text(
                                    _selectedItems.length ==
                                            provider.filteredResults.length
                                        ? '全不选'
                                        : '全选',
                                  ),
                                ),
                                const SizedBox(width: 6),
                                ElevatedButton.icon(
                                  onPressed: _selectedItems.isEmpty
                                      ? null
                                      : _onBatchDownload,
                                  style: ElevatedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                    ),
                                    textStyle: const TextStyle(fontSize: 12),
                                  ),
                                  icon: const Icon(Icons.download, size: 16),
                                  label: const Text('下载'),
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
  List<AggregateSearchResultItem> _applySorting(
    List<AggregateSearchResultItem> items,
    String sortBy,
    bool sortAscending,
  ) {
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
      case 'upload':
        // 按做种数排序（与 app.dart 的“上传量”一致，使用 seeders）
        sortedItems.sort((a, b) {
          final comparison = a.torrent.seeders.compareTo(b.torrent.seeders);
          return sortAscending ? comparison : -comparison;
        });
        break;
      case 'download':
        // 按下载量排序（使用 leechers）
        sortedItems.sort((a, b) {
          final comparison = a.torrent.leechers.compareTo(b.torrent.leechers);
          return sortAscending ? comparison : -comparison;
        });
        break;
    }

    return sortedItems;
  }

  /// 重新排序当前搜索结果
  void _resortCurrentResults() {
    final provider = Provider.of<AggregateSearchProvider>(
      context,
      listen: false,
    );
    if (provider.searchResults.isNotEmpty) {
      final sortedResults = _applySorting(
        provider.searchResults,
        provider.sortBy,
        provider.sortAscending,
      );
      provider.setSearchResults(sortedResults);
    }
  }

  void _performSearch(String query) async {
    // 允许空关键字搜索，用于获取站点最新种子

    final provider = Provider.of<AggregateSearchProvider>(
      context,
      listen: false,
    );

    if (provider.selectedStrategy.isEmpty) {
      NotificationHelper.showError(context, '请选择搜索策略');
      return;
    }

    provider.createCancelToken();
    provider.setSearching(true);
    provider.setSearchResults([]);
    provider.setSearchErrors({});
    provider.setSearchProgress(null);
    setState(() {
      _showErrorWidget = true;
    });

    try {
      final result = await AggregateSearchService.instance
          .performAggregateSearch(
            keyword: query.trim().isEmpty ? '' : query.trim(),
            configId: provider.selectedStrategy,
            maxResultsPerSite: 50,
            onProgress: (progress) {
              if (mounted) {
                provider.setSearchProgress(progress);
              }
            },
            cancelToken: provider.cancelToken,
          );

      if (mounted) {
        final sortedResults = _applySorting(
          result.items,
          provider.sortBy,
          provider.sortAscending,
        );
        provider.setSearchResults(sortedResults);
        provider.setSearchErrors(result.errors);
        provider.setSearching(false);
        provider.setSearchProgress(null);

        // 显示搜索结果摘要
        final message = provider.cancelled
            ? '已停止搜索：当前返回 ${result.items.length} 条结果，完成 ${result.successSites}/${result.totalSites} 个站点'
            : '搜索完成：共找到 ${result.items.length} 条结果，成功搜索 ${result.successSites}/${result.totalSites} 个站点';
        NotificationHelper.showInfo(context, message);
      }
    } catch (e) {
      if (mounted) {
        provider.setSearching(false);
        provider.setSearchProgress(null);
        NotificationHelper.showError(context, '搜索失败：$e');
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
      final downloaderConfigsData = await storage.loadDownloaderConfigs();
      final downloaderConfigs = downloaderConfigsData.map((configMap) {
        return DownloaderConfig.fromJson(configMap);
      }).toList();

      // 4. 跳转到详情页面
      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => TorrentDetailPage(
            torrentItem: item.torrent,
            siteFeatures: siteConfig.features,
            downloaderConfigs: downloaderConfigs,
            siteConfig: siteConfig, // 传入站点配置
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        NotificationHelper.showError(context, '打开详情失败: $e');
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
      final startPaused = result['startPaused'] as bool?;

      // 5. 发送到 qBittorrent
      await _onTorrentDownload(
        item,
        clientConfig,
        password,
        url,
        category,
        tags,
        savePath,
        autoTMM,
        startPaused,
        siteConfig,
      );
    } catch (e) {
      if (mounted) {
        NotificationHelper.showError(context, '下载失败: $e');
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
    bool? startPaused,
    SiteConfig siteConfig,
  ) async {
    try {
      // 使用统一的下载器服务
      await DownloaderService.instance.addTask(
        config: clientConfig,
        password: password,
        params: AddTaskParams(
          url: url,
          category: category,
          tags: tags,
          savePath: savePath,
          autoTMM: autoTMM,
          startPaused: startPaused,
        ),
        siteConfig: siteConfig,
      );

      if (mounted) {
        NotificationHelper.showInfo(
          context,
          '已成功发送"${item.torrent.name}"到 ${clientConfig.name}',
        );
      }
    } catch (e) {
      if (mounted) {
        NotificationHelper.showError(context, '下载失败: $e');
      }
    }
  }

  void _onPointerUp(PointerUpEvent event) {
    if (_isDraggingSelection && mounted) {
      setState(() {
        _isDraggingSelection = false;
        _dragStartIndex = null;
      });
    }
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (!_isDraggingSelection || _dragStartIndex == null || !mounted) return;

    final RenderBox? box =
        _listKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;

    final result = BoxHitTestResult();
    box.hitTest(result, position: box.globalToLocal(event.position));

    int? currentIndex;
    for (final hit in result.path) {
      if (hit.target is RenderMetaData) {
        final metaData = (hit.target as RenderMetaData).metaData;
        if (metaData is int) {
          currentIndex = metaData;
          break;
        }
      }
    }

    if (currentIndex != null) {
      final minIndex = math.min(_dragStartIndex!, currentIndex);
      final maxIndex = math.max(_dragStartIndex!, currentIndex);

      final newSelection = Set<String>.from(_preDragSelectedItems);
      final provider = Provider.of<AggregateSearchProvider>(
        context,
        listen: false,
      );
      final filteredResults = provider.filteredResults;
      for (int i = minIndex; i <= maxIndex; i++) {
        if (i >= 0 && i < filteredResults.length) {
          newSelection.add(filteredResults[i].torrent.id);
        }
      }

      setState(() {
        _selectedItems.clear();
        _selectedItems.addAll(newSelection);
        _lastSelectedIndex = currentIndex;
      });

      // Auto-scrolling logic inside list area
      if (_listController.hasClients) {
        final localY = box.globalToLocal(event.position).dy;
        if (localY < 50) {
          _listController.position.moveTo(_listController.offset - 15);
        } else if (localY > box.size.height - 50) {
          _listController.position.moveTo(_listController.offset + 15);
        }
      }
    }
  }

  // 长按触发选中模式
  void _onLongPress(AggregateSearchResultItem item, int index) {
    if (mounted) {
      // 使用 Flutter 内置的触觉反馈，提供原生的震动体验
      HapticFeedback.mediumImpact();
      setState(() {
        if (!_isSelectionMode) {
          _isSelectionMode = true;
          _selectedItems.add(item.torrent.id);
        }
        _isDraggingSelection = true;
        _dragStartIndex = index;
        _preDragSelectedItems = Set<String>.from(_selectedItems);
      });
    }
  }

  // 切换选中状态
  void _onToggleSelection(AggregateSearchResultItem item, int index) {
    if (mounted) {
      final isShiftPressed =
          HardwareKeyboard.instance.logicalKeysPressed.contains(
            LogicalKeyboardKey.shiftLeft,
          ) ||
          HardwareKeyboard.instance.logicalKeysPressed.contains(
            LogicalKeyboardKey.shiftRight,
          );
                             
      setState(() {
        if (isShiftPressed && _lastSelectedIndex != null) {
          final minIndex = math.min(_lastSelectedIndex!, index);
          final maxIndex = math.max(_lastSelectedIndex!, index);

          final isSelecting = !_selectedItems.contains(item.torrent.id);
          final provider = Provider.of<AggregateSearchProvider>(
            context,
            listen: false,
          );
          final filteredResults = provider.filteredResults;

          for (int i = minIndex; i <= maxIndex; i++) {
            if (i >= 0 && i < filteredResults.length) {
              final targetItem = filteredResults[i];
              if (isSelecting) {
                _selectedItems.add(targetItem.torrent.id);
              } else {
                _selectedItems.remove(targetItem.torrent.id);
              }
            }
          }
        } else {
          if (_selectedItems.contains(item.torrent.id)) {
            _selectedItems.remove(item.torrent.id);
            if (_selectedItems.isEmpty) {
              _isSelectionMode = false;
            }
          } else {
            _selectedItems.add(item.torrent.id);
          }
        }
        _lastSelectedIndex = index;
      });
    }
  }

  // 批量下载
  Future<void> _onBatchDownload() async {
    if (_selectedItems.isEmpty) return;

    final provider = Provider.of<AggregateSearchProvider>(
      context,
      listen: false,
    );
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
      NotificationHelper.showInfo(
        context,
        '开始批量下载${selectedItems.length}个项目到${clientConfig.name}...',
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
        await DownloaderService.instance.addTask(
          config: clientConfig,
          password: password,
          params: AddTaskParams(
            url: url,
            category: category,
            tags: tags.isEmpty ? null : tags,
            savePath: savePath,
            autoTMM: autoTMM,
          ),
          siteConfig: siteConfig,
        );

        successCount++;

        // 添加延迟避免请求过快
        await Future.delayed(const Duration(milliseconds: 500));
      } catch (e) {
        failureCount++;
        if (mounted) {
          NotificationHelper.showError(
            context,
            '下载失败: ${item.torrent.name}, 错误: $e',
            duration: const Duration(seconds: 2),
          );
        }
      }
    }

    // 显示最终结果
    if (mounted) {
      final message = failureCount == 0
          ? '批量下载完成，成功$successCount个项目'
          : '批量下载完成，成功$successCount个，失败$failureCount个';

      if (failureCount == 0) {
        NotificationHelper.showInfo(
          context,
          message,
          duration: const Duration(seconds: 2),
        );
      } else {
        NotificationHelper.showError(
          context,
          message,
          duration: const Duration(seconds: 2),
        );
      }
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
        NotificationHelper.showInfo(
          context,
          newCollectionState ? '已收藏' : '已取消收藏',
          duration: const Duration(seconds: 1),
        );
      }
    } catch (e) {
      // 请求失败，恢复原状态
      if (mounted) {
        setState(() {
          item.torrent.collection = !newCollectionState;
        });
        NotificationHelper.showError(context, '收藏操作失败：$e');
      }
    }
  }

  void _setFastScrolling(bool v) {
    if (_isFastScrolling == v) return;
    setState(() {
      _isFastScrolling = v;
    });
  }
}

class _AggregateSearchScrollbar extends StatefulWidget {
  final ScrollController controller;
  final List<_SiteSection> sections;
  final ValueChanged<bool> onFastScrollingChanged;

  const _AggregateSearchScrollbar({
    required this.controller,
    required this.sections,
    required this.onFastScrollingChanged,
  });

  @override
  State<_AggregateSearchScrollbar> createState() =>
      _AggregateSearchScrollbarState();
}

class _AggregateSearchScrollbarState extends State<_AggregateSearchScrollbar> {
  double _scrollFraction = 0.0;
  String? _overlaySiteName;
  double _overlayOpacity = 0.0;
  Timer? _overlayTimer;
  bool _isDragging = false; // 标志是否正在拖动

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_updateScrollFraction);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_updateScrollFraction);
    _overlayTimer?.cancel();
    super.dispose();
  }

  void _updateScrollFraction() {
    if (!widget.controller.hasClients) return;
    // 拖动时不更新，避免与手动更新冲突
    if (_isDragging) return;
    final max = widget.controller.position.maxScrollExtent;
    final px = widget.controller.position.pixels;
    final f = max > 0 ? (px / max).clamp(0.0, 1.0) : 0.0;
    if (f != _scrollFraction) {
      setState(() {
        _scrollFraction = f;
      });
    }
  }

  void _handleScrollbarDrag(
    double dy,
    double totalHeight, {
    bool initial = false,
  }) {
    final sections = widget.sections;
    final section = sections.firstWhere(
      (s) => dy >= s.start && dy <= s.start + s.extent,
      orElse: () => sections.isNotEmpty ? sections.last : _SiteSection.empty,
    );
    if (section == _SiteSection.empty) return;
    _overlayTimer?.cancel();
    
    // 仅当状态只有变化时才调用 setState
    if (_overlaySiteName != section.siteName || _overlayOpacity != 1.0) {
      setState(() {
        _overlaySiteName = section.siteName;
        _overlayOpacity = 1.0;
      });
    }
    
    if (initial) {
      if (widget.controller.hasClients) {
        final fraction = section.start / totalHeight;
        widget.controller.jumpTo(
          widget.controller.position.maxScrollExtent * fraction,
        );
      }
    }
  }

  void _startOverlayFadeOut() {
    _overlayTimer?.cancel();
    _overlayTimer = Timer(const Duration(milliseconds: 500), () {
      if (mounted) {
        setState(() {
          _overlayOpacity = 0.0;
        });
      }
    });
  }

  void _scrollToFraction(double f) {
    if (!widget.controller.hasClients) return;
    // 增加安全性检查，防止 NaN 导致断言错误
    if (f.isNaN || f.isInfinite) return;
    
    final max = widget.controller.position.maxScrollExtent;
    final clampedF = f.clamp(0.0, 1.0);
    final target = max * clampedF;

    try {
      widget.controller.jumpTo(target);
    } catch (_) {
      // 忽略滚动过程中的潜在错误
    }

    if (_scrollFraction != clampedF) {
      setState(() {
        _scrollFraction = clampedF;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final totalHeight = constraints.maxHeight;
        return Stack(
          children: [
            Positioned(
              right: 0,
              top: 0,
              bottom: 0,
              width: 20,
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTapDown: (details) {
                  if (totalHeight <= 0) return;
                  final y = details.localPosition.dy;
                  final fraction = (y / totalHeight).clamp(0.0, 1.0);
                  _scrollToFraction(fraction);
                  final sec = widget.sections.firstWhere(
                    (s) => y >= s.start && y <= s.start + s.extent,
                    orElse: () => _SiteSection.empty,
                  );
                  if (sec != _SiteSection.empty) {
                    setState(() {
                      _overlaySiteName = sec.siteName;
                      _overlayOpacity = 1.0;
                    });
                  }
                  _startOverlayFadeOut();
                },
                onPanStart: (details) {
                  if (totalHeight <= 0) return;
                  setState(() {
                    _isDragging = true;
                  });
                  widget.onFastScrollingChanged(true);
                  _handleScrollbarDrag(
                    details.localPosition.dy,
                    totalHeight,
                    initial: true,
                  );
                },
                onPanUpdate: (details) {
                  if (totalHeight <= 0) return;
                  _handleScrollbarDrag(details.localPosition.dy, totalHeight);
                  final y = details.localPosition.dy;
                  final fraction = (y / totalHeight).clamp(0.0, 1.0);
                  // 拖动时也需要更新状态以重绘滑块位置
                  _scrollToFraction(fraction);
                },
                onPanEnd: (details) {
                  setState(() {
                    _isDragging = false;
                  });
                  widget.onFastScrollingChanged(false);
                  _startOverlayFadeOut();
                  // 拖动结束后同步最终状态
                  _updateScrollFraction();
                },
                child: Align(
                  alignment: Alignment.centerRight,
                  child: CustomPaint(
                    size: Size(8, totalHeight),
                    painter: _SiteScrollbarPainter(
                      sections: widget.sections,
                      fraction: _scrollFraction,
                      knobColor: Theme.of(context).colorScheme.primary,
                      knobBorder: Theme.of(context).colorScheme.onPrimary,
                    ),
                  ),
                ),
              ),
            ),
            if (_overlaySiteName != null)
              Positioned.fill(
                child: IgnorePointer(
                  ignoring: true,
                  child: AnimatedOpacity(
                    opacity: _overlayOpacity,
                    duration: _overlayOpacity == 1.0
                        ? Duration.zero
                        : const Duration(seconds: 1),
                    child: Container(
                      color: Theme.of(
                        context,
                      ).colorScheme.scrim.withValues(alpha: 0.35),
                      alignment: Alignment.center,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primaryContainer,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.2),
                              blurRadius: 8,
                              spreadRadius: 0,
                            ),
                          ],
                        ),
                        child: Text(
                          _overlaySiteName!,
                          style:
                              Theme.of(
                                context,
                              ).textTheme.headlineSmall?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onPrimaryContainer,
                                fontWeight: FontWeight.w600,
                              ) ??
                              TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.w600,
                                color: Theme.of(
                                  context,
                                ).colorScheme.onPrimaryContainer,
                              ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }


}

class _SiteSection {
  final String siteId;
  final String siteName;
  final Color color;
  final double start;
  final double extent;
  final int firstIndex;

  const _SiteSection({
    required this.siteId,
    required this.siteName,
    required this.color,
    required this.start,
    required this.extent,
    required this.firstIndex,
  });

  static const empty = _SiteSection(
    siteId: '',
    siteName: '',
    color: Colors.transparent,
    start: 0,
    extent: 0,
    firstIndex: 0,
  );
}

class _SiteScrollbarPainter extends CustomPainter {
  final List<_SiteSection> sections;
  final double fraction;
  final Color knobColor;
  final Color knobBorder;

  _SiteScrollbarPainter({
    required this.sections,
    required this.fraction,
    required this.knobColor,
    required this.knobBorder,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;
    for (final s in sections) {
      paint.color = s.color.withValues(alpha: 0.8);
      canvas.drawRect(
        Rect.fromLTWH(size.width - 4, s.start, 4, s.extent),
        paint,
      );
    }

    final knobSize = 18.0;
    final y = (size.height - knobSize) * fraction;
    final knobPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = knobColor;
    canvas.drawCircle(
      Offset(size.width - 2, y + knobSize / 2),
      knobSize / 2,
      knobPaint,
    );
    final borderPaint = Paint()
      ..style = PaintingStyle.stroke
      ..color = knobBorder
      ..strokeWidth = 2;
    canvas.drawCircle(
      Offset(size.width - 2, y + knobSize / 2),
      knobSize / 2,
      borderPaint,
    );
  }

  @override
  bool shouldRepaint(_SiteScrollbarPainter oldDelegate) {
    return oldDelegate.sections != sections ||
        oldDelegate.fraction != fraction ||
        oldDelegate.knobColor != knobColor ||
        oldDelegate.knobBorder != knobBorder;
  }
}
