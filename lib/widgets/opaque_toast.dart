import 'package:flutter/material.dart';

/// Toast types supported by [OpaqueToast].
enum OpaqueToastType {
  normal,
  error,
  warning,
  success,
  info,
}

/// Central toast utility for the Opaque design system.
///
/// Features:
/// - Small, one-line, centered floating pill layout.
/// - Dedicated background colors for each status:
///   - Normal: Inverted contrast (White on dark mode, Black on light mode).
///   - Error / Failure: Crimson Red (`#DC2626`) with white text.
///   - Warning: Crimson Red (`#DC2626`) with white text.
///   - Success: Emerald Green (`#16A34A`) with white text.
///   - Info: Vibrant Blue (`#2563EB`) with white text.
/// - Matching soft glowing shadows.
/// - Inter typography (`13px`, semi-bold, `-0.1` letter-spacing).
/// - Instant replacement of previous toasts (no queueing lag).
class OpaqueToast {
  /// Display a centered floating pill toast.
  static void show(
    BuildContext context,
    String message, {
    OpaqueToastType type = OpaqueToastType.normal,
    IconData? icon,
    bool? showIcon,
    Duration duration = const Duration(milliseconds: 2000),
    double bottomMargin = 12.0,
  }) {
    if (!context.mounted) return;

    final isDark = Theme.of(context).brightness == Brightness.dark;

    Color bg;
    Color fg = Colors.white;
    Color shadowColor;

    switch (type) {
      case OpaqueToastType.error:
        bg = const Color(0xFFDC2626);
        shadowColor = const Color(0xFFDC2626).withOpacity(0.35);
        break;
      case OpaqueToastType.warning:
        bg = const Color(0xFFDC2626);
        shadowColor = const Color(0xFFDC2626).withOpacity(0.35);
        break;
      case OpaqueToastType.success:
        bg = const Color(0xFF16A34A);
        shadowColor = const Color(0xFF16A34A).withOpacity(0.35);
        break;
      case OpaqueToastType.info:
        bg = const Color(0xFF2563EB);
        shadowColor = const Color(0xFF2563EB).withOpacity(0.35);
        break;
      case OpaqueToastType.normal:
        bg = isDark ? Colors.white : Colors.black;
        fg = isDark ? Colors.black : Colors.white;
        shadowColor = Colors.black.withOpacity(0.18);
        break;
    }

    final messenger = ScaffoldMessenger.of(context);
    messenger.removeCurrentSnackBar();

    Widget? leadingIcon;
    final bool shouldShowIcon = showIcon ?? (type != OpaqueToastType.normal || icon != null);

    if (shouldShowIcon) {
      if (icon != null) {
        leadingIcon = Icon(icon, size: 15, color: fg);
      } else {
        switch (type) {
          case OpaqueToastType.error:
            leadingIcon = const Icon(
              Icons.error_outline_rounded,
              size: 15,
              color: Colors.white,
            );
            break;
          case OpaqueToastType.warning:
            leadingIcon = const Icon(
              Icons.warning_amber_rounded,
              size: 15,
              color: Colors.white,
            );
            break;
          case OpaqueToastType.success:
            leadingIcon = const Icon(
              Icons.check_circle_outline_rounded,
              size: 15,
              color: Colors.white,
            );
            break;
          case OpaqueToastType.info:
            leadingIcon = const Icon(
              Icons.info_outline_rounded,
              size: 15,
              color: Colors.white,
            );
            break;
          case OpaqueToastType.normal:
            leadingIcon = null;
            break;
        }
      }
    }

    messenger.showSnackBar(
      SnackBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        // Fixed placement anchors above navigation/keyboard, rather than
        // above the floating action button (including its expanded menu).
        padding: EdgeInsets.fromLTRB(16, 0, 16, bottomMargin),
        behavior: SnackBarBehavior.fixed,
        duration: duration,
        content: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: shadowColor,
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (leadingIcon != null) ...[
                  leadingIcon,
                  const SizedBox(width: 7),
                ],
                Flexible(
                  child: Text(
                    message,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: fg,
                      letterSpacing: -0.1,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Convenience method for error and failure toasts (Red pill)
  static void error(
    BuildContext context,
    String message, {
    bool showIcon = true,
    Duration duration = const Duration(milliseconds: 2500),
    double bottomMargin = 12.0,
  }) {
    show(
      context,
      message,
      type: OpaqueToastType.error,
      showIcon: showIcon,
      duration: duration,
      bottomMargin: bottomMargin,
    );
  }

  /// Convenience method for warning toasts (Red pill)
  static void warning(
    BuildContext context,
    String message, {
    bool showIcon = true,
    Duration duration = const Duration(milliseconds: 2500),
    double bottomMargin = 12.0,
  }) {
    show(
      context,
      message,
      type: OpaqueToastType.warning,
      showIcon: showIcon,
      duration: duration,
      bottomMargin: bottomMargin,
    );
  }

  /// Convenience method for success toasts (Green pill)
  static void success(
    BuildContext context,
    String message, {
    bool showIcon = true,
    Duration duration = const Duration(milliseconds: 2000),
    double bottomMargin = 12.0,
  }) {
    show(
      context,
      message,
      type: OpaqueToastType.success,
      showIcon: showIcon,
      duration: duration,
      bottomMargin: bottomMargin,
    );
  }

  /// Convenience method for info toasts (Blue pill)
  static void info(
    BuildContext context,
    String message, {
    bool showIcon = true,
    Duration duration = const Duration(milliseconds: 2000),
    double bottomMargin = 12.0,
  }) {
    show(
      context,
      message,
      type: OpaqueToastType.info,
      showIcon: showIcon,
      duration: duration,
      bottomMargin: bottomMargin,
    );
  }
}
