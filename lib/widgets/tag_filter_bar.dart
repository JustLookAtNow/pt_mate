import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/app_models.dart';
import '../services/storage/storage_service.dart';

/// 标签过滤栏 Widget
///
/// 提供标签的包含/排除筛选功能:
/// - 短按: 在"未选择 ↔ 包含"之间切换
/// - 长按/右键: 切换到"排除"状态
class TagFilterBar extends StatelessWidget {
  /// 包含的标签集合
  final Set<TagType> includedTags;

  /// 排除的标签集合
  final Set<TagType> excludedTags;

  /// 包含标签变化时的回调
  final ValueChanged<Set<TagType>> onIncludedChanged;

  /// 排除标签变化时的回调
  final ValueChanged<Set<TagType>> onExcludedChanged;

  /// 自定义padding,默认为 EdgeInsets.fromLTRB(12.0, 0, 12.0, 8.0)
  final EdgeInsetsGeometry? padding;

  const TagFilterBar({
    super.key,
    required this.includedTags,
    required this.excludedTags,
    required this.onIncludedChanged,
    required this.onExcludedChanged,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    final visibleTagNames = StorageService.instance.visibleTags;
    final allTags = TagType.values
        .where((tag) => visibleTagNames.contains(tag.name))
        .toList();
    if (allTags.isEmpty) return const SizedBox.shrink();

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: padding ?? const EdgeInsets.fromLTRB(12.0, 0, 12.0, 8.0),
      child: Row(
        children: allTags.map((tag) {
          final isIncluded = includedTags.contains(tag);
          final isExcluded = excludedTags.contains(tag);

          Color backgroundColor;
          Color foregroundColor;
          Color borderColor;
          IconData? icon;

          if (isIncluded) {
            // 包含状态: 使用标签颜色的加深版本
            backgroundColor = tag.color.withValues(alpha: 0.2);
            foregroundColor = tag.color;
            borderColor = tag.color.withValues(alpha: 0.6);
            icon = Icons.check_circle_outline;
          } else if (isExcluded) {
            // 排除状态: 红色背景
            backgroundColor = Theme.of(
              context,
            ).colorScheme.errorContainer.withValues(alpha: 0.5);
            foregroundColor = Theme.of(context).colorScheme.error;
            borderColor = Theme.of(
              context,
            ).colorScheme.error.withValues(alpha: 0.6);
            icon = Icons.cancel_outlined;
          } else {
            // 未选中状态: 使用标签原本的颜色
            backgroundColor = tag.color.withValues(alpha: 0.15);
            foregroundColor = tag.color;
            borderColor = tag.color.withValues(alpha: 0.3);
          }

          return Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: GestureDetector(
              // 短按: 在未选择↔包含之间切换
              onTap: () {
                final newIncluded = Set<TagType>.from(includedTags);
                final newExcluded = Set<TagType>.from(excludedTags);

                if (isIncluded) {
                  newIncluded.remove(tag);
                } else if (isExcluded) {
                  newExcluded.remove(tag);
                } else {
                  newIncluded.add(tag);
                }

                onIncludedChanged(newIncluded);
                onExcludedChanged(newExcluded);
              },
              // 长按: 切换到排除状态
              onLongPress: () {
                HapticFeedback.mediumImpact();
                final newIncluded = Set<TagType>.from(includedTags);
                final newExcluded = Set<TagType>.from(excludedTags);

                newIncluded.remove(tag);
                if (isExcluded) {
                  newExcluded.remove(tag);
                } else {
                  newExcluded.add(tag);
                }

                onIncludedChanged(newIncluded);
                onExcludedChanged(newExcluded);
              },
              // 鼠标右键: 切换到排除状态
              onSecondaryTap: () {
                final newIncluded = Set<TagType>.from(includedTags);
                final newExcluded = Set<TagType>.from(excludedTags);

                newIncluded.remove(tag);
                if (isExcluded) {
                  newExcluded.remove(tag);
                } else {
                  newExcluded.add(tag);
                }

                onIncludedChanged(newIncluded);
                onExcludedChanged(newExcluded);
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: backgroundColor,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: borderColor, width: 1.5),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (icon != null) ...[
                      Icon(icon, size: 16, color: foregroundColor),
                      const SizedBox(width: 4),
                    ],
                    Text(
                      tag.content,
                      style: TextStyle(
                        color: foregroundColor,
                        fontSize: 13,
                        fontWeight: (isIncluded || isExcluded)
                            ? FontWeight.bold
                            : FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
