import 'package:flutter/services.dart';

/// 管理排序拖拽过程中的触感反馈，避免同一插入位置重复震动。
class ReorderHapticFeedbackController {
  ReorderHapticFeedbackController({
    Future<void> Function()? onHeavyImpact,
    Future<void> Function()? onLightImpact,
  }) : _onHeavyImpact = onHeavyImpact ?? HapticFeedback.heavyImpact,
       _onLightImpact = onLightImpact ?? HapticFeedback.lightImpact;

  final Future<void> Function() _onHeavyImpact;
  final Future<void> Function() _onLightImpact;

  bool _isDragging = false;
  int? _lastInsertionIndex;

  void startDrag(int insertionIndex) {
    _isDragging = true;
    _lastInsertionIndex = insertionIndex;
    _onHeavyImpact();
  }

  void updateInsertionIndex(int insertionIndex) {
    if (!_isDragging || insertionIndex == _lastInsertionIndex) return;

    _lastInsertionIndex = insertionIndex;
    _onLightImpact();
  }

  void endDrag() {
    _isDragging = false;
    _lastInsertionIndex = null;
  }
}
