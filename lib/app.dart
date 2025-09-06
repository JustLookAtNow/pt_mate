import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:async';
import 'package:flutter/services.dart';

import 'models/app_models.dart';
import 'pages/torrent_detail_page.dart';
import 'services/api/api_service.dart';
import 'services/api/api_client.dart';
import 'services/storage/storage_service.dart';
import 'services/theme/theme_manager.dart';
import 'services/site_config_service.dart';
import 'utils/format.dart';
import 'services/qbittorrent/qb_client.dart';
import 'pages/settings_page.dart';
import 'pages/about_page.dart';
import 'pages/server_settings_page.dart';
import 'widgets/qb_speed_indicator.dart';

class AppState extends ChangeNotifier {
  SiteConfig? _site;
  SiteConfig? get site => _site;

  Future<void> loadInitial() async {
    _site = await StorageService.instance.getActiveSiteConfig();
    await ApiService.instance.init();
    notifyListeners();
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
}

class MTeamApp extends StatelessWidget {
  const MTeamApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AppState()..loadInitial()),
        ChangeNotifierProvider(
          create: (_) =>
              ThemeManager(StorageService.instance)..initializeDynamicColor(),
        ),
        Provider<StorageService>(create: (_) => StorageService.instance),
      ],
      child: Consumer<ThemeManager>(
        builder: (context, themeManager, child) {
          return MaterialApp(
            debugShowCheckedModeBanner: false,
            title: 'M-Team',
            theme: themeManager.lightTheme,
            darkTheme: themeManager.darkTheme,
            themeMode: themeManager.flutterThemeMode,
            home: const LaunchDecider(),
          );
        },
      ),
    );
  }
}

class LaunchDecider extends StatefulWidget {
  const LaunchDecider({super.key});

  @override
  State<LaunchDecider> createState() => _LaunchDeciderState();
}

class _LaunchDeciderState extends State<LaunchDecider> {
  bool _checking = true;
  Widget? _target;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    // 自动检测会话：如果有活跃站点信息且 profile 测试通过 -> HomePage
    try {
      final site = await StorageService.instance.getActiveSiteConfig();
      await ApiService.instance.init();
      if (site != null && (site.apiKey ?? '').isNotEmpty) {
        // 验证 key 是否可用
        await ApiService.instance.fetchMemberProfile();
        _target = const HomePage();
      } else {
        _target = const ServerSettingsPage();
      }
    } catch (_) {
      _target = const ServerSettingsPage();
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return _target ?? const ServerSettingsPage();
  }
}

class ProfilePreviewPage extends StatefulWidget {
  const ProfilePreviewPage({super.key});

  @override
  State<ProfilePreviewPage> createState() => _ProfilePreviewPageState();
}

class _ProfilePreviewPageState extends State<ProfilePreviewPage> {
  final _apiKeyCtrl = TextEditingController();
  final _customNameCtrl = TextEditingController(text: '自定义');
  final _customBaseCtrl = TextEditingController();

  bool _loading = false;
  MemberProfile? _profile;
  String? _error;
  List<SiteConfig> _presetSites = [];

  // 站点选择：index=0/1 为预置，-1 为自定义
  int _siteIndex = 0;

  @override
  void initState() {
    super.initState();
    _loadPresetSites();
  }
  
  Future<void> _loadPresetSites() async {
    try {
      final presets = await SiteConfigService.loadPresetSites();
      setState(() {
        _presetSites = presets;
      });
      
      // 加载当前活跃站点配置
      final loaded = await StorageService.instance.getActiveSiteConfig();
      if (loaded != null) {
        _apiKeyCtrl.text = loaded.apiKey ?? '';
        final idx = presets.indexWhere((s) => s.baseUrl == loaded.baseUrl);
        if (idx >= 0) {
          _siteIndex = idx;
        } else {
          _siteIndex = -1;
          _customNameCtrl.text = loaded.name;
          _customBaseCtrl.text = loaded.baseUrl;
        }
        setState(() {});
      }
    } catch (e) {
      setState(() {
        _presetSites = [];
      });
    }
  }

  SiteConfig _composeCurrentSite() {
    if (_siteIndex >= 0 && _siteIndex < _presetSites.length) {
      final preset = _presetSites[_siteIndex];
      return preset.copyWith(apiKey: _apiKeyCtrl.text.trim());
    }
    var base = _customBaseCtrl.text.trim();
    if (base.isNotEmpty && !base.endsWith('/')) base = '$base/';
    return SiteConfig(
      id: 'custom-${DateTime.now().millisecondsSinceEpoch}',
      name: _customNameCtrl.text.trim().isEmpty
          ? '自定义'
          : _customNameCtrl.text.trim(),
      baseUrl: base.isEmpty ? 'https://api.m-team.cc/' : base,
      apiKey: _apiKeyCtrl.text.trim(),
    );
  }

  Future<void> _onTest() async {
    setState(() {
      _loading = true;
      _error = null;
      _profile = null;
    });
    try {
      final site = _composeCurrentSite();
      // 临时设置站点进行测试
      await ApiService.instance.setActiveSite(site);
      final prof = await ApiService.instance.fetchMemberProfile();
      setState(() => _profile = prof);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _onSave() async {
    final site = _composeCurrentSite();
    if (site.baseUrl.isEmpty) {
      setState(() => _error = '请输入有效的站点地址');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await context.read<AppState>().setSite(site);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('已保存站点与 API Key')));
      // 跳转到首页
      if (!mounted) return;
      Navigator.of(
        context,
      ).pushReplacement(MaterialPageRoute(builder: (_) => const HomePage()));
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final presets = _presetSites;
    return Scaffold(
      appBar: AppBar(
        title: const Text('服务器设置'),
        actions: const [QbSpeedIndicator()],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<int>(
                    initialValue: _siteIndex,
                    decoration: const InputDecoration(
                      labelText: '选择站点',
                      border: OutlineInputBorder(),
                    ),
                    isExpanded: true,
                    selectedItemBuilder: (context) {
                      final widgets = [
                        for (var i = 0; i < presets.length; i++)
                          Text(
                            '${presets[i].name} (${presets[i].baseUrl})',
                            overflow: TextOverflow.ellipsis,
                          ),
                        const Text('自定义…', overflow: TextOverflow.ellipsis),
                      ];
                      return widgets;
                    },
                    items: [
                      for (var i = 0; i < presets.length; i++)
                        DropdownMenuItem(
                          value: i,
                          child: Text(
                            '${presets[i].name} (${presets[i].baseUrl})',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      const DropdownMenuItem(value: -1, child: Text('自定义…')),
                    ],
                    onChanged: (v) {
                      if (v == null) return;
                      setState(() {
                        _siteIndex = v;
                        _profile = null;
                        _error = null;
                      });
                    },
                  ),
                ),
              ],
            ),
            if (_siteIndex < 0) const SizedBox(height: 8),
            if (_siteIndex < 0)
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _customNameCtrl,
                      decoration: const InputDecoration(
                        labelText: '站点名称',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _customBaseCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Base URL，例如 https://example.com/',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
            const SizedBox(height: 12),
            TextField(
              controller: _apiKeyCtrl,
              decoration: const InputDecoration(
                labelText: 'API Key (x-api-key)',
                hintText: '从 控制台-实验室-存储令牌 获取并粘贴此处',
                border: OutlineInputBorder(),
              ),
              obscureText: true,
              maxLines: 1,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                OutlinedButton.icon(
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('测试'),
                  onPressed: _loading ? null : _onTest,
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  icon: const Icon(Icons.save),
                  label: const Text('保存'),
                  onPressed: _loading ? null : _onSave,
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (_loading) const LinearProgressIndicator(),
            if (_error != null)
              Text(_error!, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 12),
            if (_profile != null) _ProfileView(profile: _profile!),
          ],
        ),
      ),
    );
  }
}

class _ProfileView extends StatelessWidget {
  final MemberProfile profile;
  const _ProfileView({required this.profile});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '用户名：${profile.username}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text('魔力值：${Formatters.bonus(profile.bonus)}'),
            const SizedBox(height: 4),
            Text('下载量：${Formatters.dataFromBytes(profile.downloadedBytes)}'),
            const SizedBox(height: 4),
            Text('上传量：${Formatters.dataFromBytes(profile.uploadedBytes)}'),
            const SizedBox(height: 4),
            Text('分享率：${Formatters.shareRate(profile.shareRate)}'),
          ],
        ),
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

  int _selectedCategoryIndex = 0;
  List<SearchCategoryConfig> _categories = [];
  bool _loading = false;
  String? _error;

  // 用户信息与搜索结果分页状态
  MemberProfile? _profile;
  final List<TorrentItem> _items = [];
  int _pageNumber = 1;
  final int _pageSize = 30;
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

  // 收藏请求间隔控制
  DateTime? _lastCollectionRequest;
  final Map<String, bool> _pendingCollectionRequests = <String, bool>{};
  
  // 下载请求状态管理
  final Set<String> _pendingDownloadRequests = <String>{};
  
  // 当前站点配置
  SiteConfig? _currentSite;

  @override
  void initState() {
    super.initState();
    _scrollCtrl.addListener(_onScroll);
    _init(); // 进入时默认搜索“综合”类型
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    _keywordCtrl.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    setState(() => _loading = true);
    try {
      // 加载当前活跃站点的分类配置
      final storageService = Provider.of<StorageService>(context, listen: false);
      final activeSite = await storageService.getActiveSiteConfig();
      final categories = activeSite?.searchCategories ?? SearchCategoryConfig.getDefaultConfigs();
      setState(() {
        _currentSite = activeSite;
        _categories = categories;
        _selectedCategoryIndex = categories.isNotEmpty ? 0 : -1;
      });
      
      // 拉取用户基础信息
      final prof = await ApiService.instance.fetchMemberProfile();
      setState(() => _profile = prof);
    } catch (e) {
      // 用户信息失败不阻塞首页使用，仅提示
      setState(() => _error = _error ?? e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
    // 仅在站点支持种子搜索功能时执行默认搜索
    if (_currentSite?.features.supportTorrentSearch ?? true) {
      await _search(reset: true);
    }
  }

  Future<void> _reloadCategories() async {
    try {
      // 重新加载当前活跃站点的分类配置
      final storageService = Provider.of<StorageService>(context, listen: false);
      final activeSite = await storageService.getActiveSiteConfig();
      final categories = activeSite?.searchCategories ?? SearchCategoryConfig.getDefaultConfigs();
      setState(() {
        _categories = categories;
        // 如果当前选中的分类索引超出范围，重置为第一个分类
        if (categories.isNotEmpty && (_selectedCategoryIndex < 0 || _selectedCategoryIndex >= categories.length)) {
          _selectedCategoryIndex = 0;
        } else if (categories.isEmpty) {
          _selectedCategoryIndex = -1;
        }
      });
    } catch (e) {
      // 分类加载失败时显示错误信息
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('重新加载分类失败: $e')),
        );
      }
    }
  }

  Future<void> _refresh() async {
    try {
      final prof = await ApiService.instance.fetchMemberProfile();
      if (mounted) setState(() => _profile = prof);
    } catch (_) {
      // 忽略用户信息失败
    }
    await _search(reset: true);
  }

  void _onScroll() {
    if (!_hasMore || _loading) return;
    if (_scrollCtrl.position.pixels >=
        _scrollCtrl.position.maxScrollExtent - 200) {
      _loadMore();
    }
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
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // 获取当前分类的额外参数 - 仅在站点支持高级搜索功能时使用
      Map<String, dynamic>? additionalParams;
      if ((_currentSite?.features.supportAdvancedSearch ?? true) && 
          _categories.isNotEmpty && _selectedCategoryIndex >= 0 && _selectedCategoryIndex < _categories.length) {
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
      setState(() {
        _items.addAll(res.items);
        _totalPages = res.totalPages;
        _hasMore = _pageNumber < _totalPages;
      });
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Color _discountColor(String d) {
    if (d.toUpperCase().startsWith('FREE')) return Colors.green;
    if (d.toUpperCase().startsWith('PERCENT_')) return Colors.amber;
    return Colors.grey;
  }

  String _discountText(String d, String? endTime) {
    if (d.toUpperCase().startsWith('FREE')) {
      if (endTime != null && endTime.isNotEmpty) {
        try {
          final endDateTime = DateTime.parse(endTime);
          final now = DateTime.now();
          final difference = endDateTime.difference(now);
          final hoursLeft = difference.inHours;

          if (hoursLeft > 0) {
            return '$d ${hoursLeft}h';
          } else {
            return d;
          }
        } catch (e) {
          return d;
        }
      }
      return d;
    }
    if (d.toUpperCase().startsWith('PERCENT_')) {
      final p = d.split('_').last;
      return '$p%';
    }
    return d;
  }

  void _onSortSelected(String sortType) {
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

    setState(() {}); // 触发重建以显示排序结果
  }

  void _onTorrentTap(TorrentItem item) {
    // 检查站点是否支持种子详情功能
    if (_currentSite?.features.supportTorrentDetail == false) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('当前站点不支持种子详情功能')),
      );
      return;
    }
    
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) =>
            TorrentDetailPage(torrentId: item.id, torrentName: item.name),
      ),
    );
  }

  Future<void> _onDownload(TorrentItem item) async {
    try {
      // 1. 获取下载 URL
      final url = await ApiService.instance.genDlToken(id: item.id,url: item.downloadUrl);

      // 2. 弹出对话框让用户选择下载器设置
      if (!mounted) return;
      final result = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (_) => _TorrentDownloadDialog(
          torrentName: item.name,
          downloadUrl: url,
        ),
      );
      
      if (result == null) return; // 用户取消了
      
      // 3. 从对话框结果中获取设置
      final clientConfig = result['clientConfig'] as QbClientConfig;
      final password = result['password'] as String;
      final category = result['category'] as String?;
      final tags = result['tags'] as List<String>?;
      final savePath = result['savePath'] as String?;
      final autoTMM = result['autoTMM'] as bool?;

      // 4. 发送到 qBittorrent
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
          SnackBar(content: Text('已成功发送"${item.name}"到 ${clientConfig.name}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('下载失败：$e')));
      }
    }
  }

  Future<void> _onToggleCollection(TorrentItem item) async {
    final newCollectionState = !item.collection;
    
    // 立即更新UI状态
    final index = _items.indexWhere((t) => t.id == item.id);
    if (index != -1) {
      setState(() {
        _items[index] = TorrentItem(
          id: item.id,
          name: item.name,
          smallDescr: item.smallDescr,
          discount: item.discount,
          discountEndTime: item.discountEndTime,
          downloadUrl: item.downloadUrl,
          seeders: item.seeders,
          leechers: item.leechers,
          sizeBytes: item.sizeBytes,
          imageList: item.imageList,
          downloadStatus: item.downloadStatus,
          collection: newCollectionState,
        );
      });
    }

    // 不显示开始通知，直接进行后台处理

    // 异步后台请求
    _performCollectionRequest(item, newCollectionState);
  }

  Future<void> _performCollectionRequest(TorrentItem item, bool newCollectionState) async {
    // 检查请求间隔
    final now = DateTime.now();
    if (_lastCollectionRequest != null) {
      final timeDiff = now.difference(_lastCollectionRequest!);
      if (timeDiff.inMilliseconds < 1000) {
        await Future.delayed(Duration(milliseconds: 1000 - timeDiff.inMilliseconds));
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
      
      final index = _items.indexWhere((t) => t.id == item.id);
      if (index != -1) {
        setState(() {
          _items[index] = TorrentItem(
            id: item.id,
            name: item.name,
            smallDescr: item.smallDescr,
            discount: item.discount,
            discountEndTime: item.discountEndTime,
            downloadUrl: item.downloadUrl,
            seeders: item.seeders,
            leechers: item.leechers,
            sizeBytes: item.sizeBytes,
            imageList: item.imageList,
            downloadStatus: item.downloadStatus,
            collection: !newCollectionState, // 恢复原状态
          );
        });
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('收藏操作失败：$e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, appState, child) {
        // 当AppState变化时，检查是否需要重新初始化
        if (appState.site != null && 
            (_currentSite == null || _currentSite!.id != appState.site!.id)) {
          // 站点发生变化，需要重新初始化
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _init();
          });
        }
        
        return Scaffold(
          appBar: AppBar(
            title: const Text('M-Team 首页'),
            actions: const [QbSpeedIndicator()],
          ),
          drawer: _AppDrawer(onSettingsChanged: _reloadCategories),
      body: Column(
        children: [
          // 顶部用户基础信息 - 仅在站点支持用户资料功能时显示
          if (_profile != null && (_currentSite?.features.supportMemberProfile ?? true))
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      const Icon(Icons.person_outline),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _profile!.username,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 12,
                              runSpacing: 4,
                              children: [
                                Text(
                                  '↑ ${Formatters.dataFromBytes(_profile!.uploadedBytes)}',
                                ),
                                Text(
                                  '↓ ${Formatters.dataFromBytes(_profile!.downloadedBytes)}',
                                ),
                                Text(
                                  '比率 ${Formatters.shareRate(_profile!.shareRate)}',
                                ),
                                Text('魔力 ${Formatters.bonus(_profile!.bonus)}'),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                // 分类下拉菜单 - 仅在站点支持分类搜索功能时显示
                if (_currentSite?.features.supportCategories ?? true) ...[
                  DropdownButton<int>(
                    value: _categories.isNotEmpty && _selectedCategoryIndex >= 0 && _selectedCategoryIndex < _categories.length ? _selectedCategoryIndex : null,
                    items: _categories.asMap().entries.map((entry) => 
                      DropdownMenuItem(
                        value: entry.key,
                        child: Text(entry.value.displayName),
                      ),
                    ).toList(),
                    onChanged: (v) {
                      if (v != null && v >= 0 && v < _categories.length) {
                        setState(() => _selectedCategoryIndex = v);
                        if (_currentSite?.features.supportTorrentSearch ?? true) {
                          _search(reset: true);
                        } else {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('当前站点不支持搜索功能')),
                          );
                        }
                      }
                    },
                  ),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: TextField(
                    controller: _keywordCtrl,
                    textInputAction: TextInputAction.search,
                    enabled: _currentSite?.features.supportTorrentSearch ?? true,
                    decoration: InputDecoration(
                      hintText: (_currentSite?.features.supportTorrentSearch ?? true) 
                          ? '输入关键词（可选）' 
                          : '当前站点不支持搜索功能',
                      border: const OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(25)),
                      ),
                      enabledBorder: const OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(25)),
                      ),
                      focusedBorder: const OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(25)),
                      ),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                    ),
                    onSubmitted: (_) {
                      if (_currentSite?.features.supportTorrentSearch ?? true) {
                        _search(reset: true);
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('当前站点不支持搜索功能')),
                        );
                      }
                    },
                  ),
                ),
                const SizedBox(width: 8),
                if (_currentSite?.features.supportCollection == true)
                  IconButton(
                    onPressed: () {
                      setState(() {
                        _onlyFavorites = !_onlyFavorites;
                      });
                      if (_currentSite?.features.supportTorrentSearch ?? true) {
                        _search(reset: true);
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('当前站点不支持搜索功能')),
                        );
                      }
                    },
                    icon: Icon(
                      _onlyFavorites ? Icons.favorite : Icons.favorite_border,
                      color: _onlyFavorites
                          ? Theme.of(context).colorScheme.secondary
                          : null,
                    ),
                    tooltip: _onlyFavorites ? '显示全部' : '仅显示收藏',
                  ),
                const SizedBox(width: 8),
                PopupMenuButton<String>(
                  onSelected: _onSortSelected,
                  icon: Icon(
                    _sortBy == 'none' ? Icons.sort : Icons.sort,
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
                              ? Theme.of(
                                  context,
                                ).colorScheme.primary.withValues(alpha: 0.1)
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
                                  ? Theme.of(context).colorScheme.secondary
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
                          color: _sortBy == 'size'
                              ? Theme.of(
                                  context,
                                ).colorScheme.primary.withValues(alpha: 0.1)
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
                                  ? Theme.of(context).colorScheme.secondary
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
                          color: _sortBy == 'upload'
                              ? Theme.of(
                                  context,
                                ).colorScheme.primary.withValues(alpha: 0.1)
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
                              _sortBy == 'upload' && _sortAscending
                                  ? Icons.arrow_upward
                                  : Icons.arrow_downward,
                              color: _sortBy == 'upload'
                                  ? Theme.of(context).colorScheme.secondary
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
                          color: _sortBy == 'download'
                              ? Theme.of(
                                  context,
                                ).colorScheme.primary.withValues(alpha: 0.1)
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
                              _sortBy == 'download' && _sortAscending
                                  ? Icons.arrow_upward
                                  : Icons.arrow_downward,
                              color: _sortBy == 'download'
                                  ? Theme.of(context).colorScheme.secondary
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
          ),
          if (_loading) const LinearProgressIndicator(),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(_error!, style: const TextStyle(color: Colors.red)),
            ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _refresh,
              child: ListView.builder(
                controller: _scrollCtrl,
                physics: const AlwaysScrollableScrollPhysics(),
                itemCount: _items.length + (_hasMore ? 1 : 0),
                itemBuilder: (_, i) {
                  if (i >= _items.length) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Center(
                        child: SizedBox(
                          height: 24,
                          width: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    );
                  }
                  final t = _items[i];
                  final isSelected = _selectedItems.contains(t.id);
                  return GestureDetector(
                    onTap: () => _isSelectionMode
                        ? _onToggleSelection(t)
                        : _onTorrentTap(t),
                    onLongPress: () => _onLongPress(t),
                    child: Container(
                      decoration: BoxDecoration(
                        color: isSelected
                            ? Theme.of(
                                context,
                              ).colorScheme.primary.withValues(alpha: 0.1)
                            : null,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      margin: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 4,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    t.name,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.titleMedium,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    t.smallDescr,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(
                                          color: Theme.of(
                                            context,
                                          ).textTheme.bodySmall?.color,
                                        ),
                                  ),
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: _discountColor(t.discount!),
                                          borderRadius: BorderRadius.circular(
                                            4,
                                          ),
                                        ),
                                        child: Text(
                                          _discountText(
                                            t.discount!,
                                            t.discountEndTime,
                                          ),
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      _buildSeedLeechInfo(
                                        t.seeders,
                                        t.leechers,
                                      ),
                                      const SizedBox(width: 10),
                                      Text(
                                        Formatters.dataFromBytes(t.sizeBytes),
                                      ),
                                      const Spacer(),
                                      // 下载状态图标 - 仅在站点支持下载历史功能时显示
                                      if (_currentSite?.features.supportHistory ?? true)
                                        _buildDownloadStatusIcon(
                                          t.downloadStatus,
                                        ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                // 收藏按钮 - 仅在站点支持收藏功能时显示
                                if (_currentSite?.features.supportCollection ?? true)
                                  IconButton(
                                    onPressed: () => _onToggleCollection(t),
                                    icon: Icon(
                                      t.collection
                                          ? Icons.favorite
                                          : Icons.favorite_border,
                                      color: t.collection ? Colors.red : null,
                                    ),
                                    tooltip: t.collection ? '取消收藏' : '收藏',
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(
                                      minWidth: 40,
                                      minHeight: 40,
                                    ),
                                  ),
                                // 下载按钮 - 仅在站点支持下载功能时显示
                                if (_currentSite?.features.supportDownload ?? true)
                                  IconButton(
                                    onPressed: () => _onDownload(t),
                                    icon: const Icon(Icons.download_outlined),
                                    tooltip: '下载',
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(
                                      minWidth: 40,
                                      minHeight: 40,
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
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
                    child: ElevatedButton(
                      onPressed: _onCancelSelection,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Theme.of(
                          context,
                        ).colorScheme.secondary,
                        foregroundColor: Theme.of(
                          context,
                        ).colorScheme.onSecondary,
                      ),
                      child: const Text('取消'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // 批量收藏按钮 - 仅在站点支持收藏功能时显示
                  if (_currentSite?.features.supportCollection ?? true) ...[
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _selectedItems.isNotEmpty
                            ? _onBatchFavorite
                            : null,
                        style: ElevatedButton.styleFrom(
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
                        backgroundColor: Theme.of(context).colorScheme.primary,
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
    );
      },
    );
  }

  // 长按触发选中模式
  void _onLongPress(TorrentItem item) {
    if (!_isSelectionMode) {
      // 使用 Flutter 内置的触觉反馈，提供原生的震动体验
      HapticFeedback.mediumImpact();
      setState(() {
        _isSelectionMode = true;
        _selectedItems.add(item.id);
      });
    }
  }

  // 切换选中状态
  void _onToggleSelection(TorrentItem item) {
    setState(() {
      if (_selectedItems.contains(item.id)) {
        _selectedItems.remove(item.id);
        if (_selectedItems.isEmpty) {
          _isSelectionMode = false;
        }
      } else {
        _selectedItems.add(item.id);
      }
    });
  }

  // 取消选中模式
  void _onCancelSelection() {
    setState(() {
      _isSelectionMode = false;
      _selectedItems.clear();
    });
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('开始批量收藏${selectedItems.length}个项目...')),
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
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('收藏失败: ${item.name}, 错误: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
    
    // 显示最终结果
    if (mounted) {
      final total = items.length;
      final message = '已成功收藏/取消收藏 $successCount/$total 个';
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: failureCount == 0 ? Colors.green : Colors.orange,
          duration: const Duration(seconds: 2),
        ),
      );
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
      builder: (context) => _BatchDownloadDialog(
        itemCount: selectedItems.length,
      ),
    );
    
    if (result == null) return; // 用户取消了
    
    _onCancelSelection(); // 取消选择模式
    
    // 显示开始下载的提示
    if (mounted) {
      final clientConfig = result['clientConfig'] as QbClientConfig;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('开始批量下载${selectedItems.length}个项目到${clientConfig.name}...')),
      );
    }

    // 异步处理下载
    _performBatchDownload(
      selectedItems,
      result['clientConfig'] as QbClientConfig,
      result['password'] as String,
      result['category'] as String?,
      result['tags'] as List<String>? ?? [],
      result['savePath'] as String?,
      result['autoTMM'] as bool?,
    );
  }
  
  Future<void> _performBatchDownload(
    List<TorrentItem> items,
    QbClientConfig clientConfig,
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
        final url = await ApiService.instance.genDlToken(id: item.id,url: item.downloadUrl);
        
        // 发送到 qBittorrent
        await QbService.instance.addTorrentByUrl(
          config: clientConfig,
          password: password,
          url: url,
          category: category,
          tags: tags.isEmpty ? null : tags,
          savePath: savePath,
          autoTMM: autoTMM,
        );
        
        successCount++;
        
        // 添加延迟避免请求过快
        await Future.delayed(const Duration(milliseconds: 500));
      } catch (e) {
        failureCount++;
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('下载失败: ${item.name}, 错误: $e'),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 2),
            ),
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
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: failureCount == 0 ? null : Colors.orange,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Widget _buildSeedLeechInfo(int seeders, int leechers) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.arrow_upward, color: Colors.green, size: 16),
        Text('$seeders', style: const TextStyle(fontSize: 12)),
        const SizedBox(width: 4),
        Icon(Icons.arrow_downward, color: Colors.red, size: 16),
        Text('$leechers', style: const TextStyle(fontSize: 12)),
      ],
    );
  }

  Widget _buildDownloadStatusIcon(DownloadStatus status) {
    switch (status) {
      case DownloadStatus.completed:
        return const Icon(Icons.download_done, color: Colors.green, size: 20);
      case DownloadStatus.downloading:
        return const SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
          ),
        );
      case DownloadStatus.none:
        return const SizedBox(width: 20); // 占位，保持布局一致
    }
  }
}

class HomePlaceholderPage extends StatelessWidget {
  const HomePlaceholderPage({super.key});

  @override
  Widget build(BuildContext context) {
    final site = context.watch<AppState>().site;
    return Scaffold(
      appBar: AppBar(
        title: const Text('M-Team 首页（占位）'),
        actions: const [QbSpeedIndicator()],
      ),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [Text('已保存站点：${site?.name ?? ''}')],
        ),
      ),
    );
  }
}

// 应用左侧抽屉
class _AppDrawer extends StatelessWidget {
  final VoidCallback? onSettingsChanged;
  
  const _AppDrawer({this.onSettingsChanged});

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: SafeArea(
        child: ListView(
          children: [
            const DrawerHeader(
              child: Align(
                alignment: Alignment.bottomLeft,
                child: Text(
                  'M-Team',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.home_outlined),
              title: const Text('主页'),
              onTap: () => Navigator.of(context).pop(),
            ),
            ListTile(
              leading: const Icon(Icons.download_outlined),
              title: const Text('下载器设置'),
              onTap: () {
                Navigator.of(context).pop();
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const DownloaderSettingsPage(),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.dns),
              title: const Text('服务器配置'),
              onTap: () {
                Navigator.of(context).pop();
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const ServerSettingsPage(),
                  ),
                );
              },
            ),

            ListTile(
              leading: const Icon(Icons.settings_outlined),
              title: const Text('设置'),
              onTap: () async {
                Navigator.of(context).pop();
                await Navigator.of(
                  context,
                ).push(MaterialPageRoute(builder: (_) => const SettingsPage()));
                // 从设置页面返回后，重新加载分类配置
                onSettingsChanged?.call();
              },
            ),
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('关于'),
              onTap: () {
                Navigator.of(context).pop();
                Navigator.of(
                  context,
                ).push(MaterialPageRoute(builder: (_) => const AboutPage()));
              },
            ),
          ],
        ),
      ),
    );
  }
}

class DownloaderSettingsPage extends StatefulWidget {
  const DownloaderSettingsPage({super.key});

  @override
  State<DownloaderSettingsPage> createState() => _DownloaderSettingsPageState();
}

class _DownloaderSettingsPageState extends State<DownloaderSettingsPage> {
  List<QbClientConfig> _clients = [];
  String? _defaultId;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final clients = await StorageService.instance.loadQbClients();
      final def = await StorageService.instance.loadDefaultQbId();
      if (mounted) {
        setState(() {
          _clients = clients;
          _defaultId = def;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _addOrEdit({QbClientConfig? existing}) async {
    final result = await showDialog<_QbEditorResult>(
      context: context,
      builder: (_) => _QbClientEditorDialog(existing: existing),
    );
    if (result == null) return;
    // 保存
    final updated = [..._clients];
    final idx = existing == null
        ? -1
        : updated.indexWhere((c) => c.id == existing.id);
    final cfg = result.config;
    if (idx >= 0) {
      updated[idx] = cfg;
    } else {
      updated.add(cfg);
    }
    await StorageService.instance.saveQbClients(updated, defaultId: _defaultId);
    if ((result.password ?? '').isNotEmpty) {
      await StorageService.instance.saveQbPassword(cfg.id, result.password!);
    }
    await _load();
  }

  Future<void> _delete(QbClientConfig c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('删除下载器'),
        content: Text('确定删除下载器“${c.name}”吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final list = _clients.where((e) => e.id != c.id).toList();
    await StorageService.instance.saveQbClients(
      list,
      defaultId: _defaultId == c.id ? null : _defaultId,
    );
    await StorageService.instance.deleteQbPassword(c.id);
    await _load();
  }

  Future<void> _setDefault(QbClientConfig c) async {
    setState(() => _defaultId = c.id);
    await StorageService.instance.saveQbClients(_clients, defaultId: c.id);
  }

  Future<void> _testDefault() async {
    final id = _defaultId;
    if (id == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请先在列表中选择一个默认下载器')));
      return;
    }
    final c = _clients.firstWhere(
      (e) => e.id == id,
      orElse: () => _clients.first,
    );
    await _test(c);
  }

  Future<void> _test(QbClientConfig c) async {
    // 获取密码
    var password = await StorageService.instance.loadQbPassword(c.id);
    if ((password ?? '').isEmpty) {
      if (!mounted) return;
      password = await showDialog<String>(
        context: context,
        builder: (_) => _PasswordPromptDialog(name: c.name),
      );
      if ((password ?? '').isEmpty) return;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(
                  Theme.of(context).colorScheme.onPrimaryContainer,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Text(
              '正在测试连接…',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onPrimaryContainer,
              ),
            ),
          ],
        ),
        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
        behavior: SnackBarBehavior.floating,
      ),
    );
    try {
      await QbService.instance.testConnection(config: c, password: password!);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(Icons.check_circle, color: Colors.green[700], size: 20),
              const SizedBox(width: 12),
              Text(
                '连接成功',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          backgroundColor: Theme.of(
            context,
          ).colorScheme.surfaceContainerHighest,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(
                Icons.error,
                color: Theme.of(context).colorScheme.onErrorContainer,
                size: 20,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '连接失败：$e',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onErrorContainer,
                  ),
                ),
              ),
            ],
          ),
          backgroundColor: Theme.of(context).colorScheme.errorContainer,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _openCategoriesTags(QbClientConfig c) async {
    // 优先读取已保存密码；若无则提示输入
    var pwd = await StorageService.instance.loadQbPassword(c.id);
    if ((pwd ?? '').isEmpty) {
      if (!mounted) return;
      pwd = await showDialog<String>(
        context: context,
        builder: (_) => _PasswordPromptDialog(name: c.name),
      );
      if ((pwd ?? '').isEmpty) return;
    }
    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (_) => _QbCategoriesTagsDialog(config: c, password: pwd!),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('下载器设置'),
        actions: [
          IconButton(
            tooltip: '测试默认下载器',
            onPressed: _testDefault,
            icon: const Icon(Icons.wifi_tethering),
          ),
          const QbSpeedIndicator(),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      _error!,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),
                Expanded(
                  child: RadioGroup<String>(
                    groupValue: _defaultId,
                    onChanged: (String? value) {
                      if (value != null) {
                        final client = _clients.firstWhere(
                          (c) => c.id == value,
                        );
                        _setDefault(client);
                      }
                    },
                    child: ListView.builder(
                      itemCount: _clients.length,
                      itemBuilder: (_, i) {
                        final c = _clients[i];
                        final subtitle =
                            '${c.host}:${c.port}  ·  ${c.username}';
                        return ListTile(
                          leading: Radio<String>(value: c.id),
                          title: Text(c.name),
                          subtitle: Text(subtitle),
                          onTap: () => _addOrEdit(existing: c),
                          trailing: Wrap(
                            spacing: 8,
                            children: [
                              IconButton(
                                tooltip: '测试连接',
                                onPressed: () => _test(c),
                                icon: const Icon(Icons.wifi_tethering),
                              ),
                              IconButton(
                                tooltip: '分类与标签',
                                onPressed: () => _openCategoriesTags(c),
                                icon: const Icon(Icons.folder_open),
                              ),
                              IconButton(
                                tooltip: '删除',
                                onPressed: () => _delete(c),
                                icon: const Icon(Icons.delete_outline),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _addOrEdit(),
        icon: const Icon(Icons.add),
        label: const Text('新增下载器'),
      ),
    );
  }
}

class _PasswordPromptDialog extends StatefulWidget {
  final String name;
  const _PasswordPromptDialog({required this.name});

  @override
  State<_PasswordPromptDialog> createState() => _PasswordPromptDialogState();
}

class _PasswordPromptDialogState extends State<_PasswordPromptDialog> {
  final _pwdCtrl = TextEditingController();

  @override
  void dispose() {
    _pwdCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('输入“${widget.name}”密码'),
      content: TextField(
        controller: _pwdCtrl,
        obscureText: true,
        decoration: const InputDecoration(
          labelText: '密码',
          border: OutlineInputBorder(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _pwdCtrl.text.trim()),
          child: const Text('确定'),
        ),
      ],
    );
  }
}

class _QbEditorResult {
  final QbClientConfig config;
  final String? password;
  _QbEditorResult(this.config, this.password);
}

class _QbClientEditorDialog extends StatefulWidget {
  final QbClientConfig? existing;
  const _QbClientEditorDialog({this.existing});

  @override
  State<_QbClientEditorDialog> createState() => _QbClientEditorDialogState();
}

class _QbClientEditorDialogState extends State<_QbClientEditorDialog> {
  final _nameCtrl = TextEditingController();
  final _hostCtrl = TextEditingController();
  final _portCtrl = TextEditingController(text: '8080');
  final _userCtrl = TextEditingController();
  final _pwdCtrl = TextEditingController();
  bool _testing = false;
  String? _testMsg;
  bool? _testOk;
  bool _useLocalRelay = false; // 本地中转选项状态

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      _nameCtrl.text = e.name;
      _hostCtrl.text = e.host;
      _portCtrl.text = e.port.toString();
      _userCtrl.text = e.username;
      _useLocalRelay = e.useLocalRelay; // 初始化本地中转状态
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _hostCtrl.dispose();
    _portCtrl.dispose();
    _userCtrl.dispose();
    _pwdCtrl.dispose();
    super.dispose();
  }

  Future<void> _onSubmit() async {
    final name = _nameCtrl.text.trim();
    final host = _hostCtrl.text.trim();
    final port = int.tryParse(_portCtrl.text.trim());
    final user = _userCtrl.text.trim();
    final pwd = _pwdCtrl.text.trim();
    if (name.isEmpty || host.isEmpty || port == null || user.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请完整填写名称、主机、端口、用户名')));
      return;
    }
    final id =
        widget.existing?.id ?? DateTime.now().millisecondsSinceEpoch.toString();
    final cfg = QbClientConfig(
      id: id,
      name: name,
      host: host,
      port: port,
      username: user,
      useLocalRelay: _useLocalRelay, // 包含本地中转选项
    );
    // 可选先测连
    Navigator.of(context).pop(_QbEditorResult(cfg, pwd.isEmpty ? null : pwd));
  }

  Future<void> _testConnection() async {
    final name = _nameCtrl.text.trim();
    final host = _hostCtrl.text.trim();
    final port = int.tryParse(_portCtrl.text.trim());
    final user = _userCtrl.text.trim();
    final pwd = _pwdCtrl.text.trim();

    if (name.isEmpty ||
        host.isEmpty ||
        port == null ||
        user.isEmpty ||
        pwd.isEmpty) {
      setState(() {
        _testOk = false;
        _testMsg = '请完整填写名称、主机、端口、用户名和密码后再测试';
      });
      return;
    }

    setState(() {
      _testing = true;
      _testMsg = null;
    });
    try {
      final cfg = QbClientConfig(
        id: widget.existing?.id ?? 'temp',
        name: name,
        host: host,
        port: port,
        username: user,
        useLocalRelay: _useLocalRelay, // 包含本地中转选项
      );

      await QbService.instance.testConnection(config: cfg, password: pwd);
      if (!mounted) return;
      setState(() {
        _testOk = true;
        _testMsg = '连接成功';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _testOk = false;
        _testMsg = '连接失败：$e';
      });
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Container(
        width: 420,
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.8,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 标题栏
            Container(
              padding: const EdgeInsets.all(24),
              decoration: const BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: Colors.grey, width: 0.5),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.existing == null ? '新增下载器' : '编辑下载器',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                ],
              ),
            ),
            // 内容区域
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: _nameCtrl,
                      decoration: const InputDecoration(
                        labelText: '名称',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _hostCtrl,
                      decoration: const InputDecoration(
                        labelText: '主机/IP（可含协议）',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _portCtrl,
                      decoration: const InputDecoration(
                        labelText: '端口',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _userCtrl,
                      decoration: const InputDecoration(
                        labelText: '用户名',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _pwdCtrl,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: '密码（仅用于保存/测试，不会明文入库）',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    // 本地中转选项
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '本地中转',
                                  style: Theme.of(context).textTheme.titleSmall,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '启用后先下载种子文件到本地，再提交给 qBittorrent',
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(color: Colors.grey.shade600),
                                ),
                              ],
                            ),
                          ),
                          Switch(
                            value: _useLocalRelay,
                            onChanged: (value) {
                              setState(() {
                                _useLocalRelay = value;
                              });
                            },
                          ),
                        ],
                      ),
                    ),
                    if (_testMsg != null) ...[
                      const SizedBox(height: 16),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: _testOk == true
                              ? Theme.of(context).colorScheme.primaryContainer
                              : Theme.of(context).colorScheme.errorContainer,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: _testOk == true
                                ? Theme.of(context).colorScheme.primary
                                : Theme.of(context).colorScheme.error,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              _testOk == true
                                  ? Icons.check_circle
                                  : Icons.error_outline,
                              size: 18,
                              color: _testOk == true
                                  ? Theme.of(context).colorScheme.primary
                                  : Theme.of(context).colorScheme.error,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _testMsg!,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: _testOk == true
                                      ? Theme.of(
                                          context,
                                        ).colorScheme.onPrimaryContainer
                                      : Theme.of(
                                          context,
                                        ).colorScheme.onErrorContainer,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            // 按钮栏
            Container(
              padding: const EdgeInsets.all(12),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: Colors.grey, width: 0.5)),
              ),
              child: Column(
                children: [
                  // 测试按钮单独一排
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      OutlinedButton.icon(
                        onPressed: _testing ? null : _testConnection,
                        icon: _testing
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.wifi_tethering),
                        label: Text(_testing ? '测试中…' : '测试连接'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // 取消和保存按钮一排
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('取消'),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: _onSubmit,
                        child: const Text('保存'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QbCategoriesTagsDialog extends StatefulWidget {
  final QbClientConfig config;
  final String password;
  const _QbCategoriesTagsDialog({required this.config, required this.password});

  @override
  State<_QbCategoriesTagsDialog> createState() =>
      _QbCategoriesTagsDialogState();
}

class _QbCategoriesTagsDialogState extends State<_QbCategoriesTagsDialog> {
  List<String> _categories = [];
  List<String> _tags = [];
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadCacheThenRefresh();
  }

  Future<void> _loadCacheThenRefresh() async {
    // 先读取本地缓存，提升首屏体验
    final cachedCats = await StorageService.instance.loadQbCategories(
      widget.config.id,
    );
    final cachedTags = await StorageService.instance.loadQbTags(
      widget.config.id,
    );
    if (mounted) {
      setState(() {
        _categories = cachedCats;
        _tags = cachedTags;
      });
    }
    // 再尝试远程拉取
    await _refresh();
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final cats = await QbService.instance.fetchCategories(
        config: widget.config,
        password: widget.password,
      );
      final tags = await QbService.instance.fetchTags(
        config: widget.config,
        password: widget.password,
      );
      if (!mounted) return;
      setState(() {
        _categories = cats;
        _tags = tags;
        _error = null;
      });
      // 成功后写入本地缓存
      await StorageService.instance.saveQbCategories(widget.config.id, cats);
      await StorageService.instance.saveQbTags(widget.config.id, tags);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '拉取失败：$e';
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('分类与标签 - ${widget.config.name}'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_error != null) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFEBEE),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: const Color(0xFFEA4335)),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.error_outline,
                        size: 18,
                        color: Color(0xFFEA4335),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _error!,
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
              ],
              Row(
                children: [
                  const Icon(Icons.folder, size: 18),
                  const SizedBox(width: 6),
                  const Text(
                    '分类',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(width: 8),
                  if (_loading)
                    const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              if (_categories.isEmpty)
                const Text(
                  '暂无分类，点击右下角“刷新”尝试获取…',
                  style: TextStyle(color: Colors.black54),
                )
              else
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _categories
                      .map((e) => Chip(label: Text(e)))
                      .toList(),
                ),
              const SizedBox(height: 16),
              Row(
                children: [
                  const Icon(Icons.label_outline, size: 18),
                  const SizedBox(width: 6),
                  const Text(
                    '标签',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (_tags.isEmpty)
                const Text(
                  '暂无标签，点击右下角“刷新”尝试获取…',
                  style: TextStyle(color: Colors.black54),
                )
              else
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _tags.map((e) => Chip(label: Text(e))).toList(),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('关闭'),
        ),
        OutlinedButton.icon(
          onPressed: _loading ? null : _refresh,
          icon: _loading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.refresh),
          label: Text(_loading ? '刷新中…' : '刷新'),
        ),
      ],
    );
  }
}

class _BatchDownloadDialog extends StatefulWidget {
  final int itemCount;

  const _BatchDownloadDialog({
    required this.itemCount,
  });

  @override
  State<_BatchDownloadDialog> createState() => _BatchDownloadDialogState();
}

class _BatchDownloadDialogState extends State<_BatchDownloadDialog> {
  List<QbClientConfig> _clients = [];
  QbClientConfig? _selectedClient;
  String? _selectedCategory;
  final List<String> _selectedTags = [];
  final _savePathCtrl = TextEditingController();

  List<String> _categories = [];
  List<String> _tags = [];
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadClients();
  }

  @override
  void dispose() {
    _savePathCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadClients() async {
    try {
      final clients = await StorageService.instance.loadQbClients();
      final defaultId = await StorageService.instance.loadDefaultQbId();

      if (mounted) {
        setState(() {
          _clients = clients;
          _selectedClient = clients.isNotEmpty
              ? clients.firstWhere(
                  (c) => c.id == defaultId,
                  orElse: () => clients.first,
                )
              : null;
        });

        if (_selectedClient != null) {
          _loadCategoriesAndTags();
        }
      }
    } catch (e) {
      if (mounted) setState(() => _error = '加载下载器列表失败：$e');
    }
  }

  Future<void> _loadCategoriesAndTags() async {
    if (_selectedClient == null) return;

    setState(() => _loading = true);
    try {
      // 优先读取缓存
      final cachedCategories = await StorageService.instance.loadQbCategories(
        _selectedClient!.id,
      );
      final cachedTags = await StorageService.instance.loadQbTags(
        _selectedClient!.id,
      );

      if (mounted) {
        setState(() {
          _categories = cachedCategories;
          _tags = cachedTags;
        });
      }

      // 只有缓存为空时才刷新
      if (cachedCategories.isEmpty || cachedTags.isEmpty) {
        await _refreshCategoriesAndTags();
      }
    } catch (e) {
      if (mounted) setState(() => _error = '加载分类标签失败：$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _refreshCategoriesAndTags() async {
    if (_selectedClient == null) return;

    try {
      String? password = await StorageService.instance.loadQbPassword(
        _selectedClient!.id,
      );

      if (password == null || password.isEmpty) {
        password = await _promptPassword(_selectedClient!.name);
        if (password == null) return;
      }

      final categories = await QbService.instance.fetchCategories(
        config: _selectedClient!,
        password: password,
      );
      final tags = await QbService.instance.fetchTags(
        config: _selectedClient!,
        password: password,
      );

      // 保存到缓存
      await StorageService.instance.saveQbCategories(
        _selectedClient!.id,
        categories,
      );
      await StorageService.instance.saveQbTags(_selectedClient!.id, tags);

      if (mounted) {
        setState(() {
          _categories = categories;
          _tags = tags;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = '刷新分类标签失败：$e');
    }
  }

  Future<String?> _promptPassword(String clientName) async {
    return await showDialog<String>(
      context: context,
      builder: (_) => _PasswordPromptDialog(name: clientName),
    );
  }

  Future<void> _onSubmit() async {
    if (_selectedClient == null) {
      setState(() => _error = '请选择下载器');
      return;
    }

    String? password = await StorageService.instance.loadQbPassword(
      _selectedClient!.id,
    );
    if (password == null || password.isEmpty) {
      if (!mounted) return;
      password = await _promptPassword(_selectedClient!.name);
      if (password == null) return;
    }

    // 只有选择了分类才强制启用自动管理；未选择分类时不传该参数，遵循服务器默认
    final bool? autoTMM =
        (_selectedCategory != null && _selectedCategory!.isNotEmpty)
        ? true
        : null;

    if (!mounted) return;
    Navigator.pop(context, {
      'clientConfig': _selectedClient!,
      'password': password,
      'category': _selectedCategory,
      'tags': _selectedTags.isEmpty ? null : _selectedTags,
      'savePath': _savePathCtrl.text.trim().isEmpty
          ? null
          : _savePathCtrl.text.trim(),
      'autoTMM': autoTMM,
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('批量下载设置 (${widget.itemCount}个项目)'),
      scrollable: true,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      content: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: SizedBox(
          width: 400,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '将下载 ${widget.itemCount} 个种子文件',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 16),

                // 选择下载器
                Text('下载器', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                DropdownButtonFormField<QbClientConfig>(
                  initialValue: _selectedClient,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  isExpanded: true,
                  selectedItemBuilder: (context) => _clients
                      .map(
                        (c) => Text(
                          '${c.name} (${c.host}:${c.port})',
                          overflow: TextOverflow.ellipsis,
                        ),
                      )
                      .toList(),
                  items: _clients
                      .map(
                        (client) => DropdownMenuItem<QbClientConfig>(
                          value: client,
                          child: Text(
                            '${client.name} (${client.host}:${client.port})',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (client) {
                    setState(() {
                      _selectedClient = client;
                      _selectedCategory = null;
                      _selectedTags.clear();
                      _categories.clear();
                      _tags.clear();
                    });
                    if (client != null) _loadCategoriesAndTags();
                  },
                ),
                const SizedBox(height: 16),

                // 选择分类
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '分类',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    ),
                    if (_loading)
                      const SizedBox(
                        height: 16,
                        width: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    if (!_loading)
                      IconButton(
                        onPressed: _refreshCategoriesAndTags,
                        icon: const Icon(Icons.refresh, size: 20),
                        tooltip: '刷新',
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String?>(
                  initialValue: _selectedCategory,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    isDense: true,
                    hintText: '选择分类（可选）',
                  ),
                  isExpanded: true,
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('不使用分类'),
                    ),
                    ..._categories.map(
                      (cat) => DropdownMenuItem<String?>(
                        value: cat,
                        child: Text(cat, overflow: TextOverflow.ellipsis),
                      ),
                    ),
                  ],
                  onChanged: (cat) => setState(() => _selectedCategory = cat),
                ),
                const SizedBox(height: 16),

                // 选择标签
                Text('标签', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                if (_tags.isEmpty)
                  const Text('暂无可用标签', style: TextStyle(color: Colors.grey))
                else
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: _tags.map((tag) {
                      final selected = _selectedTags.contains(tag);
                      return FilterChip(
                        label: Text(tag),
                        selected: selected,
                        onSelected: (sel) {
                          setState(() {
                            if (sel) {
                              _selectedTags.add(tag);
                            } else {
                              _selectedTags.remove(tag);
                            }
                          });
                        },
                      );
                    }).toList(),
                  ),
                const SizedBox(height: 16),

                // 保存路径
                Text('保存路径', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                TextField(
                  controller: _savePathCtrl,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    isDense: true,
                    hintText: '留空使用默认路径',
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '提示：选择分类时将启用自动管理模式',
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: Colors.grey),
                ),

                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Text(
                      _error!,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(onPressed: _onSubmit, child: const Text('开始下载')),
      ],
    );
  }
}

class _TorrentDownloadDialog extends StatefulWidget {
  final String torrentName;
  final String downloadUrl;

  const _TorrentDownloadDialog({
    required this.torrentName,
    required this.downloadUrl,
  });

  @override
  State<_TorrentDownloadDialog> createState() => _TorrentDownloadDialogState();
}

class _TorrentDownloadDialogState extends State<_TorrentDownloadDialog> {
  List<QbClientConfig> _clients = [];
  QbClientConfig? _selectedClient;
  String? _selectedCategory;
  final List<String> _selectedTags = [];
  final _savePathCtrl = TextEditingController();

  List<String> _categories = [];
  List<String> _tags = [];
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadClients();
  }

  @override
  void dispose() {
    _savePathCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadClients() async {
    try {
      final clients = await StorageService.instance.loadQbClients();
      final defaultId = await StorageService.instance.loadDefaultQbId();

      if (mounted) {
        setState(() {
          _clients = clients;
          _selectedClient = clients.isNotEmpty
              ? clients.firstWhere(
                  (c) => c.id == defaultId,
                  orElse: () => clients.first,
                )
              : null;
        });

        if (_selectedClient != null) {
          _loadCategoriesAndTags();
        }
      }
    } catch (e) {
      if (mounted) setState(() => _error = '加载下载器列表失败：$e');
    }
  }

  Future<void> _loadCategoriesAndTags() async {
    if (_selectedClient == null) return;

    setState(() => _loading = true);
    try {
      // 优先读取缓存
      final cachedCategories = await StorageService.instance.loadQbCategories(
        _selectedClient!.id,
      );
      final cachedTags = await StorageService.instance.loadQbTags(
        _selectedClient!.id,
      );

      if (mounted) {
        setState(() {
          _categories = cachedCategories;
          _tags = cachedTags;
        });
      }

      // 只有缓存为空时才刷新
      if (cachedCategories.isEmpty || cachedTags.isEmpty) {
        await _refreshCategoriesAndTags();
      }
    } catch (e) {
      if (mounted) setState(() => _error = '加载分类标签失败：$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _refreshCategoriesAndTags() async {
    if (_selectedClient == null) return;

    try {
      String? password = await StorageService.instance.loadQbPassword(
        _selectedClient!.id,
      );

      if (password == null || password.isEmpty) {
        password = await _promptPassword(_selectedClient!.name);
        if (password == null) return;
      }

      final categories = await QbService.instance.fetchCategories(
        config: _selectedClient!,
        password: password,
      );
      final tags = await QbService.instance.fetchTags(
        config: _selectedClient!,
        password: password,
      );

      // 保存到缓存
      await StorageService.instance.saveQbCategories(
        _selectedClient!.id,
        categories,
      );
      await StorageService.instance.saveQbTags(_selectedClient!.id, tags);

      if (mounted) {
        setState(() {
          _categories = categories;
          _tags = tags;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = '刷新分类标签失败：$e');
    }
  }

  Future<String?> _promptPassword(String clientName) async {
    return await showDialog<String>(
      context: context,
      builder: (_) => _PasswordPromptDialog(name: clientName),
    );
  }

  Future<void> _onSubmit() async {
    if (_selectedClient == null) {
      setState(() => _error = '请选择下载器');
      return;
    }

    String? password = await StorageService.instance.loadQbPassword(
      _selectedClient!.id,
    );
    if (password == null || password.isEmpty) {
      if (!mounted) return;
      password = await _promptPassword(_selectedClient!.name);
      if (password == null) return;
    }

    // 只有选择了分类才强制启用自动管理；未选择分类时不传该参数，遵循服务器默认
    final bool? autoTMM =
        (_selectedCategory != null && _selectedCategory!.isNotEmpty)
        ? true
        : null;

    if (!mounted) return;
    Navigator.pop(context, {
      'clientConfig': _selectedClient!,
      'password': password,
      'category': _selectedCategory,
      'tags': _selectedTags.isEmpty ? null : _selectedTags,
      'savePath': _savePathCtrl.text.trim().isEmpty
          ? null
          : _savePathCtrl.text.trim(),
      'autoTMM': autoTMM,
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('配置下载'),
      scrollable: true,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      content: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: SizedBox(
          width: 400,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '种子：${widget.torrentName}',
                  style: Theme.of(context).textTheme.bodyMedium,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 16),

                // 选择下载器
                Text('下载器', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                DropdownButtonFormField<QbClientConfig>(
                  initialValue: _selectedClient,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  isExpanded: true,
                  selectedItemBuilder: (context) => _clients
                      .map(
                        (c) => Text(
                          '${c.name} (${c.host}:${c.port})',
                          overflow: TextOverflow.ellipsis,
                        ),
                      )
                      .toList(),
                  items: _clients
                      .map(
                        (client) => DropdownMenuItem<QbClientConfig>(
                          value: client,
                          child: Text(
                            '${client.name} (${client.host}:${client.port})',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (client) {
                    setState(() {
                      _selectedClient = client;
                      _selectedCategory = null;
                      _selectedTags.clear();
                      _categories.clear();
                      _tags.clear();
                    });
                    if (client != null) _loadCategoriesAndTags();
                  },
                ),
                const SizedBox(height: 16),

                // 选择分类
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '分类',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    ),
                    if (_loading)
                      const SizedBox(
                        height: 16,
                        width: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    if (!_loading)
                      IconButton(
                        onPressed: _refreshCategoriesAndTags,
                        icon: const Icon(Icons.refresh, size: 20),
                        tooltip: '刷新',
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String?>(
                  initialValue: _selectedCategory,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    isDense: true,
                    hintText: '选择分类（可选）',
                  ),
                  isExpanded: true,
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('不使用分类'),
                    ),
                    ..._categories.map(
                      (cat) => DropdownMenuItem<String?>(
                        value: cat,
                        child: Text(cat, overflow: TextOverflow.ellipsis),
                      ),
                    ),
                  ],
                  onChanged: (cat) => setState(() => _selectedCategory = cat),
                ),
                const SizedBox(height: 16),

                // 选择标签
                Text('标签', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                if (_tags.isEmpty)
                  const Text('暂无可用标签', style: TextStyle(color: Colors.grey))
                else
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: _tags.map((tag) {
                      final selected = _selectedTags.contains(tag);
                      return FilterChip(
                        label: Text(tag),
                        selected: selected,
                        onSelected: (sel) {
                          setState(() {
                            if (sel) {
                              _selectedTags.add(tag);
                            } else {
                              _selectedTags.remove(tag);
                            }
                          });
                        },
                      );
                    }).toList(),
                  ),
                const SizedBox(height: 16),

                // 保存路径
                Text('保存路径', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                TextField(
                  controller: _savePathCtrl,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    isDense: true,
                    hintText: '留空使用默认路径',
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '提示：选择分类时将启用自动管理模式',
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: Colors.grey),
                ),

                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Text(
                      _error!,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(onPressed: _onSubmit, child: const Text('开始下载')),
      ],
    );
  }
}
