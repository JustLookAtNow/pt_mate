import 'package:flutter/material.dart';

/// 全局设计 token：间距、圆角、辅助字号。
///
/// 列表项、徽章等组件的尺寸常量统一从这里取值，
/// 避免各文件散落魔法数字导致视觉不一致。
abstract final class AppSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
}

abstract final class AppRadius {
  /// 小元素：标签 chip、角标
  static const double sm = 6;

  /// 卡片、输入框
  static const double md = 12;

  /// 对话框、大面板
  static const double lg = 16;

  /// 胶囊形
  static const double pill = 999;
}

/// 辅助文本字号阶梯（正文用 textTheme，这里只管列表元数据等小字）
abstract final class AppFontSize {
  /// 角标、徽章
  static const double badge = 10;

  /// 列表元数据（做种数、大小、时间）
  static const double meta = 11;

  /// 副标题
  static const double caption = 12;

  /// 列表标题
  static const double title = 14;
}

/// 语义色 ThemeExtension：优惠、做种/下载、评分源、收藏等
/// 与品牌主题色无关的固定语义色，按明暗模式分别给出。
@immutable
class AppSemanticColors extends ThemeExtension<AppSemanticColors> {
  /// 优惠：免费（绿）
  final Color discountFree;

  /// 优惠：折扣（琥珀）
  final Color discountPercent;

  /// 优惠：其他（蓝）
  final Color discountOther;

  /// 做种数（上行）
  final Color seeders;

  /// 下载数（下行）
  final Color leechers;

  /// 收藏红
  final Color favorite;

  /// IMDB 徽章底色
  final Color imdbBadge;

  /// IMDB 徽章前景色
  final Color onImdbBadge;

  /// 豆瓣徽章底色
  final Color doubanBadge;

  /// 豆瓣徽章前景色
  final Color onDoubanBadge;

  const AppSemanticColors({
    required this.discountFree,
    required this.discountPercent,
    required this.discountOther,
    required this.seeders,
    required this.leechers,
    required this.favorite,
    required this.imdbBadge,
    required this.onImdbBadge,
    required this.doubanBadge,
    required this.onDoubanBadge,
  });

  static const light = AppSemanticColors(
    discountFree: Color(0xFF2E7D32), // green.shade800 提高浅色下对比度
    discountPercent: Color(0xFFB26A00), // amber 深化
    discountOther: Color(0xFF0277BD), // lightBlue.shade800
    seeders: Color(0xFF2E7D32),
    leechers: Color(0xFFC62828),
    favorite: Color(0xFFE53935),
    imdbBadge: Color(0xFFF5C518),
    onImdbBadge: Colors.black,
    doubanBadge: Color(0xFF007711),
    onDoubanBadge: Colors.white,
  );

  static const dark = AppSemanticColors(
    discountFree: Color(0xFF81C784), // green.shade300
    discountPercent: Color(0xFFFFD54F), // amber.shade300
    discountOther: Color(0xFF4FC3F7), // lightBlue.shade300
    seeders: Color(0xFF81C784),
    leechers: Color(0xFFE57373),
    favorite: Color(0xFFEF5350),
    imdbBadge: Color(0xFFF5C518),
    onImdbBadge: Colors.black,
    doubanBadge: Color(0xFF007711),
    onDoubanBadge: Colors.white,
  );

  @override
  AppSemanticColors copyWith({
    Color? discountFree,
    Color? discountPercent,
    Color? discountOther,
    Color? seeders,
    Color? leechers,
    Color? favorite,
    Color? imdbBadge,
    Color? onImdbBadge,
    Color? doubanBadge,
    Color? onDoubanBadge,
  }) {
    return AppSemanticColors(
      discountFree: discountFree ?? this.discountFree,
      discountPercent: discountPercent ?? this.discountPercent,
      discountOther: discountOther ?? this.discountOther,
      seeders: seeders ?? this.seeders,
      leechers: leechers ?? this.leechers,
      favorite: favorite ?? this.favorite,
      imdbBadge: imdbBadge ?? this.imdbBadge,
      onImdbBadge: onImdbBadge ?? this.onImdbBadge,
      doubanBadge: doubanBadge ?? this.doubanBadge,
      onDoubanBadge: onDoubanBadge ?? this.onDoubanBadge,
    );
  }

  @override
  AppSemanticColors lerp(ThemeExtension<AppSemanticColors>? other, double t) {
    if (other is! AppSemanticColors) return this;
    return AppSemanticColors(
      discountFree: Color.lerp(discountFree, other.discountFree, t)!,
      discountPercent: Color.lerp(discountPercent, other.discountPercent, t)!,
      discountOther: Color.lerp(discountOther, other.discountOther, t)!,
      seeders: Color.lerp(seeders, other.seeders, t)!,
      leechers: Color.lerp(leechers, other.leechers, t)!,
      favorite: Color.lerp(favorite, other.favorite, t)!,
      imdbBadge: Color.lerp(imdbBadge, other.imdbBadge, t)!,
      onImdbBadge: Color.lerp(onImdbBadge, other.onImdbBadge, t)!,
      doubanBadge: Color.lerp(doubanBadge, other.doubanBadge, t)!,
      onDoubanBadge: Color.lerp(onDoubanBadge, other.onDoubanBadge, t)!,
    );
  }
}

/// 便捷取用：`context.semanticColors.discountFree`
extension AppSemanticColorsContext on BuildContext {
  AppSemanticColors get semanticColors =>
      Theme.of(this).extension<AppSemanticColors>() ?? AppSemanticColors.light;
}
