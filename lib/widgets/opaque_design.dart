import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/user_settings_provider.dart';

class OpaqueColors {
  OpaqueColors(BuildContext context)
    : dark = context.read<UserSettingsProvider>().isDarkMode;
  final bool dark;
  Color get surface => dark ? const Color(0xFF19202A) : Colors.white;
  Color get ink => dark ? const Color(0xFFE0E6EF) : const Color(0xFF202127);
  Color get muted => dark ? const Color(0xFF9CA8BB) : const Color(0xFF8B929F);
  Color get soft => dark ? const Color(0xFF283241) : const Color(0xFFF3F4F7);
  Color get line => dark ? const Color(0xFF303947) : const Color(0xFFEDEDF1);
  Color get blue => dark ? const Color(0xFF8AAFE4) : const Color(0xFF507FC3);
  TextStyle text(double size, {bool bold = false, bool muted = false}) =>
      TextStyle(
        fontFamily: 'Inter',
        fontSize: size,
        fontWeight: bold ? FontWeight.w600 : FontWeight.w400,
        color: muted ? this.muted : ink,
      );
  InputDecoration field(String hint) => InputDecoration(
    hintText: hint,
    hintStyle: text(12, muted: true),
    filled: true,
    fillColor: soft,
    contentPadding: const EdgeInsets.all(13),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: line),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: line),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: blue),
    ),
  );
}

class OpaqueButton extends StatelessWidget {
  const OpaqueButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.primary = false,
    this.danger = false,
  });
  final String label;
  final VoidCallback? onPressed;
  final bool primary, danger;
  @override
  Widget build(BuildContext context) {
    final c = OpaqueColors(context);
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        backgroundColor: danger
            ? const Color(0xFFBF6974)
            : primary
            ? const Color(0xFF507FC3)
            : c.soft,
        foregroundColor: primary || danger ? Colors.white : c.muted,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
      ),
      child: Text(label, style: const TextStyle(fontSize: 12)),
    );
  }
}

class OpaqueDialog extends StatelessWidget {
  const OpaqueDialog({
    super.key,
    required this.title,
    required this.body,
    required this.actions,
    this.icon = Icons.notes_outlined,
  });
  final String title;
  final Widget body;
  final List<Widget> actions;
  final IconData icon;
  @override
  Widget build(BuildContext context) {
    final c = OpaqueColors(context);
    return Dialog(
      backgroundColor: c.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: c.line),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: c.soft,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: c.blue, size: 19),
            ),
            const SizedBox(height: 16),
            Text(title, style: c.text(18, bold: true)),
            const SizedBox(height: 9),
            body,
            const SizedBox(height: 21),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.end,
              children: actions,
            ),
          ],
        ),
      ),
    );
  }
}

Future<bool> showOpaqueConfirmation(
  BuildContext context, {
  required String title,
  required String body,
  String confirm = 'Save',
  bool danger = false,
  IconData icon = Icons.notes_outlined,
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (ctx) => OpaqueDialog(
        title: title,
        icon: icon,
        body: Text(
          body,
          style: OpaqueColors(ctx).text(12, muted: true).copyWith(height: 1.8),
        ),
        actions: [
          OpaqueButton(
            label: 'Cancel',
            onPressed: () => Navigator.pop(ctx, false),
          ),
          OpaqueButton(
            label: confirm,
            primary: true,
            danger: danger,
            onPressed: () => Navigator.pop(ctx, true),
          ),
        ],
      ),
    ) ??
    false;

class OpaqueSheet extends StatelessWidget {
  const OpaqueSheet({
    super.key,
    required this.title,
    required this.description,
    required this.child,
    this.icon,
    this.showIcon = true,
  });
  final String title, description;
  final Widget child;
  final IconData? icon;
  final bool showIcon;
  @override
  Widget build(BuildContext context) {
    final c = OpaqueColors(context);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * .85,
        ),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 10, 24, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Center(
                  child: Container(
                    width: 32,
                    height: 3,
                    decoration: BoxDecoration(
                      color: c.line,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    if (showIcon)
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: c.soft,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          icon ?? Icons.notes_outlined,
                          color: c.blue,
                          size: 19,
                        ),
                      ),
                    const Spacer(),
                    IconButton(
                      tooltip: 'Close',
                      onPressed: () => Navigator.pop(context),
                      icon: Icon(Icons.close, size: 20, color: c.muted),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Text(title, style: c.text(20, bold: true)),
                const SizedBox(height: 8),
                Text(description, style: c.text(12, muted: true)),
                const SizedBox(height: 20),
                child,
              ],
            ),
          ),
        ),
      ),
    );
  }
}
