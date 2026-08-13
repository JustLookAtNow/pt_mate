import 'package:flutter/material.dart';

import '../models/app_models.dart';

class CategoryFilterDialog extends StatefulWidget {
  final List<SearchCategoryConfig> categories;
  final int selectedCategoryIndex;
  final String keyword;

  const CategoryFilterDialog({
    super.key,
    required this.categories,
    required this.selectedCategoryIndex,
    required this.keyword,
  });

  @override
  State<CategoryFilterDialog> createState() => _CategoryFilterDialogState();
}

class _CategoryFilterDialogState extends State<CategoryFilterDialog> {
  static const double _categoryTileExtent = 56.0;

  late int _selectedCategoryIndex;
  late final TextEditingController _keywordController;
  late final ScrollController _categoryScrollController;

  bool _initialAlignmentScheduled = false;
  bool _didAlignInitialSelection = false;
  bool _hasInteractedWithCategories = false;
  double? _lastAlignedViewportHeight;

  @override
  void initState() {
    super.initState();
    _selectedCategoryIndex = widget.selectedCategoryIndex;
    _keywordController = TextEditingController(text: widget.keyword);
    _categoryScrollController = ScrollController();
  }

  bool get _hasValidSelection =>
      _selectedCategoryIndex >= 0 &&
      _selectedCategoryIndex < widget.categories.length;

  void _scheduleInitialSelectionAlignment(double expectedViewportHeight) {
    if (_hasInteractedWithCategories || !_hasValidSelection) return;

    final viewportUnchanged =
        _lastAlignedViewportHeight != null &&
        (_lastAlignedViewportHeight! - expectedViewportHeight).abs() < 0.5;
    if (_didAlignInitialSelection &&
        (viewportUnchanged || _initialAlignmentScheduled)) {
      return;
    }
    if (_initialAlignmentScheduled) return;

    _initialAlignmentScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initialAlignmentScheduled = false;
      if (!mounted ||
          _hasInteractedWithCategories ||
          !_hasValidSelection ||
          !_categoryScrollController.hasClients) {
        return;
      }

      final position = _categoryScrollController.position;
      final selectedItemCenter =
          _selectedCategoryIndex * _categoryTileExtent +
          _categoryTileExtent / 2;
      final targetOffset = selectedItemCenter - position.viewportDimension / 2;
      final clampedOffset = targetOffset.clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      );

      _categoryScrollController.jumpTo(clampedOffset);
      _didAlignInitialSelection = true;
      _lastAlignedViewportHeight = position.viewportDimension;
    });
  }

  void _selectCategory(int index) {
    _hasInteractedWithCategories = true;
    setState(() {
      _selectedCategoryIndex = index;
    });
  }

  @override
  void dispose() {
    _categoryScrollController.dispose();
    _keywordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final availableHeight =
        MediaQuery.sizeOf(context).height -
        MediaQuery.viewInsetsOf(context).bottom;
    final categoryListHeight = (availableHeight * 0.32).clamp(96.0, 200.0);
    _scheduleInitialSelectionAlignment(categoryListHeight);

    return AlertDialog(
      scrollable: true,
      title: const Text('分类筛选'),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('搜索关键词', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            TextField(
              key: const ValueKey('search-keyword-field'),
              controller: _keywordController,
              autofocus: true,
              onTapOutside: (event) => FocusScope.of(context).unfocus(),
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: '输入关键词（可选）',
                isDense: true,
              ),
            ),
            const SizedBox(height: 16),
            Text('选择分类', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            if (widget.categories.isEmpty)
              const Text('暂无可用分类', style: TextStyle(color: Colors.grey))
            else
              SizedBox(
                height: categoryListHeight,
                child: Material(
                  key: const ValueKey('category-list-viewport'),
                  type: MaterialType.transparency,
                  clipBehavior: Clip.hardEdge,
                  child: NotificationListener<ScrollStartNotification>(
                    onNotification: (notification) {
                      if (notification.dragDetails != null) {
                        _hasInteractedWithCategories = true;
                      }
                      return false;
                    },
                    child: RadioGroup<int>(
                      groupValue: _selectedCategoryIndex,
                      onChanged: (value) {
                        if (value != null) {
                          _selectCategory(value);
                        }
                      },
                      child: ListView.builder(
                        controller: _categoryScrollController,
                        itemExtent: _categoryTileExtent,
                        itemCount: widget.categories.length,
                        itemBuilder: (context, index) {
                          final category = widget.categories[index];
                          final isSelected = index == _selectedCategoryIndex;
                          return ListTile(
                            key: ValueKey('category-item-$index'),
                            title: Text(
                              category.displayName,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            leading: Radio<int>(value: index),
                            selected: isSelected,
                            selectedTileColor: Theme.of(context)
                                .colorScheme
                                .primaryContainer
                                .withValues(alpha: 0.3),
                            onTap: () => _selectCategory(index),
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          style: TextButton.styleFrom(
            side: BorderSide(
              color: Theme.of(context).colorScheme.outline,
              width: 1.0,
            ),
          ),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () {
            Navigator.of(context).pop({
              'categoryIndex': _selectedCategoryIndex,
              'keyword': _keywordController.text,
            });
          },
          child: const Text('确定'),
        ),
      ],
    );
  }
}
