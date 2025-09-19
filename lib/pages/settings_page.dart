import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/storage/storage_service.dart';
import '../services/theme/theme_manager.dart';
import '../widgets/qb_speed_indicator.dart';
import '../widgets/responsive_layout.dart';
import 'backup_restore_page.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ResponsiveLayout(
      currentRoute: '/settings',
      appBar: AppBar(
        title: const Text('设置'),
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
      body: const _SettingsBody(),
    );
  }
}

// 查询分类配置已移至站点配置中，请在服务器设置页面进行配置

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
        
        // 备份恢复
        Text(
          '数据管理',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Card(
          child: ListTile(
            leading: const Icon(Icons.backup),
            title: const Text('备份与恢复'),
            subtitle: const Text('导出或导入应用数据'),
            trailing: const Icon(Icons.arrow_forward_ios),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => const BackupRestorePage(),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 16),
        
        // 查询条件配置已移至站点配置中，可在服务器配置页面管理
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