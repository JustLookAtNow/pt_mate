import 'package:flutter/material.dart';

/// 全局屏幕断点配置
class ScreenUtils {
  /// 大屏设备断点宽度 (768px)
  static const double kLargeScreenBreakpoint = 768.0;

  /// 判断是否为大屏设备
  static bool isLargeScreen(BuildContext context) {
    return MediaQuery.of(context).size.width > kLargeScreenBreakpoint;
  }
}
