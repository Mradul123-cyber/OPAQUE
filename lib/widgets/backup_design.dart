import 'package:flutter/material.dart';
import 'opaque_design.dart';

class BackupHeader extends StatelessWidget implements PreferredSizeWidget {
  const BackupHeader({super.key, this.onHelp});
  final VoidCallback? onHelp;
  @override
  Size get preferredSize => const Size.fromHeight(60);
  @override
  Widget build(BuildContext context) {
    final c = OpaqueColors(context);
    return AppBar(
      backgroundColor: c.surface,
      foregroundColor: c.muted,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      toolbarHeight: 60,
      centerTitle: true,
      leading: IconButton(
        tooltip: 'Back',
        icon: const Icon(Icons.arrow_back, size: 20),
        onPressed: () => Navigator.maybePop(context),
      ),
      title: Semantics(
        label: 'OPAQUE',
        child: ExcludeSemantics(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 23,
                height: 25,
                child: CustomPaint(painter: _BackupMark(c.ink, c.surface)),
              ),
              Text(
                'PAQUE',
                style: c
                    .text(19, bold: true)
                    .copyWith(letterSpacing: 2.5, fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
      ),
      actions: [
        if (onHelp != null)
          IconButton(
            tooltip: 'How backup works',
            onPressed: onHelp,
            icon: const Icon(Icons.info_outline, size: 20),
          ),
        const SizedBox(width: 8),
      ],
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Divider(height: 1, color: c.line),
      ),
    );
  }
}

class _BackupMark extends CustomPainter {
  _BackupMark(this.ink, this.surface);
  final Color ink, surface;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawOval(
      Rect.fromLTWH(2.5, 2.5, size.width - 5, size.height - 5),
      Paint()
        ..color = ink
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5,
    );
    canvas.drawLine(
      Offset(size.width * .25, size.height),
      Offset(size.width * .75, 0),
      Paint()
        ..color = surface
        ..strokeWidth = 2.5,
    );
  }

  @override
  bool shouldRepaint(_BackupMark old) =>
      old.ink != ink || old.surface != surface;
}

Future<T?> showBackupSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
}) => showModalBottomSheet<T>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  backgroundColor: Colors.transparent,
  builder: builder,
);

// Accepts the existing action widgets so their backup handlers remain unchanged.
class BackupDialog extends StatelessWidget {
  const BackupDialog({
    super.key,
    this.title,
    this.content,
    this.actions,
    this.backgroundColor,
    this.shape,
  });
  final Widget? title, content;
  final List<Widget>? actions;
  final Color? backgroundColor;
  final ShapeBorder? shape;
  @override
  Widget build(BuildContext context) {
    final c = OpaqueColors(context);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * .88,
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
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 32,
                    height: 3,
                    decoration: BoxDecoration(
                      color: c.line,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    BackupSymbol(icon: Icons.backup_outlined),
                    const Spacer(),
                    IconButton(
                      tooltip: 'Close',
                      onPressed: () => Navigator.pop(context),
                      icon: Icon(Icons.close, color: c.muted, size: 20),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if (title != null)
                  DefaultTextStyle(
                    style: c.text(20, bold: true),
                    child: title!,
                  ),
                const SizedBox(height: 16),
                if (content != null)
                  DefaultTextStyle(
                    style: c.text(12, muted: true),
                    child: content!,
                  ),
                if (actions?.isNotEmpty == true) ...[
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: TextButtonTheme(
                      data: TextButtonThemeData(
                        style: TextButton.styleFrom(
                          backgroundColor: c.soft,
                          foregroundColor: c.blue,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(11),
                          ),
                        ),
                      ),
                      child: Wrap(
                        alignment: WrapAlignment.end,
                        spacing: 8,
                        runSpacing: 8,
                        children: actions!,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class BackupSymbol extends StatelessWidget {
  const BackupSymbol({super.key, required this.icon});
  final IconData icon;
  @override
  Widget build(BuildContext context) {
    final c = OpaqueColors(context);
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: c.soft,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(icon, color: c.blue, size: 20),
    );
  }
}

class BackupPassphraseSheet extends StatefulWidget {
  const BackupPassphraseSheet({
    super.key,
    required this.title,
    required this.hint,
    required this.confirm,
  });
  final String title, hint;
  final bool confirm;
  @override
  State<BackupPassphraseSheet> createState() => _BackupPassphraseSheetState();
}

class _BackupPassphraseSheetState extends State<BackupPassphraseSheet> {
  final _password = TextEditingController(),
      _confirmation = TextEditingController();
  bool _obscured = true;
  String? _error;
  @override
  void dispose() {
    _password.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  void _submit() {
    if (_password.text.isEmpty) {
      setState(() => _error = 'Enter your passphrase.');
      return;
    }
    if (widget.confirm && _password.text != _confirmation.text) {
      setState(() => _error = 'The passphrases don’t match.');
      return;
    }
    Navigator.pop(context, _password.text);
  }

  @override
  Widget build(BuildContext context) {
    final c = OpaqueColors(context);
    return OpaqueSheet(
      title: widget.title,
      description: widget.confirm
          ? 'Keep your passphrase safe. You’ll need it to restore.'
          : 'Enter the passphrase used to create this backup.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('PASSPHRASE', style: c.text(10, muted: true)),
          const SizedBox(height: 7),
          TextField(
            controller: _password,
            autofocus: true,
            obscureText: _obscured,
            autocorrect: false,
            enableSuggestions: false,
            style: c.text(13),
            decoration: c
                .field(widget.hint)
                .copyWith(
                  suffixIcon: IconButton(
                    tooltip: _obscured ? 'Show passphrase' : 'Hide passphrase',
                    onPressed: () => setState(() => _obscured = !_obscured),
                    icon: Icon(
                      _obscured
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                      color: c.muted,
                      size: 19,
                    ),
                  ),
                ),
            onSubmitted: widget.confirm ? null : (_) => _submit(),
          ),
          if (widget.confirm) ...[
            const SizedBox(height: 14),
            Text('CONFIRM PASSPHRASE', style: c.text(10, muted: true)),
            const SizedBox(height: 7),
            TextField(
              controller: _confirmation,
              obscureText: _obscured,
              autocorrect: false,
              enableSuggestions: false,
              style: c.text(13),
              decoration: c.field('Enter it again'),
              onSubmitted: (_) => _submit(),
            ),
          ],
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                _error!,
                style: c.text(11).copyWith(color: const Color(0xFFBF6974)),
              ),
            ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: OpaqueButton(
              label: widget.confirm ? 'Continue' : 'Restore backup',
              primary: true,
              onPressed: _submit,
            ),
          ),
        ],
      ),
    );
  }
}

class BackupAction extends StatelessWidget {
  const BackupAction({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
    this.primary = false,
  });
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool primary;
  @override
  Widget build(BuildContext context) {
    final c = OpaqueColors(context);
    return TextButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 16),
      label: Text(label, style: const TextStyle(fontSize: 12)),
      style: TextButton.styleFrom(
        backgroundColor: primary ? const Color(0xFF507FC3) : c.soft,
        foregroundColor: primary ? Colors.white : c.muted,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}
