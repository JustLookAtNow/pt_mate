import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/app_models.dart';

class AggregateSearchStrategyList extends StatefulWidget {
  const AggregateSearchStrategyList({
    super.key,
    required this.configs,
    required this.selectedStrategy,
    required this.onChanged,
    this.maximumHeight = 200,
    this.availableHeightFactor = 0.32,
  });

  final List<AggregateSearchConfig> configs;
  final String? selectedStrategy;
  final ValueChanged<String> onChanged;
  final double maximumHeight;
  final double availableHeightFactor;

  @override
  State<AggregateSearchStrategyList> createState() =>
      _AggregateSearchStrategyListState();
}

class _AggregateSearchStrategyListState
    extends State<AggregateSearchStrategyList> {
  static const double _strategyTileExtent = 56;

  late final ScrollController _strategyScrollController;

  bool _initialAlignmentScheduled = false;
  bool _didAlignInitialSelection = false;
  bool _hasInteractedWithStrategies = false;
  double? _lastAlignedViewportHeight;

  @override
  void initState() {
    super.initState();
    _strategyScrollController = ScrollController();
  }

  int get _selectedStrategyIndex => widget.configs.indexWhere(
    (config) => config.id == widget.selectedStrategy,
  );

  void _scheduleInitialSelectionAlignment(double expectedViewportHeight) {
    final selectedIndex = _selectedStrategyIndex;
    if (_hasInteractedWithStrategies || selectedIndex < 0) return;

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
          _hasInteractedWithStrategies ||
          _selectedStrategyIndex < 0 ||
          !_strategyScrollController.hasClients) {
        return;
      }

      final position = _strategyScrollController.position;
      final selectedItemCenter =
          _selectedStrategyIndex * _strategyTileExtent +
          _strategyTileExtent / 2;
      final targetOffset = selectedItemCenter - position.viewportDimension / 2;
      final clampedOffset = targetOffset.clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      );

      _strategyScrollController.jumpTo(clampedOffset);
      _didAlignInitialSelection = true;
      _lastAlignedViewportHeight = position.viewportDimension;
    });
  }

  void _selectStrategy(String strategyId) {
    _hasInteractedWithStrategies = true;
    widget.onChanged(strategyId);
  }

  @override
  void dispose() {
    _strategyScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.configs.isEmpty) {
      return Text(
        '暂无可用策略',
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      );
    }

    final availableHeight =
        MediaQuery.sizeOf(context).height -
        MediaQuery.viewInsetsOf(context).bottom;
    final maximumListHeight = (availableHeight * widget.availableHeightFactor)
        .clamp(96.0, widget.maximumHeight);
    final strategyListHeight = math.min(
      widget.configs.length * _strategyTileExtent,
      maximumListHeight,
    );
    _scheduleInitialSelectionAlignment(strategyListHeight);

    return SizedBox(
      height: strategyListHeight,
      child: Material(
        key: const ValueKey('aggregate-search-strategy-list'),
        type: MaterialType.transparency,
        clipBehavior: Clip.hardEdge,
        child: NotificationListener<ScrollStartNotification>(
          onNotification: (notification) {
            if (notification.dragDetails != null) {
              _hasInteractedWithStrategies = true;
            }
            return false;
          },
          child: RadioGroup<String>(
            groupValue: widget.selectedStrategy,
            onChanged: (value) {
              if (value != null) {
                _selectStrategy(value);
              }
            },
            child: ListView.builder(
              controller: _strategyScrollController,
              itemExtent: _strategyTileExtent,
              itemCount: widget.configs.length,
              itemBuilder: (context, index) {
                final config = widget.configs[index];
                final isSelected = config.id == widget.selectedStrategy;
                return ListTile(
                  key: ValueKey('aggregate-search-strategy-${config.id}'),
                  title: Text(
                    config.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  leading: Radio<String>(value: config.id),
                  selected: isSelected,
                  selectedTileColor: Theme.of(
                    context,
                  ).colorScheme.primaryContainer.withValues(alpha: 0.3),
                  onTap: () => _selectStrategy(config.id),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
