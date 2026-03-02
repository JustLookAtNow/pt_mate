import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter/foundation.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter/services.dart';
import 'dart:io';

import '../services/storage/storage_service.dart';
import '../models/app_models.dart';
import '../services/theme/theme_manager.dart';
import '../widgets/qb_speed_indicator.dart';
import '../widgets/responsive_layout.dart';
import '../services/logging/log_file_service.dart';
import 'backup_restore_page.dart';
import 'aggregate_search_settings_page.dart';
import 'downloader_settings_page.dart';
import '../services/update_service.dart';
import '../services/debug/web_debug_service.dart';
import 'package:pt_mate/utils/notification_helper.dart';

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


        // 下载器设置
        Text(
          '下载器设置',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Card(
          child: ListTile(
            leading: const Icon(Icons.download_outlined),
            title: const Text('下载器配置'),
            subtitle: const Text('管理跟配置所有下载器'),
            trailing: const Icon(Icons.arrow_forward_ios),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => const DownloaderSettingsPage(),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 16),

        // 显示设置
        Text(
          '显示设置',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Card(
          child: Column(
            children: [
              _AutoLoadImagesTile(),
              const Divider(height: 1),
              _ShowCoverImagesTile(),
              const Divider(height: 1),
              const _DisplayTagSettingsTile(),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // 聚合搜索设置
        Text(
          '聚合搜索',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Card(
          child: ListTile(
            leading: const Icon(Icons.search),
            title: const Text('聚合搜索设置'),
            subtitle: const Text('配置搜索策略和线程数'),
            trailing: const Icon(Icons.arrow_forward_ios),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => const AggregateSearchSettingsPage(),
                ),
              );
            },
          ),
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
        // 更新设置
        Text(
          '更新设置',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        const _BetaUpdateTile(),
        const SizedBox(height: 16),

        // 查询条件配置已移至站点配置中，可在站点配置页面管理
        // 日志与诊断（底部）
        const SizedBox(height: 8),
        Text(
          '调试与诊断',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Card(
          child: Column(
            children: const [
              _LogToFileTile(),
              Divider(height: 1),
              _ExportLogsTile(),
              Divider(height: 1),
              _ClearLogsTile(),
              Divider(height: 1),
              _WebDebugToggleTile(),
            ],
          ),
        ),
        const SizedBox(height: 24),
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

class _WebDebugToggleTile extends StatefulWidget {
  const _WebDebugToggleTile();

  @override
  State<_WebDebugToggleTile> createState() => _WebDebugToggleTileState();
}

class _WebDebugToggleTileState extends State<_WebDebugToggleTile> {
  bool _enabled = false;
  List<String> _serviceUrls = [];

  Future<void> _toggle(bool value) async {
    setState(() {
      _enabled = value;
    });
    if (value) {
      if (kIsWeb) {
        NotificationHelper.showError(context, '当前为 Web 构建，无法启动本地调试服务');
        setState(() {
          _enabled = false;
        });
        return;
      }
      try {
        final ok = await WebDebugService.instance.start();
        if (!mounted) return;
        _serviceUrls = WebDebugService.instance.hostUrls;
        setState(() {});
        NotificationHelper.showInfo(
          context,
          ok ? 'Web 调试服务已启动' : 'Web 调试服务启动失败',
        );
      } catch (e) {
        NotificationHelper.showError(context, '启动失败：$e');
        setState(() {
          _enabled = false;
        });
      }
    } else {
      await WebDebugService.instance.stop();
      if (!mounted) return;
      _serviceUrls = [];
      setState(() {});
      NotificationHelper.showError(context, 'Web 调试服务已停止');
    }
  }

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      secondary: const Icon(Icons.bug_report),
      title: const Text('Web 调试'),
      subtitle: WebDebugService.instance.isRunning
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('运行中，点击复制地址：'),
                const SizedBox(height: 4),
                ...(_serviceUrls.isNotEmpty
                        ? _serviceUrls
                        : WebDebugService.instance.hostUrls)
                    .map(
                      (url) => InkWell(
                        onTap: () {
                          Clipboard.setData(ClipboardData(text: url));
                          NotificationHelper.showInfo(context, '已复制到剪贴板');
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Text(
                            url,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.primary,
                              decoration: TextDecoration.underline,
                            ),
                          ),
                        ),
                      ),
                    ),
              ],
            )
          : const Text('启用后在局域网使用浏览器访问来调试网站配置'),
      value: _enabled && WebDebugService.instance.isRunning,
      onChanged: _toggle,
    );
  }
}


class _BetaUpdateTile extends StatefulWidget {
  const _BetaUpdateTile();

  @override
  State<_BetaUpdateTile> createState() => _BetaUpdateTileState();
}

class _BetaUpdateTileState extends State<_BetaUpdateTile> {
  bool _enabled = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final v = await UpdateService.instance.isBetaOptInEnabled();
    if (!mounted) return;
    setState(() {
      _enabled = v;
      _loading = false;
    });
  }

  Future<void> _set(bool value) async {
    setState(() {
      _enabled = value;
    });
    await UpdateService.instance.setBetaOptIn(value);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Card(
        child: ListTile(
          leading: SizedBox(
            height: 24,
            width: 24,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          title: Text('尝鲜（接收 Beta 版本更新）'),
          subtitle: Text('正在加载当前设置…'),
        ),
      );
    }

    return Card(
      child: SwitchListTile(
        secondary: const Icon(Icons.new_releases),
        title: const Text('尝鲜（接收 Beta 版本更新）'),
        subtitle: const Text('默认仅接收稳定版本；开启后可接收 Beta/RC 等预发布版本更新'),
        value: _enabled,
        onChanged: _set,
      ),
    );
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
  bool _customMode = false;
  final TextEditingController _hexController = TextEditingController();
  double _h = 0.0;
  double _s = 1.0;
  double _v = 1.0;

  @override
  void initState() {
    super.initState();
    _selectedColor = widget.initialColor;
    _hexController.text = '#${_selectedColor.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase().substring(2)}';
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

  // 移除透明度逻辑，使用 HSV 的 h/s/v 构成颜色

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
                          onTap: () => setState(() {
                            _selectedColor = color;
                            _hexController.text = _toHexRGB(color);
                            _customMode = false;
                          }),
              )).toList(),
            ),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.palette_outlined),
              title: const Text('自定义颜色...'),
              subtitle: const Text('支持 #RRGGBB 或 #AARRGGBB'),
              onTap: () => setState(() => _customMode = true),
            ),
            if (_customMode) ...[
              const SizedBox(height: 8),
              // 上方矩形：固定色相，调饱和度/明度
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
                              _hexController.text =
                                  '#${_selectedColor.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase().substring(2)}';
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
              // 下方色相条
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
                            _hexController.text =
                                '#${_selectedColor.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase().substring(2)}';
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
              const SizedBox(height: 8),
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
              // const SizedBox(height: 8),
              // Container(
              //   width: double.infinity,
              //   height: 36,
              //   decoration: BoxDecoration(
              //     color: _selectedColor,
              //     borderRadius: BorderRadius.circular(6),
              //     border: Border.all(color: Theme.of(context).colorScheme.outline),
              //   ),
              // ),
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
      title: const Text('详情页图片'),
      subtitle: const Text('在种子详情页面自动显示图片'),
      value: _autoLoad,
      onChanged: _saveSetting,
    );
  }
}

class _ShowCoverImagesTile extends StatefulWidget {
  @override
  State<_ShowCoverImagesTile> createState() => _ShowCoverImagesTileState();
}

class _ShowCoverImagesTileState extends State<_ShowCoverImagesTile> {
  bool _showCover = true;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadSetting();
  }

  Future<void> _loadSetting() async {
    try {
      final storage = Provider.of<StorageService>(context, listen: false);
      final showCover = await storage.loadShowCoverImages();
      if (mounted) {
        setState(() {
          _showCover = showCover;
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
      await storage.saveShowCoverImages(value);
      if (mounted) {
        setState(() => _showCover = value);
      }
    } catch (e) {
      // 保存失败时恢复原值
      if (mounted) {
        setState(() => _showCover = !value);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const ListTile(
        leading: Icon(Icons.photo_library),
        title: Text('封面图片'),
        trailing: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    return SwitchListTile(
      secondary: const Icon(Icons.photo_library),
      title: const Text('封面图片'),
      subtitle: Text(_showCover ? '根据站点配置显示' : '不显示封面'),
      value: _showCover,
      onChanged: _saveSetting,
    );
  }
}

class _DisplayTagSettingsTile extends StatefulWidget {
  const _DisplayTagSettingsTile();

  @override
  State<_DisplayTagSettingsTile> createState() =>
      _DisplayTagSettingsTileState();
}

class _DisplayTagSettingsTileState extends State<_DisplayTagSettingsTile> {
  bool _expanded = false;
  List<String> _visibleTags = [];

  @override
  void initState() {
    super.initState();
    _visibleTags = List.from(StorageService.instance.visibleTags);
  }

  Future<void> _toggleTag(String tagName) async {
    setState(() {
      if (_visibleTags.contains(tagName)) {
        _visibleTags.remove(tagName);
      } else {
        _visibleTags.add(tagName);
      }
    });
    await StorageService.instance.saveVisibleTags(_visibleTags);
  }

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      leading: const Icon(Icons.label_outline),
      title: const Text('过滤标签设置'),
      subtitle: const Text('设置显示在顶部的快捷过滤标签'),
      initiallyExpanded: _expanded,
      onExpansionChanged: (value) {
        setState(() {
          _expanded = value;
        });
      },
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: TagType.values.map((tag) {
              final isSelected = _visibleTags.contains(tag.name);
              return FilterChip(
                label: Text(tag.content),
                selected: isSelected,
                onSelected: (bool selected) {
                  _toggleTag(tag.name);
                },
                backgroundColor: tag.color.withValues(alpha: 0.1),
                selectedColor: tag.color.withValues(alpha: 0.3),
                labelStyle: TextStyle(
                  color: isSelected
                      ? tag.color
                      : Theme.of(context).textTheme.bodyMedium?.color,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
                checkmarkColor: tag.color,
                side: BorderSide(
                  color: isSelected
                      ? tag.color
                      : Colors.grey.withValues(alpha: 0.3),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }
}

class _LogToFileTile extends StatefulWidget {
  const _LogToFileTile();

  @override
  State<_LogToFileTile> createState() => _LogToFileTileState();
}

class _LogToFileTileState extends State<_LogToFileTile> {
  bool _enabled = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final enabled = await StorageService.instance.loadLogToFileEnabled();
      if (mounted) {
        setState(() {
          _enabled = enabled;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _set(bool value) async {
    try {
      await StorageService.instance.saveLogToFileEnabled(value);
      await LogFileService.instance.setEnabled(value);
      if (!mounted) return;
      setState(() => _enabled = value);

      NotificationHelper.showInfo(context, value ? '已开启本地日志记录' : '已关闭本地日志记录');
    } catch (e) {
      if (!mounted) return;
      NotificationHelper.showError(context, '操作失败: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const ListTile(
        leading: Icon(Icons.bug_report),
        title: Text('记录日志到本地文件'),
        trailing: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    return SwitchListTile(
      secondary: const Icon(Icons.bug_report),
      title: const Text('记录日志到本地文件'),
      subtitle: const Text('用于问题定位与反馈（Web 不支持）'),
      value: _enabled,
      onChanged: kIsWeb ? null : _set,
    );
  }
}

class _ExportLogsTile extends StatelessWidget {
  const _ExportLogsTile();

  Future<void> _shareLatest(BuildContext context) async {
    try {
      if (kIsWeb) {
        NotificationHelper.showError(context, 'Web 平台不支持文件落盘');
        return;
      }

      final path = await LogFileService.instance.currentLogFilePath();
      if (!context.mounted) return;
      if (path == null || !(await File(path).exists())) {
        if (!context.mounted) return;
        NotificationHelper.showError(context, '暂无日志文件或未开启记录');
        return;
      }
      await SharePlus.instance.share(
        ShareParams(files: [XFile(path)], text: 'PT Mate 日志'),
      );
    } catch (e) {
      if (!context.mounted) return;
      NotificationHelper.showError(context, '分享失败: $e');
    }
  }

  Future<void> _openDir(BuildContext context) async {
    try {
      if (kIsWeb) {
        NotificationHelper.showError(context, 'Web 平台不支持文件落盘');
        return;
      }
      final dir = await LogFileService.instance.logsDirectoryPath();
      if (!context.mounted) return;
      NotificationHelper.showInfo(context, '日志目录: $dir');
    } catch (e) {
      NotificationHelper.showError(context, '打开目录失败: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.share),
      title: const Text('导出日志'),
      subtitle: const Text('通过系统分享面板发送日志给开发者'),
      onTap: () async {
        await showModalBottomSheet<void>(
          context: context,
          builder: (ctx) {
            return SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListTile(
                    leading: const Icon(Icons.ios_share),
                    title: const Text('分享最新日志文件'),
                    onTap: () async {
                      Navigator.pop(ctx);
                      await _shareLatest(context);
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.folder_open),
                    title: const Text('显示日志目录路径'),
                    onTap: () async {
                      Navigator.pop(ctx);
                      await _openDir(context);
                    },
                  ),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          style: TextButton.styleFrom(
                            side: BorderSide(
                              color: Theme.of(ctx).colorScheme.outline,
                              width: 1.0,
                            ),
                          ),
                          child: const Text('取消'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _ClearLogsTile extends StatelessWidget {
  const _ClearLogsTile();

  Future<void> _clear(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清理日志'),
        content: const Text('确定要删除所有日志文件吗？此操作不可恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            style: TextButton.styleFrom(
              side: BorderSide(
                color: Theme.of(ctx).colorScheme.outline,
                width: 1.0,
              ),
            ),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      final count = await LogFileService.instance.clearLogs();
      if (!context.mounted) return;
      NotificationHelper.showInfo(context, '已清理日志文件 $count 个');
    } catch (e) {
      if (!context.mounted) return;
      NotificationHelper.showError(context, '清理失败: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.delete_forever),
      title: const Text('清理日志'),
      subtitle: const Text('删除应用日志目录下的所有日志文件'),
      onTap: () => _clear(context),
    );
  }
}
