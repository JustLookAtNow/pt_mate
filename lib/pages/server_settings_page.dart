import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:io';
import 'dart:math';
import '../models/app_models.dart';
import '../services/storage/storage_service.dart';
import '../services/api/api_service.dart';
import '../utils/screen_utils.dart';
import '../services/site_config_service.dart';
import '../widgets/qb_speed_indicator.dart';
import '../widgets/nexusphp_web_login.dart';
import '../widgets/responsive_layout.dart';

import '../utils/format.dart';
import '../app.dart';

class _HealthStatus {
  final bool ok;
  final String? message;
  final String? username;
  final MemberProfile? profile;
  final DateTime updatedAt;
  const _HealthStatus({
    required this.ok,
    this.message,
    this.username,
    this.profile,
    required this.updatedAt,
  });

  factory _HealthStatus.fromJson(Map<String, dynamic> json) {
    final ok = json['ok'] == true || json['ok'] == 'true';
    final message = json['message']?.toString();
    final username = json['username']?.toString();
    final updatedAtStr = json['updatedAt']?.toString();
    DateTime updatedAt;
    try {
      updatedAt = DateTime.parse(
        updatedAtStr ?? DateTime.now().toIso8601String(),
      );
    } catch (_) {
      updatedAt = DateTime.now();
    }
    MemberProfile? profile;
    final p = json['profile'];
    if (p is Map<String, dynamic>) {
      try {
        profile = MemberProfile.fromJson(p);
      } catch (_) {
        profile = null;
      }
    }
    return _HealthStatus(
      ok: ok,
      message: message,
      username: username,
      profile: profile,
      updatedAt: updatedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'ok': ok,
      'message': message,
      'username': username,
      'profile': profile?.toJson(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }
}

/// 解析 "yyyy-MM-dd HH:mm:ss" 格式的时间字符串
// _parseLastAccess 已废弃，字段现为 DateTime 类型

/// 判断最后访问时间是否超过一个月
bool _isLastAccessOverMonth(DateTime? lastAccess) {
  if (lastAccess == null) return false;
  final now = DateTime.now();
  return now.difference(lastAccess).inDays >= 30;
}

// 站点排序下拉功能已移除

class ServerSettingsPage extends StatefulWidget {
  const ServerSettingsPage({super.key});

  @override
  State<ServerSettingsPage> createState() => _ServerSettingsPageState();
}

class _ServerSettingsPageState extends State<ServerSettingsPage> {
  List<SiteConfig> _sites = [];
  String? _activeSiteId;
  bool _loading = true;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  String _searchQuery = '';
  bool _healthChecking = false;
  Map<String, _HealthStatus> _healthStatuses = {}; // siteId -> status
  // 排序状态已移除
  bool _reorderMode = false;
  List<SiteConfig> _sitesBackup = [];

  // 站点图标路径缓存：siteId -> asset path
  final Map<String, String> _logoPathCache = {};

  Future<String> _resolveLogoPath(SiteConfig site) async {
    // 命中缓存直接返回
    final cached = _logoPathCache[site.id];
    if (cached != null && cached.isNotEmpty) return cached;

    // 默认回退图标
    String path = 'assets/sites_icon/_default_nexusphp.png';
    try {
      // 通过模板ID加载模板以获取可选的 logo 字段
      final template = await SiteConfigService.getTemplateById(
        site.templateId,
        site.siteType,
      );
      final logo = template?.logo;
      if (logo != null && logo.isNotEmpty) {
        // 统一使用 PNG：如果不是以 .png 结尾，尝试替换为 .png
        final lower = logo.toLowerCase();
        path = lower.endsWith('.png')
            ? logo
            : (logo.contains('.')
                  ? '${logo.substring(0, logo.lastIndexOf('.'))}.png'
                  : logo);
      }
    } catch (_) {
      // 静默失败，使用默认图标
    }

    _logoPathCache[site.id] = path;
    return path;
  }

  @override
  void initState() {
    super.initState();
    _loadSites();
    _searchFocusNode.addListener(_onSearchFocusChange);
  }

  void _onSearchFocusChange() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.removeListener(_onSearchFocusChange);
    _searchFocusNode.dispose();
    super.dispose();
  }

  // 简单的健康状态模型

  Future<void> _loadSites() async {
    setState(() => _loading = true);
    try {
      var sites = await StorageService.instance.loadSiteConfigs();
      // 若没有配置颜色则生成哈希色并持久化（只持久化颜色，不改其他字段）
      bool needPersist = false;
      sites = sites.map((s) {
        if (s.siteColor == null) {
          final primaries = Colors.primaries;
          final color = primaries[(s.id.hashCode.abs()) % primaries.length];
          needPersist = true;
          return s.copyWith(siteColor: color.toARGB32());
        }
        return s;
      }).toList();
      if (needPersist) {
        // 仅更新颜色，避免覆盖 apiKey：saveSiteConfigs 会正确分离持久化
        await StorageService.instance.saveSiteConfigs(sites);
      }
      final activeSiteId = await StorageService.instance.getActiveSiteId();
      setState(() {
        _sites = sites;
        _activeSiteId = activeSiteId;
      });
      // 加载已缓存的健康检查结果；若无缓存则自动触发一次刷新
      await _loadCachedHealthStatuses(triggerRefreshWhenEmpty: true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '加载站点配置失败: $e',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onErrorContainer,
              ),
            ),
            backgroundColor: Theme.of(context).colorScheme.errorContainer,
            behavior: SnackBarBehavior.fixed,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadCachedHealthStatuses({
    bool triggerRefreshWhenEmpty = false,
  }) async {
    try {
      final map = await StorageService.instance.loadHealthStatuses();
      if (mounted) {
        setState(() {
          _healthStatuses = map.map(
            (siteId, json) => MapEntry(siteId, _HealthStatus.fromJson(json)),
          );
        });
      }
      // 若需要在无缓存时自动刷新，且当前未在刷新过程中
      if (triggerRefreshWhenEmpty &&
          _healthStatuses.isEmpty &&
          !_healthChecking) {
        // 站点列表为空时不触发，等待站点加载完成再触发
        if (_sites.isNotEmpty) {
          _runHealthCheck();
        }
      }
    } catch (_) {
      // ignore read errors
    }
  }

  List<SiteConfig> get _filteredSites {
    if (_searchQuery.trim().isEmpty) return _sites;
    final q = _searchQuery.trim().toLowerCase();
    return _sites.where((s) {
      return s.name.toLowerCase().contains(q) ||
          s.baseUrl.toLowerCase().contains(q) ||
          s.siteType.displayName.toLowerCase().contains(q);
    }).toList();
  }

  Future<void> _runHealthCheck() async {
    if (_healthChecking) return;
    setState(() {
      _healthChecking = true;
      _healthStatuses = {};
    });

    // 加载包含API Key的站点，以便调用用户资料接口
    final allSites = await StorageService.instance.loadSiteConfigs(
      includeApiKeys: true,
    );
    final targetSites = _filteredSites.map((s) {
      final found = allSites.firstWhere((x) => x.id == s.id, orElse: () => s);
      return found;
    }).toList();

    // 并发控制：借鉴聚合搜索的思路，按线程数限制并发
    final settings = await StorageService.instance
        .loadAggregateSearchSettings();
    final maxConcurrency = settings.searchThreads;

    int index = 0;
    int active = 0;

    Future<void> startNext() async {
      while (active < maxConcurrency && index < targetSites.length) {
        final site = targetSites[index++];
        active++;
        _checkSingleSite(site)
            .then((status) {
              if (mounted) {
                setState(() {
                  _healthStatuses[site.id] = status;
                });
              }
            })
            .catchError((error) {
              if (mounted) {
                setState(() {
                  _healthStatuses[site.id] = _HealthStatus(
                    ok: false,
                    message: error.toString(),
                    username: null,
                    updatedAt: DateTime.now(),
                  );
                });
              }
            })
            .whenComplete(() async {
              active--;
              // 继续下一个
              startNext();
              // 如果全部完成，结束检查
              if (index >= targetSites.length && active == 0) {
                if (mounted) {
                  setState(() {
                    _healthChecking = false;
                  });
                  // 持久化健康检查结果
                  try {
                    final jsonMap = _healthStatuses.map(
                      (siteId, status) => MapEntry(siteId, status.toJson()),
                    );
                    await StorageService.instance.saveHealthStatuses(jsonMap);
                  } catch (_) {
                    // ignore save errors
                  }
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        '站点信息获取完成',
                        style: TextStyle(
                          color: Theme.of(
                            context,
                          ).colorScheme.onPrimaryContainer,
                        ),
                      ),
                      backgroundColor: Theme.of(
                        context,
                      ).colorScheme.primaryContainer,
                      behavior: SnackBarBehavior.fixed,
                    ),
                  );
                }
              }
            });
      }
    }

    await startNext();
  }

  Future<_HealthStatus> _checkSingleSite(SiteConfig site) async {
    // 仅在站点支持用户资料时进行检查，其他标记为不支持
    if (!site.features.supportMemberProfile) {
      return _HealthStatus(
        ok: false,
        message: '站点不支持用户资料接口',
        username: null,
        profile: null,
        updatedAt: DateTime.now(),
      );
    }
    try {
      final adapter = await ApiService.instance.getAdapter(site);
      final profile = await adapter.fetchMemberProfile(apiKey: site.apiKey);
      return _HealthStatus(
        ok: true,
        message: '正常',
        username: profile.username,
        profile: profile,
        updatedAt: DateTime.now(),
      );
    } catch (e) {
      return _HealthStatus(
        ok: false,
        message: e.toString(),
        username: null,
        profile: null,
        updatedAt: DateTime.now(),
      );
    }
  }

  Future<void> _setActiveSite(String siteId) async {
    if (!mounted) return;
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final appState = context.read<AppState>();

    try {
      await appState.setActiveSite(siteId);
      setState(() => _activeSiteId = siteId);
      if (mounted) {
        scaffoldMessenger.showSnackBar(
          SnackBar(
            content: Text(
              '已切换活跃站点',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onPrimaryContainer,
              ),
            ),
            backgroundColor: Theme.of(context).colorScheme.primaryContainer,
            behavior: SnackBarBehavior.fixed,
          ),
        );

        // 切换站点成功后跳转回首页
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    } catch (e) {
      if (mounted) {
        scaffoldMessenger.showSnackBar(
          SnackBar(
            content: Text(
              '切换站点失败: $e',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onErrorContainer,
              ),
            ),
            backgroundColor: Theme.of(context).colorScheme.errorContainer,
            behavior: SnackBarBehavior.fixed,
          ),
        );
      }
    }
  }

  Future<void> _deleteSite(SiteConfig site) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定要删除站点 "${site.name}" 吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            style: TextButton.styleFrom(
              side: BorderSide(
                color: Theme.of(context).colorScheme.outline,
                width: 1.0,
              ),
            ),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await StorageService.instance.deleteSiteConfig(site.id);
        await _loadSites();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '站点已删除',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                ),
              ),
              backgroundColor: Theme.of(context).colorScheme.primaryContainer,
              behavior: SnackBarBehavior.fixed,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '删除站点失败: $e',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onErrorContainer,
                ),
              ),
              backgroundColor: Theme.of(context).colorScheme.errorContainer,
              behavior: SnackBarBehavior.fixed,
            ),
          );
        }
      }
    }
  }

  void _addSite() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => SiteEditPage(
          onSaved: () {
            _loadSites();
          },
        ),
      ),
    );
  }

  void _editSite(SiteConfig site) async {
    // 编辑前加载包含 API Key 的完整站点配置，以便预填充密钥等敏感信息
    final allSites = await StorageService.instance.loadSiteConfigs(
      includeApiKeys: true,
    );
    final fullSite = allSites.firstWhere(
      (s) => s.id == site.id,
      orElse: () => site,
    );

    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => SiteEditPage(
          site: fullSite,
          onSaved: () {
            _loadSites();
          },
        ),
      ),
    );
  }

  // 小屏长按弹菜单；大屏右侧按钮使用此数据源
  void _showSiteMenu(SiteConfig site, bool isActive) {
    showModalBottomSheet<void>(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!isActive)
                ListTile(
                  leading: const Icon(Icons.radio_button_checked),
                  title: const Text('设为当前'),
                  onTap: () {
                    Navigator.pop(context);
                    _setActiveSite(site.id);
                  },
                ),
              ListTile(
                leading: const Icon(Icons.refresh),
                title: const Text('刷新站点'),
                onTap: () async {
                  Navigator.pop(context);
                  await _refreshSingleSite(site);
                },
              ),
              ListTile(
                leading: const Icon(Icons.edit),
                title: const Text('编辑'),
                onTap: () {
                  Navigator.pop(context);
                  _editSite(site);
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete),
                title: const Text('删除'),
                onTap: () {
                  Navigator.pop(context);
                  _deleteSite(site);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  // 大屏右侧菜单按钮
  Widget _buildSiteMenuButton(SiteConfig site, bool isActive) {
    return PopupMenuButton<String>(
      onSelected: (value) async {
        switch (value) {
          case 'activate':
            _setActiveSite(site.id);
            break;
          case 'refresh':
            await _refreshSingleSite(site);
            break;
          case 'edit':
            _editSite(site);
            break;
          case 'delete':
            _deleteSite(site);
            break;
        }
      },
      itemBuilder: (context) => [
        if (!isActive)
          const PopupMenuItem(
            value: 'activate',
            child: ListTile(
              leading: Icon(Icons.radio_button_checked),
              title: Text('设为当前'),
              contentPadding: EdgeInsets.zero,
            ),
          ),
        const PopupMenuItem(
          value: 'refresh',
          child: ListTile(
            leading: Icon(Icons.refresh),
            title: Text('刷新站点'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        const PopupMenuItem(
          value: 'edit',
          child: ListTile(
            leading: Icon(Icons.edit),
            title: Text('编辑'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        const PopupMenuItem(
          value: 'delete',
          child: ListTile(
            leading: Icon(Icons.delete),
            title: Text('删除'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
      ],
    );
  }

  // 构建单个滑动作按钮
  Widget _buildSwipeActionBtn({
    required BuildContext context,
    required Color color,
    required IconData icon,
    required String text,
    required VoidCallback onTap,
  }) {
    return Container(
      width: 60,
      margin: const EdgeInsets.only(left: 4),
      child: Material(
        color: color,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: Colors.white, size: 20),
              const SizedBox(height: 2),
              Text(
                text,
                style: const TextStyle(color: Colors.white, fontSize: 10),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // 构建站点列表项的左滑菜单按钮
  List<Widget> _buildSwipeActions(
    BuildContext context,
    SiteConfig site,
    bool isActive,
  ) {
    final actions = <Widget>[];

    // Refresh
    actions.add(
      _buildSwipeActionBtn(
        context: context,
        color: Theme.of(context).colorScheme.primary,
        icon: Icons.refresh,
        text: '刷新',
        onTap: () => _refreshSingleSite(site),
      ),
    );

    // Edit
    actions.add(
      _buildSwipeActionBtn(
        context: context,
        color: Colors.amber[700]!,
        icon: Icons.edit,
        text: '编辑',
        onTap: () => _editSite(site),
      ),
    );

    // Delete
    actions.add(
      _buildSwipeActionBtn(
        context: context,
        color: Colors.red,
        icon: Icons.delete,
        text: '删除',
        onTap: () => _deleteSite(site),
      ),
    );

    return actions;
  }

  Future<void> _refreshSingleSite(SiteConfig site) async {
    if (!mounted) return;
    final theme = Theme.of(context);
    try {
      final activeId = await StorageService.instance.getActiveSiteId();
      if (activeId == site.id) {
        ApiService.instance.removeAdapter(site.id);
        final activeSite = await StorageService.instance.getActiveSiteConfig();
        if (activeSite == null) {
          throw Exception('未找到活跃站点配置');
        }
        await ApiService.instance.setActiveSite(activeSite);

        try {
          final profile = await ApiService.instance.fetchMemberProfile();
          setState(() {
            _healthStatuses[site.id] = _HealthStatus(
              ok: true,
              message: '正常',
              username: profile.username,
              profile: profile,
              updatedAt: DateTime.now(),
            );
          });
          await StorageService.instance.saveHealthStatuses(
            _healthStatuses.map((k, v) => MapEntry(k, v.toJson())),
          );
        } catch (e) {
          setState(() {
            _healthStatuses[site.id] = _HealthStatus(
              ok: false,
              message: e.toString(),
              username: null,
              profile: null,
              updatedAt: DateTime.now(),
            );
          });
          await StorageService.instance.saveHealthStatuses(
            _healthStatuses.map((k, v) => MapEntry(k, v.toJson())),
          );
        }
      } else {
        final allSites = await StorageService.instance.loadSiteConfigs(
          includeApiKeys: true,
        );
        final fullSite = allSites.firstWhere(
          (s) => s.id == site.id,
          orElse: () => site,
        );
        final status = await _checkSingleSite(fullSite);
        setState(() {
          _healthStatuses[site.id] = status;
        });
        await StorageService.instance.saveHealthStatuses(
          _healthStatuses.map((k, v) => MapEntry(k, v.toJson())),
        );
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '站点已刷新',
            style: TextStyle(color: theme.colorScheme.onPrimaryContainer),
          ),
          backgroundColor: theme.colorScheme.primaryContainer,
          behavior: SnackBarBehavior.fixed,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '刷新失败: $e',
            style: TextStyle(color: theme.colorScheme.onErrorContainer),
          ),
          backgroundColor: theme.colorScheme.errorContainer,
          behavior: SnackBarBehavior.fixed,
        ),
      );
    }
  }

  Widget _buildEmptyState() {
    return Expanded(
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.dns_outlined,
              size: 64,
              color: Theme.of(context).colorScheme.outline,
            ),
            const SizedBox(height: 16),
            Text(
              '暂无站点配置',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: Theme.of(context).colorScheme.outline,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '点击右下角按钮添加第一个服务器',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.outline,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSiteList() {
    return Expanded(
      child: _reorderMode
          ? ReorderableListView.builder(
              buildDefaultDragHandles: false,
              padding: const EdgeInsets.all(16),
              itemCount: _sites.length,
              onReorder: (oldIndex, newIndex) {
                setState(() {
                  if (newIndex > oldIndex) newIndex -= 1;
                  final item = _sites.removeAt(oldIndex);
                  _sites.insert(newIndex, item);
                });
              },
              itemBuilder: (context, index) => _buildSiteItem(index),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _filteredSites.length,
              itemBuilder: (context, index) {
                final site = _filteredSites[index];
                final isActive = site.id == _activeSiteId;
                return _buildSiteCard(site, isActive);
              },
            ),
    );
  }

  Widget _buildSiteItem(int index) {
    final site = _sites[index];
    final isActive = site.id == _activeSiteId;
    final Color? siteColor = site.siteColor != null
        ? Color(site.siteColor!)
        : null;
    return Container(
      key: ValueKey('site_${site.id}'),
      margin: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: isActive
            ? Theme.of(
                context,
              ).colorScheme.primaryContainer.withOpacity(0.3)
            : Theme.of(context).colorScheme.surface,
        shape: RoundedRectangleBorder(
          side: BorderSide(
            color: siteColor ?? Theme.of(context).colorScheme.outline,
            width: 2.0,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: ListTile(
          title: Text(site.name, overflow: TextOverflow.ellipsis),
          subtitle: Text(
            site.baseUrl,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: ReorderableDragStartListener(
            index: index,
            child: const Icon(Icons.drag_handle),
          ),
        ),
      ),
    );
  }

  Widget _buildSiteCard(SiteConfig site, bool isActive) {
    final Color? siteColor = site.siteColor != null
        ? Color(site.siteColor!)
        : null;
    final hs = _healthStatuses[site.id];

    final card = Card(
      elevation: 2,
      shadowColor: (siteColor ?? Theme.of(context).colorScheme.outline)
          .withOpacity(0.4),
      shape: RoundedRectangleBorder(
        side: BorderSide(
          color: siteColor ?? Theme.of(context).colorScheme.outline,
          width: 2.0,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      margin: const EdgeInsets.only(bottom: 8),
      color: isActive
          ? Theme.of(
              context,
            ).colorScheme.primaryContainer.withOpacity(0.3)
          : null,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Builder(
            builder: (context) {
              final isLarge = ScreenUtils.isLargeScreen(context);
              return InkWell(
                onTap: isActive ? null : () => _setActiveSite(site.id),
                onLongPress: isLarge
                    ? null
                    : () => _showSiteMenu(site, isActive),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                CircleAvatar(
                                  radius: 14,
                                  backgroundColor: isActive
                                      ? Theme.of(context).colorScheme.primary
                                      : Theme.of(
                                          context,
                                        ).colorScheme.surfaceContainerHighest,
                                  child: FutureBuilder<String>(
                                    future: _resolveLogoPath(site),
                                    builder: (context, snapshot) {
                                      final Color fgColor = isActive
                                          ? Theme.of(
                                              context,
                                            ).colorScheme.onPrimary
                                          : Theme.of(
                                              context,
                                            ).colorScheme.onSurfaceVariant;
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

                                      final String path = snapshot.data!;
                                      return ClipOval(
                                        child: Image.asset(
                                          path,
                                          width: 24,
                                          height: 24,
                                          fit: BoxFit.cover,
                                          errorBuilder:
                                              (context, error, stackTrace) {
                                                return Image.asset(
                                                  'assets/sites_icon/_default_nexusphp.png',
                                                  width: 24,
                                                  height: 24,
                                                  fit: BoxFit.cover,
                                                );
                                              },
                                        ),
                                      );
                                    },
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.start,
                                    children: [
                                      Flexible(
                                        child: Text(
                                          site.name,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                      if (hs?.profile?.lastAccess != null &&
                                          _isLastAccessOverMonth(
                                            hs!.profile!.lastAccess,
                                          )) ...[
                                        Padding(
                                          padding: const EdgeInsets.only(
                                            left: 6,
                                          ),
                                          child: Tooltip(
                                            message: '超过一个月未登录',
                                            child: Icon(
                                              Icons.priority_high,
                                              color: Theme.of(
                                                context,
                                              ).colorScheme.error,
                                              size: 18,
                                            ),
                                          ),
                                        ),
                                      ],
                                      const SizedBox(width: 8),
                                    ],
                                  ),
                                ),
                                Text(
                                  hs?.username ?? '',
                                  style: Theme.of(context).textTheme.bodyMedium
                                      ?.copyWith(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.primary,
                                      ),
                                ),
                                if (hs != null)
                                  Text(
                                    '(${Formatters.formatTorrentCreatedDate(hs.updatedAt)})',
                                    style: Theme.of(context).textTheme.bodySmall
                                        ?.copyWith(
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.onSurfaceVariant,
                                        ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            if (hs != null) _buildHealthStatus(site, hs),
                          ],
                        ),
                      ),
                      if (isLarge) _buildSiteMenuButton(site, isActive),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );

    // Mobile swipe
    if (!ScreenUtils.isLargeScreen(context)) {
      return _SwipeableSiteItem(
        actions: _buildSwipeActions(context, site, isActive),
        onTap: isActive ? null : () => _setActiveSite(site.id),
        // Keep null or use _showSiteMenu if user still wants it on long press,
        // but typically swipe replaces it. Requirement says "change to left slide".
        onLongPress: null,
        child: card,
      );
    }

    return card;
  }

  Widget _buildHealthStatus(SiteConfig site, _HealthStatus hs) {
    return Builder(
      builder: (context) {
        if (hs.ok && hs.profile != null) {
          final p = hs.profile!;
          Widget buildItem(IconData icon, Color color, String label) {
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 14, color: color),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(height: 1.0),
                  ),
                ),
              ],
            );
          }

          final items = <Widget>[
            buildItem(
              Icons.stars,
              Theme.of(context).colorScheme.primary,
              '${Formatters.bonus(p.bonus)}${p.bonusPerHour != null ? '(${ScreenUtils.isLargeScreen(context) ? p.bonusPerHour! : p.bonusPerHour!.toInt()})' : ''}',
            ),
            buildItem(Icons.upload, Colors.green, p.uploadedBytesString),
            buildItem(Icons.download, Colors.red, p.downloadedBytesString),
            buildItem(
              Icons.trending_up,
              Theme.of(context).colorScheme.primary,
              p.shareRate.toStringAsFixed(2),
            ),
            if (p.seedingSizeBytes != null)
              buildItem(
                Icons.cloud_upload,
                Theme.of(context).colorScheme.primary,
                Formatters.dataFromBytes(p.seedingSizeBytes!),
              ),
            if (p.lastAccess != null)
              buildItem(
                Icons.schedule,
                Theme.of(context).colorScheme.primary,
                p.lastAccess?.toIso8601String().substring(0, 10) ?? '',
              ),
          ];

          final isLarge = ScreenUtils.isLargeScreen(context);
          if (isLarge) {
            return Row(
              children: [
                for (int i = 0; i < items.length; i++) ...[
                  items[i],
                  if (i != items.length - 1)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8.0),
                      child: Text(
                        '•',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                ],
              ],
            );
          } else {
            return GridView.count(
              crossAxisCount: 3,
              crossAxisSpacing: 6,
              mainAxisSpacing: 6,
              childAspectRatio: 8.0,
              padding: EdgeInsets.zero,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              children: items,
            );
          }
        } else {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              IconButton(
                icon: const Icon(
                  Icons.error_outline,
                  size: 18,
                  color: Colors.red,
                ),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: () {
                  final msg = hs.message ?? '异常';
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      backgroundColor: Theme.of(
                        context,
                      ).colorScheme.errorContainer,
                      content: Text(
                        msg,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onErrorContainer,
                        ),
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '请求失败，请检查站点状态，点击感叹号查看详情',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
          );
        }
      },
    );
  }

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _searchController,
              focusNode: _searchFocusNode,
              onChanged: (val) {
                setState(() {
                  _searchQuery = val;
                });
              },
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search, size: 20),
                prefixIconConstraints: const BoxConstraints(
                  minWidth: 36,
                  minHeight: 36,
                ),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(25)),
                  borderSide: BorderSide(
                    color: Theme.of(
                      context,
                    ).colorScheme.primary.withValues(alpha: 0.3),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          if (_reorderMode)
            Row(
              children: [
                FilledButton.icon(
                  onPressed: () async {
                    final messenger = ScaffoldMessenger.of(context);
                    final theme = Theme.of(context);
                    try {
                      await StorageService.instance.saveSiteConfigs(
                        _sites.map((c) => c.copyWith(apiKey: null)).toList(),
                      );
                      messenger.showSnackBar(
                        SnackBar(
                          content: Text(
                            '已保存自定义排序',
                            style: TextStyle(
                              color: theme.colorScheme.onPrimaryContainer,
                            ),
                          ),
                          backgroundColor: theme.colorScheme.primaryContainer,
                          behavior: SnackBarBehavior.fixed,
                        ),
                      );
                    } catch (e) {
                      messenger.showSnackBar(
                        SnackBar(
                          content: Text(
                            '保存失败: $e',
                            style: TextStyle(
                              color: theme.colorScheme.onErrorContainer,
                            ),
                          ),
                          backgroundColor: theme.colorScheme.errorContainer,
                          behavior: SnackBarBehavior.fixed,
                        ),
                      );
                    } finally {
                      if (mounted) {
                        setState(() {
                          _reorderMode = false;
                          _sitesBackup = [];
                        });
                      }
                    }
                  },
                  icon: const Icon(Icons.check),
                  label: const Text('完成'),
                ),
                const SizedBox(width: 8),
                TextButton.icon(
                  onPressed: () {
                    if (!mounted) return;
                    setState(() {
                      if (_sitesBackup.isNotEmpty) {
                        _sites = List<SiteConfig>.from(_sitesBackup);
                      }
                      _reorderMode = false;
                      _sitesBackup = [];
                    });
                  },
                  icon: const Icon(Icons.close),
                  label: const Text('取消'),
                  style: TextButton.styleFrom(
                    side: BorderSide(
                      color: Theme.of(context).colorScheme.outline,
                      width: 1.0,
                    ),
                  ),
                ),
              ],
            )
          else if (ScreenUtils.isLargeScreen(context) ||
              !_searchFocusNode.hasFocus) ...[
            FilledButton.icon(
              onPressed: _addSite,
              icon: const Icon(Icons.add),
              label: const Text('新增'),
            ),
            const SizedBox(width: 12),
            FilledButton.icon(
              onPressed: _healthChecking ? null : _runHealthCheck,
              icon: const Icon(Icons.refresh),
              label: Text(_healthChecking ? '刷新中…' : '刷新'),
            ),
            const SizedBox(width: 12),
            Builder(
              builder: (context) {
                final isLarge = ScreenUtils.isLargeScreen(context);
                if (isLarge) {
                  return FilledButton.tonalIcon(
                    onPressed: () {
                      setState(() {
                        _sitesBackup = List<SiteConfig>.from(_sites);
                        _reorderMode = true;
                      });
                    },
                    icon: const Icon(Icons.drag_indicator),
                    label: const Text('排序'),
                  );
                } else {
                  return IconButton.filledTonal(
                    onPressed: () {
                      setState(() {
                        _sitesBackup = List<SiteConfig>.from(_sites);
                        _reorderMode = true;
                      });
                    },
                    icon: const Icon(Icons.drag_indicator),
                    tooltip: '排序',
                  );
                }
              },
            ),
          ],
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(BuildContext context) {
    return AppBar(
      title: const Text('站点配置'),
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
    );
  }

  @override
  Widget build(BuildContext context) {
    return ResponsiveLayout(
      currentRoute: '/server_settings',
      appBar: _buildAppBar(context),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : PopScope(
              canPop: !_searchFocusNode.hasFocus,
              onPopInvokedWithResult: (didPop, result) {
                if (didPop) return;
                if (_searchFocusNode.hasFocus) {
                  _searchFocusNode.unfocus();
                }
              },
              child: Column(
                children: [
                  _buildTopBar(),
                  if (_sites.isEmpty) _buildEmptyState() else _buildSiteList(),
                ],
              ),
            ),
    );
  }
}

class _CategoryEditDialog extends StatefulWidget {
  final SearchCategoryConfig category;

  const _CategoryEditDialog({required this.category});

  @override
  State<_CategoryEditDialog> createState() => _CategoryEditDialogState();
}

class _CategoryEditDialogState extends State<_CategoryEditDialog> {
  late TextEditingController _nameController;
  late TextEditingController _parametersController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.category.displayName);
    _parametersController = TextEditingController(
      text: widget.category.parameters,
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _parametersController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('编辑分类'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: '显示名称',
                hintText: '例如：综合',
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _parametersController,
              decoration: const InputDecoration(
                labelText: '请求参数',
                hintText:
                    '推荐JSON格式：{"mode": "normal", "teams": ["44", "9", "43"]}',
              ),
              maxLines: 4,
            ),
            const SizedBox(height: 16),
            const Text(
              '参数格式说明：\n'
              '• 推荐JSON格式：{"mode": "normal", "teams": ["44", "9", "43"]}\n'
              '• 键值对格式：mode: normal; teams: ["44", "9", "43"]\n'
              '• JSON格式支持复杂数据结构，避免解析错误\n'
              '• 键值对格式用分号分隔，避免数组参数被错误分割',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
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
            final name = _nameController.text.trim();
            final parameters = _parametersController.text.trim();
            if (name.isEmpty || parameters.isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    '请填写完整信息',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onErrorContainer,
                    ),
                  ),
                  backgroundColor: Theme.of(context).colorScheme.errorContainer,
                  behavior: SnackBarBehavior.fixed,
                ),
              );
              return;
            }
            final result = widget.category.copyWith(
              displayName: name,
              parameters: parameters,
            );
            Navigator.pop(context, result);
          },
          child: const Text('确定'),
        ),
      ],
    );
  }
}

class SiteEditPage extends StatefulWidget {
  final SiteConfig? site;
  final VoidCallback? onSaved;

  const SiteEditPage({super.key, this.site, this.onSaved});

  @override
  State<SiteEditPage> createState() => _SiteEditPageState();
}

class _SiteEditPageState extends State<SiteEditPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _baseUrlController = TextEditingController();
  final _apiKeyController = TextEditingController();
  final _passKeyController = TextEditingController();
  final _cookieController = TextEditingController(); // 手工输入cookie的控制器
  final _presetSearchController = TextEditingController(); // 预设站点搜索控制器

  SiteType? _selectedSiteType;
  bool _loading = false;
  String? _error;

  List<SearchCategoryConfig> _searchCategories = [];
  SiteFeatures _siteFeatures = SiteFeatures.mteamDefault;
  List<SiteConfigTemplate> _presetTemplates = []; // 预设站点模板列表
  List<SiteConfigTemplate> _filteredPresetTemplates = []; // 过滤后的预设站点模板列表
  String? _cookieStatus; // 登录状态信息
  String? _savedCookie; // 保存的cookie
  bool _isCustomSite = true; // 是否选择自定义站点
  bool _hasUserMadeSelection = false; // 用户是否已经做出选择（预设或自定义）
  String? _selectedTemplateUrl; // 从多URL模板中选择的URL
  bool _showPresetList = true; // 控制预设站点列表的显示/隐藏
  bool _showManualCookieInput = false; // 是否展示手动输入cookie框
  Color? _siteColor; // 站点颜色（编辑页）

  @override
  void initState() {
    super.initState();

    // 如果是编辑模式，默认不展开预设站点列表
    if (widget.site != null) {
      _showPresetList = false;
    }

    _loadPresetSites();

    // 添加预设站点搜索监听器
    _presetSearchController.addListener(_filterPresetSites);

    if (widget.site != null) {
      // 编辑现有站点时，先保存原始数据，但不立即填充到UI字段
      _apiKeyController.text = widget.site!.apiKey ?? '';
      _passKeyController.text = widget.site!.passKey ?? '';
      _cookieController.text = widget.site!.cookie ?? '';
      _selectedSiteType = widget.site!.siteType;
      _searchCategories = List.from(widget.site!.searchCategories);
      _siteFeatures = widget.site!.features;
      _savedCookie = widget.site!.cookie;
      _siteColor = widget.site!.siteColor != null
          ? Color(widget.site!.siteColor!)
          : null;

      // 检查是否是预设站点，这会根据检测结果填充相应字段
      _checkIfPresetSite();
    } else {
      // 新建站点时，查询分类配置初始为空，字段保持空白
      _searchCategories = [];
      _hasUserMadeSelection = false; // 新建站点时用户还未做出选择
      // 不设置默认的 _selectedSiteType，让用户选择后再设置
      _siteColor = null;
    }
  }

  Future<void> _loadPresetSites() async {
    try {
      final templates = await SiteConfigService.loadPresetSiteTemplates();
      setState(() {
        _presetTemplates = templates;
        _filteredPresetTemplates = templates; // 初始化过滤模板列表
      });
    } catch (e) {
      // 加载失败时使用空列表
      setState(() {
        _presetTemplates = [];
        _filteredPresetTemplates = [];
      });
    }
  }

  void _filterPresetSites() {
    final query = _presetSearchController.text.toLowerCase();
    setState(() {
      if (query.isEmpty) {
        _filteredPresetTemplates = _presetTemplates
            .where((template) => template.isShow)
            .toList();
      } else {
        _filteredPresetTemplates = _presetTemplates.where((template) {
          return template.isShow &&
              (template.name.toLowerCase().contains(query) ||
                  template.baseUrls.any(
                    (url) => url.toLowerCase().contains(query),
                  ) ||
                  template.siteType.displayName.toLowerCase().contains(query));
        }).toList();
      }
    });
  }

  void _checkIfPresetSite() {
    if (widget.site != null) {
      bool foundPreset = false;

      // 检查模板格式（所有预设站点现在都是模板格式）
      for (final template in _presetTemplates) {
        if (template.baseUrls.contains(widget.site!.baseUrl)) {
          setState(() {
            _isCustomSite = false;
            _selectedSiteType = template.siteType;
            _hasUserMadeSelection = true;
            _selectedTemplateUrl = widget.site!.baseUrl;
            // 填充模板信息
            _nameController.text = template.name;
            _baseUrlController.text = widget.site!.baseUrl;
          });
          foundPreset = true;
          break;
        }
      }

      // 如果没有找到匹配的预设站点，则设为自定义，填充原始站点信息
      if (!foundPreset) {
        setState(() {
          _isCustomSite = true;
          _selectedTemplateUrl = null;
          _hasUserMadeSelection = true; // 编辑现有站点时用户已经有选择
          // 填充原始站点的自定义配置信息
          _nameController.text = widget.site!.name;
          _baseUrlController.text = widget.site!.baseUrl;
        });
      }
    } else {
      // 新建站点时默认为自定义，清空字段
      setState(() {
        _isCustomSite = true;
        _selectedTemplateUrl = null;
        _nameController.clear();
        _baseUrlController.clear();
      });
    }
  }

  void _selectCustomSite() {
    setState(() {
      // 选择自定义 - 清空所有字段
      _isCustomSite = true;
      _selectedTemplateUrl = null;
      _selectedSiteType = SiteType.mteam; // 默认类型
      _searchCategories = [];
      _hasUserMadeSelection = true; // 用户已做出选择
      _loadDefaultFeatures(_selectedSiteType!);

      // 清空自定义字段
      _nameController.clear();
      _baseUrlController.clear();

      // 清空搜索框
      _presetSearchController.clear();

      // 清空之前的错误和用户信息
      _error = null;

    });
  }

  void _selectPresetTemplate(SiteConfigTemplate template, String selectedUrl) {
    setState(() {
      // 选择模板站点 - 填充模板信息
      _isCustomSite = false;
      _selectedTemplateUrl = selectedUrl;
      _selectedSiteType = template.siteType;
      _searchCategories = [];
      _siteFeatures = template.features;
      _hasUserMadeSelection = true; // 用户已做出选择

      // 填充模板站点信息到字段中
      _nameController.text = template.name;
      _baseUrlController.text = selectedUrl;

      // 清空搜索框
      _presetSearchController.clear();

      // 清空之前的错误和用户信息
      _error = null;

    });
  }

  Future<void> _loadDefaultFeatures(SiteType siteType) async {
    try {
      final defaultTemplate = await SiteConfigService.getTemplateById(
        "",
        siteType,
      );
      if (defaultTemplate?.features != null) {
        setState(() {
          _siteFeatures = defaultTemplate!.features;
        });
      } else {
        // 如果没有找到默认模板，使用硬编码的默认值
        setState(() {
          _siteFeatures = siteType == SiteType.nexusphp
              ? const SiteFeatures(
                  supportMemberProfile: true,
                  supportTorrentSearch: true,
                  supportTorrentDetail: true,
                  supportDownload: true,
                  supportCollection: false,
                  supportHistory: false,
                  supportCategories: true,
                  supportAdvancedSearch: true,
                )
              : SiteFeatures.mteamDefault;
        });
      }
    } catch (e) {
      // 加载失败时使用硬编码的默认值
      setState(() {
        _siteFeatures = siteType == SiteType.nexusphp
            ? const SiteFeatures(
                supportMemberProfile: true,
                supportTorrentSearch: true,
                supportTorrentDetail: true,
                supportDownload: true,
                supportCollection: false,
                supportHistory: false,
                supportCategories: true,
                supportAdvancedSearch: true,
              )
            : SiteFeatures.mteamDefault;
      });
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _baseUrlController.dispose();
    _apiKeyController.dispose();
    _passKeyController.dispose();
    _cookieController.dispose();
    _presetSearchController.dispose();
    super.dispose();
  }

  SiteConfig _composeCurrentSite() {
    String id;
    String templateId;

    if (widget.site != null) {
      // 编辑现有站点时，保持原有的 id 和 templateId
      id = widget.site!.id;
      templateId = widget.site!.templateId;
    } else {
      // 新建站点时，生成新的 id 和设置 templateId
      id =
          'site-${DateTime.now().millisecondsSinceEpoch}-${Random().nextInt(1000)}';

      // 根据是否选择预设站点来设置 templateId
      if (!_isCustomSite && _selectedTemplateUrl != null) {
        // 使用模板的 id 作为 templateId
        final template = _presetTemplates.firstWhere(
          (t) => t.baseUrls.contains(_selectedTemplateUrl),
          orElse: () => throw StateError('Template not found for selected URL'),
        );
        templateId = template.id;
      } else {
        // 自定义站点使用 -1 作为 templateId
        templateId = '-1';
      }
    }

    // 如果选择了预设站点（非自定义）
    if (!_isCustomSite && _selectedTemplateUrl != null) {
      // 使用模板站点（所有预设站点现在都是模板格式）
      final template = _presetTemplates.firstWhere(
        (t) => t.baseUrls.contains(_selectedTemplateUrl),
        orElse: () => throw StateError('Template not found for selected URL'),
      );
      return SiteConfig(
        id: id,
        name: template.name,
        baseUrl: _selectedTemplateUrl!,
        apiKey: _apiKeyController.text.trim(),
        passKey: _passKeyController.text.trim().isEmpty
            ? null
            : _passKeyController.text.trim(),
        siteType: template.siteType,
        searchCategories: _searchCategories,
        features: _siteFeatures,
        cookie: template.siteType == SiteType.nexusphpweb ? _savedCookie : null,
        templateId: templateId,
        siteColor: _siteColor?.toARGB32(),
      );
    }

    // 自定义站点配置
    var baseUrl = _baseUrlController.text.trim();
    if (baseUrl.isNotEmpty && !baseUrl.endsWith('/')) {
      baseUrl = '$baseUrl/';
    }

    return SiteConfig(
      id: id,
      name: _nameController.text.trim().isEmpty
          ? '自定义站点'
          : _nameController.text.trim(),
      baseUrl: baseUrl.isEmpty ? 'https://api.m-team.cc/' : baseUrl,
      apiKey: _apiKeyController.text.trim(),
      passKey: _passKeyController.text.trim().isEmpty
          ? null
          : _passKeyController.text.trim(),
      siteType: _selectedSiteType!,
      searchCategories: _searchCategories,
      features: _siteFeatures,
      cookie: _selectedSiteType == SiteType.nexusphpweb ? _savedCookie : null,
      templateId: templateId,
      siteColor: _siteColor?.toARGB32(),
    );
  }

  void _addSearchCategory() {
    setState(() {
      _searchCategories.add(
        SearchCategoryConfig(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          displayName: '新分类',
          parameters: '{"mode": "normal"}',
        ),
      );
    });
  }

  void _editSearchCategory(int index) async {
    final category = _searchCategories[index];
    final result = await showDialog<SearchCategoryConfig>(
      context: context,
      builder: (context) => _CategoryEditDialog(category: category),
    );
    if (result != null) {
      setState(() {
        _searchCategories[index] = result;
      });
    }
  }

  void _deleteSearchCategory(int index) {
    setState(() {
      _searchCategories.removeAt(index);
    });
  }

  Future<void> _resetSearchCategories() async {
    // 检查必要的配置是否完整
    if (_selectedSiteType == SiteType.nexusphpweb) {
      // nexusphpweb类型需要cookie
      if (_savedCookie == null || _savedCookie!.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '请先完成登录获取Cookie',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onErrorContainer,
                ),
              ),
              backgroundColor: Theme.of(context).colorScheme.errorContainer,
              behavior: SnackBarBehavior.fixed,
            ),
          );
        }
        return;
      }
    } else {
      // 其他类型需要API Key
      if (_apiKeyController.text.trim().isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '请先填写API Key',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onErrorContainer,
                ),
              ),
              backgroundColor: Theme.of(context).colorScheme.errorContainer,
              behavior: SnackBarBehavior.fixed,
            ),
          );
        }
        return;
      }
    }

    try {
      // 创建临时站点配置用于获取分类
      final tempSite = _composeCurrentSite();
      await ApiService.instance.setActiveSite(tempSite);

      // 从适配器获取分类配置
      final adapter = ApiService.instance.activeAdapter;
      if (adapter != null) {
        final categories = await adapter.getSearchCategories();
        setState(() {
          _searchCategories = List.from(categories);
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '已成功加载 ${categories.length} 个分类配置',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                ),
              ),
              backgroundColor: Theme.of(context).colorScheme.primaryContainer,
              behavior: SnackBarBehavior.fixed,
            ),
          );
        }
      } else {
        throw Exception('无法获取适配器实例');
      }
    } catch (e) {
      // 如果获取失败，使用默认配置
      setState(() {
        _searchCategories = SearchCategoryConfig.getDefaultConfigs();
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '获取分类配置失败，已使用默认配置: $e',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onErrorContainer,
              ),
            ),
            backgroundColor: Theme.of(context).colorScheme.errorContainer,
            behavior: SnackBarBehavior.fixed,
          ),
        );
      }
    }
  }

  Widget _buildFeatureSwitch(
    String title,
    String subtitle,
    bool value,
    ValueChanged<bool> onChanged,
  ) {
    return SwitchListTile(
      title: Text(title),
      subtitle: Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
      value: value,
      onChanged: onChanged,
      contentPadding: EdgeInsets.zero,
    );
  }

  Future<void> _testConnection() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      // 如果搜索分类为空，先重置分类配置
      if (_searchCategories.isEmpty) {
        await _resetSearchCategories();
      }

      final site = _composeCurrentSite();
      // 临时设置站点进行测试
      await ApiService.instance.setActiveSite(site);
      final profile = await ApiService.instance.fetchMemberProfile();
      
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('测试连接成功'),
          content: SingleChildScrollView(child: _ProfileView(profile: profile)),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('关闭'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('测试连接失败'),
          content: Text(e.toString()),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('关闭'),
            ),
          ],
        ),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    // 如果搜索分类为空，先重置分类配置
    if (_searchCategories.isEmpty) {
      setState(() {
        _loading = true;
        _error = null;

      });

      try {
        await _resetSearchCategories();
      } catch (e) {
        setState(() => _error = '重置分类配置失败: $e');
        if (mounted) setState(() => _loading = false);
        return;
      }
    }

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
      // 先验证连接并获取用户信息
      await ApiService.instance.setActiveSite(site);
      final profile = await ApiService.instance.fetchMemberProfile();

      // 创建包含userId和passKey的最终站点配置
      // 优先使用用户填写的passKey，如果没有填写则使用从fetchMemberProfile获取的
      final userPassKey = _passKeyController.text.trim();
      final finalPassKey = userPassKey.isNotEmpty
          ? userPassKey
          : profile.passKey;
      final finalSite = site.copyWith(
        userId: profile.userId,
        passKey: finalPassKey,
      );

      if (widget.site != null) {
        await StorageService.instance.updateSiteConfig(finalSite);
        
        // 同步更新聚合搜索配置，移除已删除的分类
        final storage = StorageService.instance;
        final aggregateSettings = await storage.loadAggregateSearchSettings();
        bool settingsChanged = false;

        final updatedConfigs = aggregateSettings.searchConfigs.map((config) {
          // 检查该配置是否包含当前站点
          final siteIndex = config.enabledSites.indexWhere(
            (s) => s.id == finalSite.id,
          );
          if (siteIndex == -1) return config;

          final siteItem = config.enabledSites[siteIndex];
          final selectedCategories =
              siteItem.additionalParams?['selectedCategories'] as List?;

          if (selectedCategories != null && selectedCategories.isNotEmpty) {
            // 获取当前站点所有有效的分类ID
            final validCategoryIds = finalSite.searchCategories
                .map((c) => c.id)
                .toSet();
            // 过滤掉不存在的分类
            final validSelectedCategories = selectedCategories
                .where((c) => validCategoryIds.contains(c))
                .toList();

            // 如果分类数量发生了变化，说明有分类被删除了
            if (validSelectedCategories.length != selectedCategories.length) {
              settingsChanged = true;

              final Map<String, dynamic>? newParams;
              if (validSelectedCategories.isNotEmpty) {
                newParams = {'selectedCategories': validSelectedCategories};
              } else {
                newParams = null;
              }

              final newSiteItem = siteItem.copyWith(
                additionalParams: newParams,
              );
              final newEnabledSites = List<SiteSearchItem>.from(
                config.enabledSites,
              );
              newEnabledSites[siteIndex] = newSiteItem;

              return config.copyWith(enabledSites: newEnabledSites);
            }
          }

          return config;
        }).toList();

        if (settingsChanged) {
          await storage.saveAggregateSearchSettings(
            aggregateSettings.copyWith(searchConfigs: updatedConfigs),
          );
        }

        // 更新现有站点后，如果是当前活跃站点，需要重新初始化适配器
        final activeSiteId = await StorageService.instance.getActiveSiteId();
        if (activeSiteId == finalSite.id) {
          await ApiService.instance.setActiveSite(finalSite);
          // 通知AppState更新
          if (mounted) {
            final appState = context.read<AppState>();
            await appState.loadInitial(forceReload: true);
          }
        }
      } else {
        await StorageService.instance.addSiteConfig(finalSite);
        // 首次添加站点时，设置为活跃站点
        await StorageService.instance.setActiveSiteId(finalSite.id);
        // 重新初始化适配器，确保userId正确更新
        await ApiService.instance.setActiveSite(finalSite);
        // 通知AppState更新
        if (mounted) {
          final appState = context.read<AppState>();
          await appState.setActiveSite(finalSite.id);
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              widget.site != null ? '站点已更新' : '站点已添加',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onPrimaryContainer,
              ),
            ),
            backgroundColor: Theme.of(context).colorScheme.primaryContainer,
            behavior: SnackBarBehavior.fixed,
          ),
        );
        widget.onSaved?.call();
        Navigator.of(context).pop();
      }
    } catch (e) {
      setState(() => _error = '保存失败: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Widget _buildTemplateListTile(SiteConfigTemplate template) {
    final isSelected =
        !_isCustomSite &&
        _selectedTemplateUrl != null &&
        template.baseUrls.contains(_selectedTemplateUrl);

    return ExpansionTile(
      leading: Icon(
        Icons.public,
        color: Theme.of(context).colorScheme.secondary,
        size: 20,
      ),
      title: Text(template.name, style: const TextStyle(fontSize: 14)),
      subtitle: Text(
        '${template.baseUrls.length} 个地址 (${template.siteType.displayName})',
        style: const TextStyle(fontSize: 12),
      ),
      initiallyExpanded: isSelected,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      dense: true,
      visualDensity: VisualDensity.compact,
      tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      childrenPadding: EdgeInsets.zero,
      children: template.baseUrls.map((url) {
        final isUrlSelected = !_isCustomSite && _selectedTemplateUrl == url;
        return ListTile(
          leading: Icon(
            url == template.primaryUrl ? Icons.star : Icons.link,
            color: url == template.primaryUrl
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.onSurfaceVariant,
            size: 16,
          ),
          title: Text(url, style: const TextStyle(fontSize: 13)),
          subtitle: url == template.primaryUrl
              ? const Text('主要地址', style: TextStyle(fontSize: 11))
              : null,
          selected: isUrlSelected,
          onTap: () {
            _selectPresetTemplate(template, url);
            // 选中后收起下拉框
            _presetSearchController.clear();
            setState(() {
              _filteredPresetTemplates = _presetTemplates
                  .where((template) => template.isShow)
                  .toList();
              _showPresetList = false; // 收起列表
            });
          },
          contentPadding: const EdgeInsets.only(
            left: 48,
            right: 16,
            top: 2,
            bottom: 2,
          ),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          dense: true,
          visualDensity: VisualDensity.compact,
        );
      }).toList(),
    );
  }

  Future<void> _openWebLogin() async {
    final site = _composeCurrentSite();
    if (site.baseUrl.isEmpty) {
      setState(() {
        _cookieStatus = '请先填写站点地址';
      });
      return;
    }

    // 从模板配置中获取 loginPath
    String? loginPath;
    if (!_isCustomSite && _selectedTemplateUrl != null) {
      try {
        final template = _presetTemplates.firstWhere(
          (t) => t.baseUrls.contains(_selectedTemplateUrl),
        );
        final requestConfig = template.request;
        if (requestConfig != null) {
          final loginPageConfig =
              requestConfig['loginPage'] as Map<String, dynamic>?;
          if (loginPageConfig != null) {
            loginPath = loginPageConfig['path'] as String?;
          }
        }
      } catch (_) {
        // 模板未找到，使用默认路径
      }
    }

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => NexusPhpWebLogin(
          baseUrl: site.baseUrl,
          loginPath: loginPath,
          onCookieReceived: (cookie) {
            setState(() {
              _savedCookie = cookie;
              _cookieController.text = cookie;
              _cookieStatus = '登录成功，已获取认证信息';
            });
          },
          onCancel: () {
            setState(() {
              _cookieStatus = '用户取消登录';
            });
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.site != null ? '编辑服务器' : '添加服务器'),
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
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 预设站点选择（第一位）
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.language,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '选择站点',
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // 搜索框
                      TextField(
                        controller: _presetSearchController,
                        decoration: InputDecoration(
                          labelText: '搜索预设站点',
                          hintText: '输入站点名称、地址或类型进行搜索',
                          prefixIcon: const Icon(Icons.search),
                          border: const OutlineInputBorder(),
                          suffixIcon: _showPresetList
                              ? IconButton(
                                  icon: const Icon(Icons.keyboard_arrow_up),
                                  onPressed: () {
                                    setState(() {
                                      _showPresetList = false;
                                    });
                                    FocusScope.of(context).unfocus();
                                  },
                                )
                              : const Icon(Icons.keyboard_arrow_down),
                        ),
                        onTap: () {
                          setState(() {
                            _showPresetList = true;
                          });
                        },
                        onChanged: (value) {
                          setState(() {
                            _showPresetList = true;
                          });
                        },
                      ),
                      const SizedBox(height: 12),

                      // 预设站点列表（只在_showPresetList为true时显示）
                      if (_showPresetList)
                        Container(
                          constraints: const BoxConstraints(maxHeight: 400),
                          child: SingleChildScrollView(
                            child: Column(
                              children: [
                                // 自定义选项（始终显示在第一位）
                                ListTile(
                                  leading: const Icon(Icons.add_circle_outline),
                                  title: const Text('自定义'),
                                  subtitle: const Text('手动配置站点信息'),
                                  selected: _isCustomSite,
                                  onTap: () {
                                    _selectCustomSite();
                                    // 选中后收起下拉框
                                    _presetSearchController.clear();
                                    setState(() {
                                      _filteredPresetTemplates =
                                          _presetTemplates
                                              .where(
                                                (template) => template.isShow,
                                              )
                                              .toList();
                                      _showPresetList = false; // 收起列表
                                    });
                                  },
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  dense: true,
                                  visualDensity: VisualDensity.compact,
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 4,
                                  ),
                                ),

                                // 分隔线
                                if (_filteredPresetTemplates.isNotEmpty) ...[
                                  const Divider(height: 1),

                                  // 过滤后的预设模板列表（新格式，支持多URL）
                                  ..._filteredPresetTemplates.map(
                                    (template) =>
                                        _buildTemplateListTile(template),
                                  ),
                                ],

                                // 无搜索结果提示
                                if (_filteredPresetTemplates.isEmpty &&
                                    _presetSearchController.text.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.all(16),
                                    child: Text(
                                      '未找到匹配的预设站点',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyMedium
                                          ?.copyWith(
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.onSurfaceVariant,
                                          ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // 自定义配置（当用户做出选择后显示，无论是预设还是自定义）
              if (_hasUserMadeSelection) ...[
                // 网站类型选择
                DropdownButtonFormField<SiteType>(
                  initialValue: _selectedSiteType,
                  decoration: const InputDecoration(
                    labelText: '网站类型',
                    border: OutlineInputBorder(),
                  ),
                  items: SiteType.values
                      .map(
                        (type) => DropdownMenuItem(
                          value: type,
                          child: Text(type.displayName),
                        ),
                      )
                      .toList(),
                  validator: (value) {
                    if (value == null) {
                      return '请选择网站类型';
                    }
                    return null;
                  },
                  onChanged: !_isCustomSite
                      ? null
                      : (value) {
                          if (value != null) {
                            setState(() {
                              _selectedSiteType = value;
                              _searchCategories = []; // 分类配置保持为空
                              _loadDefaultFeatures(value);
                            });
                          }
                        },
                ),
                const SizedBox(height: 16),
                // 站点颜色选择
                Row(
                  children: [
                    Text('站点颜色', style: Theme.of(context).textTheme.bodyMedium),
                    const SizedBox(width: 12),
                    GestureDetector(
                      onTap: () async {
                        final picked = await showDialog<Color>(
                          context: context,
                          builder: (context) => _SiteColorPickerDialog(
                            initialColor:
                                _siteColor ??
                                Theme.of(context).colorScheme.primary,
                          ),
                        );
                        if (picked != null) {
                          setState(() => _siteColor = picked);
                        }
                      },
                      child: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color:
                              _siteColor ??
                              Theme.of(context).colorScheme.primary,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Theme.of(context).colorScheme.outline,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _siteColor != null
                            ? (() {
                                final argb = _siteColor!.toARGB32();
                                return '#${argb.toRadixString(16).padLeft(8, '0').toUpperCase()}';
                              })()
                            : '未设置（使用默认哈希色）',
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _nameController,
                  readOnly: !_isCustomSite,
                  decoration: InputDecoration(
                    labelText: '站点名称',
                    border: const OutlineInputBorder(),
                    filled: !_isCustomSite,
                    fillColor: !_isCustomSite
                        ? Theme.of(context).colorScheme.surfaceContainerHighest
                              .withValues(alpha: 0.3)
                        : null,
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return '请输入站点名称';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                // Base URL字段 - 根据是否选择模板显示不同的UI
                if (_isCustomSite) ...[
                  // 自定义站点：显示文本输入框
                  TextFormField(
                    controller: _baseUrlController,
                    decoration: const InputDecoration(
                      labelText: 'Base URL',
                      hintText: '例如: https://api.m-team.cc/',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return '请输入站点地址';
                      }
                      if (!value.startsWith('http')) {
                        return '请输入有效的URL（以http开头）';
                      }
                      return null;
                    },
                  ),
                ] else ...[
                  // 预设站点：显示URL选择下拉框（所有预设站点现在都是模板格式）
                  if (_selectedTemplateUrl != null) ...[
                    // 模板站点：显示下拉选择框
                    () {
                      final template = _presetTemplates.firstWhere(
                        (t) => t.baseUrls.contains(_selectedTemplateUrl),
                        orElse: () => throw StateError(
                          'Template not found for selected URL',
                        ),
                      );

                      return DropdownButtonFormField<String>(
                        initialValue: _selectedTemplateUrl,
                        decoration: InputDecoration(
                          labelText: 'Base URL',
                          border: const OutlineInputBorder(),
                          filled: true,
                          fillColor: Theme.of(context)
                              .colorScheme
                              .surfaceContainerHighest
                              .withValues(alpha: 0.3),
                        ),
                        items: template.baseUrls.map((url) {
                          return DropdownMenuItem<String>(
                            value: url,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  url == template.primaryUrl
                                      ? Icons.star
                                      : Icons.link,
                                  color: url == template.primaryUrl
                                      ? Theme.of(context).colorScheme.primary
                                      : Theme.of(
                                          context,
                                        ).colorScheme.onSurfaceVariant,
                                  size: 16,
                                ),
                                const SizedBox(width: 8),
                                Flexible(
                                  child: Text(
                                    url,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (url == template.primaryUrl) ...[
                                  const SizedBox(width: 4),
                                  Text(
                                    '主要',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.primary,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          );
                        }).toList(),
                        onChanged: (String? newUrl) {
                          if (newUrl != null) {
                            setState(() {
                              _selectedTemplateUrl = newUrl;
                              _baseUrlController.text = newUrl;
                            });
                          }
                        },
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return '请选择站点地址';
                          }
                          return null;
                        },
                      );
                    }(),
                  ] else ...[
                    // 如果没有选择模板URL但不是自定义站点，显示提示信息
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: Theme.of(context).colorScheme.outline,
                        ),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        '请先选择一个预设站点',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ],
                const SizedBox(height: 16),
              ],

              // API Key输入或登录按钮（只有在用户做出选择时才显示）
              if (_hasUserMadeSelection &&
                  _selectedSiteType != SiteType.nexusphpweb) ...[
                TextFormField(
                  controller: _apiKeyController,
                  decoration: InputDecoration(
                    labelText: _selectedSiteType?.apiKeyLabel ?? 'API密钥',
                    hintText: _selectedSiteType?.apiKeyHint ?? '请输入API密钥',
                    border: const OutlineInputBorder(),
                  ),
                  obscureText: true,
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return '请输入API密钥';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
              ] else if (_hasUserMadeSelection) ...[
                // NexusPHPWeb类型显示登录认证（只有在用户做出选择时才显示）
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.login),
                            const SizedBox(width: 8),
                            const Text(
                              '登录认证',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),

                        // 根据平台显示不同的认证方式
                        if (Platform.isAndroid || Platform.isIOS) ...[
                          const Text(
                            '此类型站点需要通过网页登录获取认证信息',
                            style: TextStyle(color: Colors.grey),
                          ),
                          const SizedBox(height: 16),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: _openWebLogin,
                              icon: const Icon(Icons.web),
                              label: const Text('打开登录页面'),
                            ),
                          ),
                          const SizedBox(height: 8),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: () {
                                setState(() {
                                  _showManualCookieInput =
                                      !_showManualCookieInput;
                                });
                              },
                              icon: const Icon(Icons.edit),
                              label: Text(
                                _showManualCookieInput
                                    ? '收起手动输入'
                                    : '我要手动输入cookie',
                              ),
                            ),
                          ),
                        ],
                        if (!Platform.isAndroid && !Platform.isIOS ||
                            _showManualCookieInput) ...[
                          const SizedBox(height: 16),
                          const Text(
                            '请手动输入从浏览器获取的Cookie字符串',
                            style: TextStyle(color: Colors.grey),
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _cookieController,
                            decoration: const InputDecoration(
                              labelText: 'Cookie字符串',
                              hintText: '从浏览器开发者工具中复制完整的Cookie值',
                              border: OutlineInputBorder(),
                            ),
                            maxLines: 3,
                            onChanged: (value) {
                              _savedCookie = value.trim();
                              if (_savedCookie!.isNotEmpty) {
                                setState(() {
                                  _cookieStatus = '已输入Cookie，请保存配置后测试连接';
                                });
                              } else {
                                setState(() {
                                  _cookieStatus = null;
                                });
                              }
                            },
                          ),
                        ],

                        if (_cookieStatus != null) ...[
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: _cookieStatus!.startsWith('成功')
                                  ? Colors.green.withValues(alpha: 0.1)
                                  : Colors.orange.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: _cookieStatus!.startsWith('成功')
                                    ? Colors.green
                                    : Colors.orange,
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  _cookieStatus!.startsWith('成功')
                                      ? Icons.check_circle
                                      : Icons.info,
                                  color: _cookieStatus!.startsWith('成功')
                                      ? Colors.green
                                      : Colors.orange,
                                  size: 20,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    _cookieStatus!,
                                    style: TextStyle(
                                      color: _cookieStatus!.startsWith('成功')
                                          ? Colors.green.shade700
                                          : Colors.orange.shade700,
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
                const SizedBox(height: 16),
              ],

              const SizedBox(height: 8),

              // 查询分类配置（只有在用户做出选择时才显示）
              if (_hasUserMadeSelection)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.category),
                            const SizedBox(width: 8),
                            const Text(
                              '查询分类配置',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const Spacer(),
                            TextButton.icon(
                              icon: const Icon(Icons.add),
                              label: const Text('添加'),
                              onPressed: _addSearchCategory,
                            ),
                            TextButton.icon(
                              icon: const Icon(Icons.download),
                              label: const Text('获取'),
                              onPressed: _resetSearchCategories,
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        if (_searchCategories.isEmpty)
                          const Text(
                            '暂无查询分类配置',
                            style: TextStyle(color: Colors.grey),
                          )
                        else
                          ListView.separated(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: _searchCategories.length,
                            separatorBuilder: (context, index) =>
                                const Divider(),
                            itemBuilder: (context, index) {
                              final category = _searchCategories[index];
                              return ListTile(
                                title: Text(category.displayName),
                                subtitle: Text(
                                  category.parameters.isEmpty
                                      ? '无参数'
                                      : category.parameters,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.edit),
                                      onPressed: () =>
                                          _editSearchCategory(index),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.delete),
                                      onPressed: () =>
                                          _deleteSearchCategory(index),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 24),

              // 功能配置（只有在用户做出选择时才显示）
              if (_hasUserMadeSelection)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '功能配置',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '配置此站点支持的功能',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const SizedBox(height: 12),
                        _buildFeatureSwitch(
                          '用户资料',
                          '获取用户个人信息和统计数据',
                          _siteFeatures.supportMemberProfile,
                          (value) => setState(() {
                            _siteFeatures = _siteFeatures.copyWith(
                              supportMemberProfile: value,
                            );
                          }),
                        ),
                        _buildFeatureSwitch(
                          '种子搜索',
                          '搜索和浏览种子资源',
                          _siteFeatures.supportTorrentSearch,
                          (value) => setState(() {
                            _siteFeatures = _siteFeatures.copyWith(
                              supportTorrentSearch: value,
                            );
                          }),
                        ),
                        _buildFeatureSwitch(
                          '种子详情',
                          '查看种子的详细信息',
                          _siteFeatures.supportTorrentDetail,
                          (value) => setState(() {
                            _siteFeatures = _siteFeatures.copyWith(
                              supportTorrentDetail: value,
                            );
                          }),
                        ),
                        _buildFeatureSwitch(
                          '下载功能',
                          '生成下载链接和下载种子',
                          _siteFeatures.supportDownload,
                          (value) => setState(() {
                            _siteFeatures = _siteFeatures.copyWith(
                              supportDownload: value,
                            );
                          }),
                        ),
                        _buildFeatureSwitch(
                          '收藏功能',
                          '收藏和取消收藏种子',
                          _siteFeatures.supportCollection,
                          (value) => setState(() {
                            _siteFeatures = _siteFeatures.copyWith(
                              supportCollection: value,
                            );
                          }),
                        ),
                        _buildFeatureSwitch(
                          '下载历史',
                          '查看种子下载历史记录',
                          _siteFeatures.supportHistory,
                          (value) => setState(() {
                            _siteFeatures = _siteFeatures.copyWith(
                              supportHistory: value,
                            );
                          }),
                        ),
                        _buildFeatureSwitch(
                          '分类搜索',
                          '按分类筛选搜索结果',
                          _siteFeatures.supportCategories,
                          (value) => setState(() {
                            _siteFeatures = _siteFeatures.copyWith(
                              supportCategories: value,
                            );
                          }),
                        ),
                        _buildFeatureSwitch(
                          '高级搜索',
                          '使用高级搜索参数和过滤器',
                          _siteFeatures.supportAdvancedSearch,
                          (value) => setState(() {
                            _siteFeatures = _siteFeatures.copyWith(
                              supportAdvancedSearch: value,
                            );
                          }),
                        ),
                        _buildFeatureSwitch(
                          '显示封面',
                          '在列表左侧显示封面和评分',
                          _siteFeatures.showCover,
                          (value) => setState(() {
                            _siteFeatures = _siteFeatures.copyWith(
                              showCover: value,
                            );
                          }),
                        ),
                        _buildFeatureSwitch(
                          '评论详情',
                          '在详情页加载和显示用户评论',
                          _siteFeatures.supportCommentDetail,
                          (value) => setState(() {
                            _siteFeatures = _siteFeatures.copyWith(
                              supportCommentDetail: value,
                            );
                          }),
                        ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 24),

              // 操作按钮（只有在用户做出选择时才显示）

              const SizedBox(height: 16),



              // 错误信息
              if (_error != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.error_outline,
                        color: Theme.of(context).colorScheme.onErrorContainer,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _error!,
                          style: TextStyle(
                            color: Theme.of(
                              context,
                            ).colorScheme.onErrorContainer,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              // 用户信息显示

            ],
          ),
        ),
      ),

      floatingActionButton: _hasUserMadeSelection
          ? Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                FloatingActionButton(
                  heroTag: 'test_connection',
                  onPressed: _loading ? null : _testConnection,
                  backgroundColor: Theme.of(
                    context,
                  ).colorScheme.tertiaryContainer,
                  foregroundColor: Theme.of(
                    context,
                  ).colorScheme.onTertiaryContainer,
                  tooltip: '测试连接',
                  child: _loading
                      ? SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: Theme.of(
                              context,
                            ).colorScheme.onTertiaryContainer,
                          ),
                        )
                      : const Icon(Icons.play_arrow),
                ),
                const SizedBox(height: 16),
                FloatingActionButton(
                  heroTag: 'save_site',
                  onPressed: _loading ? null : _save,
                  tooltip: widget.site != null ? '更新' : '保存',
                  child: const Icon(Icons.save),
                ),
              ],
            )
          : null,
    );
  }
}

class _ProfileView extends StatelessWidget {
  final MemberProfile profile;

  const _ProfileView({required this.profile});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.check_circle,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Text(
                '连接成功',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text('用户名: ${profile.username}'),
          Text(
            '魔力值: ${Formatters.bonus(profile.bonus)}'
            '${profile.bonusPerHour != null ? '(${ScreenUtils.isLargeScreen(context) ? profile.bonusPerHour! : profile.bonusPerHour!.toInt()})' : ''}',
          ),
          Text('上传: ${profile.uploadedBytesString}'),
          Text('下载: ${profile.downloadedBytesString}'),
          if (profile.seedingSizeBytes != null)
            Text(
              '做种体积: ${Formatters.dataFromBytes(profile.seedingSizeBytes!)}',
            ),
          Text('分享率: ${Formatters.shareRate(profile.shareRate)}'),
          Text('passKey: ${profile.passKey}'),
        ],
      ),
    );
  }
}

class _SiteColorPickerDialog extends StatefulWidget {
  final Color initialColor;

  const _SiteColorPickerDialog({required this.initialColor});

  @override
  State<_SiteColorPickerDialog> createState() => _SiteColorPickerDialogState();
}

class _SiteColorPickerDialogState extends State<_SiteColorPickerDialog> {
  late Color _selectedColor;
  bool _customMode = false;
  final TextEditingController _hexController = TextEditingController();
  // 透明度固定为不透明，颜色值仅由矩形与色相条决定
  double _h = 0.0;
  double _s = 1.0;
  double _v = 1.0;

  @override
  void initState() {
    super.initState();
    _selectedColor = widget.initialColor;
    _hexController.text =
        '#${_selectedColor.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase().substring(2)}';
    final hsv = HSVColor.fromColor(_selectedColor);
    _h = hsv.hue;
    _s = hsv.saturation;
    _v = hsv.value;
  }

  @override
  void dispose() {
    _hexController.dispose();
    super.dispose();
  }

  String _toHexRGB(Color c) {
    final r = (c.r * 255).round().toRadixString(16).padLeft(2, '0');
    final g = (c.g * 255).round().toRadixString(16).padLeft(2, '0');
    final b = (c.b * 255).round().toRadixString(16).padLeft(2, '0');
    return '#${r.toUpperCase()}${g.toUpperCase()}${b.toUpperCase()}';
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('选择站点颜色'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 调色盘：S-V 二维取值 + H 滑条
            // 预设色选择区（点击后可直接选择，无需自定义）
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children:
                  [
                    Colors.red,
                    Colors.pink,
                    Colors.purple,
                    Colors.deepPurple,
                    Colors.indigo,
                    Colors.blue,
                    Colors.lightBlue,
                    Colors.cyan,
                    Colors.teal,
                    Colors.green,
                    Colors.lightGreen,
                    Colors.lime,
                    Colors.yellow,
                    Colors.amber,
                    Colors.orange,
                    Colors.deepOrange,
                    Colors.brown,
                    Colors.grey,
                    Colors.blueGrey,
                  ].map((color) {
                    final sel = _selectedColor.toARGB32() == color.toARGB32();
                    return GestureDetector(
                      onTap: () {
                        setState(() {
                          _selectedColor = color;
                          _hexController.text = _toHexRGB(color);
                          _customMode = false;
                        });
                      },
                      child: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                          border: sel
                              ? Border.all(color: Colors.white, width: 3)
                              : null,
                          boxShadow: sel
                              ? [
                                  BoxShadow(
                                    color: color.withValues(alpha: 0.5),
                                    blurRadius: 8,
                                    spreadRadius: 2,
                                  ),
                                ]
                              : null,
                        ),
                        child: sel
                            ? const Icon(
                                Icons.check,
                                color: Colors.white,
                                size: 18,
                              )
                            : null,
                      ),
                    );
                  }).toList(),
            ),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.palette_outlined),
              title: const Text('自定义颜色...'),
              subtitle: const Text('支持 #RRGGBB 或 #AARRGGBB'),
              onTap: () => setState(() {
                _customMode = true;
                _hexController.text =
                    '#${_selectedColor.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase().substring(2)}';
              }),
            ),
            if (_customMode) ...[
              const SizedBox(height: 8),
              // 上方矩形：固定当前色相，横轴为饱和度，纵轴为明度
              SizedBox(
                width: 260,
                height: 160,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: Container(
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: Theme.of(context).colorScheme.outline,
                          ),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        clipBehavior: Clip.hardEdge,
                        child: GestureDetector(
                          onTapDown: (d) {
                            final b = d.localPosition;
                            const w = 260.0;
                            const h = 160.0;
                            setState(() {
                              _s = (b.dx / w).clamp(0.0, 1.0);
                              _v = (1.0 - (b.dy / h)).clamp(0.0, 1.0);
                              _selectedColor = HSVColor.fromAHSV(
                                1.0,
                                _h,
                                _s,
                                _v,
                              ).toColor();
                              _hexController.text =
                                  '#${_selectedColor.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase().substring(2)}';
                            });
                          },
                          onPanUpdate: (d) {
                            final b = d.localPosition;
                            const w = 260.0;
                            const h = 160.0;
                            setState(() {
                              _s = (b.dx / w).clamp(0.0, 1.0);
                              _v = (1.0 - (b.dy / h)).clamp(0.0, 1.0);
                              _selectedColor = HSVColor.fromAHSV(
                                1.0,
                                _h,
                                _s,
                                _v,
                              ).toColor();
                              _hexController.text = _toHexRGB(_selectedColor);
                            });
                          },
                          child: CustomPaint(
                            painter: _SVPalettePainter(hue: _h),
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      left: (_s * 260) - 10,
                      top: ((1.0 - _v) * 160) - 10,
                      child: IgnorePointer(
                        ignoring: true,
                        child: Container(
                          width: 20,
                          height: 20,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 3),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.3),
                                blurRadius: 4,
                              ),
                            ],
                          ),
                          child: Container(
                            margin: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: _selectedColor,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              // 下方色相滑条
              SizedBox(
                width: 260,
                height: 24,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: GestureDetector(
                        onTapDown: (d) {
                          final x = d.localPosition.dx;
                          const w = 260.0;
                          setState(() {
                            _h = (x / w * 360).clamp(0.0, 360.0);
                            _selectedColor = HSVColor.fromAHSV(
                              1.0,
                              _h,
                              _s,
                              _v,
                            ).toColor();
                            _hexController.text =
                                '#${_selectedColor.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase().substring(2)}';
                          });
                        },
                        onPanUpdate: (d) {
                          final x = d.localPosition.dx;
                          const w = 260.0;
                          setState(() {
                            _h = (x / w * 360).clamp(0.0, 360.0);
                            _selectedColor = HSVColor.fromAHSV(
                              1.0,
                              _h,
                              _s,
                              _v,
                            ).toColor();
                            _hexController.text = _toHexRGB(_selectedColor);
                          });
                        },
                        child: CustomPaint(painter: _HueBarPainter()),
                      ),
                    ),
                    Positioned(
                      left: ((_h / 360) * 260) - 10,
                      top: 2,
                      child: IgnorePointer(
                        ignoring: true,
                        child: Container(
                          width: 20,
                          height: 20,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 3),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.3),
                                blurRadius: 4,
                              ),
                            ],
                          ),
                          child: Container(
                            margin: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: HSVColor.fromAHSV(
                                1.0,
                                _h,
                                1.0,
                                1.0,
                              ).toColor(),
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: _selectedColor,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Theme.of(context).colorScheme.outline,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextFormField(
                      controller: _hexController,
                      decoration: const InputDecoration(
                        labelText: '颜色值',
                        hintText: '#RRGGBB 或 #AARRGGBB',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (v) {
                        final val = v.trim();
                        if (val.startsWith('#')) {
                          final hex = val.substring(1);
                          try {
                            final parsed = int.parse(
                              hex.length == 6 ? 'FF$hex' : hex,
                              radix: 16,
                            );
                            setState(() {
                              _selectedColor = Color(parsed);
                              final hsv = HSVColor.fromColor(_selectedColor);
                              _h = hsv.hue;
                              _s = hsv.saturation;
                              _v = hsv.value;
                            });
                          } catch (_) {}
                        }
                      },
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          style: TextButton.styleFrom(
            side: BorderSide(
              color: Theme.of(context).colorScheme.outline,
              width: 1.0,
            ),
          ),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _selectedColor),
          child: const Text('确定'),
        ),
      ],
    );
  }
}

class _SVPalettePainter extends CustomPainter {
  final double hue;
  _SVPalettePainter({required this.hue});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final baseColor = HSVColor.fromAHSV(1.0, hue, 1.0, 1.0).toColor();
    final satShader = LinearGradient(
      colors: [Colors.white, baseColor],
      begin: Alignment.centerLeft,
      end: Alignment.centerRight,
    ).createShader(rect);
    final valShader = LinearGradient(
      colors: [Colors.transparent, Colors.black],
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
    ).createShader(rect);
    final p1 = Paint()..shader = satShader;
    final p2 = Paint()..shader = valShader;
    canvas.drawRect(rect, p1);
    canvas.drawRect(rect, p2);
  }

  @override
  bool shouldRepaint(covariant _SVPalettePainter oldDelegate) {
    return oldDelegate.hue != hue;
  }
}

class _HueBarPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final shader = LinearGradient(
      colors: [
        HSVColor.fromAHSV(1, 0, 1, 1).toColor(),
        HSVColor.fromAHSV(1, 60, 1, 1).toColor(),
        HSVColor.fromAHSV(1, 120, 1, 1).toColor(),
        HSVColor.fromAHSV(1, 180, 1, 1).toColor(),
        HSVColor.fromAHSV(1, 240, 1, 1).toColor(),
        HSVColor.fromAHSV(1, 300, 1, 1).toColor(),
        HSVColor.fromAHSV(1, 360, 1, 1).toColor(),
      ],
      begin: Alignment.centerLeft,
      end: Alignment.centerRight,
    ).createShader(rect);
    final p = Paint()..shader = shader;
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(12)),
      p,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// -----------------------------------------------------------------------------
// Added _SwipeableSiteItem for left-slide menu support
// -----------------------------------------------------------------------------

class _SwipeableSiteItem extends StatefulWidget {
  final Widget child;
  final List<Widget> actions;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  const _SwipeableSiteItem({
    required this.child,
    required this.actions,
    this.onTap,
    this.onLongPress,
  });

  @override
  State<_SwipeableSiteItem> createState() => _SwipeableSiteItemState();
}

class _SwipeableSiteItemState extends State<_SwipeableSiteItem>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;
  double _dragExtent = 0;
  bool _isOpen = false;

  // Each action button is designed to be 60px width + 4px margin
  double get _actionsWidth {
    if (widget.actions.isEmpty) return 0;
    return widget.actions.length * 64.0;
  }

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 250),
      vsync: this,
    );
    _animation = Tween<double>(
      begin: 0,
      end: 0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));

    _animation.addListener(_updateDragExtent);
  }

  @override
  void dispose() {
    _animation.removeListener(_updateDragExtent);
    _controller.dispose();
    super.dispose();
  }

  void _updateDragExtent() {
    setState(() {
      _dragExtent = _animation.value;
    });
  }

  void _handleDragStart(DragStartDetails details) {
    _controller.stop();
  }

  void _handleDragUpdate(DragUpdateDetails details) {
    if (widget.actions.isEmpty) return;

    final delta = details.primaryDelta ?? 0;
    final newDragExtent = _dragExtent + delta;

    // Limit drag range: negative for left swipe
    setState(() {
      _dragExtent = newDragExtent.clamp(-_actionsWidth, 0);
    });
  }

  void _handleDragEnd(DragEndDetails details) {
    if (widget.actions.isEmpty) return;

    final velocity = details.primaryVelocity ?? 0;
    final threshold = _actionsWidth * 0.3;

    bool shouldOpen = false;

    if (velocity < -300) {
      // Fast swipe left -> open
      shouldOpen = true;
    } else if (velocity > 300) {
      // Fast swipe right -> close
      shouldOpen = false;
    } else {
      // Drag distance check
      shouldOpen = _dragExtent.abs() > threshold;
    }

    _animateToPosition(shouldOpen);
  }

  void _animateToPosition(bool open) {
    _isOpen = open;
    final targetExtent = open ? -_actionsWidth : 0.0;

    if ((_dragExtent - targetExtent).abs() < 0.1) {
      setState(() {
        _dragExtent = targetExtent;
      });
      return;
    }

    _animation = Tween<double>(
      begin: _dragExtent,
      end: targetExtent,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));

    _controller.reset();
    _controller.forward();
  }

  void _close() {
    if (_isOpen) {
      _animateToPosition(false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        if (_isOpen) {
          _close();
        } else {
          widget.onTap?.call();
        }
      },
      onLongPress: _isOpen ? null : widget.onLongPress,
      onHorizontalDragStart: _handleDragStart,
      onHorizontalDragUpdate: _handleDragUpdate,
      onHorizontalDragEnd: _handleDragEnd,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Background actions
          if (widget.actions.isNotEmpty && _dragExtent.abs() > 0.01)
            Positioned(
              right: -_actionsWidth + _dragExtent.abs(),
              top: 4, // Align with card margin/padding adjustments if needed
              bottom: 12, // Align with card bottom margin
              width: _actionsWidth,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: widget.actions,
              ),
            ),
          // Main content
          Transform.translate(
            offset: Offset(_dragExtent, 0),
            child: widget.child,
          ),
        ],
      ),
    );
  }
}
