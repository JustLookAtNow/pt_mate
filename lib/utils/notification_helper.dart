import 'package:flutter/material.dart';
import 'package:toastification/toastification.dart';

class NotificationHelper {
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
    toastification.showCustom(
      context: context,
      alignment: Alignment.bottomCenter,
      autoCloseDuration: duration,
      builder: (_, holder) {
        return Align(
          alignment: Alignment.bottomCenter,
          child: Container(
            margin: const EdgeInsets.only(bottom: 24),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            decoration: BoxDecoration(
              color: backgroundColor,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: borderColor),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Text(
              message,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: foregroundColor,
              ),
            ),
          ),
        );
      },
    );
  }
}
