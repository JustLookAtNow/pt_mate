import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/app_models.dart';
import '../services/storage/storage_service.dart';
import '../services/theme/theme_manager.dart';
import '../widgets/qb_speed_indicator.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('设置'),
        actions: const [QbSpeedIndicator()],
      ),
      body: const _SettingsBody(),
    );
  }
}

class _SearchCategoriesConfigTile extends StatefulWidget {
  @override
  State<_SearchCategoriesConfigTile> createState() => _SearchCategoriesConfigTileState();
}

class _SearchCategoriesConfigTileState extends State<_SearchCategoriesConfigTile> {
  List<SearchCategoryConfig> _categories = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadCategories();
  }

  Future<void> _loadCategories() async {
    try {
      final storage = Provider.of<StorageService>(context, listen: false);
      final categories = await storage.loadSearchCategories();
      if (mounted) {
        setState(() {
          _categories = categories;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _saveCategories() async {
    try {
      final storage = Provider.of<StorageService>(context, listen: false);
      await storage.saveSearchCategories(_categories);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('保存失败: $e')),
        );
      }
    }
  }

  void _addCategory() {
    setState(() {
      _categories.add(SearchCategoryConfig(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        displayName: '新分类',
        parameters: '{"mode": "normal"}',
      ));
    });
    _saveCategories();
  }

  void _removeCategory(int index) {
    setState(() {
      _categories.removeAt(index);
    });
    _saveCategories();
  }

  void _editCategory(int index) async {
    final category = _categories[index];
    final result = await showDialog<SearchCategoryConfig>(
      context: context,
      builder: (context) => _CategoryEditDialog(category: category),
    );
    if (result != null) {
      setState(() {
        _categories[index] = result;
      });
      _saveCategories();
    }
  }

  void _resetToDefault() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('重置确认'),
        content: const Text('确定要重置为默认配置吗？这将删除所有自定义配置。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      setState(() {
        _categories = SearchCategoryConfig.getDefaultConfigs();
      });
      _saveCategories();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const ListTile(
        leading: Icon(Icons.category),
        title: Text('查询分类'),
        trailing: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    return Column(
      children: [
        ListTile(
          leading: const Icon(Icons.category),
          title: const Text('查询分类'),
          subtitle: Text('共 ${_categories.length} 个分类'),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: _resetToDefault,
                tooltip: '重置为默认',
              ),
              IconButton(
                icon: const Icon(Icons.add),
                onPressed: _addCategory,
                tooltip: '添加分类',
              ),
            ],
          ),
        ),
        ..._categories.asMap().entries.map((entry) {
          final index = entry.key;
          final category = entry.value;
          return ListTile(
            leading: const SizedBox(width: 24),
            title: Text(category.displayName),
            subtitle: Text(
              category.parameters,
              style: const TextStyle(fontSize: 12),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.edit, size: 20),
                  onPressed: () => _editCategory(index),
                  tooltip: '编辑',
                ),
                IconButton(
                  icon: const Icon(Icons.delete, size: 20),
                  onPressed: () => _removeCategory(index),
                  tooltip: '删除',
                ),
              ],
            ),
          );
        }),
      ],
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

class _SettingsBody extends StatelessWidget {
  const _SettingsBody();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // 主题设置
        Text(
          '主题设置',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Card(
          child: Column(
            children: [
              Consumer<ThemeManager>(
                builder: (context, themeManager, child) {
                  return Column(
                    children: [
                      ListTile(
                        leading: const Icon(Icons.brightness_6),
                        title: const Text('主题模式'),
                        subtitle: Text(_getThemeModeText(themeManager.themeMode)),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16.0),
                        child: SegmentedButton<AppThemeMode>(
                          segments: const [
                            ButtonSegment(
                              value: AppThemeMode.system,
                              label: Text('自动'),
                              icon: Icon(Icons.brightness_auto),
                            ),
                            ButtonSegment(
                              value: AppThemeMode.light,
                              label: Text('浅色'),
                              icon: Icon(Icons.light_mode),
                            ),
                            ButtonSegment(
                              value: AppThemeMode.dark,
                              label: Text('深色'),
                              icon: Icon(Icons.dark_mode),
                            ),
                          ],
                          selected: {themeManager.themeMode},
                          onSelectionChanged: (Set<AppThemeMode> selection) {
                            themeManager.setThemeMode(selection.first);
                          },
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                  );
                },
              ),
              Consumer<ThemeManager>(
                builder: (context, themeManager, child) {
                  return SwitchListTile(
                    secondary: const Icon(Icons.palette),
                    title: const Text('动态取色'),
                    subtitle: const Text('根据壁纸自动调整主题色'),
                    value: themeManager.useDynamicColor,
                    onChanged: (value) {
                      themeManager.setUseDynamicColor(value);
                    },
                  );
                },
              ),
              Consumer<ThemeManager>(
                builder: (context, themeManager, child) {
                  if (themeManager.useDynamicColor) {
                    return const SizedBox();
                  }
                  return _ColorPickerTile(
                    currentColor: themeManager.seedColor,
                    onColorChanged: (color) {
                      themeManager.setSeedColor(color);
                    },
                  );
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        
        // 图片设置
        Text(
          '图片设置',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Card(
          child: _AutoLoadImagesTile(),
        ),
        const SizedBox(height: 16),
        
        // 查询条件配置
        Text(
          '查询条件配置',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Card(
          child: _SearchCategoriesConfigTile(),
        ),
      ],
    );
  }

  String _getThemeModeText(AppThemeMode mode) {
    switch (mode) {
      case AppThemeMode.system:
        return '跟随系统';
      case AppThemeMode.light:
        return '浅色';
      case AppThemeMode.dark:
        return '深色';
    }
  }
}

class _ColorPickerTile extends StatelessWidget {
  final Color currentColor;
  final ValueChanged<Color> onColorChanged;

  const _ColorPickerTile({
    required this.currentColor,
    required this.onColorChanged,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.color_lens),
      title: const Text('自定义主题色'),
      trailing: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: currentColor,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.grey),
        ),
      ),
      onTap: () async {
        final color = await showDialog<Color>(
          context: context,
          builder: (context) => _ColorPickerDialog(
            initialColor: currentColor,
          ),
        );
        if (color != null) {
          onColorChanged(color);
        }
      },
    );
  }
}

class _ColorPickerDialog extends StatefulWidget {
  final Color initialColor;

  const _ColorPickerDialog({
    required this.initialColor,
  });

  @override
  State<_ColorPickerDialog> createState() => _ColorPickerDialogState();
}

class _ColorPickerDialogState extends State<_ColorPickerDialog> {
  late Color _selectedColor;
  
  @override
  void initState() {
    super.initState();
    _selectedColor = widget.initialColor;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('选择主题色'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 预设颜色
            const Text(
              '预设颜色',
              style: TextStyle(fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
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
              ].map((color) => _ColorCircle(
                color: color,
                isSelected: _selectedColor.toARGB32() == color.toARGB32(),
                onTap: () => setState(() => _selectedColor = color),
              )).toList(),
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
          onPressed: () => Navigator.pop(context, _selectedColor),
          child: const Text('确定'),
        ),
      ],
    );
  }
}

class _ColorCircle extends StatelessWidget {
  final Color color;
  final bool isSelected;
  final VoidCallback onTap;
  
  const _ColorCircle({
    required this.color,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: isSelected
              ? Border.all(color: Colors.white, width: 3)
              : null,
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: color.withValues(alpha: 0.5),
                    blurRadius: 8,
                    spreadRadius: 2,
                  ),
                ]
              : null,
        ),
        child: isSelected
            ? const Icon(
                Icons.check,
                color: Colors.white,
                size: 20,
              )
            : null,
      ),
    );
  }
}

class _AutoLoadImagesTile extends StatefulWidget {
  @override
  State<_AutoLoadImagesTile> createState() => _AutoLoadImagesTileState();
}

class _AutoLoadImagesTileState extends State<_AutoLoadImagesTile> {
  bool _autoLoad = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadSetting();
  }

  Future<void> _loadSetting() async {
    try {
      final storage = Provider.of<StorageService>(context, listen: false);
      final autoLoad = await storage.loadAutoLoadImages();
      if (mounted) {
        setState(() {
          _autoLoad = autoLoad;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _saveSetting(bool value) async {
    try {
      final storage = Provider.of<StorageService>(context, listen: false);
      await storage.saveAutoLoadImages(value);
      if (mounted) {
        setState(() => _autoLoad = value);
      }
    } catch (e) {
      // 保存失败时恢复原值
      if (mounted) {
        setState(() => _autoLoad = !value);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const ListTile(
        leading: Icon(Icons.image),
        title: Text('自动加载图片'),
        trailing: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    return SwitchListTile(
      secondary: const Icon(Icons.image),
      title: const Text('自动加载图片'),
      subtitle: const Text('在种子详情页面自动显示图片'),
      value: _autoLoad,
      onChanged: _saveSetting,
    );
  }
}