import 'package:flutter/material.dart';
import 'opaque_design.dart';
import '../services/database_service.dart';
import '../models/note_model.dart';

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
        if (mounted) {
          setState(
            () => _error = 'That category already exists. Choose another name.',
          );
        }
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
      if (mounted) {
        setState(() => _error = 'Could not create category. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = OpaqueColors(context);
    return OpaqueSheet(
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
            child: OpaqueButton(
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
