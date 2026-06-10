import 'package:flutter/material.dart';

import '../services/theme/app_tokens.dart';

/// 种子列表加载骨架屏：模拟列表项结构（封面块 + 标签/标题/副标题/统计行）
/// 的占位条，整体做呼吸式透明度脉动。
class TorrentListSkeleton extends StatefulWidget {
  /// 占位条目数量
  final int itemCount;

  const TorrentListSkeleton({super.key, this.itemCount = 8});

  @override
  State<TorrentListSkeleton> createState() => _TorrentListSkeletonState();
}

class _TorrentListSkeletonState extends State<TorrentListSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 900),
      vsync: this,
      lowerBound: 0.45,
      upperBound: 1.0,
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _controller,
      child: ListView.builder(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: AppSpacing.lg),
        itemCount: widget.itemCount,
        itemBuilder: (context, index) => const _SkeletonItem(),
      ),
    );
  }
}

class _SkeletonItem extends StatelessWidget {
  const _SkeletonItem();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final boneColor = colorScheme.surfaceContainerHighest;

    Widget bone(double width, double height, {double radius = 4}) {
      return Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: boneColor,
          borderRadius: BorderRadius.circular(radius),
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 3,
      ),
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(
          color: colorScheme.outline.withValues(alpha: 0.15),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          bone(64, 90, radius: AppRadius.sm),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                bone(120, 14),
                const SizedBox(height: AppSpacing.sm),
                bone(double.infinity, 14),
                const SizedBox(height: 6),
                FractionallySizedBox(
                  widthFactor: 0.6,
                  child: bone(double.infinity, 12),
                ),
                const SizedBox(height: AppSpacing.md),
                bone(180, 11),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
