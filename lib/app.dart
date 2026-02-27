import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'dart:async';
import 'package:flutter/services.dart';
import 'package:logger/logger.dart';
import 'package:flutter/rendering.dart';
import 'dart:math' as math;

import 'models/app_models.dart';
import 'pages/torrent_detail_page.dart';
import 'services/api/api_service.dart';
import 'services/storage/storage_service.dart';
import 'services/theme/theme_manager.dart';
import 'services/backup_service.dart';
import 'services/webdav_service.dart';
import 'providers/aggregate_search_provider.dart';
import 'services/site_config_service.dart';

import 'services/downloader/downloader_config.dart';
import 'services/downloader/downloader_service.dart';
import 'services/downloader/downloader_models.dart';

import 'pages/server_settings_page.dart';
import 'widgets/qb_speed_indicator.dart';
import 'widgets/responsive_layout.dart';
import 'widgets/torrent_download_dialog.dart';
import 'widgets/torrent_list_item.dart';
import 'widgets/tag_filter_bar.dart';
import 'services/update_service.dart';
import 'widgets/update_notification_dialog.dart';
import 'package:pt_mate/utils/notification_helper.dart';

// 全局日志实例，供本文件内多个类使用
final Logger _logger = Logger();

class AppState extends ChangeNotifier {
  SiteConfig? _site;
  SiteConfig? get site => _site;

  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;

  // 配置版本号，用于检测站点配置变化
  int _configVersion = 0;
  int get configVersion => _configVersion;

  Completer<void>? _initCompleter;

  Future<void> loadInitial({bool forceReload = false}) async {
    if (_initCompleter != null && !forceReload) {
      return _initCompleter!.future;
    }

    // 如果是强制重新加载，重置completer
    if (forceReload) {
      _initCompleter = null;
    }

    _initCompleter = Completer<void>();

    // 使用microtask异步执行，避免阻塞UI
    Future.microtask(() => _performInitialLoad(forceReload: forceReload));

    return _initCompleter!.future;
  }

  Future<void> _performInitialLoad({bool forceReload = false}) async {
    try {
      final swTotal = Stopwatch()..start();
      if (kDebugMode) {
        _logger.i('AppState: _performInitialLoad开始，forceReload=$forceReload');
      }

      // 应用启动时首先检查并执行数据迁移
      final swMigrate = Stopwatch()..start();
      try {
        await StorageService.instance.checkAndMigrate();
      } catch (e, s) {
        _logger.e(
          'StorageService.checkAndMigrate failed',
          error: e,
          stackTrace: s,
        );
        rethrow;
      }
      swMigrate.stop();
      if (kDebugMode) {
        _logger.d('AppState: 数据迁移耗时=${swMigrate.elapsedMilliseconds}ms');
      }
      
      // 加载活跃站点配置
      final swLoadSite = Stopwatch()..start();
      try {
        _site = await StorageService.instance.getActiveSiteConfig();
      } catch (e, s) {
        _logger.e(
          'StorageService.getActiveSiteConfig failed',
          error: e,
          stackTrace: s,
        );
        rethrow;
      }
      swLoadSite.stop();
      if (kDebugMode) {
        _logger.d('AppState: 加载活跃站点耗时=${swLoadSite.elapsedMilliseconds}ms, siteId=${_site?.id}');
      }

      // 初始化API服务（适配器）
      final swApi = Stopwatch()..start();
      try {
        await ApiService.instance.init();
      } catch (e, s) {
        _logger.e('ApiService.init failed', error: e, stackTrace: s);
        rethrow;
      }
      swApi.stop();
      if (kDebugMode) {
        _logger.d('AppState: ApiService.init耗时=${swApi.elapsedMilliseconds}ms');
      }

      _isInitialized = true;
      _configVersion++; // 增加配置版本号
      swTotal.stop();
      if (kDebugMode) {
        _logger.i('AppState: _performInitialLoad完成，总耗时=${swTotal.elapsedMilliseconds}ms，配置版本号: $_configVersion, 强制重新加载: $forceReload');
      }
      notifyListeners();

      // 持久化在迁移过程中更新的配置
      try {
        await StorageService.instance.persistPendingConfigUpdates();
      } catch (e, s) {
        _logger.e(
          'StorageService.persistPendingConfigUpdates failed',
          error: e,
          stackTrace: s,
        );
        // Don't rethrow here, as it's not critical
      }
      
      // 应用启动时检查自动同步
      Future.microtask(() => _checkAutoSync());
      
      _initCompleter!.complete();
    } catch (e) {
      _initCompleter!.completeError(e);
      rethrow;
    } finally {
      // 完成后重置completer，允许下次重新加载
      _initCompleter = null;
    }
  }

  Future<void> waitForInitialization() async {
    if (_isInitialized) return;
    if (_initCompleter != null) {
      return _initCompleter!.future;
    }
    // 如果还没开始初始化，等待一下
    await Future.delayed(const Duration(milliseconds: 50));
    if (_initCompleter != null) {
      return _initCompleter!.future;
    }
  }

  Future<void> setSite(SiteConfig site) async {
    await StorageService.instance.saveSite(site);
    _site = site;
    await ApiService.instance.setActiveSite(site);
    notifyListeners();
  }

  Future<void> setActiveSite(String siteId) async {
    await StorageService.instance.setActiveSiteId(siteId);
    _site = await StorageService.instance.getActiveSiteConfig();
    if (_site != null) {
      await ApiService.instance.setActiveSite(_site!);
    }
    notifyListeners();
  }

  /// 检查自动同步
  Future<void> _checkAutoSync() async {
    try {
      final webdavService = WebDAVService.instance;
      final config = await webdavService.loadConfig();
      
      // 检查是否启用了自动同步
      if (config != null && config.autoSync) {
        if (kDebugMode) {
          _logger.i('AppState: 检测到启用自动同步，开始执行自动同步检查');
        }
        
        final backupService = BackupService(StorageService.instance);
        
        // 异步执行自动同步，不阻塞应用启动
         Future.microtask(() async {
           try {
             // 检查是否有远程备份可以下载
             final remoteBackups = await backupService.listWebDAVBackups();
               if (remoteBackups.isNotEmpty) {
                 if (kDebugMode) {
                   _logger.i('AppState: 发现${remoteBackups.length}个远程备份，准备自动同步最新的');
                 }
               
               // 获取最新的备份文件路径
               final latestBackup = remoteBackups.first;
               final backupPath = latestBackup['path'] as String;
               
               // 下载并恢复最新的备份
               final backupData = await backupService.downloadWebDAVBackup(backupPath);
               if (backupData != null) {
                 final result = await backupService.restoreBackup(backupData);
                 if (result.success) {
                   if (kDebugMode) {
                     _logger.i('AppState: 自动同步完成');
                   }
                 } else {
                   if (kDebugMode) {
                     _logger.e('AppState: 自动同步失败: ${result.message}');
                   }
                 }
               }
             } else {
                 if (kDebugMode) {
                   _logger.i('AppState: 未发现远程备份，跳过自动同步');
                 }
               }
             } catch (e) {
               if (kDebugMode) {
                 _logger.e('AppState: 自动同步失败: $e');
               }
             // 自动同步失败不影响应用正常启动
           }
         });
      } else {
        if (kDebugMode) {
          _logger.i('AppState: 自动同步未启用或配置不存在');
        }
      }
    } catch (e) {
      if (kDebugMode) {
        _logger.e('AppState: 检查自动同步配置失败: $e');
      }
      // 配置检查失败不影响应用正常启动
    }
  }
}

class _CategoryFilterDialog extends StatefulWidget {
  final List<SearchCategoryConfig> categories;
  final int selectedCategoryIndex;
  final String keyword;

  const _CategoryFilterDialog({
    required this.categories,
    required this.selectedCategoryIndex,
    required this.keyword,
  });

  @override
  State<_CategoryFilterDialog> createState() => _CategoryFilterDialogState();
}

class _CategoryFilterDialogState extends State<_CategoryFilterDialog> {
  late int _selectedCategoryIndex;
  late TextEditingController _keywordController;

  @override
  void initState() {
    super.initState();
    _selectedCategoryIndex = widget.selectedCategoryIndex;
    _keywordController = TextEditingController(text: widget.keyword);
  }

  @override
  void dispose() {
    _keywordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('分类筛选'),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 搜索框
            Text('搜索关键词', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            TextField(
              controller: _keywordController,
              onTapOutside: (event) => FocusScope.of(context).unfocus(),
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: '输入关键词（可选）',
                isDense: true,
              ),
            ),
            const SizedBox(height: 16),

            // 分类选择
            Text('选择分类', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            if (widget.categories.isEmpty)
              const Text('暂无可用分类', style: TextStyle(color: Colors.grey))
            else
              SizedBox(
                height: 200,
                child: RadioGroup<int>(
                  groupValue: _selectedCategoryIndex,
                  onChanged: (value) {
                    if (value != null) {
                      setState(() {
                        _selectedCategoryIndex = value;
                      });
                    }
                  },
                  child: ListView.builder(
                    itemCount: widget.categories.length,
                    itemBuilder: (context, index) {
                      final category = widget.categories[index];
                      final isSelected = index == _selectedCategoryIndex;
                      return ListTile(
                        title: Text(category.displayName),
                        leading: Radio<int>(value: index),
                        selected: isSelected,
                        selectedTileColor: Theme.of(
                          context,
                        ).colorScheme.primaryContainer.withValues(alpha: 0.3),
                        onTap: () {
                          setState(() {
                            _selectedCategoryIndex = index;
                          });
                        },
                      );
                    },
                  ),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          style: TextButton.styleFrom(
            side: BorderSide(
              color: Theme.of(context).colorScheme.outline,
              width: 1.0,
            ),
          ),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () {
            Navigator.of(context).pop({
              'categoryIndex': _selectedCategoryIndex,
              'keyword': _keywordController.text,
            });
          },
          child: const Text('确定'),
        ),
      ],
    );
  }
}

class _SiteSelectionDialog extends StatefulWidget {
  final List<SiteConfig> sites;
  final String activeSiteId;

  const _SiteSelectionDialog({required this.sites, required this.activeSiteId});

  @override
  State<_SiteSelectionDialog> createState() => _SiteSelectionDialogState();
}

class _SiteSelectionDialogState extends State<_SiteSelectionDialog> {
  late String _selectedSiteId;
  late TextEditingController _searchController;
  late List<SiteConfig> _filteredSites;

  final Map<String, String> _logoPathCache = {};

  Future<String> _resolveLogoPath(SiteConfig site) async {
    final cached = _logoPathCache[site.id];
    if (cached != null && cached.isNotEmpty) return cached;

    String path = 'assets/sites_icon/_default_nexusphp.png';
    try {
      final template = await SiteConfigService.getTemplateById(
        site.templateId,
        site.siteType,
      );
      final logo = template?.logo;
      if (logo != null && logo.isNotEmpty) {
        final lower = logo.toLowerCase();
        path = lower.endsWith('.png')
            ? logo
            : (logo.contains('.')
                  ? '${logo.substring(0, logo.lastIndexOf('.'))}.png'
                  : logo);
      }
    } catch (_) {}

    _logoPathCache[site.id] = path;
    return path;
  }

  @override
  void initState() {
    super.initState();
    _selectedSiteId = widget.activeSiteId;
    _searchController = TextEditingController();
    _filteredSites = widget.sites;
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _filterSites(String keyword) {
    setState(() {
      if (keyword.isEmpty) {
        _filteredSites = widget.sites;
      } else {
        final lowerKeyword = keyword.toLowerCase();
        _filteredSites = widget.sites.where((s) {
          return s.name.toLowerCase().contains(lowerKeyword) ||
              s.baseUrl.toLowerCase().contains(lowerKeyword);
        }).toList();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('切换站点'),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _searchController,
              onTapOutside: (event) => FocusScope.of(context).unfocus(),
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: '搜索站点名称或网址',
                isDense: true,
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: _filterSites,
            ),
            const SizedBox(height: 16),
            if (_filteredSites.isEmpty)
              const Text('未找到匹配的站点', style: TextStyle(color: Colors.grey))
            else
              SizedBox(
                height: 300,
                child: ListView.builder(
                    itemCount: _filteredSites.length,
                    itemBuilder: (context, index) {
                      final site = _filteredSites[index];
                      final isSelected = site.id == _selectedSiteId;
                      final Color? siteColor = site.siteColor != null
                          ? Color(site.siteColor!)
                          : null;

                      Widget buildImage(String path, Color fgColor) {
                        if (path.isEmpty) {
                          return Icon(Icons.dns, size: 24, color: fgColor);
                        }
                        return ClipOval(
                          child: Image.asset(
                            path,
                            width: 24,
                            height: 24,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) {
                              return Image.asset(
                                'assets/sites_icon/_default_nexusphp.png',
                                width: 24,
                                height: 24,
                                fit: BoxFit.cover,
                              );
                            },
                          ),
                        );
                      }

                      return ListTile(
                        leading: CircleAvatar(
                          radius: 18,
                          backgroundColor: isSelected
                              ? Theme.of(context).colorScheme.primary
                              : siteColor?.withValues(alpha: 0.2) ??
                                    Theme.of(
                                      context,
                                    ).colorScheme.surfaceContainerHighest,
                          child: Builder(
                            builder: (context) {
                              final fgColor = isSelected
                                  ? Theme.of(context).colorScheme.onPrimary
                                  : siteColor ??
                                        Theme.of(
                                          context,
                                        ).colorScheme.onSurfaceVariant;

                              final cached = _logoPathCache[site.id];
                              if (cached != null) {
                                return buildImage(cached, fgColor);
                              }

                              return FutureBuilder<String>(
                                future: _resolveLogoPath(site),
                                builder: (context, snapshot) {
                                  if (snapshot.connectionState !=
                                          ConnectionState.done ||
                                      (snapshot.data == null ||
                                          snapshot.data!.isEmpty)) {
                                    return Icon(
                                      Icons.dns,
                                      size: 24,
                                      color: fgColor,
                                    );
                                  }
                                  return buildImage(snapshot.data!, fgColor);
                                },
                              );
                            },
                          ),
                      ),
                        title: Text(site.name),
                        subtitle: Text(
                          site.baseUrl,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        selected: isSelected,
                        selectedTileColor: Theme.of(
                          context,
                        ).colorScheme.primaryContainer.withValues(alpha: 0.3),
                        onTap: () {
                          Navigator.of(context).pop(site.id);
                        },
                      );
                    },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class MTeamApp extends StatefulWidget {
  const MTeamApp({super.key});

  @override
  State<MTeamApp> createState() => _MTeamAppState();
}

class _MTeamAppState extends State<MTeamApp> {
  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AppState()..loadInitial()),
        ChangeNotifierProvider(
          create: (_) =>
              ThemeManager(StorageService.instance)..initializeDynamicColor(),
        ),
        ChangeNotifierProvider(create: (_) => AggregateSearchProvider()),
        Provider<StorageService>(create: (_) => StorageService.instance),
      ],
      child: Consumer2<ThemeManager, AppState>(
        builder: (context, themeManager, appState, child) {
          return MaterialApp(
            debugShowCheckedModeBanner: false,
            title: 'PT Mate',
            theme: themeManager.lightTheme,
            darkTheme: themeManager.darkTheme,
            themeMode: themeManager.flutterThemeMode,
            // 添加本地化配置
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: const [
              Locale('zh', 'CN'), // 中文简体
              Locale('en', 'US'), // 英文
            ],
            locale: const Locale('zh', 'CN'), // 默认使用中文简体
            home: !appState.isInitialized
                ? const Scaffold(
                    body: Center(
                      child: CircularProgressIndicator(),
                    ),
                  )
                : appState.site == null
                    ? const ServerSettingsPage()
                    : const HomePage(),
          );
        },
      ),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _keywordCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();
  final FocusNode _searchFocusNode = FocusNode();

  int _selectedCategoryIndex = 0;
  List<SearchCategoryConfig> _categories = [];
  bool _loading = false;
  String? _error;
  DateTime? _lastPressedAt;

  // 用户信息与搜索结果分页状态
  // 下载器配置
  List<DownloaderConfig> _downloaderConfigs = [];
  final List<TorrentItem> _items = [];
  int _pageNumber = 1;
  final int _pageSize = 30;
  
  // 标签筛选状态
  final Set<TagType> _includedTags = {};
  final Set<TagType> _excludedTags = {};

  // 获取经过筛选的列表
  List<TorrentItem> get _filteredItems {
    if (_includedTags.isEmpty && _excludedTags.isEmpty) {
      return _items;
    }
    return _items.where((item) {
      // 包含筛选：必须包含所有选中的标签
      for (final tag in _includedTags) {
        if (!item.tags.contains(tag)) return false;
      }
      // 排除筛选：不能包含任何选中的标签
      for (final tag in _excludedTags) {
        if (item.tags.contains(tag)) return false;
      }
      return true;
    }).toList();
  }

  int _totalPages = 1;
  bool _hasMore = true;

  // 排序相关状态
  String _sortBy = 'none'; // none, size, upload, download
  bool _sortAscending = false;

  // 收藏筛选状态
  bool _onlyFavorites = false;

  // 选中状态管理
  bool _isSelectionMode = false;
  final Set<String> _selectedItems = <String>{};

  // 拖动与多选增强功能
  bool _isDraggingSelection = false;
  int? _dragStartIndex;
  int? _lastSelectedIndex;
  Set<String> _preDragSelectedItems = <String>{};
  final GlobalKey _listKey = GlobalKey();

  // 收藏请求间隔控制
  DateTime? _lastCollectionRequest;
  final Map<String, bool> _pendingCollectionRequests = <String, bool>{};

  // 下载请求状态管理
  final Set<String> _pendingDownloadRequests = <String>{};

  // 当前站点配置
  SiteConfig? _currentSite;
  
  // 配置版本号跟踪
  int _lastConfigVersion = -1;
  
  // 防止重复处理重新初始化的标志
  bool _isProcessingReload = false;
  
  // didChangeDependencies中一次性预同步标志，避免首次构建时出现null/-1
  bool _didSyncFromAppState = false; // 首帧前从AppState预同步，避免首次渲染null/-1
  bool _didInitialLoad = false; // 首次进入页面后的初始化是否已完成
  
  // 统一头部（用户信息 + 搜索栏）滚动进度控制
  double _headerProgress = 1.0; // 0.0=隐藏, 1.0=完全显示
  double _lastScrollOffset = 0.0; // 上次滚动位置
  static const double _maxHideDistance = 200.0; // 累计滚动200px完全隐藏/显示
  
  // 封面图片显示设置（用户偏好）
  bool _showCoverSetting = true; // 默认自动显示
  
  // 切换站点 FAB 按钮的显示状态（向上滑动隐藏，向下滑动显示）
  bool _fabVisible = true;
  
  @override
  void initState() {
    super.initState();
    _scrollCtrl.addListener(_onScroll);
    // 首次加载改为在 didChangeDependencies 完成预同步后触发，避免在AppState尚未就绪时执行
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_didSyncFromAppState) {
      final appState = Provider.of<AppState>(context, listen: false);
      if (appState.site != null) {
        _currentSite = appState.site;
        _lastConfigVersion = appState.configVersion;
        if (kDebugMode) {
          _logger.d('HomePage: didChangeDependencies预同步 - 站点: ${_currentSite?.id}, 版本: $_lastConfigVersion');
        }
      }
      _didSyncFromAppState = true;

      // 预同步完成后触发一次初始化（仅一次）
      if (!_didInitialLoad) {
        _isProcessingReload = true;
        final capturedSite = _currentSite; // 捕获当前站点，避免后续变化导致条件抖动
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          if (!_didInitialLoad && capturedSite != null) {
            await _init();
            _didInitialLoad = true;
            _isProcessingReload = false;
          } else {
            // 即使未触发初始化，也要释放标志位
            _isProcessingReload = false;
          }
        });
      }
    }
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    _keywordCtrl.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    setState(() => _loading = true);
    try {
      // 等待AppState初始化完成
      final appState = Provider.of<AppState>(context, listen: false);

      // 等待AppState完全初始化完成
      await appState.waitForInitialization();

      // 如果没有站点配置，说明确实没有配置
      if (appState.site == null) {
        if (mounted) {
          setState(() {
            _currentSite = null;
            _categories = SearchCategoryConfig.getDefaultConfigs();
            _selectedCategoryIndex = -1;
            _loading = false;
          });
        }
        return;
      }

      final activeSite = appState.site!;
      final categories = activeSite.searchCategories.isNotEmpty
          ? activeSite.searchCategories
          : SearchCategoryConfig.getDefaultConfigs();
      if (mounted) {
        setState(() {
          _currentSite = activeSite;
          _categories = categories;
          _selectedCategoryIndex = categories.isNotEmpty ? 0 : -1;
        });
      }

      // 加载下载器配置
      final downloaderConfigsData = await StorageService.instance.loadDownloaderConfigs();
      final downloaderConfigs = downloaderConfigsData.map((data) => DownloaderConfig.fromJson(data)).toList();
      if (mounted) setState(() => _downloaderConfigs = downloaderConfigs);

      // 加载封面图片显示设置
      final showCoverSetting = await StorageService.instance
          .loadShowCoverImages();
      if (mounted) setState(() => _showCoverSetting = showCoverSetting);

      // 拉取用户基础信息
      await ApiService.instance.fetchMemberProfile();
      if (mounted) setState(() {});
    } catch (e) {
      if (e.toString().contains('CookieExpiredException')) {
        _showCookieExpiredDialog();
      } else {
        // 用户信息失败不阻塞首页使用，仅提示
        if (mounted) setState(() => _error = _error ?? e.toString());
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
    
    // 检查应用更新（异步执行，不阻塞界面）
    _checkForUpdates();
    
    // 仅在站点支持种子搜索功能时执行默认搜索
    if (_currentSite?.features.supportTorrentSearch ?? true) {
      await _search(reset: true);
    }
  }

  Future<void> _reloadCategories() async {
    try {
      // 从AppState获取最新的站点配置
      final appState = Provider.of<AppState>(context, listen: false);
      final activeSite = appState.site;
      final categories = activeSite?.searchCategories.isNotEmpty == true
          ? activeSite!.searchCategories
          : SearchCategoryConfig.getDefaultConfigs();
      
      if (kDebugMode) {
        _logger.d('HomePage: _reloadCategories - 重新加载分类，分类数量: ${categories.length}');
      }
      
      if (mounted) {
        setState(() {
          _categories = categories;
          // 如果当前选中的分类索引超出范围，重置为第一个分类
          if (categories.isNotEmpty &&
              (_selectedCategoryIndex < 0 ||
                  _selectedCategoryIndex >= categories.length)) {
            _selectedCategoryIndex = 0;
          } else if (categories.isEmpty) {
            _selectedCategoryIndex = -1;
          }
        });
      }
    } catch (e) {
      // 分类加载失败时显示错误信息
      if (mounted) {
        NotificationHelper.showError(context, '重新加载分类失败: $e');
      }
    }
  }

  /// 检查应用更新
  Future<void> _checkForUpdates() async {
    try {
      final updateResult = await UpdateService.instance.checkForUpdates();
      
      if (updateResult != null && updateResult.hasUpdate && mounted) {
        // 延迟显示更新对话框，避免与其他初始化对话框冲突
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) {
            UpdateNotificationDialog.show(context, updateResult);
          }
        });
      }
    } catch (e) {
      // 更新检查失败时静默处理，不影响用户体验
      if (kDebugMode) {
        _logger.e('Update check failed: $e');
      }
    }
  }

  void _showCookieExpiredDialog() {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('登录已过期'),
        content: const Text('您的登录状态已过期，请重新设置Cookie以继续使用。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            style: TextButton.styleFrom(
              side: BorderSide(
                color: Theme.of(context).colorScheme.outline,
                width: 1.0,
              ),
            ),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => const ServerSettingsPage(),
                ),
              );
            },
            child: const Text('去设置'),
          ),
        ],
      ),
    );
  }

  void _onScroll() {
    // 滑动时收起键盘（滑动不触发 onTapOutside）
    if (_searchFocusNode.hasFocus) {
      _searchFocusNode.unfocus();
    }
    final currentOffset = _scrollCtrl.position.pixels;
    final delta = currentOffset - _lastScrollOffset;

    // 基于滚动距离的连续进度控制：向下滚动逐步隐藏，向上滚动逐步显示
    double newProgress = _headerProgress;
    if (delta > 0) {
      // 向下滚动（内容上移）：减少头部显示进度，隐藏 FAB
      newProgress = (newProgress - delta / _maxHideDistance).clamp(0.0, 1.0);
      if (_fabVisible) {
        setState(() {
          _headerProgress = newProgress;
          _fabVisible = false;
        });
      } else if (newProgress != _headerProgress) {
        setState(() {
          _headerProgress = newProgress;
        });
      }
    } else if (delta < 0) {
      // 向上滚动（内容下移）：增加头部显示进度，显示 FAB
      newProgress = (newProgress + (-delta) / _maxHideDistance).clamp(0.0, 1.0);
      if (!_fabVisible) {
        setState(() {
          _headerProgress = newProgress;
          _fabVisible = true;
        });
      } else if (newProgress != _headerProgress) {
        setState(() {
          _headerProgress = newProgress;
        });
      }
    }
    _lastScrollOffset = currentOffset;

    // 原有的分页加载逻辑
    if (!_hasMore || _loading) return;
    // 使用筛选后的列表长度来判断是否触底加载可能不太准确，但通常加载更多是基于原始列表
    // 这里保持原逻辑，只要滚动到底部就加载更多
    if (currentOffset >= _scrollCtrl.position.maxScrollExtent - 200) {
      _loadMore();
    }
  }

  /// 统一头部组件（搜索栏 + 标签筛选）
  Widget _buildHeaderPanel(BuildContext context, AppState appState) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 搜索栏与筛选、排序行
        Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              Row(
                children: [
                  // 分类按钮 - 仅在站点支持分类搜索功能时显示
                  if (_currentSite?.features.supportCategories ?? true)
                    IconButton(
                      onPressed: () {
                        _showCategoryFilterDialog();
                      },
                      icon: const Icon(Icons.category, size: 20),
                      style: IconButton.styleFrom(
                        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                        foregroundColor: Theme.of(context).colorScheme.onPrimaryContainer,
                        elevation: 2,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.all(8),
                      ),
                      tooltip: _categories.isNotEmpty &&
                              _selectedCategoryIndex >= 0 &&
                              _selectedCategoryIndex < _categories.length
                          ? _categories[_selectedCategoryIndex].displayName
                          : '分类筛选',
                    ),
                  if (_currentSite?.features.supportCategories ?? true)
                    const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _keywordCtrl,
                      focusNode: _searchFocusNode,
                      onTapOutside: (event) => FocusScope.of(context).unfocus(),
                      textInputAction: TextInputAction.search,
                      enabled: _currentSite?.features.supportTorrentSearch ?? true,
                      decoration: InputDecoration(
                        hintText: (_currentSite?.features.supportTorrentSearch ?? true)
                            ? '输入关键词（可选）'
                            : '当前站点不支持搜索功能',
                        border: OutlineInputBorder(
                          borderRadius: const BorderRadius.all(Radius.circular(25)),
                          borderSide: BorderSide(
                            color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3),
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: const BorderRadius.all(Radius.circular(25)),
                          borderSide: BorderSide(
                            color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3),
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: const BorderRadius.all(Radius.circular(25)),
                          borderSide: BorderSide(
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      ),
                      onSubmitted: (_) {
                        if (_currentSite?.features.supportTorrentSearch ?? true) {
                          _search(reset: true);
                        } else {
                          NotificationHelper.showError(context, '当前站点不支持搜索功能');
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (_currentSite?.features.supportCollection == true)
                    IconButton(
                      onPressed: () {
                        if (mounted) {
                          setState(() {
                            _onlyFavorites = !_onlyFavorites;
                          });
                        }
                        if (_currentSite?.features.supportTorrentSearch ?? true) {
                          _search(reset: true);
                        } else {
                          NotificationHelper.showError(context, '当前站点不支持搜索功能');
                        }
                      },
                      icon: Icon(
                        _onlyFavorites ? Icons.favorite : Icons.favorite_border,
                        color: _onlyFavorites ? Theme.of(context).colorScheme.secondary : null,
                      ),
                      tooltip: _onlyFavorites ? '显示全部' : '仅显示收藏',
                    ),
                  const SizedBox(width: 8),
                  PopupMenuButton<String>(
                    onSelected: _onSortSelected,
                    icon: Icon(
                      _sortBy == 'none' ? Icons.sort : Icons.sort,
                      color: _sortBy == 'none' ? null : Theme.of(context).colorScheme.secondary,
                    ),
                    tooltip: '排序',
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        value: 'none',
                        child: Container(
                          decoration: BoxDecoration(
                            color: _sortBy == 'none'
                                ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.1)
                                : null,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          child: Row(
                            children: [
                              Icon(
                                Icons.clear,
                                color: _sortBy == 'none' ? Theme.of(context).colorScheme.secondary : null,
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
                            color: _sortBy == 'size'
                                ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.1)
                                : null,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          child: Row(
                            children: [
                              Icon(
                                _sortBy == 'size' && _sortAscending ? Icons.arrow_upward : Icons.arrow_downward,
                                color: _sortBy == 'size' ? Theme.of(context).colorScheme.secondary : null,
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
                            color: _sortBy == 'upload'
                                ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.1)
                                : null,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          child: Row(
                            children: [
                              Icon(
                                _sortBy == 'upload' && _sortAscending ? Icons.arrow_upward : Icons.arrow_downward,
                                color: _sortBy == 'upload' ? Theme.of(context).colorScheme.secondary : null,
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
                            color: _sortBy == 'download'
                                ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.1)
                                : null,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          child: Row(
                            children: [
                              Icon(
                                _sortBy == 'download' && _sortAscending ? Icons.arrow_upward : Icons.arrow_downward,
                                color: _sortBy == 'download' ? Theme.of(context).colorScheme.secondary : null,
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
            ],
          ),
        ),
        TagFilterBar(
          includedTags: _includedTags,
          excludedTags: _excludedTags,
          onIncludedChanged: (tags) {
            setState(() {
              _includedTags.clear();
              _includedTags.addAll(tags);
            });
          },
          onExcludedChanged: (tags) {
            setState(() {
              _excludedTags.clear();
              _excludedTags.addAll(tags);
            });
          },
        ),
      ],
    );
  }

  Future<void> _loadMore() async {
    if (_loading || !_hasMore) return;
    _pageNumber += 1;
    await _search();
  }

  Future<void> _search({bool reset = false}) async {
    if (reset) {
      _pageNumber = 1;
      _items.clear();
      _hasMore = true;
      _totalPages = 1;
      // 重置排序状态
      _sortBy = 'none';
      _sortAscending = false;
      // 重置标签筛选
      // _includedTags.clear(); // 标签筛选由用户手动控制，不随搜索重置
      // _excludedTags.clear();
    }
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      // 获取当前分类的额外参数 - 仅在站点支持高级搜索功能时使用
      Map<String, dynamic>? additionalParams;
      if ((_currentSite?.features.supportAdvancedSearch ?? true) &&
          _categories.isNotEmpty &&
          _selectedCategoryIndex >= 0 &&
          _selectedCategoryIndex < _categories.length) {
        final currentCategory = _categories[_selectedCategoryIndex];
        if (currentCategory.parameters.isNotEmpty) {
          additionalParams = currentCategory.parseParameters();
        }
      }

      final res = await ApiService.instance.searchTorrents(
        keyword: _keywordCtrl.text.trim().isEmpty
            ? null
            : _keywordCtrl.text.trim(),
        pageNumber: _pageNumber,
        pageSize: _pageSize,
        onlyFav: _onlyFavorites ? 1 : null,
        additionalParams: additionalParams,
      );
      if (mounted) {
        setState(() {
          // 如果是重置搜索或第一页，清空现有数据
          if (reset || _pageNumber == 1) {
            _items.clear();
          }
          // 去重处理：过滤掉已存在的项目ID
          final existingIds = _items.map((item) => item.id).toSet();
          final newItems = res.items
              .where((item) => !existingIds.contains(item.id))
              .toList();
          _items.addAll(newItems);
          _totalPages = res.totalPages;
          _hasMore = _pageNumber < _totalPages;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }



  void _onSortSelected(String sortType) {
    if (mounted) {
      setState(() {
        if (_sortBy == sortType) {
          // 如果选择相同的排序类型，切换升序/降序
          _sortAscending = !_sortAscending;
        } else {
          // 选择新的排序类型，默认降序
          _sortBy = sortType;
          _sortAscending = false;
        }
      });
    }
    _sortItems();
  }

  void _sortItems() {
    if (_sortBy == 'none') {
      return; // 不排序，保持原始顺序
    }

    _items.sort((a, b) {
      int comparison = 0;

      switch (_sortBy) {
        case 'size':
          comparison = a.sizeBytes.compareTo(b.sizeBytes);
          break;
        case 'upload':
          comparison = a.seeders.compareTo(b.seeders);
          break;
        case 'download':
          comparison = a.leechers.compareTo(b.leechers);
          break;
      }

      return _sortAscending ? comparison : -comparison;
    });

    if (mounted) setState(() {}); // 触发重建以显示排序结果
  }

  void _onTorrentTap(TorrentItem item) async {
    // 检查站点是否支持种子详情功能
    if (_currentSite?.features.supportTorrentDetail == false) {
      NotificationHelper.showError(context, '当前站点不支持种子详情功能');
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => TorrentDetailPage(
          torrentItem: item,
          siteFeatures: _currentSite?.features ?? SiteFeatures.mteamDefault,
          downloaderConfigs: _downloaderConfigs,
          siteConfig: _currentSite,
        ),
      ),
    );
    
    // 从详情页返回后，刷新列表页状态以确保收藏状态同步
    if (mounted) {
      setState(() {});
      // 路由 pop 后 Flutter 焦点恢复机制会在下一帧重新聚焦 TextField，
      // 必须在 postFrameCallback 中再次取消焦点才能真正阻止键盘弹出
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _searchFocusNode.unfocus();
      });
    }
  }

  Future<void> _onDownload(TorrentItem item) async {
    try {
      // 1. 获取下载 URL
      final url = await ApiService.instance.genDlToken(
        id: item.id,
        url: item.downloadUrl,
      );

      // 2. 弹出对话框让用户选择下载器设置
      if (!mounted) return;
      final result = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (_) =>
            TorrentDownloadDialog(torrentName: item.name, downloadUrl: url),
      );

      if (result == null) return; // 用户取消了

      // 3. 从对话框结果中获取设置
      final clientConfig = result['clientConfig'] as DownloaderConfig;
      final password = result['password'] as String;
      final category = result['category'] as String?;
      final tags = result['tags'] as List<String>?;
      final savePath = result['savePath'] as String?;
      final autoTMM = result['autoTMM'] as bool?;
      final startPaused = result['startPaused'] as bool?;

      // 4. 发送到下载器
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
        siteConfig: _currentSite,
      );

      if (mounted) {
        NotificationHelper.showInfo(
          context,
          '已成功发送"${item.name}"到 ${clientConfig.name}',
        );
      }
    } catch (e) {
      if (mounted) {
        NotificationHelper.showError(context, '下载失败：$e');
      }
    }
  }

  Future<void> _onToggleCollection(TorrentItem item) async {
    final newCollectionState = !item.collection;

    // 立即更新UI状态 - 直接修改现有对象
    if (mounted) {
      setState(() {
        item.collection = newCollectionState;
      });
    }

    // 不显示开始通知，直接进行后台处理

    // 异步后台请求
    _performCollectionRequest(item, newCollectionState);
  }

  Future<void> _showCategoryFilterDialog() async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => _CategoryFilterDialog(
        categories: _categories,
        selectedCategoryIndex: _selectedCategoryIndex,
        keyword: _keywordCtrl.text,
      ),
    );

    if (result != null) {
      final newCategoryIndex = result['categoryIndex'] as int?;
      final newKeyword = result['keyword'] as String?;

      if (mounted) {
        setState(() {
          if (newCategoryIndex != null &&
              newCategoryIndex >= 0 &&
              newCategoryIndex < _categories.length) {
            _selectedCategoryIndex = newCategoryIndex;
          }
          if (newKeyword != null) {
            _keywordCtrl.text = newKeyword;
          }
        });
      }

      if (_currentSite?.features.supportTorrentSearch ?? true) {
        _search(reset: true);
      } else {
        if (mounted) {
          NotificationHelper.showError(context, '当前站点不支持搜索功能');
        }
      }
    }
  }

  Future<void> _performCollectionRequest(
    TorrentItem item,
    bool newCollectionState,
  ) async {
    // 检查请求间隔
    final now = DateTime.now();
    if (_lastCollectionRequest != null) {
      final timeDiff = now.difference(_lastCollectionRequest!);
      if (timeDiff.inMilliseconds < 1000) {
        await Future.delayed(
          Duration(milliseconds: 1000 - timeDiff.inMilliseconds),
        );
      }
    }
    _lastCollectionRequest = DateTime.now();

    // 标记为处理中
    _pendingCollectionRequests[item.id] = newCollectionState;

    try {
      await ApiService.instance.toggleCollection(
        id: item.id,
        make: newCollectionState,
      );

      // 请求成功，移除处理标记
      _pendingCollectionRequests.remove(item.id);
      // 不显示成功通知
    } catch (e) {
      // 请求失败，恢复原状态
      _pendingCollectionRequests.remove(item.id);

      if (mounted) {
        setState(() {
          item.collection = !newCollectionState; // 恢复原状态
        });
      }

      if (mounted) {
        NotificationHelper.showError(
          context,
          '收藏操作失败：$e',
          duration: const Duration(seconds: 2),
        );
      }
    }
  }

  Future<void> _showSiteSelectionDialog() async {

    final sitesData = await StorageService.instance.loadSiteConfigs(
      includeApiKeys: false,
    );
    if (!mounted) return;

    final appState = context.read<AppState>();
    final activeSiteId = appState.site?.id ?? '';

    final selectedSiteId = await showDialog<String>(
      context: context,
      builder: (context) =>
          _SiteSelectionDialog(sites: sitesData, activeSiteId: activeSiteId),
    );

    if (selectedSiteId != null && selectedSiteId != activeSiteId && mounted) {
      await _setActiveSite(selectedSiteId);
    }
  }

  Future<void> _setActiveSite(String siteId) async {
    if (!mounted) return;
    final appState = context.read<AppState>();

    try {
      await appState.setActiveSite(siteId);
      if (mounted) {
        setState(() {
          _currentSite = appState.site;
          _headerProgress = 1.0;
          _fabVisible = true;
        });
        await _init(); // 加载新站点的数据
        if (mounted) {
          NotificationHelper.showInfo(context, '已切换活跃站点');
        }
      }
    } catch (e) {
      if (mounted) {
        NotificationHelper.showError(context, '切换站点失败: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, appState, child) {
        // 当AppState变化时，检查是否需要重新初始化
        if (!_isProcessingReload) {
          bool needsReload = false;
          String reloadReason = '';
          
          if (kDebugMode) {
            _logger.d('HomePage Consumer: 当前站点=${_currentSite?.id}, AppState站点=${appState.site?.id}, 配置版本=${appState.configVersion}, 上次版本=$_lastConfigVersion');
          }
          
          if (appState.site != null) {
            final isFirstSync = (_currentSite == null && _lastConfigVersion == -1);
            // 首次同步：仅同步站点与版本，不触发重新加载
            if (isFirstSync) {
              if (kDebugMode) {
                _logger.d('HomePage: 首次同步（不重载） - 同步站点: ${appState.site!.id}, 版本: ${appState.configVersion}');
              }
              final currentSite = appState.site;
              final currentConfigVersion = appState.configVersion;
              WidgetsBinding.instance.addPostFrameCallback((_) async {
                // 先同步站点与版本
                _currentSite = currentSite;
                _lastConfigVersion = currentConfigVersion;
                // 若尚未进行过首次初始化，则触发一次初始化
                if (!_didInitialLoad && !_isProcessingReload && _currentSite != null) {
                  _isProcessingReload = true;
                  await _init();
                  _didInitialLoad = true;
                  _isProcessingReload = false;
                }
              });
            }
            // 站点变化（排除首次同步情形）
            else if (_currentSite != null && _currentSite!.id != appState.site!.id) {
              needsReload = true;
              reloadReason = '站点变化';
              if (kDebugMode) {
                _logger.i('HomePage: 站点变化检测 - 当前站点: ${_currentSite?.id}, 新站点: ${appState.site!.id}');
              }
            }
            // 配置版本变化（排除首次同步情形）
            else if (_lastConfigVersion != -1 && _lastConfigVersion != appState.configVersion) {
              needsReload = true;
              reloadReason = '配置更新';
              if (kDebugMode) {
                _logger.i('HomePage: 配置更新检测 - 上次版本: $_lastConfigVersion, 当前版本: ${appState.configVersion}');
              }
            }
          }
          
          if (needsReload) {
            if (kDebugMode) {
              _logger.i('HomePage: 检测到$reloadReason，重新初始化 - 配置版本: ${appState.configVersion}, 上次版本: $_lastConfigVersion');
            }
            // 设置标志，防止重复处理
            _isProcessingReload = true;
            // 捕获当前值，避免异步执行时值发生变化
            final currentSite = appState.site;
            final currentConfigVersion = appState.configVersion;
            WidgetsBinding.instance.addPostFrameCallback((_) async {
              // 在PostFrameCallback中更新状态，避免在builder中触发重建
              _currentSite = currentSite;
              _lastConfigVersion = currentConfigVersion;
              await _init();
              // 重新初始化完成后重置标志
              _isProcessingReload = false;
            });
          }
        }

        return PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, result) async {
            if (didPop) return;

            // 如果处于选中模式，先退出选中模式
            if (_isSelectionMode) {
              _onCancelSelection();
              return;
            }

            final now = DateTime.now();
            if (_lastPressedAt == null ||
                now.difference(_lastPressedAt!) > const Duration(seconds: 3)) {
              _lastPressedAt = now;

              // 先清除之前的 SnackBar
              ScaffoldMessenger.of(context).clearSnackBars();
              
              // 显示提示信息
              NotificationHelper.showInfo(
                context,
                '再按一次返回键退出应用',
                duration: const Duration(seconds: 3),
              );
              return;
            }

            // 第二次按返回键，退出应用
            SystemNavigator.pop();
          },
          child: ResponsiveLayout(
            currentRoute: '/',
            onSettingsChanged: _reloadCategories,
            appBar: AppBar(
            title: GestureDetector(
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => const ServerSettingsPage(),
                  ),
                );
              },
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(text: appState.site?.name ?? 'PT Mate'),
                    TextSpan(
                      text: ' - PT Mate',
                      style: const TextStyle(fontSize: 14),
                    ),
                  ],
                ),
              ),
            ),
            actions: const [QbSpeedIndicator()],
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
          ),
          body: Column(
            children: [
              // 统一头部（用户信息 + 搜索栏），使用进度控制：向下滚动逐步隐藏，向上滚动逐步显示
              ClipRect(
                child: Align(
                  alignment: Alignment.bottomCenter,
                  heightFactor: _headerProgress,
                  child: Opacity(
                    opacity: _headerProgress,
                    child: _buildHeaderPanel(context, appState),
                  ),
                ),
              ),
              if (_loading) const LinearProgressIndicator(),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    _error!,
                    style: const TextStyle(color: Colors.red),
                  ),
                ),
              Expanded(
                child: _currentSite == null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32.0),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.settings_outlined,
                                size: 64,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                              const SizedBox(height: 24),
                              Text(
                                '尚未配置站点信息',
                                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                                  color: Theme.of(context).colorScheme.onSurface,
                                ),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                '请先配置站点信息以开始使用应用',
                                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                                ),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 32),
                              FilledButton.icon(
                                onPressed: () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (context) => const ServerSettingsPage(),
                                    ),
                                  );
                                },
                                icon: const Icon(Icons.add),
                                label: const Text('配置站点'),
                              ),
                            ],
                          ),
                        ),
                      )
                      : Builder(
                          builder: (context) {
                            final filteredItems = _filteredItems;
                            if (filteredItems.isEmpty) {
                              // 空状态也支持下拉刷新
                              return RefreshIndicator(
                                onRefresh: () => _search(reset: true),
                                child: ListView(
                                  physics:
                                      const AlwaysScrollableScrollPhysics(),
                                  keyboardDismissBehavior:
                                      ScrollViewKeyboardDismissBehavior.onDrag,
                                  children: [
                                    SizedBox(
                                      height:
                                          MediaQuery.of(context).size.height *
                                          0.5,
                                      child: Center(
                                        child: Column(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            Icon(
                                              Icons.search_off,
                                              size: 64,
                                              color: Theme.of(
                                                context,
                                              ).colorScheme.outline,
                                            ),
                                            const SizedBox(height: 16),
                                            Text(
                                              _items.isEmpty
                                                  ? '未找到相关种子'
                                                  : '没有符合筛选条件的种子',
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .titleMedium
                                                  ?.copyWith(
                                                    color: Theme.of(
                                                      context,
                                                    ).colorScheme.outline,
                                                  ),
                                            ),
                                            const SizedBox(height: 8),
                                            Text(
                                              '下拉刷新',
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .bodySmall
                                                  ?.copyWith(
                                                    color: Theme.of(
                                                      context,
                                                    ).colorScheme.outline,
                                                  ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }
                            return RefreshIndicator(
                              onRefresh: () => _search(reset: true),
                              child: Listener(
                                onPointerMove: _onPointerMove,
                                onPointerUp: _onPointerUp,
                                child: ListView.builder(
                                  key: _listKey,
                                  controller: _scrollCtrl,
                                  physics:
                                      const AlwaysScrollableScrollPhysics(),
                                  keyboardDismissBehavior:
                                      ScrollViewKeyboardDismissBehavior.onDrag,
                                  padding: const EdgeInsets.fromLTRB(
                                    0,
                                    0,
                                    0,
                                    16,
                                  ),
                                  itemCount:
                                      filteredItems.length + (_hasMore ? 1 : 0),
                                  itemBuilder: (context, index) {
                                    if (index == filteredItems.length) {
                                      return const Padding(
                                        padding: EdgeInsets.all(16.0),
                                        child: Center(
                                          child: SizedBox(
                                            width: 24,
                                            height: 24,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                            ),
                                          ),
                                        ),
                                      );
                                    }
                                    final item = filteredItems[index];
                                    final isSelected = _selectedItems.contains(
                                      item.id,
                                    );
                                    return MetaData(
                                      metaData: index,
                                      behavior: HitTestBehavior.translucent,
                                      child: TorrentListItem(
                                        torrent: item,
                                        isSelected: isSelected,
                                        isSelectionMode: _isSelectionMode,
                                        currentSite: _currentSite,
                                        showCoverSetting: _showCoverSetting,
                                        onTap: () => _isSelectionMode
                                            ? _onToggleSelection(item, index)
                                            : _onTorrentTap(item),
                                        onLongPress: () =>
                                            _onLongPress(item, index),
                                        onToggleCollection: () =>
                                            _onToggleCollection(item),
                                        onDownload: () => _onDownload(item),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            );
                          },
                        ),
              ),
              // 选中模式下的操作栏
              if (_isSelectionMode)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    border: Border(
                      top: BorderSide(
                        color: Theme.of(context).dividerColor,
                        width: 1,
                      ),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      Expanded(
                          child: TextButton(
                          onPressed: _onCancelSelection,
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 0,
                              ),
                              textStyle: const TextStyle(fontSize: 13),
                              side: BorderSide(
                                color: Theme.of(context).colorScheme.outline,
                                width: 1.0,
                              ),
                          ),
                          child: const Text('取消'),
                        ),
                      ),
                        const SizedBox(width: 8),
                        // 全选按钮
                        Expanded(
                          child: TextButton(
                            onPressed: () {
                              if (_selectedItems.length ==
                                  _filteredItems.length) {
                                setState(() => _selectedItems.clear());
                              } else {
                                setState(() {
                                  _selectedItems.addAll(
                                    _filteredItems.map((e) => e.id),
                                  );
                                });
                              }
                            },
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 0,
                              ),
                              textStyle: const TextStyle(fontSize: 13),
                              side: BorderSide(
                                color: Theme.of(context).colorScheme.outline,
                                width: 1.0,
                              ),
                            ),
                            child: Text(
                              _selectedItems.length == _filteredItems.length
                                  ? '全不选'
                                  : '全选',
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                      // 批量收藏按钮 - 仅在站点支持收藏功能时显示
                      if (_currentSite?.features.supportCollection ?? true) ...[
                        Expanded(
                          child: ElevatedButton(
                            onPressed: _selectedItems.isNotEmpty
                                ? _onBatchFavorite
                                : null,
                            style: ElevatedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 0,
                                ),
                                textStyle: const TextStyle(fontSize: 13),
                              backgroundColor: Colors.red,
                              foregroundColor: Colors.white,
                            ),
                            child: Text('收藏 (${_selectedItems.length})'),
                          ),
                        ),
                        const SizedBox(width: 12),
                      ],
                      // 批量下载按钮 - 仅在站点支持下载功能时显示
                      if (_currentSite?.features.supportDownload ?? true)
                        Expanded(
                          child: ElevatedButton(
                            onPressed: _selectedItems.isNotEmpty
                                ? _onBatchDownload
                                : null,
                            style: ElevatedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 0,
                                ),
                                textStyle: const TextStyle(fontSize: 13),
                              backgroundColor: Theme.of(
                                context,
                              ).colorScheme.primary,
                              foregroundColor: Theme.of(
                                context,
                              ).colorScheme.onPrimary,
                            ),
                            child: Text('下载 (${_selectedItems.length})'),
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ),
            floatingActionButton: !_isSelectionMode
                ? AnimatedSlide(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeInOut,
                    offset: _fabVisible ? Offset.zero : const Offset(0, 2),
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeInOut,
                      opacity: _fabVisible ? 1.0 : 0.0,
                      child: FloatingActionButton.extended(
                        onPressed: _fabVisible
                            ? _showSiteSelectionDialog
                            : null,
                        icon: const Icon(Icons.swap_horiz),
                        label: const Text('切换站点'),
                      ),
                    ),
                  )
                : null,
            floatingActionButtonLocation:
                FloatingActionButtonLocation.centerFloat,
          ),
        );
      },
    );
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
      final filteredItems = _filteredItems;
      for (int i = minIndex; i <= maxIndex; i++) {
        if (i >= 0 && i < filteredItems.length) {
          newSelection.add(filteredItems[i].id);
        }
      }

      setState(() {
        _selectedItems.clear();
        _selectedItems.addAll(newSelection);
        _lastSelectedIndex = currentIndex;
      });

      // Auto-scrolling logic inside list area
      final localY = box.globalToLocal(event.position).dy;
      if (localY < 50) {
        _scrollCtrl.position.moveTo(_scrollCtrl.offset - 15);
      } else if (localY > box.size.height - 50) {
        _scrollCtrl.position.moveTo(_scrollCtrl.offset + 15);
      }
    }
  }

  // 长按触发选中模式
  void _onLongPress(TorrentItem item, int index) {
    if (mounted) {
      // 使用 Flutter 内置的触觉反馈，提供原生的震动体验
      HapticFeedback.mediumImpact();
      setState(() {
        if (!_isSelectionMode) {
          _isSelectionMode = true;
          _selectedItems.add(item.id);
        }
        _isDraggingSelection = true;
        _dragStartIndex = index;
        _preDragSelectedItems = Set<String>.from(_selectedItems);
      });
    }
  }

  // 切换选中状态
  void _onToggleSelection(TorrentItem item, int index) {
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

          final isSelecting = !_selectedItems.contains(item.id);
          final filteredItems =
              _filteredItems; // Make sure to use the active list

          for (int i = minIndex; i <= maxIndex; i++) {
            if (i >= 0 && i < filteredItems.length) {
              final targetItem = filteredItems[i];
              if (isSelecting) {
                _selectedItems.add(targetItem.id);
              } else {
                _selectedItems.remove(targetItem.id);
              }
            }
          }
        } else {
          if (_selectedItems.contains(item.id)) {
            _selectedItems.remove(item.id);
            if (_selectedItems.isEmpty) {
              _isSelectionMode = false;
            }
          } else {
            _selectedItems.add(item.id);
          }
        }
        _lastSelectedIndex = index;
      });
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

  // 批量收藏
  Future<void> _onBatchFavorite() async {
    if (_selectedItems.isEmpty) return;

    final selectedItems = _items
        .where((item) => _selectedItems.contains(item.id))
        .toList();
    _onCancelSelection(); // 立即取消选择模式

    // 显示开始收藏的提示
    if (mounted) {
      NotificationHelper.showInfo(
        context,
        '开始批量收藏${selectedItems.length}个项目...',
      );
    }

    // 异步处理收藏
    _performBatchFavorite(selectedItems);
  }

  Future<void> _performBatchFavorite(List<TorrentItem> items) async {
    int successCount = 0;
    int failureCount = 0;

    for (int i = 0; i < items.length; i++) {
      final item = items[i];
      try {
        await _onToggleCollection(item);
        successCount++;

        // 间隔控制
        if (i < items.length - 1) {
          await Future.delayed(Duration(seconds: 2));
        }
      } catch (e) {
        failureCount++;
        if (mounted) {
          NotificationHelper.showError(context, '收藏失败: ${item.name}, 错误: $e');
        }
      }
    }

    // 显示最终结果
    if (mounted) {
      final total = items.length;
      final message = '已成功收藏/取消收藏 $successCount/$total 个';

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

  // 批量下载
  Future<void> _onBatchDownload() async {
    if (_selectedItems.isEmpty) return;

    final selectedItems = _items
        .where((item) => _selectedItems.contains(item.id))
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
      final clientConfig = result['clientConfig'] as DownloaderConfig;
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
    List<TorrentItem> items,
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
        // 检查是否在待处理列表中
        if (_pendingDownloadRequests.contains(item.id)) {
          continue;
        }

        _pendingDownloadRequests.add(item.id);

        // 获取下载 URL
        final url = await ApiService.instance.genDlToken(
          id: item.id,
          url: item.downloadUrl,
        );

        // 发送到下载器
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
        );

        successCount++;

        // 添加延迟避免请求过快
        await Future.delayed(const Duration(milliseconds: 500));
      } catch (e) {
        failureCount++;
        if (mounted) {
          NotificationHelper.showError(
            context,
            '下载失败: ${item.name}, 错误: $e',
            duration: const Duration(seconds: 2),
          );
        }
      } finally {
        _pendingDownloadRequests.remove(item.id);
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
}

/// 用户信息骨架屏组件
