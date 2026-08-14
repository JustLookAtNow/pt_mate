import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'dart:math' as math;

/// 将 ListView.builder 滚动到指定下标。
///
/// 实现策略：
/// 1. 若目标条目已构建，直接几何计算精确 offset 平滑滚动过去；
/// 2. 否则基于可见条目的平均高度估算 offset 粗定位 jumpTo，等待下一帧
///    ListView 懒构建出目标条目后重新校准，直至目标可见（上限 [maxAttempts] 次）。
///
/// 使用前提：列表条目需用 `MetaData(metaData: index)` 包裹（两个列表现状均如此）。
class ListIndexScroller {
  ListIndexScroller({required this.controller, required this.listViewKey});

  final ScrollController controller;
  final GlobalKey listViewKey;

  static const int maxAttempts = 5;
  static const double topInsetRatio = 0.1;

  /// 滚动到 [index]，使该条目位于视口顶部约 10% 处。
  Future<void> scrollToIndex(int index) async {
    if (!controller.hasClients || index < 0) return;

    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      final items = _collectVisibleItems();
      if (items.isEmpty) return;

      final exact = items[index];
      if (exact != null) {
        await _animateToItemTop(exact);
        return;
      }

      // 估算平均条目高度做粗定位
      final avgHeight = _averageItemHeight(items);
      if (avgHeight == null) return;
      final position = controller.position;
      final firstIndex = items.keys.reduce(math.min);
      final listViewBox =
          listViewKey.currentContext?.findRenderObject() as RenderBox?;
      if (listViewBox == null) return;
      final firstScreenY = items[firstIndex]!
          .localToGlobal(Offset.zero, ancestor: listViewBox)
          .dy;
      final firstContentY = position.pixels + firstScreenY;
      final targetTop =
          firstContentY +
          (index - firstIndex) * avgHeight -
          position.viewportDimension * topInsetRatio;
      final clamped = targetTop.clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      );
      controller.jumpTo(clamped);
      // 等待下一帧完成，带超时保护避免测试环境无帧调度时挂起
      await SchedulerBinding.instance.endOfFrame.timeout(
        const Duration(milliseconds: 100),
      );
      if (!controller.hasClients) return;
    }
  }

  /// 收集视口内（含缓存区）已构建条目的 {下标: RenderBox}。
  Map<int, RenderBox> _collectVisibleItems() {
    final result = <int, RenderBox>{};
    final root = listViewKey.currentContext?.findRenderObject();
    if (root == null) return result;

    void visit(RenderObject node) {
      if (node is RenderMetaData && node.metaData is int) {
        result[node.metaData as int] = node;
      }
      node.visitChildren(visit);
    }

    root.visitChildren(visit);
    return result;
  }

  double? _averageItemHeight(Map<int, RenderBox> items) {
    if (items.isEmpty) return null;
    var total = 0.0;
    for (final box in items.values) {
      total += box.size.height;
    }
    return total / items.length;
  }

  Future<void> _animateToItemTop(RenderBox item) async {
    final position = controller.position;
    final listViewBox =
        listViewKey.currentContext?.findRenderObject() as RenderBox?;
    if (listViewBox == null) return;

    // item 在列表坐标系（未滚动前）中的纵向位置
    final itemLocalTop = item
        .localToGlobal(Offset.zero, ancestor: listViewBox)
        .dy;
    final itemAbsoluteTop = position.pixels + itemLocalTop;
    final target =
        (itemAbsoluteTop - position.viewportDimension * topInsetRatio)
            .clamp(position.minScrollExtent, position.maxScrollExtent)
            .toDouble();
    await controller.animateTo(
      target,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }
}
