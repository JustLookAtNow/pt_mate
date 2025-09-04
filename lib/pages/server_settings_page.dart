import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:math';

import '../models/app_models.dart';
import '../services/storage/storage_service.dart';
import '../services/api/api_service.dart';
import '../services/api/api_client.dart';
import '../widgets/qb_speed_indicator.dart';
import '../widgets/server_settings_drawer.dart';
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('加载站点配置失败: $e')),
        );
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
      await StorageService.instance.setActiveSiteId(siteId);
      await appState.loadInitial();
      setState(() => _activeSiteId = siteId);
      if (mounted) {
        scaffoldMessenger.showSnackBar(
          const SnackBar(content: Text('已切换活跃站点')),
        );
      }
    } catch (e) {
      if (mounted) {
        scaffoldMessenger.showSnackBar(
          SnackBar(content: Text('切换站点失败: $e')),
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
            child: const Text('取消'),
          ),
          TextButton(
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
            const SnackBar(content: Text('站点已删除')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('删除站点失败: $e')),
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('服务器设置'),
        actions: const [QbSpeedIndicator()],
      ),
      drawer: const ServerSettingsDrawer(),
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
                            '暂无服务器配置',
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
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: isActive
                                  ? Theme.of(context).colorScheme.primary
                                  : Theme.of(context).colorScheme.surfaceContainerHighest,
                              child: Icon(
                                Icons.dns,
                                color: isActive
                                    ? Theme.of(context).colorScheme.onPrimary
                                    : Theme.of(context).colorScheme.onSurfaceVariant,
                              ),
                            ),
                            title: Text(
                              site.name,
                              style: TextStyle(
                                fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                              ),
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
                                        color: Theme.of(context).colorScheme.primaryContainer,
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Text(
                                        site.siteType.displayName,
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Theme.of(context).colorScheme.onPrimaryContainer,
                                        ),
                                      ),
                                    ),
                                    if (isActive) ...[
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Theme.of(context).colorScheme.primary,
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        child: Text(
                                          '当前使用',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Theme.of(context).colorScheme.onPrimary,
                                          ),
                                        ),
                                      ),
                                    ],
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
                            onTap: isActive ? null : () => _setActiveSite(site.id),
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
    _parametersController = TextEditingController(text: widget.category.parameters);
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
                hintText: '推荐JSON格式：{"mode": "normal", "teams": ["44", "9", "43"]}',
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
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () {
            final name = _nameController.text.trim();
            final parameters = _parametersController.text.trim();
            if (name.isEmpty || parameters.isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('请填写完整信息')),
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
  
  SiteType _selectedSiteType = SiteType.mteam;
  int _presetIndex = -1; // -1 表示自定义
  bool _loading = false;
  String? _error;
  MemberProfile? _profile;
  List<SearchCategoryConfig> _searchCategories = [];

  @override
  void initState() {
    super.initState();
    if (widget.site != null) {
      _nameController.text = widget.site!.name;
      _baseUrlController.text = widget.site!.baseUrl;
      _apiKeyController.text = widget.site!.apiKey ?? '';
      _selectedSiteType = widget.site!.siteType;
      _searchCategories = List.from(widget.site!.searchCategories);
      
      // 检查是否是预设站点
      final presets = Defaults.presetSites;
      for (int i = 0; i < presets.length; i++) {
        if (presets[i].baseUrl == widget.site!.baseUrl) {
          _presetIndex = i;
          break;
        }
      }
    } else {
      _searchCategories = SearchCategoryConfig.getDefaultConfigs();
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _baseUrlController.dispose();
    _apiKeyController.dispose();
    super.dispose();
  }

  SiteConfig _composeCurrentSite() {
    String id;
    if (widget.site != null) {
      id = widget.site!.id;
    } else {
      id = 'site-${DateTime.now().millisecondsSinceEpoch}-${Random().nextInt(1000)}';
    }

    if (_presetIndex >= 0) {
      final preset = Defaults.presetSites[_presetIndex];
      return SiteConfig(
        id: id,
        name: preset.name,
        baseUrl: preset.baseUrl,
        apiKey: _apiKeyController.text.trim(),
        siteType: _selectedSiteType,
        searchCategories: _searchCategories,
      );
    }
    
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
      siteType: _selectedSiteType,
      searchCategories: _searchCategories,
    );
  }

  void _addSearchCategory() {
    setState(() {
      _searchCategories.add(SearchCategoryConfig(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        displayName: '新分类',
        parameters: '{"mode": "normal"}',
      ));
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

  void _resetSearchCategories() {
    setState(() {
      _searchCategories = SearchCategoryConfig.getDefaultConfigs();
    });
  }

  Future<void> _testConnection() async {
    if (!_formKey.currentState!.validate()) return;
    
    setState(() {
      _loading = true;
      _error = null;
      _profile = null;
    });
    
    try {
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
      if (widget.site != null) {
        await StorageService.instance.updateSiteConfig(site);
      } else {
        await StorageService.instance.addSiteConfig(site);
      }
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(widget.site != null ? '站点已更新' : '站点已添加')),
        );
        widget.onSaved?.call();
        Navigator.of(context).pop();
      }
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final presets = Defaults.presetSites;
    
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.site != null ? '编辑服务器' : '添加服务器'),
        actions: const [QbSpeedIndicator()],
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 网站类型选择
              DropdownButtonFormField<SiteType>(
                  initialValue: _selectedSiteType,
                decoration: const InputDecoration(
                  labelText: '网站类型',
                  border: OutlineInputBorder(),
                ),
                items: SiteType.values.map((type) => DropdownMenuItem(
                  value: type,
                  child: Text(type.displayName),
                )).toList(),
                onChanged: (value) {
                  if (value != null) {
                    setState(() {
                      _selectedSiteType = value;
                      _presetIndex = -1; // 重置预设选择
                    });
                  }
                },
              ),
              const SizedBox(height: 16),
              
              // 预设站点选择（仅M-Team类型显示）
              if (_selectedSiteType == SiteType.mteam) ...[
                DropdownButtonFormField<int>(
                  initialValue: _presetIndex,
                  decoration: const InputDecoration(
                    labelText: '选择预设站点',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    for (int i = 0; i < presets.length; i++)
                      DropdownMenuItem(
                        value: i,
                        child: Text('${presets[i].name} (${presets[i].baseUrl})'),
                      ),
                    const DropdownMenuItem(
                      value: -1,
                      child: Text('自定义…'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setState(() {
                        _presetIndex = value;
                        _profile = null;
                        _error = null;
                      });
                    }
                  },
                ),
                const SizedBox(height: 16),
              ],
              
              // 自定义配置（当选择自定义时显示）
              if (_presetIndex < 0) ...[
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: '站点名称',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return '请输入站点名称';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
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
                const SizedBox(height: 16),
              ],
              
              // API Key输入
              TextFormField(
                controller: _apiKeyController,
                decoration: InputDecoration(
                  labelText: _selectedSiteType == SiteType.mteam
                      ? 'API Key (x-api-key)'
                      : 'API Key',
                  hintText: _selectedSiteType == SiteType.mteam
                      ? '从 控制台-实验室-存储令牌 获取并粘贴此处'
                      : '请输入API密钥',
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
              const SizedBox(height: 24),
              
              // 查询分类配置
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
                            icon: const Icon(Icons.refresh),
                            label: const Text('重置'),
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
                                    onPressed: () => _deleteSearchCategory(index),
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
              
              // 操作按钮
              Row(
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
                            color: Theme.of(context).colorScheme.onErrorContainer,
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
          Text('上传: ${Formatters.dataFromBytes(profile.uploadedBytes)}'),
          Text('下载: ${Formatters.dataFromBytes(profile.downloadedBytes)}'),
          Text('分享率: ${Formatters.shareRate(profile.shareRate)}'),
        ],
      ),
    );
  }
}