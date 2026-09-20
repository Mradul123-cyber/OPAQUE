import 'package:flutter/material.dart';

/// Shared palette and header for About and its document pages.
class OpaqueInfoColors {
  const OpaqueInfoColors(this.dark);
  final bool dark;
  Color get surface => dark ? const Color(0xFF19202A) : Colors.white;
  Color get ink => dark ? const Color(0xFFE0E6EF) : const Color(0xFF202127);
  Color get muted => dark ? const Color(0xFF97A3B6) : const Color(0xFF73747C);
  Color get line => dark ? const Color(0xFF303947) : const Color(0xFFEDEDF0);
  Color get soft => dark ? const Color(0xFF252E3B) : const Color(0xFFF4F6FA);
  Color get accent => dark ? const Color(0xFF9BBCFF) : const Color(0xFF335FE8);
  TextStyle text(double size, {bool bold = false, bool muted = false}) =>
      TextStyle(
        fontFamily: 'Inter',
        fontSize: size,
        fontWeight: bold ? FontWeight.w600 : FontWeight.w400,
        color: muted ? this.muted : ink,
      );
}

class OpaqueInfoHeader extends StatelessWidget implements PreferredSizeWidget {
  const OpaqueInfoHeader({
    super.key,
    required this.title,
    required this.colors,
  });
  final String title;
  final OpaqueInfoColors colors;
  @override
  Size get preferredSize => const Size.fromHeight(62);
  @override
  Widget build(BuildContext context) => AppBar(
    backgroundColor: colors.surface,
    foregroundColor: colors.ink,
    surfaceTintColor: Colors.transparent,
    elevation: 0,
    scrolledUnderElevation: 0,
    toolbarHeight: 61,
    centerTitle: false,
    titleSpacing: 0,
    leading: IconButton(
      tooltip: 'Back',
      style: ButtonStyle(
        overlayColor: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.hovered) ||
                  states.contains(WidgetState.focused)
              ? colors.soft
              : null,
        ),
      ),
      icon: const Icon(Icons.arrow_back, size: 20),
      onPressed: () => Navigator.maybePop(context),
    ),
    title: Text(
      title,
      style: colors.text(16).copyWith(fontWeight: FontWeight.w500),
    ),
    bottom: PreferredSize(
      preferredSize: const Size.fromHeight(1),
      child: Divider(height: 1, color: colors.line),
    ),
  );
}
