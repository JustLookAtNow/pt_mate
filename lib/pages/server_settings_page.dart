import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:io';
import 'dart:math';
import '../models/app_models.dart';
import '../services/storage/storage_service.dart';
import '../services/api/api_service.dart';
import '../services/site_config_service.dart';
import '../widgets/qb_speed_indicator.dart';
import '../widgets/nexusphp_web_login.dart';
import '../widgets/responsive_layout.dart';

import '../utils/format.dart';
import '../app.dart';

class ServerSettingsPage extends StatefulWidget {
  const ServerSettingsPage({super.key});

  @override
  State<ServerSettingsPage> createState() => _ServerSettingsPageState();
}

class _ServerSettingsPageState extends State<ServerSettingsPage> {
  List<SiteConfig> _sites = [];
  String? _activeSiteId;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadSites();
  }

  Future<void> _loadSites() async {
    setState(() => _loading = true);
    try {
      final sites = await StorageService.instance.loadSiteConfigs();
      final activeSiteId = await StorageService.instance.getActiveSiteId();
      setState(() {
        _sites = sites;
        _activeSiteId = activeSiteId;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(
          content: Text(
            '加载站点配置失败: $e',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onErrorContainer,
            ),
          ),
          backgroundColor: Theme.of(context).colorScheme.errorContainer,
          behavior: SnackBarBehavior.fixed,
        ));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
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
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(
            content: Text(
              '站点已删除',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onPrimaryContainer,
              ),
            ),
            backgroundColor: Theme.of(context).colorScheme.primaryContainer,
            behavior: SnackBarBehavior.fixed,
          ));
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(
            content: Text(
              '删除站点失败: $e',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onErrorContainer,
              ),
            ),
            backgroundColor: Theme.of(context).colorScheme.errorContainer,
            behavior: SnackBarBehavior.fixed,
          ));
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

  void _editSite(SiteConfig site) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => SiteEditPage(
          site: site,
          onSaved: () {
            _loadSites();
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ResponsiveLayout(
      currentRoute: '/server_settings',
      appBar: AppBar(
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
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                if (_sites.isEmpty)
                  Expanded(
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
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(
                                  color: Theme.of(context).colorScheme.outline,
                                ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '点击右下角按钮添加第一个服务器',
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  color: Theme.of(context).colorScheme.outline,
                                ),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  Expanded(
                    child: ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _sites.length,
                      itemBuilder: (context, index) {
                        final site = _sites[index];
                        final isActive = site.id == _activeSiteId;

                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          color: isActive
                              ? Theme.of(context).colorScheme.primaryContainer
                                    .withValues(alpha: 0.3)
                              : null,
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: isActive
                                  ? Theme.of(context).colorScheme.primary
                                  : Theme.of(
                                      context,
                                    ).colorScheme.surfaceContainerHighest,
                              child: Icon(
                                Icons.dns,
                                color: isActive
                                    ? Theme.of(context).colorScheme.onPrimary
                                    : Theme.of(
                                        context,
                                      ).colorScheme.onSurfaceVariant,
                              ),
                            ),
                            title: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    site.name,
                                    style: TextStyle(
                                      fontWeight: isActive
                                          ? FontWeight.bold
                                          : FontWeight.normal,
                                    ),
                                  ),
                                ),
                                if (isActive)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.primary,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      'active',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.onPrimary,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(site.baseUrl),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.primaryContainer,
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Text(
                                        site.siteType.displayName,
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.onPrimaryContainer,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            trailing: PopupMenuButton<String>(
                              onSelected: (value) {
                                switch (value) {
                                  case 'activate':
                                    _setActiveSite(site.id);
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
                            ),
                            onTap: isActive
                                ? null
                                : () => _setActiveSite(site.id),
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addSite,
        child: const Icon(Icons.add),
      ),
      floatingActionButtonLocation: const _CustomFloatingActionButtonLocation(),
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
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(
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
  MemberProfile? _profile;
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

  @override
  void initState() {
    super.initState();
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
      
      // 检查是否是预设站点，这会根据检测结果填充相应字段
      _checkIfPresetSite();
    } else {
      // 新建站点时，查询分类配置初始为空，字段保持空白
      _searchCategories = [];
      _hasUserMadeSelection = false; // 新建站点时用户还未做出选择
      // 不设置默认的 _selectedSiteType，让用户选择后再设置
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
      _profile = null;
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
      _profile = null;
    });
  }

  Future<void> _loadDefaultFeatures(SiteType siteType) async {
    try {
      final defaultTemplate = await SiteConfigService.getTemplateById(
        "",
        siteType
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
      id = 'site-${DateTime.now().millisecondsSinceEpoch}-${Random().nextInt(1000)}';
      
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
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(
            content: Text(
              '请先完成登录获取Cookie',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onErrorContainer,
              ),
            ),
            backgroundColor: Theme.of(context).colorScheme.errorContainer,
            behavior: SnackBarBehavior.fixed,
          ));
        }
        return;
      }
    } else {
      // 其他类型需要API Key
      if (_apiKeyController.text.trim().isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(
            content: Text(
              '请先填写API Key',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onErrorContainer,
              ),
            ),
            backgroundColor: Theme.of(context).colorScheme.errorContainer,
            behavior: SnackBarBehavior.fixed,
          ));
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(
          content: Text(
            '获取分类配置失败，已使用默认配置: $e',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onErrorContainer,
            ),
          ),
          backgroundColor: Theme.of(context).colorScheme.errorContainer,
          behavior: SnackBarBehavior.fixed,
        ));
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
      _profile = null;
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
      setState(() => _profile = profile);
    } catch (e) {
      setState(() => _error = e.toString());
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
        _profile = null;
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
      _profile = null;
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
    final isSelected = !_isCustomSite && _selectedTemplateUrl != null && 
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
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
      ),
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
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
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

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => NexusPhpWebLogin(
          baseUrl: site.baseUrl,
          onCookieReceived: (cookie) {
            setState(() {
              _savedCookie = cookie;
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
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
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
                  onChanged: !_isCustomSite ? null : (value) {
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
                TextFormField(
                  controller: _nameController,
                  readOnly: !_isCustomSite,
                  decoration: InputDecoration(
                    labelText: '站点名称',
                    border: const OutlineInputBorder(),
                    filled: !_isCustomSite,
                    fillColor: !_isCustomSite ? Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3) : null,
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
                        orElse: () => throw StateError('Template not found for selected URL'),
                      );
                      
                      return DropdownButtonFormField<String>(
                         initialValue: _selectedTemplateUrl,
                        decoration: InputDecoration(
                          labelText: 'Base URL',
                          border: const OutlineInputBorder(),
                          filled: true,
                          fillColor: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                        ),
                        items: template.baseUrls.map((url) {
                          return DropdownMenuItem<String>(
                            value: url,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  url == template.primaryUrl ? Icons.star : Icons.link,
                                  color: url == template.primaryUrl 
                                      ? Theme.of(context).colorScheme.primary
                                      : Theme.of(context).colorScheme.onSurfaceVariant,
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
                                      color: Theme.of(context).colorScheme.primary,
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
                        border: Border.all(color: Theme.of(context).colorScheme.outline),
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
              if (_hasUserMadeSelection && _selectedSiteType != SiteType.nexusphpweb) ...[
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
                        if (Platform.isAndroid) ...[
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
                        ] else ...[
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
                              // 当用户输入cookie时，更新保存的cookie
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

              // Pass Key输入（仅NexusPHP类型显示，且用户已做出选择）
              if (_hasUserMadeSelection && _selectedSiteType?.requiresPassKey == true) ...[
                TextFormField(
                  controller: _passKeyController,
                  decoration: InputDecoration(
                    labelText: _selectedSiteType?.passKeyLabel ?? 'Pass Key',
                    hintText: _selectedSiteType?.passKeyHint ?? '请输入Pass Key',
                    border: const OutlineInputBorder(),
                  ),
                  obscureText: true,
                  validator: (value) {
                    if (_selectedSiteType?.requiresPassKey == true &&
                        (value == null || value.trim().isEmpty)) {
                      return '请输入Pass Key';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
              ],
              const SizedBox(height: 8),

              // 查询分类配置（只有在用户做出选择时才显示）
              if (_hasUserMadeSelection) Card(
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
                          separatorBuilder: (context, index) => const Divider(),
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
                                    onPressed: () => _editSearchCategory(index),
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
              if (_hasUserMadeSelection) Card(
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
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // 操作按钮（只有在用户做出选择时才显示）
              if (_hasUserMadeSelection) Row(
                children: [
                  OutlinedButton.icon(
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('测试连接'),
                    onPressed: _loading ? null : _testConnection,
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.save),
                    label: Text(widget.site != null ? '更新' : '保存'),
                    onPressed: _loading ? null : _save,
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // 加载指示器
              if (_loading) const LinearProgressIndicator(),

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
              if (_profile != null) ...[
                const SizedBox(height: 16),
                _ProfileView(profile: _profile!),
              ],
            ],
          ),
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
          Text('魔力值: ${Formatters.bonus(profile.bonus)}'),
          Text('上传: ${profile.uploadedBytesString}'),
          Text('下载: ${profile.downloadedBytesString}'),
          Text('分享率: ${Formatters.shareRate(profile.shareRate)}'),
          Text('passKey: ${profile.passKey}')
        ],
      ),
    );
  }
}

/// 自定义FloatingActionButton位置，远离底边1.5cm，远离右边1cm
class _CustomFloatingActionButtonLocation extends FloatingActionButtonLocation {
  const _CustomFloatingActionButtonLocation();

  @override
  Offset getOffset(ScaffoldPrelayoutGeometry scaffoldGeometry) {
    // 1.5cm ≈ 57像素，1cm ≈ 38像素
    const double bottomMargin = 80.0; // 1.5cm
    const double rightMargin = 50.0;  // 1cm
    
    // 计算FloatingActionButton的位置
    final double fabX = scaffoldGeometry.scaffoldSize.width - 
                       scaffoldGeometry.floatingActionButtonSize.width - 
                       rightMargin;
    final double fabY = scaffoldGeometry.scaffoldSize.height - 
                       scaffoldGeometry.floatingActionButtonSize.height - 
                       bottomMargin;
    
    return Offset(fabX, fabY);
  }
}
