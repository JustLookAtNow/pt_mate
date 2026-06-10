import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart';
import 'package:dynamic_color/dynamic_color.dart';
import '../storage/storage_service.dart';
import 'app_tokens.dart';

enum AppThemeMode { system, light, dark }

class ThemeManager extends ChangeNotifier {
  final StorageService _storageService;

  AppThemeMode _themeMode = AppThemeMode.system;
  bool _useDynamicColor = true;
  Color _seedColor = Colors.deepPurple;
  ColorScheme? _dynamicLightColorScheme;
  ColorScheme? _dynamicDarkColorScheme;
  static final Logger _logger = Logger();

  ThemeManager(this._storageService) {
    _loadThemeSettings();
  }

  // 获取字体fallback配置
  List<String>? _getFontFallback() {
    switch (Platform.operatingSystem) {
      case 'windows':
        return [
          'Microsoft YaHei UI',
          'Microsoft YaHei',
          'SimHei',
          'SimSun',
          'Arial Unicode MS',
          'sans-serif',
        ];
      case 'linux':
        return [
          'WenQuanYi Zen Hei',
          'Noto Sans CJK SC',
          'Source Han Sans SC',
          'DejaVu Sans',
          'Liberation Sans',
          'sans-serif',
        ];
      case 'macos':
        return [
          'PingFang SC',
          'Hiragino Sans GB',
          'STHeiti',
          'Arial Unicode MS',
          'Helvetica Neue',
          'sans-serif',
        ];
      default:
        // 安卓、iOS使用系统默认字体
        return null;
    }
  }

  // Getters
  AppThemeMode get themeMode => _themeMode;
  bool get useDynamicColor => _useDynamicColor;
  Color get seedColor => _seedColor;
  ColorScheme? get dynamicLightColorScheme => _dynamicLightColorScheme;
  ColorScheme? get dynamicDarkColorScheme => _dynamicDarkColorScheme;

  // 获取当前的亮色主题
  ThemeData get lightTheme {
    ColorScheme colorScheme;

    if (_useDynamicColor && _dynamicLightColorScheme != null) {
      colorScheme = _dynamicLightColorScheme!;
    } else {
      colorScheme = ColorScheme.fromSeed(
        seedColor: _seedColor,
        brightness: Brightness.light,
      );
    }

    return _buildTheme(colorScheme, AppSemanticColors.light);
  }

  // 获取当前的暗色主题
  ThemeData get darkTheme {
    ColorScheme colorScheme;

    if (_useDynamicColor && _dynamicDarkColorScheme != null) {
      colorScheme = _dynamicDarkColorScheme!;
    } else {
      colorScheme = ColorScheme.fromSeed(
        seedColor: _seedColor,
        brightness: Brightness.dark,
      );
    }

    return _buildTheme(colorScheme, AppSemanticColors.dark);
  }

  ThemeData _buildTheme(ColorScheme colorScheme, AppSemanticColors semantic) {
    final fontFallback = _getFontFallback();
    final isDark = colorScheme.brightness == Brightness.dark;
    final appBarBackground = isDark
        ? colorScheme.primaryContainer
        : colorScheme.primary;
    final appBarForeground = isDark
        ? colorScheme.onPrimaryContainer
        : colorScheme.onPrimary;

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      fontFamilyFallback: fontFallback,
      extensions: [semantic],
      appBarTheme: AppBarTheme(
        backgroundColor: appBarBackground,
        foregroundColor: appBarForeground,
        elevation: 0,
        scrolledUnderElevation: 2,
        surfaceTintColor: Colors.transparent,
        iconTheme: IconThemeData(color: appBarForeground),
        actionsIconTheme: IconThemeData(color: appBarForeground),
        titleTextStyle: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w500,
          color: appBarForeground,
          fontFamilyFallback: fontFallback,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: colorScheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          side: BorderSide(color: colorScheme.outline.withValues(alpha: 0.15)),
        ),
        margin: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs,
        ),
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        labelStyle: TextStyle(
          fontSize: AppFontSize.caption,
          color: colorScheme.onSurfaceVariant,
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: 2,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        isDense: true,
      ),
      dividerTheme: DividerThemeData(
        color: colorScheme.outlineVariant.withValues(alpha: 0.5),
        space: 1,
        thickness: 1,
      ),
      listTileTheme: ListTileThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
      ),
    );
  }

  // 获取Flutter的ThemeMode
  ThemeMode get flutterThemeMode {
    switch (_themeMode) {
      case AppThemeMode.light:
        return ThemeMode.light;
      case AppThemeMode.dark:
        return ThemeMode.dark;
      case AppThemeMode.system:
        return ThemeMode.system;
    }
  }

  // 初始化动态颜色
  Future<void> initializeDynamicColor() async {
    final corePalette = await DynamicColorPlugin.getCorePalette();
    if (corePalette != null) {
      _dynamicLightColorScheme = corePalette.toColorScheme();
      _dynamicDarkColorScheme = corePalette.toColorScheme(
        brightness: Brightness.dark,
      );
      notifyListeners();
    }
  }

  // 设置主题模式
  Future<void> setThemeMode(AppThemeMode mode) async {
    if (_themeMode != mode) {
      _themeMode = mode;
      await _storageService.saveThemeMode(mode.name);
      notifyListeners();
    }
  }

  // 设置是否使用动态颜色
  Future<void> setUseDynamicColor(bool useDynamic) async {
    if (_useDynamicColor != useDynamic) {
      _useDynamicColor = useDynamic;
      await _storageService.saveUseDynamicColor(useDynamic);
      notifyListeners();
    }
  }

  // 设置种子颜色
  Future<void> setSeedColor(Color color) async {
    if (_seedColor != color) {
      _seedColor = color;
      await _storageService.saveSeedColor(color.toARGB32());
      notifyListeners();
    }
  }

  // 加载主题设置
  Future<void> _loadThemeSettings() async {
    try {
      // 加载主题模式
      final themeModeString = await _storageService.loadThemeMode();
      if (themeModeString != null) {
        _themeMode = AppThemeMode.values.firstWhere(
          (mode) => mode.name == themeModeString,
          orElse: () => AppThemeMode.system,
        );
      }

      // 加载动态颜色设置
      final useDynamic = await _storageService.loadUseDynamicColor();
      if (useDynamic != null) {
        _useDynamicColor = useDynamic;
      }

      // 加载种子颜色
      final seedColorValue = await _storageService.loadSeedColor();
      if (seedColorValue != null) {
        _seedColor = Color(seedColorValue);
      }

      notifyListeners();
    } catch (e) {
      if (kDebugMode) {
        _logger.e('加载主题设置失败: $e');
      }
    }
  }
}
