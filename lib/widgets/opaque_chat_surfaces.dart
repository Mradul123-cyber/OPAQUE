import 'package:flutter/material.dart';
import 'opaque_info_design.dart';

class OpaqueEncryptionNotice extends StatelessWidget {
  const OpaqueEncryptionNotice({super.key});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final color = dark ? const Color(0xFF8BEA91) : const Color(0xFF26833C);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Text.rich(
        TextSpan(
          children: [
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Icon(Icons.lock_outline_rounded, size: 13, color: color),
              ),
            ),
            const TextSpan(text: 'Messages are end-to-end encrypted.'),
          ],
        ),
        textAlign: TextAlign.center,
        style: TextStyle(
          fontFamily: 'Inter',
          fontSize: 11,
          height: 1.5,
          fontWeight: FontWeight.w500,
          color: color,
        ),
      ),
    );
  }
}

/// Shared dialog surface; callers retain their original actions and route results.
class OpaqueChatDialog extends StatelessWidget {
  const OpaqueChatDialog({
    super.key,
    required this.title,
    this.content,
    this.actions,
    this.contentPadding,
  });
  final Widget title;
  final Widget? content;
  final List<Widget>? actions;
  final EdgeInsetsGeometry? contentPadding;

  @override
  Widget build(BuildContext context) {
    final c = OpaqueInfoColors(Theme.of(context).brightness == Brightness.dark);
    return Theme(
      data: Theme.of(context).copyWith(
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: c.accent,
            minimumSize: const Size(64, 44),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            textStyle: c.text(13, bold: true),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        listTileTheme: ListTileThemeData(
          textColor: c.ink,
          iconColor: c.muted,
          titleTextStyle: c.text(13, bold: true),
          subtitleTextStyle: c.text(12, muted: true),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          minLeadingWidth: 22,
          horizontalTitleGap: 12,
        ),
      ),
      child: AlertDialog(
        backgroundColor: c.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 3,
        scrollable: true,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: BorderSide(color: c.line),
        ),
        titlePadding: const EdgeInsets.fromLTRB(22, 22, 22, 12),
        contentPadding:
            contentPadding ?? const EdgeInsets.fromLTRB(22, 0, 22, 8),
        actionsPadding: const EdgeInsets.fromLTRB(14, 4, 14, 14),
        titleTextStyle: c.text(17, bold: true),
        contentTextStyle: c.text(13, muted: true).copyWith(height: 1.6),
        title: title,
        content: content,
        actions: actions,
      ),
    );
  }
}

class OpaqueChatSheet extends StatelessWidget {
  const OpaqueChatSheet({super.key, required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = OpaqueInfoColors(Theme.of(context).brightness == Brightness.dark);
    return Material(
      color: c.surface,
      shape: RoundedRectangleBorder(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        side: BorderSide(color: c.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 32,
                height: 4,
                decoration: BoxDecoration(
                  color: c.line,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(6, 18, 6, 14),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(title, style: c.text(16, bold: true)),
                ),
              ),
              Flexible(
                child: ListTileTheme(
                  data: ListTileThemeData(
                    textColor: c.ink,
                    iconColor: c.muted,
                    titleTextStyle: c.text(13, bold: true),
                    subtitleTextStyle: c.text(12, muted: true),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: child,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Focused confirmation surface for chat-level actions.
class OpaqueChatConfirmation extends StatelessWidget {
  const OpaqueChatConfirmation({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
    required this.note,
    required this.actionLabel,
    required this.onConfirm,
  });
  final IconData icon;
  final String title, description, note, actionLabel;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    final c = OpaqueInfoColors(Theme.of(context).brightness == Brightness.dark);
    final accent = c.dark ? const Color(0xFFF0A0A7) : const Color(0xFFB94C5B);
    final primary = c.dark ? const Color(0xFFECA0A8) : const Color(0xFFB94C5B);
    return Dialog(
      backgroundColor: c.surface,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(26),
        side: BorderSide(color: c.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: .12),
                        borderRadius: BorderRadius.circular(15),
                      ),
                      child: Icon(icon, size: 23, color: accent),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'CHAT CONTROLS',
                        style: c
                            .text(10, bold: true, muted: true)
                            .copyWith(letterSpacing: 1.2),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Text(
                  title,
                  style: c
                      .text(22, bold: true)
                      .copyWith(height: 1.2, letterSpacing: -.5),
                ),
                const SizedBox(height: 10),
                Text(
                  description,
                  style: c.text(13, muted: true).copyWith(height: 1.6),
                ),
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: c.soft,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    note,
                    style: c.text(12, muted: true).copyWith(height: 1.5),
                  ),
                ),
                const SizedBox(height: 24),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final cancel = OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: c.ink,
                        side: BorderSide(color: c.line),
                        minimumSize: const Size.fromHeight(48),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    );
                    final confirm = FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: primary,
                        foregroundColor: c.dark
                            ? const Color(0xFF351B22)
                            : Colors.white,
                        minimumSize: const Size.fromHeight(48),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        textStyle: c.text(13, bold: true),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      onPressed: onConfirm,
                      child: Text(actionLabel, textAlign: TextAlign.center),
                    );
                    if (constraints.maxWidth < 250 ||
                        MediaQuery.textScalerOf(context).scale(13) > 18) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [confirm, const SizedBox(height: 8), cancel],
                      );
                    }
                    return Row(
                      children: [
                        Expanded(child: cancel),
                        const SizedBox(width: 10),
                        Expanded(child: confirm),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
