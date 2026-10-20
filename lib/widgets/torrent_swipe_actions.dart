import 'package:flutter/material.dart';

/// 松手达到阈值后执行操作，始终保留列表项并回到原位。
class TorrentSwipeActions extends StatefulWidget {
  final Widget child;
  final bool enabled;
  final bool collected;
  final VoidCallback? onCollection;
  final VoidCallback? onDownload;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  const TorrentSwipeActions({
    super.key,
    required this.child,
    required this.enabled,
    required this.collected,
    this.onCollection,
    this.onDownload,
    this.onTap,
    this.onLongPress,
  });

  @override
  State<TorrentSwipeActions> createState() => _TorrentSwipeActionsState();
}

class _TorrentSwipeActionsState extends State<TorrentSwipeActions>
    with SingleTickerProviderStateMixin {
  late final AnimationController _offset = AnimationController.unbounded(
    vsync: this,
  );
  double _width = 0;
  bool _tracking = false;
  bool _returning = false;
  int _gestureGeneration = 0;

  double get _threshold => (_width * 0.25).clamp(72.0, 120.0);

  @override
  void didUpdateWidget(TorrentSwipeActions oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled ||
        (_offset.value < 0 && widget.onCollection == null) ||
        (_offset.value > 0 && widget.onDownload == null)) {
      _gestureGeneration++;
      _tracking = false;
      _returning = false;
      _offset.stop();
      _offset.value = 0;
    }
  }

  @override
  void dispose() {
    _offset.dispose();
    super.dispose();
  }

  void _start(DragStartDetails details) {
    if (_returning) return;
    _tracking = true;
    _gestureGeneration++;
  }

  void _update(DragUpdateDetails details) {
    if (!_tracking) return;
    _offset.value = (_offset.value + (details.primaryDelta ?? 0)).clamp(
      widget.onCollection == null ? 0.0 : -_width * 0.6,
      widget.onDownload == null ? 0.0 : _width * 0.6,
    );
  }

  Future<void> _finish({bool cancelled = false}) async {
    if (!_tracking) return;
    _tracking = false;
    _returning = true;
    final generation = _gestureGeneration;
    final extent = _offset.value;
    final shouldAct = !cancelled && extent.abs() >= _threshold;
    try {
      await _offset
          .animateTo(
            0,
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
          )
          .orCancel;
    } on TickerCanceled {
      return;
    }
    if (!mounted || generation != _gestureGeneration) return;
    _returning = false;
    if (!widget.enabled || !shouldAct) return;
    if (extent < 0) {
      widget.onCollection?.call();
    } else {
      widget.onDownload?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    final canSwipe =
        widget.enabled &&
        (widget.onCollection != null || widget.onDownload != null);
    return LayoutBuilder(
      builder: (context, constraints) {
        _width = constraints.maxWidth;
        return Listener(
          // Flutter 的拖动识别器在已接管手势后，也会对 PointerCancel
          // 调用 onEnd；先拦截原始取消事件，确保不会执行操作。
          onPointerCancel: (_) => _finish(cancelled: true),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onTap,
            onLongPress: widget.onLongPress,
            onHorizontalDragStart: canSwipe ? _start : null,
            onHorizontalDragUpdate: canSwipe ? _update : null,
            onHorizontalDragEnd: canSwipe ? (_) => _finish() : null,
            onHorizontalDragCancel: canSwipe
                ? () => _finish(cancelled: true)
                : null,
            child: ClipRect(
              child: AnimatedBuilder(
                animation: _offset,
                child: widget.child,
                builder: (context, child) {
                  final collection = _offset.value < 0;
                  final armed = _offset.value.abs() >= _threshold;
                  final colors = Theme.of(context).colorScheme;
                  return Stack(
                    children: [
                      if (_offset.value != 0)
                        Positioned.fill(
                          child: Container(
                            margin: const EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 3,
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            alignment: collection
                                ? Alignment.centerRight
                                : Alignment.centerLeft,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              color: collection
                                  ? colors.secondaryContainer
                                  : colors.primaryContainer,
                            ),
                            child: Opacity(
                              opacity: armed ? 1 : 0.6,
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    collection
                                        ? widget.collected
                                              ? Icons.favorite
                                              : Icons.favorite_border
                                        : Icons.download_outlined,
                                    color: collection
                                        ? colors.onSecondaryContainer
                                        : colors.onPrimaryContainer,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    collection
                                        ? widget.collected
                                              ? '取消收藏'
                                              : '收藏'
                                        : '下载',
                                    style: TextStyle(
                                      color: collection
                                          ? colors.onSecondaryContainer
                                          : colors.onPrimaryContainer,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      Transform.translate(
                        offset: Offset(_offset.value, 0),
                        child: child,
                      ),
                    ],
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
