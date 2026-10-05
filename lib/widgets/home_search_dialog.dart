import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/app_models.dart';
import '../models/home_search_request.dart';

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
  late final TextEditingController _keywordController;
  late HomeSearchMode _mode;
  late int _selectedCategoryIndex;
  late List<AggregateSearchConfig> _searchConfigs;
  String? _selectedStrategy;
  bool _isConfiguringAggregate = false;

  @override
  void initState() {
    super.initState();
    _keywordController = TextEditingController(text: widget.keyword);
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

  Widget _buildScopeOption({
    required HomeSearchMode mode,
    required String title,
    required String subtitle,
    required IconData icon,
  }) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final selected = _mode == mode;
    final foreground = selected ? colors.primary : colors.onSurface;
    return Expanded(
      child: Semantics(
        key: ValueKey('home-search-mode-${mode.name}'),
        button: true,
        selected: selected,
        inMutuallyExclusiveGroup: true,
        child: Material(
          color: selected
              ? colors.primary.withValues(alpha: 0.12)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => setState(() => _mode = mode),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Row(
                    children: [
                      Icon(
                        selected ? Icons.radio_button_checked : icon,
                        size: 20,
                        color: foreground,
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          title,
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: foreground,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    subtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: selected
                          ? colors.primary
                          : colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildChoices() {
    final theme = Theme.of(context);
    final currentSite = _mode == HomeSearchMode.currentSite;
    if (currentSite && !widget.supportsCurrentSiteSearch) {
      return const Text('当前站点不支持搜索，可切换到聚合搜索');
    }
    if (currentSite && !widget.supportsCategories) {
      return const SizedBox.shrink();
    }
    final labels = currentSite
        ? widget.categories.map((category) => category.displayName).toList()
        : _searchConfigs.map((config) => config.name).toList();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(currentSite ? '选择分类' : '搜索策略', style: theme.textTheme.titleSmall),
        const SizedBox(height: 6),
        Text(
          currentSite ? '选择要搜索的资源分类' : '选择已配置的搜索策略',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 12),
        if (labels.isEmpty)
          Text(currentSite ? '暂无可用分类' : '暂无可用策略')
        else
          _SearchOptionGrid(
            key: ValueKey(_mode),
            labels: labels,
            selectedIndex: currentSite
                ? _selectedCategoryIndex
                : _searchConfigs.indexWhere(
                    (config) => config.id == _selectedStrategy,
                  ),
            viewportKey: ValueKey(
              currentSite
                  ? 'category-list-viewport'
                  : 'aggregate-search-strategy-list',
            ),
            itemKeys: [
              for (var index = 0; index < labels.length; index++)
                ValueKey(
                  currentSite
                      ? 'category-item-$index'
                      : 'aggregate-search-strategy-${_searchConfigs[index].id}',
                ),
            ],
            onChanged: (index) => setState(() {
              if (currentSite) {
                _selectedCategoryIndex = index;
              } else {
                _selectedStrategy = _searchConfigs[index].id;
              }
            }),
          ),
        if (!currentSite) ...[
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              key: const ValueKey('aggregate-search-settings-button'),
              onPressed:
                  widget.onConfigureAggregate == null || _isConfiguringAggregate
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
    );
  }

  @override
  void dispose() {
    _keywordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final dialogWidth = math.min(MediaQuery.sizeOf(context).width - 48, 640.0);
    return AlertDialog(
      key: const ValueKey('home-search-dialog'),
      scrollable: true,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      constraints: BoxConstraints(minWidth: dialogWidth, maxWidth: dialogWidth),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
      contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
      actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      title: const Text('分类筛选'),
      content: SizedBox(
        width: dialogWidth - 48,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('搜索范围', style: theme.textTheme.titleSmall),
            const SizedBox(height: 10),
            Container(
              key: const ValueKey('home-search-mode-selector'),
              decoration: BoxDecoration(
                border: Border.all(color: colors.outlineVariant),
                borderRadius: BorderRadius.circular(14),
              ),
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildScopeOption(
                      mode: HomeSearchMode.currentSite,
                      title: '当前站点',
                      subtitle: '仅在当前站点搜索',
                      icon: Icons.dns_outlined,
                    ),
                    _buildScopeOption(
                      mode: HomeSearchMode.aggregate,
                      title: '全站搜索',
                      subtitle: '按所选策略跨站搜索',
                      icon: Icons.public_outlined,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            _buildChoices(),
            const SizedBox(height: 24),
            Text('搜索关键词', style: theme.textTheme.titleSmall),
            const SizedBox(height: 10),
            TextField(
              key: const ValueKey('search-keyword-field'),
              controller: _keywordController,
              textInputAction: TextInputAction.search,
              onTapOutside: (_) => FocusScope.of(context).unfocus(),
              onSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                hintText: '输入关键词（可选）',
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 18,
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
            side: BorderSide(color: colors.outline),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          ),
          child: const Text('取消'),
        ),
        FilledButton(
          key: const ValueKey('home-search-submit-button'),
          onPressed: _canSubmit ? _submit : null,
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          ),
          child: const Text('确定'),
        ),
      ],
    );
  }
}

/// The home dialog has its own grid so other search pages keep their layout.
class _SearchOptionGrid extends StatefulWidget {
  const _SearchOptionGrid({
    super.key,
    required this.labels,
    required this.itemKeys,
    required this.selectedIndex,
    required this.viewportKey,
    required this.onChanged,
  });

  final List<String> labels;
  final List<Key> itemKeys;
  final int selectedIndex;
  final Key viewportKey;
  final ValueChanged<int> onChanged;

  @override
  State<_SearchOptionGrid> createState() => _SearchOptionGridState();
}

class _SearchOptionGridState extends State<_SearchOptionGrid> {
  final _scrollController = ScrollController();
  bool _alignmentScheduled = false;
  bool _hasInteracted = false;
  (int, double, double)? _alignedLayout;

  void _scheduleAlignment(int columns, double tileHeight, double height) {
    final layout = (columns, tileHeight, height);
    if (_hasInteracted || _alignmentScheduled || _alignedLayout == layout) {
      return;
    }
    _alignmentScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _alignmentScheduled = false;
      if (!mounted ||
          _hasInteracted ||
          !_scrollController.hasClients ||
          widget.selectedIndex < 0 ||
          widget.selectedIndex >= widget.labels.length) {
        return;
      }
      final position = _scrollController.position;
      final row = widget.selectedIndex ~/ columns;
      final itemCenter = 4 + row * (tileHeight + 10) + tileHeight / 2;
      _scrollController.jumpTo(
        (itemCenter - position.viewportDimension / 2).clamp(
          position.minScrollExtent,
          position.maxScrollExtent,
        ),
      );
      _alignedLayout = layout;
    });
  }

  @override
  void didUpdateWidget(covariant _SearchOptionGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!listEquals(oldWidget.itemKeys, widget.itemKeys)) {
      _hasInteracted = false;
      _alignedLayout = null;
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final fontSize = theme.textTheme.bodyMedium?.fontSize ?? 14;
    final scaledFontSize = MediaQuery.textScalerOf(context).scale(fontSize);
    final tileHeight = math.max(56.0, scaledFontSize * 2.8 + 16);
    final availableHeight =
        MediaQuery.sizeOf(context).height -
        MediaQuery.viewInsetsOf(context).bottom;
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns =
            ((constraints.maxWidth - 8 + 10) /
                    (86 * (scaledFontSize / fontSize) + 10))
                .floor()
                .clamp(2, 6);
        final rows = (widget.labels.length / columns).ceil();
        final height = math.min(
          rows * (tileHeight + 10) - 10 + 8,
          (availableHeight * 0.32)
              .clamp(tileHeight + 8, math.max(200.0, tileHeight + 8))
              .toDouble(),
        );
        _scheduleAlignment(columns, tileHeight, height);
        return SizedBox(
          height: height,
          child: Material(
            key: widget.viewportKey,
            type: MaterialType.transparency,
            clipBehavior: Clip.hardEdge,
            child: NotificationListener<ScrollStartNotification>(
              onNotification: (notification) {
                if (notification.dragDetails != null) _hasInteracted = true;
                return false;
              },
              child: GridView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.all(4),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  mainAxisExtent: tileHeight,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                ),
                itemCount: widget.labels.length,
                itemBuilder: (context, index) {
                  final selected = index == widget.selectedIndex;
                  final borderRadius = BorderRadius.circular(12);
                  return Tooltip(
                    message: widget.labels[index],
                    excludeFromSemantics: true,
                    child: Semantics(
                      key: widget.itemKeys[index],
                      button: true,
                      selected: selected,
                      inMutuallyExclusiveGroup: true,
                      child: Stack(
                        fit: StackFit.expand,
                        clipBehavior: Clip.none,
                        children: [
                          Material(
                            color: selected
                                ? colors.primary.withValues(alpha: 0.12)
                                : Colors.transparent,
                            shape: RoundedRectangleBorder(
                              borderRadius: borderRadius,
                              side: BorderSide(
                                color: selected
                                    ? colors.primary.withValues(alpha: 0.35)
                                    : colors.outlineVariant,
                              ),
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: InkWell(
                              borderRadius: borderRadius,
                              onTap: () {
                                _hasInteracted = true;
                                widget.onChanged(index);
                              },
                              child: Padding(
                                padding: const EdgeInsets.all(8),
                                child: _SearchOptionLabel(
                                  label: widget.labels[index],
                                  style: theme.textTheme.bodyMedium!.copyWith(
                                    color: selected
                                        ? colors.primary
                                        : colors.onSurface,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          if (selected)
                            Positioned(
                              top: -4,
                              right: -4,
                              child: IgnorePointer(
                                child: ExcludeSemantics(
                                  child: DecoratedBox(
                                    key: const ValueKey(
                                      'home-search-selection-marker',
                                    ),
                                    decoration: BoxDecoration(
                                      color: colors.primary,
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: colors.surface,
                                        width: 1,
                                      ),
                                    ),
                                    child: Padding(
                                      padding: const EdgeInsets.all(2),
                                      child: Icon(
                                        Icons.check_rounded,
                                        size: 10,
                                        color: colors.onPrimary,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Fit names into two lines without taking space away for the selection marker.
class _SearchOptionLabel extends StatelessWidget {
  const _SearchOptionLabel({required this.label, required this.style});

  final String label;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    final textScaler = MediaQuery.textScalerOf(context);
    final textDirection = Directionality.of(context);
    final locale = Localizations.maybeLocaleOf(context);
    final baseFontSize = style.fontSize ?? 14;
    final minFontSize = math.max(10.0, baseFontSize * 0.75);
    return LayoutBuilder(
      builder: (context, constraints) {
        var fontSize = baseFontSize;
        final painter = TextPainter(
          maxLines: 2,
          textDirection: textDirection,
          textScaler: textScaler,
          locale: locale,
        );
        while (true) {
          painter.text = TextSpan(
            text: label,
            style: style.copyWith(fontSize: fontSize, height: 1.25),
          );
          painter.layout(maxWidth: constraints.maxWidth);
          if ((!painter.didExceedMaxLines &&
                  painter.height <= constraints.maxHeight) ||
              fontSize <= minFontSize) {
            break;
          }
          fontSize = math.max(minFontSize, fontSize - 0.5);
        }
        painter.dispose();
        return Center(
          child: Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            textScaler: textScaler,
            locale: locale,
            style: style.copyWith(fontSize: fontSize, height: 1.25),
          ),
        );
      },
    );
  }
}
