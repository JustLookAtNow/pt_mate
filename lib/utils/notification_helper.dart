import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

class NotificationHelper {
  static const Duration _showAnimationDuration = Duration(milliseconds: 220);
  static const Duration _hideAnimationDuration = Duration(milliseconds: 180);
  static const double _horizontalMargin = 16;
  static const double _topSpacing = 12;
  static const double _maxWidth = 520;
  static const int _maxMessageLines = 4;
  static final BorderRadius _borderRadius = BorderRadius.circular(18);

  static OverlayEntry? _currentEntry;
  static _NotificationHandle? _currentHandle;
  static Timer? _autoDismissTimer;
  static int _notificationVersion = 0;

  static void showInfo(
    BuildContext context,
    String message, {
    Duration? duration,
  }) {
    final scheme = Theme.of(context).colorScheme;
    _show(
      context: context,
      message: message,
      duration: duration ?? const Duration(seconds: 3),
      backgroundColor: scheme.primaryContainer,
      foregroundColor: scheme.onPrimaryContainer,
      borderColor: scheme.onPrimaryContainer.withValues(alpha: 0.3),
    );
  }

  static void showError(
    BuildContext context,
    String message, {
    Duration? duration,
  }) {
    final scheme = Theme.of(context).colorScheme;
    _show(
      context: context,
      message: message,
      duration: duration ?? const Duration(seconds: 4),
      backgroundColor: scheme.errorContainer,
      foregroundColor: scheme.onErrorContainer,
      borderColor: scheme.onErrorContainer.withValues(alpha: 0.3),
    );
  }

  static void showSuccess(
    BuildContext context,
    String message, {
    Duration? duration,
  }) {
    final scheme = Theme.of(context).colorScheme;
    _show(
      context: context,
      message: message,
      duration: duration ?? const Duration(seconds: 3),
      backgroundColor: scheme.primaryContainer,
      foregroundColor: scheme.onPrimaryContainer,
      borderColor: scheme.primary.withValues(alpha: 0.3),
    );
  }

  static void _show({
    required BuildContext context,
    required String message,
    required Duration duration,
    required Color backgroundColor,
    required Color foregroundColor,
    required Color borderColor,
  }) {
    if (!context.mounted) return;

    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null || !overlay.mounted) return;

    final version = ++_notificationVersion;
    _removeCurrent(immediately: true);

    final handle = _NotificationHandle();
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (overlayContext) {
        return _NotificationOverlay(
          handle: handle,
          message: message,
          backgroundColor: backgroundColor,
          foregroundColor: foregroundColor,
          borderColor: borderColor,
          onHidden: () {
            if (!identical(_currentEntry, entry)) {
              _removeEntry(entry);
              return;
            }

            _autoDismissTimer?.cancel();
            _autoDismissTimer = null;
            _currentHandle = null;
            _currentEntry = null;
            _removeEntry(entry);
          },
        );
      },
    );

    _currentEntry = entry;
    _currentHandle = handle;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_notificationVersion != version || !overlay.mounted) return;
      overlay.insert(entry);
    });

    _autoDismissTimer = Timer(duration, () {
      if (_notificationVersion != version) return;
      _dismissCurrent();
    });
  }

  static void _dismissCurrent() {
    _autoDismissTimer?.cancel();
    _autoDismissTimer = null;
    _currentHandle?.dismiss();
  }

  static void _removeCurrent({required bool immediately}) {
    _autoDismissTimer?.cancel();
    _autoDismissTimer = null;

    final entry = _currentEntry;
    final handle = _currentHandle;
    _currentEntry = null;
    _currentHandle = null;

    if (entry == null) return;

    if (immediately) {
      handle?.detach();
      _removeEntry(entry);
      return;
    }

    handle?.dismiss();
  }

  static void _removeEntry(OverlayEntry entry) {
    try {
      entry.remove();
    } catch (_) {
      // OverlayEntry might not have been inserted yet.
    }
  }

  @visibleForTesting
  static void resetForTest() {
    _notificationVersion++;
    _removeCurrent(immediately: true);
  }
}

class _NotificationHandle {
  Future<void> Function()? _dismiss;

  void attach(Future<void> Function() dismiss) {
    _dismiss = dismiss;
  }

  void detach() {
    _dismiss = null;
  }

  void dismiss() {
    _dismiss?.call();
  }
}

class _NotificationOverlay extends StatefulWidget {
  const _NotificationOverlay({
    required this.handle,
    required this.message,
    required this.backgroundColor,
    required this.foregroundColor,
    required this.borderColor,
    required this.onHidden,
  });

  final _NotificationHandle handle;
  final String message;
  final Color backgroundColor;
  final Color foregroundColor;
  final Color borderColor;
  final VoidCallback onHidden;

  @override
  State<_NotificationOverlay> createState() => _NotificationOverlayState();
}

class _NotificationOverlayState extends State<_NotificationOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;
  late final Animation<Offset> _slide;
  bool _isDismissing = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: NotificationHelper._showAnimationDuration,
      reverseDuration: NotificationHelper._hideAnimationDuration,
    );
    _opacity = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    _slide = Tween<Offset>(begin: const Offset(0, -0.12), end: Offset.zero)
        .animate(
          CurvedAnimation(
            parent: _controller,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic,
          ),
        );

    widget.handle.attach(_dismiss);
    _controller.forward();
  }

  @override
  void didUpdateWidget(covariant _NotificationOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.handle, widget.handle)) {
      oldWidget.handle.detach();
      widget.handle.attach(_dismiss);
    }
  }

  Future<void> _dismiss() async {
    if (_isDismissing) return;
    _isDismissing = true;
    widget.handle.detach();

    if (_controller.status != AnimationStatus.dismissed) {
      await _controller.reverse();
    }

    widget.onHidden();
  }

  @override
  void dispose() {
    widget.handle.detach();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: true,
      child: SizedBox.expand(
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              NotificationHelper._horizontalMargin,
              NotificationHelper._topSpacing,
              NotificationHelper._horizontalMargin,
              0,
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final maxWidth = math.min(
                  constraints.maxWidth,
                  NotificationHelper._maxWidth,
                );

                return Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: maxWidth,
                      minHeight: 28,
                    ),
                    child: FadeTransition(
                      opacity: _opacity,
                      child: SlideTransition(
                        position: _slide,
                        child: Material(
                          key: const Key('notification_helper_toast'),
                          color: widget.backgroundColor,
                          elevation: 6,
                          shadowColor: Colors.black.withValues(alpha: 0.12),
                          clipBehavior: Clip.antiAlias,
                          shape: RoundedRectangleBorder(
                            borderRadius: NotificationHelper._borderRadius,
                            side: BorderSide(color: widget.borderColor),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 6,
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  widget.message,
                                  key: const Key('notification_helper_message'),
                                  maxLines: NotificationHelper._maxMessageLines,
                                  overflow: TextOverflow.ellipsis,
                                  softWrap: true,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                    height: 1.25,
                                    leadingDistribution:
                                        TextLeadingDistribution.even,
                                    color: widget.foregroundColor,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
