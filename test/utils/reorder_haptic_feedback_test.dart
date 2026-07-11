import 'package:flutter_test/flutter_test.dart';
import 'package:pt_mate/utils/reorder_haptic_feedback.dart';

void main() {
  test('拖拽开始重震动，跨越插入位置时轻震动', () {
    var heavyImpactCount = 0;
    var lightImpactCount = 0;
    final controller = ReorderHapticFeedbackController(
      onHeavyImpact: () async {
        heavyImpactCount++;
      },
      onLightImpact: () async {
        lightImpactCount++;
      },
    );

    controller.startDrag(1);
    controller.updateInsertionIndex(1);
    controller.updateInsertionIndex(2);
    controller.updateInsertionIndex(3);
    controller.updateInsertionIndex(3);

    expect(heavyImpactCount, 1);
    expect(lightImpactCount, 2);
  });

  test('拖拽结束后不再触发轻震动', () {
    var lightImpactCount = 0;
    final controller = ReorderHapticFeedbackController(
      onHeavyImpact: () async {},
      onLightImpact: () async {
        lightImpactCount++;
      },
    );

    controller.startDrag(0);
    controller.endDrag();
    controller.updateInsertionIndex(1);

    expect(lightImpactCount, 0);
  });
}
