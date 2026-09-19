import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/user_settings_provider.dart';
import '../services/database_service.dart';
import '../models/note_model.dart';

class NotesColors {
  NotesColors(BuildContext context)
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

class NotesButton extends StatelessWidget {
  const NotesButton({
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
    final c = NotesColors(context);
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

class NotesDialog extends StatelessWidget {
  const NotesDialog({
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
    final c = NotesColors(context);
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

Future<bool> showNotesConfirmation(
  BuildContext context, {
  required String title,
  required String body,
  String confirm = 'Save',
  bool danger = false,
  IconData icon = Icons.notes_outlined,
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (ctx) => NotesDialog(
        title: title,
        icon: icon,
        body: Text(
          body,
          style: NotesColors(ctx).text(12, muted: true).copyWith(height: 1.8),
        ),
        actions: [
          NotesButton(
            label: 'Cancel',
            onPressed: () => Navigator.pop(ctx, false),
          ),
          NotesButton(
            label: confirm,
            primary: true,
            danger: danger,
            onPressed: () => Navigator.pop(ctx, true),
          ),
        ],
      ),
    ) ??
    false;

class NotesSheet extends StatelessWidget {
  const NotesSheet({
    super.key,
    required this.title,
    required this.description,
    required this.child,
  });
  final String title, description;
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final c = NotesColors(context);
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
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: c.soft,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.notes_outlined,
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

Future<NoteCategory?> showNotesCategoryCreation(BuildContext context) =>
    showModalBottomSheet<NoteCategory>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _CategoryCreation(),
    );

class _CategoryCreation extends StatefulWidget {
  const _CategoryCreation();
  @override
  State<_CategoryCreation> createState() => _CategoryCreationState();
}

class _CategoryCreationState extends State<_CategoryCreation> {
  final _name = TextEditingController();
  String _color = '#719cdd';
  String? _error;
  bool _busy = false;
  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    if (_busy) return;
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Enter a category name.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final existing = await DatabaseService.instance.getAllCategories();
      final normalized = name.toLowerCase();
      if (normalized == 'all' ||
          normalized == 'no category' ||
          existing.any((c) => c.name.toLowerCase() == normalized)) {
        if (mounted)
          setState(
            () => _error = 'That category already exists. Choose another name.',
          );
        return;
      }
      final category = NoteCategory(
        name: name,
        colorCode: _color,
        createdAt: DateTime.now(),
      );
      await DatabaseService.instance.createCategory(category);
      if (mounted) Navigator.pop(context, category);
    } catch (_) {
      if (mounted)
        setState(() => _error = 'Could not create category. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = NotesColors(context);
    return NotesSheet(
      title: 'Add category',
      description: 'Give your notes a place to belong.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('CATEGORY NAME', style: c.text(10, muted: true)),
          const SizedBox(height: 8),
          TextField(
            controller: _name,
            autofocus: true,
            maxLength: 30,
            enabled: !_busy,
            style: c.text(13),
            decoration: c.field('e.g. Work'),
            onSubmitted: (_) => _create(),
          ),
          const SizedBox(height: 14),
          Text('COLOUR', style: c.text(10, muted: true)),
          const SizedBox(height: 12),
          Wrap(
            spacing: 14,
            children: [
              for (final item in [
                ('Blue', '#719cdd'),
                ('Lilac', '#a58bd4'),
                ('Mint', '#70b9a4'),
                ('Rose', '#d88fa4'),
                ('Amber', '#d9ad76'),
              ])
                Semantics(
                  label: item.$1,
                  selected: _color == item.$2,
                  button: true,
                  child: InkWell(
                    onTap: _busy
                        ? null
                        : () => setState(() => _color = item.$2),
                    borderRadius: BorderRadius.circular(18),
                    child: Container(
                      width: 30,
                      height: 30,
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: _color == item.$2
                              ? c.muted
                              : Colors.transparent,
                        ),
                      ),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Color(
                            int.parse(item.$2.replaceFirst('#', '0xFF')),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 14),
              child: Text(
                _error!,
                style: c.text(12).copyWith(color: const Color(0xFFBF6974)),
              ),
            ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: NotesButton(
              label: _busy ? 'Creating…' : 'Create category',
              primary: true,
              onPressed: _busy ? null : _create,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'New categories appear in the picker and Notes filters.',
            style: c.text(10, muted: true),
          ),
        ],
      ),
    );
  }
}
