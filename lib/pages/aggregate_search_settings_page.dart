import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/app_models.dart';
import '../services/storage/storage_service.dart';
import '../widgets/qb_speed_indicator.dart';
import 'package:pt_mate/utils/notification_helper.dart';

class AggregateSearchSettingsPage extends StatefulWidget {
  const AggregateSearchSettingsPage({super.key});

  @override
  State<AggregateSearchSettingsPage> createState() => _AggregateSearchSettingsPageState();
}

class _AggregateSearchSettingsPageState extends State<AggregateSearchSettingsPage> {
  AggregateSearchSettings _settings = const AggregateSearchSettings();
  List<SiteConfig> _allSites = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    try {
      final storage = Provider.of<StorageService>(context, listen: false);
      final settings = await storage.loadAggregateSearchSettings();
      final sites = await storage.loadSiteConfigs();

      // 确保存在默认的"所有站点"配置
      var updatedSettings = settings;
      final hasAllSitesConfig = settings.searchConfigs.any((config) => config.isAllSitesType);
      if (!hasAllSitesConfig) {
        final defaultConfig = AggregateSearchConfig.createDefaultConfig([]);
        updatedSettings = settings.copyWith(
          searchConfigs: [defaultConfig, ...settings.searchConfigs],
        );
        // 保存更新后的设置
        await storage.saveAggregateSearchSettings(updatedSettings);
      }

      if (mounted) {
        setState(() {
          _settings = updatedSettings;
          _allSites = sites;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
                NotificationHelper.showError(context, '加载设置失败: $e');
      }
    }
  }

  Future<void> _saveSettings() async {
    try {
      final storage = Provider.of<StorageService>(context, listen: false);
      await storage.saveAggregateSearchSettings(_settings);
      if (mounted) {
                NotificationHelper.showInfo(context, '设置已保存');
      }
    } catch (e) {
      if (mounted) {
                NotificationHelper.showError(context, '保存设置失败: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('聚合搜索设置'),
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
        actions: const [QbSpeedIndicator()],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // 搜索线程设置
                Text(
                  '搜索设置',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '搜索线程数',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: Slider(
                                value: _settings.searchThreads.toDouble(),
                                min: 1,
                                max: 10,
                                divisions: 9,
                                label: '${_settings.searchThreads}',
                                onChanged: (value) {
                                  setState(() {
                                    _settings = _settings.copyWith(
                                      searchThreads: value.round(),
                                    );
                                  });
                                },
                                onChangeEnd: (value) => _saveSettings(),
                              ),
                            ),
                            SizedBox(
                              width: 40,
                              child: Text(
                                '${_settings.searchThreads}',
                                textAlign: TextAlign.center,
                                style: Theme.of(context).textTheme.bodyLarge,
                              ),
                            ),
                          ],
                        ),
                        Text(
                          '同时搜索的站点数量，建议设置为3-5',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.outline,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // 搜索配置管理
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '搜索配置',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    FilledButton.icon(
                      onPressed: _showAddConfigDialog,
                      icon: const Icon(Icons.add),
                      label: const Text('添加配置'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                // 配置列表
                if (_settings.searchConfigs.isEmpty)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        children: [
                          Icon(
                            Icons.search_off,
                            size: 48,
                            color: Theme.of(context).colorScheme.outline,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            '暂无搜索配置',
                            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                              color: Theme.of(context).colorScheme.outline,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '点击上方"添加配置"按钮创建第一个搜索配置',
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: Theme.of(context).colorScheme.outline,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  ...(_settings.searchConfigs.map((config) => Card(
                    child: ListTile(
                      leading: Icon(
                        config.isActive ? Icons.search : Icons.search_off,
                        color: config.isActive
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).colorScheme.outline,
                      ),
                      title: Row(
                        children: [
                          Text(config.name),
                          if (config.isAllSitesType) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.primaryContainer,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                '默认',
                                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      subtitle: Text(config.isAllSitesType
                          ? '包含所有已配置的站点'
                          : '${config.enabledSites.length} 个站点'),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Switch(
                            value: config.isActive,
                            onChanged: (value) => _toggleConfig(config.id, value),
                          ),
                          PopupMenuButton<String>(
                            onSelected: (action) {
                              switch (action) {
                                case 'edit':
                                  _showEditConfigDialog(config);
                                  break;
                                case 'delete':
                                  _deleteConfig(config.id);
                                  break;
                              }
                            },
                            itemBuilder: (context) => [
                              if (config.canEdit)
                                const PopupMenuItem(
                                  value: 'edit',
                                  child: Row(
                                    children: [
                                      Icon(Icons.edit),
                                      SizedBox(width: 8),
                                      Text('编辑'),
                                    ],
                                  ),
                                ),
                              if (config.canDelete)
                                const PopupMenuItem(
                                  value: 'delete',
                                  child: Row(
                                    children: [
                                      Icon(Icons.delete),
                                      SizedBox(width: 8),
                                      Text('删除'),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ))),
              ],
            ),
    );
  }

  void _toggleConfig(String configId, bool isActive) {
    final configs = _settings.searchConfigs.map((config) {
      if (config.id == configId) {
        return config.copyWith(isActive: isActive);
      }
      return config;
    }).toList();

    setState(() {
      _settings = _settings.copyWith(searchConfigs: configs);
    });
    _saveSettings();
  }

  void _deleteConfig(String configId) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认删除'),
        content: const Text('确定要删除这个搜索配置吗？'),
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
              Navigator.pop(context);
              final configs = _settings.searchConfigs
                  .where((config) => config.id != configId)
                  .toList();
              setState(() {
                _settings = _settings.copyWith(searchConfigs: configs);
              });
              _saveSettings();
            },
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }

  void _showAddConfigDialog() {
    _showConfigDialog(null);
  }

  void _showEditConfigDialog(AggregateSearchConfig config) {
    _showConfigDialog(config);
  }

  void _showConfigDialog(AggregateSearchConfig? existingConfig) {
    final nameController = TextEditingController(text: existingConfig?.name ?? '');

    // 初始化选中的站点ID
    Set<String> selectedSiteIds;
    if (existingConfig?.isAllSitesType == true) {
      // 对于"所有站点"配置，默认选中所有站点
      selectedSiteIds = Set<String>.from(_allSites.map((site) => site.id));
    } else {
      selectedSiteIds = Set<String>.from(existingConfig?.enabledSites.map((site) => site.id) ?? []);
    }

    // 存储每个站点的分类选择
    final Map<String, Set<String>> siteCategories = {};

    // 初始化现有配置的分类选择
    if (existingConfig != null) {
      for (final siteItem in existingConfig.enabledSites) {
        final params = siteItem.additionalParams;
        if (params != null && params['selectedCategories'] != null) {
          siteCategories[siteItem.id] = Set<String>.from(params['selectedCategories'] as List);
        } else {
          siteCategories[siteItem.id] = <String>{};
        }
      }
    }

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(existingConfig == null ? '添加搜索配置' : '编辑搜索配置'),
          content: SizedBox(
            width: double.maxFinite,
            height: 600, // 增加高度以容纳分类选择
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: '配置名称',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  '选择站点和分类',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: Theme.of(context).colorScheme.outline),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: ListView(
                      children: _allSites.map((site) {
                        final isSelected = selectedSiteIds.contains(site.id);
                        final selectedCategories = siteCategories[site.id] ?? <String>{};

                        return ExpansionTile(
                          leading: Checkbox(
                            value: isSelected,
                            onChanged: (value) {
                              setDialogState(() {
                                if (value == true) {
                                  selectedSiteIds.add(site.id);
                                  if (!siteCategories.containsKey(site.id)) {
                                    siteCategories[site.id] = <String>{};
                                  }
                                } else {
                                  selectedSiteIds.remove(site.id);
                                  siteCategories.remove(site.id);
                                }
                              });
                            },
                          ),
                          title: Text(site.name),
                          subtitle: Text(site.baseUrl),
                          initiallyExpanded: false, // 默认关闭分类选择
                          children: site.searchCategories.isNotEmpty
                              ? [
                                  Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        if (!isSelected)
                                          Text(
                                            '请先选择站点才能配置分类',
                                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                              color: Theme.of(context).colorScheme.outline,
                                            ),
                                          )
                                        else ...[
                                          Text(
                                            '选择分类（不选择表示使用所有分类）',
                                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                              color: Theme.of(context).colorScheme.outline,
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                          Wrap(
                                            spacing: 8,
                                            runSpacing: 4,
                                            children: site.searchCategories.map((category) {
                                              final isCategorySelected = selectedCategories.contains(category.id);
                                              return FilterChip(
                                                label: Text(category.displayName),
                                                selected: isCategorySelected,
                                                onSelected: isSelected ? (selected) {
                                                  setDialogState(() {
                                                    if (selected) {
                                                      selectedCategories.add(category.id);
                                                    } else {
                                                      selectedCategories.remove(category.id);
                                                    }
                                                    siteCategories[site.id] = selectedCategories;
                                                  });
                                                } : null, // 未选中站点时禁用分类选择
                                              );
                                            }).toList(),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                ]
                              : [],
                        );
                      }).toList(),
                    ),
                  ),
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
                if (nameController.text.trim().isEmpty) {
                                    NotificationHelper.showError(context, '请输入配置名称');
                  return;
                }
                if (selectedSiteIds.isEmpty) {
                                    NotificationHelper.showError(context, '请至少选择一个站点');
                  return;
                }

                Navigator.pop(context);
                _saveConfig(existingConfig, nameController.text.trim(), selectedSiteIds.toList(), siteCategories);
              },
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
  }

  void _saveConfig(AggregateSearchConfig? existingConfig, String name, List<String> siteIds, Map<String, Set<String>> siteCategories) {
    final config = AggregateSearchConfig(
      id: existingConfig?.id ?? 'config-${DateTime.now().millisecondsSinceEpoch}',
      name: name,
      type: existingConfig?.type ?? 'custom', // 保持原有类型
      enabledSites: siteIds.map((id) {
        final selectedCategories = siteCategories[id];
        Map<String, dynamic>? additionalParams;

        // 只有当用户选择了特定分类时才保存分类信息
        if (selectedCategories != null && selectedCategories.isNotEmpty) {
          // 过滤掉不存在的分类ID
          final site = _allSites.firstWhere(
            (s) => s.id == id,
            orElse: () => const SiteConfig(id: '', name: '', baseUrl: ''),
          );
          final validCategoryIds = site.searchCategories
              .map((c) => c.id)
              .toSet();
          final validSelectedCategories = selectedCategories
              .where((c) => validCategoryIds.contains(c))
              .toList();

          if (validSelectedCategories.isNotEmpty) {
            additionalParams = {
              'selectedCategories': validSelectedCategories};
          }
        }

        return SiteSearchItem(
          id: id,
          additionalParams: additionalParams,
        );
      }).toList(),
      isActive: existingConfig?.isActive ?? true,
    );

    List<AggregateSearchConfig> configs;
    if (existingConfig == null) {
      // 添加新配置
      configs = [..._settings.searchConfigs, config];
    } else {
      // 更新现有配置
      configs = _settings.searchConfigs.map((c) {
        return c.id == existingConfig.id ? config : c;
      }).toList();
    }

    setState(() {
      _settings = _settings.copyWith(searchConfigs: configs);
    });
    _saveSettings();
  }
}