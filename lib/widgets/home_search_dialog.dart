import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/app_models.dart';
import '../models/home_search_request.dart';
import 'aggregate_search_strategy_list.dart';

class HomeSearchDialog extends StatefulWidget {
  const HomeSearchDialog({
    super.key,
    required this.categories,
    required this.selectedCategoryIndex,
    required this.keyword,
    required this.initialMode,
    required this.searchConfigs,
    this.selectedStrategy,
    this.supportsCurrentSiteSearch = true,
    this.supportsCategories = true,
    this.onConfigureAggregate,
  });

  final List<SearchCategoryConfig> categories;
  final int selectedCategoryIndex;
  final String keyword;
  final HomeSearchMode initialMode;
  final List<AggregateSearchConfig> searchConfigs;
  final String? selectedStrategy;
  final bool supportsCurrentSiteSearch;
  final bool supportsCategories;
  final Future<List<AggregateSearchConfig>?> Function()? onConfigureAggregate;

  @override
  State<HomeSearchDialog> createState() => _HomeSearchDialogState();
}

class _HomeSearchDialogState extends State<HomeSearchDialog> {
  static const double _categoryTileExtent = 56;

  late final TextEditingController _keywordController;
  late final ScrollController _categoryScrollController;
  late HomeSearchMode _mode;
  late int _selectedCategoryIndex;
  late List<AggregateSearchConfig> _searchConfigs;
  String? _selectedStrategy;
  bool _isConfiguringAggregate = false;
  bool _initialAlignmentScheduled = false;
  bool _didAlignInitialSelection = false;
  bool _hasInteractedWithCategories = false;
  double? _lastAlignedViewportHeight;

  @override
  void initState() {
    super.initState();
    _keywordController = TextEditingController(text: widget.keyword);
    _categoryScrollController = ScrollController();
    _mode = widget.initialMode;
    _selectedCategoryIndex = widget.selectedCategoryIndex;
    _updateSearchConfigs(widget.searchConfigs, widget.selectedStrategy);
  }

  void _updateSearchConfigs(
    List<AggregateSearchConfig> configs,
    String? preferredStrategy,
  ) {
    _searchConfigs = configs.where((config) => config.isActive).toList();
    _selectedStrategy =
        _searchConfigs.any((config) => config.id == preferredStrategy)
        ? preferredStrategy
        : (_searchConfigs
                      .where((config) => config.isAllSitesType)
                      .firstOrNull ??
                  _searchConfigs.firstOrNull)
              ?.id;
  }

  bool get _hasValidCategorySelection =>
      _selectedCategoryIndex >= 0 &&
      _selectedCategoryIndex < widget.categories.length;

  bool get _canSubmit =>
      !_isConfiguringAggregate &&
      (_mode == HomeSearchMode.currentSite
          ? widget.supportsCurrentSiteSearch
          : _selectedStrategy != null);

  void _submit() {
    if (!_canSubmit) return;
    Navigator.of(context).pop(
      HomeSearchRequest(
        mode: _mode,
        keyword: _keywordController.text,
        categoryIndex:
            _mode == HomeSearchMode.currentSite && widget.supportsCategories
            ? _selectedCategoryIndex
            : null,
        strategyId: _mode == HomeSearchMode.aggregate
            ? _selectedStrategy
            : null,
      ),
    );
  }

  Future<void> _configureAggregate() async {
    final configure = widget.onConfigureAggregate;
    if (configure == null || _isConfiguringAggregate) return;
    FocusScope.of(context).unfocus();
    setState(() => _isConfiguringAggregate = true);
    try {
      final configs = await configure();
      if (!mounted) return;
      setState(() {
        if (configs != null) {
          _updateSearchConfigs(configs, _selectedStrategy);
        }
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('更新聚合搜索设置失败，请重试')));
    } finally {
      if (mounted) {
        setState(() => _isConfiguringAggregate = false);
      }
    }
  }

  void _scheduleCategoryAlignment(double expectedViewportHeight) {
    if (_hasInteractedWithCategories || !_hasValidCategorySelection) return;
    final viewportUnchanged =
        _lastAlignedViewportHeight != null &&
        (_lastAlignedViewportHeight! - expectedViewportHeight).abs() < 0.5;
    if (_initialAlignmentScheduled ||
        (_didAlignInitialSelection && viewportUnchanged)) {
      return;
    }
    _initialAlignmentScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initialAlignmentScheduled = false;
      if (!mounted ||
          _hasInteractedWithCategories ||
          !_hasValidCategorySelection ||
          !_categoryScrollController.hasClients) {
        return;
      }
      final position = _categoryScrollController.position;
      final selectedItemCenter =
          (_selectedCategoryIndex + 0.5) * _categoryTileExtent;
      _categoryScrollController.jumpTo(
        (selectedItemCenter - position.viewportDimension / 2).clamp(
          position.minScrollExtent,
          position.maxScrollExtent,
        ),
      );
      _didAlignInitialSelection = true;
      _lastAlignedViewportHeight = position.viewportDimension;
    });
  }

  void _selectCategory(int index) {
    _hasInteractedWithCategories = true;
    setState(() => _selectedCategoryIndex = index);
  }

  Widget _buildCategories(BuildContext context) {
    final availableHeight =
        MediaQuery.sizeOf(context).height -
        MediaQuery.viewInsetsOf(context).bottom;
    final listHeight = math.min(
      widget.categories.length * _categoryTileExtent,
      (availableHeight * 0.32).clamp(96.0, 200.0),
    );
    _scheduleCategoryAlignment(listHeight);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('选择分类', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        if (widget.categories.isEmpty)
          const Text('暂无可用分类')
        else
          SizedBox(
            height: listHeight,
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
                    if (value != null) _selectCategory(value);
                  },
                  child: ListView.builder(
                    controller: _categoryScrollController,
                    itemExtent: _categoryTileExtent,
                    itemCount: widget.categories.length,
                    itemBuilder: (context, index) => ListTile(
                      key: ValueKey('category-item-$index'),
                      title: Text(
                        widget.categories[index].displayName,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      leading: Radio<int>(value: index),
                      selected: index == _selectedCategoryIndex,
                      selectedTileColor: Theme.of(context)
                          .colorScheme
                          .primaryContainer
                          .withValues(alpha: 0.3),
                      onTap: () => _selectCategory(index),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  @override
  void dispose() {
    _keywordController.dispose();
    _categoryScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dialogWidth = math.min(MediaQuery.sizeOf(context).width * 0.8, 440.0);
    return AlertDialog(
      key: const ValueKey('home-search-dialog'),
      scrollable: true,
      constraints: BoxConstraints(minWidth: dialogWidth, maxWidth: dialogWidth),
      title: const Text('搜索'),
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
              textInputAction: TextInputAction.search,
              onTapOutside: (_) => FocusScope.of(context).unfocus(),
              onSubmitted: (_) => _submit(),
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: '输入关键词（可选）',
                isDense: true,
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<HomeSearchMode>(
                key: const ValueKey('home-search-mode-selector'),
                segments: const [
                  ButtonSegment(
                    value: HomeSearchMode.currentSite,
                    label: Text('当前站点'),
                  ),
                  ButtonSegment(
                    value: HomeSearchMode.aggregate,
                    label: Text('聚合搜索'),
                  ),
                ],
                selected: {_mode},
                showSelectedIcon: false,
                onSelectionChanged: (selection) {
                  setState(() {
                    _mode = selection.single;
                    _didAlignInitialSelection = false;
                  });
                },
              ),
            ),
            const SizedBox(height: 16),
            if (_mode == HomeSearchMode.currentSite) ...[
              if (!widget.supportsCurrentSiteSearch)
                const Text('当前站点不支持搜索，可切换到聚合搜索')
              else if (widget.supportsCategories)
                _buildCategories(context),
            ] else ...[
              Text('搜索策略', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              AggregateSearchStrategyList(
                configs: _searchConfigs,
                selectedStrategy: _selectedStrategy,
                onChanged: (strategy) {
                  setState(() => _selectedStrategy = strategy);
                },
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  key: const ValueKey('aggregate-search-settings-button'),
                  onPressed:
                      widget.onConfigureAggregate == null ||
                          _isConfiguringAggregate
                      ? null
                      : _configureAggregate,
                  icon: _isConfiguringAggregate
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.settings_outlined, size: 18),
                  label: const Text('聚合搜索设置'),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          key: const ValueKey('home-search-submit-button'),
          onPressed: _canSubmit ? _submit : null,
          child: const Text('搜索'),
        ),
      ],
    );
  }
}
