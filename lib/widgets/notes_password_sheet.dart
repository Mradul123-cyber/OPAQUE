import 'package:flutter/material.dart';
import '../services/notes_password_service.dart';

enum NotesPasswordAction { setup, unlock, change, disable }

/// Presentation for the existing Notes password service and stored credentials.
class NotesPasswordSheet extends StatefulWidget {
  const NotesPasswordSheet({super.key, required this.action, required this.isDark});
  final NotesPasswordAction action;
  final bool isDark;
  @override
  State<NotesPasswordSheet> createState() => _NotesPasswordSheetState();
}

class _NotesPasswordSheetState extends State<NotesPasswordSheet> {
  final _current = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  final _visible = <TextEditingController>{};
  bool _busy = false;
  String? _error;
  bool get _newPassword => widget.action == NotesPasswordAction.setup || widget.action == NotesPasswordAction.change;

  @override
  void dispose() {
    _current.dispose(); _password.dispose(); _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    setState(() { _busy = true; _error = null; });
    try {
      final service = NotesPasswordService.instance;
      if (widget.action != NotesPasswordAction.setup && !await service.verifyPassword(_current.text)) {
        if (mounted) setState(() => _error = 'That password doesn’t match. Try again.');
        return;
      }
      if (_newPassword) {
        if (_password.text.length < 4) {
          if (mounted) setState(() => _error = 'Use at least 4 characters.');
          return;
        }
        if (_password.text != _confirm.text) {
          if (mounted) setState(() => _error = 'The passwords don’t match.');
          return;
        }
        final saved = widget.action == NotesPasswordAction.change
            ? await service.changePassword(_current.text, _password.text)
            : await service.setPassword(_password.text);
        if (!saved) {
          if (mounted) setState(() => _error = 'Could not save the password. Please try again.');
          return;
        }
      } else if (widget.action == NotesPasswordAction.disable) {
        await service.disablePassword();
      }
      if (!mounted) return;
      setState(() => _busy = false);
      // Rebuild PopScope before completing the modal route.
      WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) Navigator.of(context).pop(true); });
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not access Notes protection. Please try again.');
    } finally {
      if (mounted && _busy) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dark = widget.isDark;
    final ink = dark ? const Color(0xFFE0E6EF) : const Color(0xFF202127);
    final muted = dark ? const Color(0xFF9CA8BB) : const Color(0xFF8B929F);
    final soft = dark ? const Color(0xFF283241) : const Color(0xFFF3F4F7);
    final line = dark ? const Color(0xFF303947) : const Color(0xFFEDEDF1);
    final blue = dark ? const Color(0xFF8AAFE4) : const Color(0xFF507FC3);
    final copy = switch (widget.action) {
      NotesPasswordAction.setup => ('Create a password', 'Use a password to open Notes.', 'Enable protection'),
      NotesPasswordAction.change => ('Change password', 'Enter your current password, then choose a new one.', 'Update password'),
      NotesPasswordAction.disable => ('Turn off protection?', 'Your notes will open without a password.', 'Turn off protection'),
      NotesPasswordAction.unlock => ('Unlock your notes', 'Enter your password to continue.', 'Unlock notes'),
    };
    Widget field(TextEditingController controller, String label, {bool last = false}) => Padding(
      padding: const EdgeInsets.only(top: 14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: TextStyle(fontSize: 11, color: muted)), const SizedBox(height: 7),
        TextField(controller: controller, enabled: !_busy, obscureText: !_visible.contains(controller),
          enableSuggestions: false, autocorrect: false, cursorColor: muted,
          textInputAction: last ? TextInputAction.done : TextInputAction.next,
          onSubmitted: (_) { if (last) _submit(); else FocusScope.of(context).nextFocus(); },
          style: TextStyle(fontSize: 14, color: ink), decoration: InputDecoration(
            filled: true, fillColor: soft, isDense: true, contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: line)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: line)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: muted)),
            suffixIcon: IconButton(tooltip: _visible.contains(controller) ? 'Hide password' : 'Show password',
              onPressed: _busy ? null : () => setState(() { if (!_visible.remove(controller)) _visible.add(controller); }),
              icon: Icon(_visible.contains(controller) ? Icons.visibility_outlined : Icons.visibility_off_outlined, size: 18, color: muted)),
          )),
      ]));
    return PopScope(canPop: !_busy, child: SafeArea(top: false, child: SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(24, 10, 24, 24 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Center(child: Container(width: 32, height: 3, decoration: BoxDecoration(color: line, borderRadius: BorderRadius.circular(3)))), const SizedBox(height: 12),
        Row(children: [Container(width: 42, height: 42, decoration: BoxDecoration(color: soft, borderRadius: BorderRadius.circular(14)), child: Icon(Icons.lock_outline, color: blue, size: 21)), const Spacer(),
          IconButton(tooltip: 'Close password panel', onPressed: _busy ? null : () => Navigator.pop(context, false), icon: Icon(Icons.close, color: muted, size: 20))]),
        const SizedBox(height: 16), Text(copy.$1, style: TextStyle(fontSize: 19, fontWeight: FontWeight.w600, letterSpacing: -.4, color: ink)),
        const SizedBox(height: 6), Text(copy.$2, style: TextStyle(fontSize: 12, height: 1.75, color: muted)), const SizedBox(height: 6),
        if (widget.action != NotesPasswordAction.setup) field(_current, widget.action == NotesPasswordAction.unlock ? 'Password' : 'Current password', last: !_newPassword),
        if (_newPassword) ...[field(_password, 'New password'), field(_confirm, widget.action == NotesPasswordAction.change ? 'Confirm new password' : 'Confirm password', last: true)],
        Padding(padding: const EdgeInsets.only(top: 8, bottom: 8), child: Semantics(liveRegion: true, child: Text(_error ?? '', style: const TextStyle(fontSize: 11, color: Color(0xFFC66F77))))),
        SizedBox(width: double.infinity, child: FilledButton(style: FilledButton.styleFrom(backgroundColor: blue, foregroundColor: dark ? const Color(0xFF19202A) : Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 13), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13))),
          onPressed: _busy ? null : _submit, child: Text(_busy ? 'Please wait…' : copy.$3, style: const TextStyle(fontSize: 12)))),
        if (_newPassword) Padding(padding: const EdgeInsets.only(top: 12), child: Text('At least 4 characters.', style: TextStyle(fontSize: 10, color: muted))),
      ]),
    )));
  }
}
