import '../widgets/notes_design.dart';
import '../widgets/notes_password_sheet.dart';
import '../widgets/opaque_navigation.dart';
import '../widgets/opaque_toast.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import '../services/database_service.dart';
import '../services/user_settings_provider.dart';
import '../services/notes_password_service.dart';
import '../models/note_model.dart';
import 'create_note_screen.dart';

class NotesScreen extends StatefulWidget {
  const NotesScreen({super.key, this.embedded = false});
  final bool embedded;

  @override
  State<NotesScreen> createState() => _NotesScreenState();
}

class _NotesScreenState extends State<NotesScreen> {
  final TextEditingController _searchController = TextEditingController();
  List<Note> _notes = [];
  List<Note> _filteredNotes = [];
  List<NoteCategory> _categories = [];
  bool _isLoading = true;
  bool _isSearching = false;
  String? _selectedCategory;
  bool _isUnlocked = false;
  bool _isPasswordEnabled = false;

  @override
  void initState() {
    super.initState();
    _checkPasswordProtection();
    _searchController.addListener(_filterNotes);
  }

  Future<void> _updatePasswordStatus() async {
    final enabled = await NotesPasswordService.instance.isPasswordEnabled();
    if (mounted) {
      setState(() {
        _isPasswordEnabled = enabled;
      });
    }
  }

  Future<void> _checkPasswordProtection({bool requestUnlock = false}) async {
    try {
      final enabled = await NotesPasswordService.instance.isPasswordEnabled();
      if (!mounted) return;
      setState(() {
        _isPasswordEnabled = enabled;
        _isUnlocked = !enabled;
      });
      if (enabled) {
        // IndexedStack constructs Notes before it is visible. Show its locked
        // surface first, and ask for the password only when Unlock is tapped.
        if (!requestUnlock) return;
        final unlocked = await _showPasswordSheet(NotesPasswordAction.unlock);
        if (!mounted || !unlocked) return;
        setState(() => _isUnlocked = true);
      }
      await _loadNotes();
    } catch (_) {
      if (mounted) {
        setState(() => _isUnlocked = false);
        OpaqueToast.error(
          context,
          'Could not access Notes protection. Please try again.',
        );
      }
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadNotes() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      final dbService = DatabaseService.instance;
      final notes = await dbService.getAllNotes();
      final categories = await dbService.getAllCategories();

      if (mounted) {
        setState(() {
          _notes = notes;
          _filteredNotes = notes;
          _categories = categories;
          _isLoading = false;
        });
        _filterNotes();
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _filterNotes() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      _isSearching = query.isNotEmpty;
      _filteredNotes = _notes.where((note) {
        if (_selectedCategory != null && note.category != _selectedCategory)
          return false;
        return note.title.toLowerCase().contains(query) ||
            _extractPlainText(note.content).toLowerCase().contains(query);
      }).toList();
    });
  }

  String _extractPlainText(String content) {
    try {
      final doc = quill.Document.fromJson(jsonDecode(content));
      return doc.toPlainText();
    } catch (e) {
      return content;
    }
  }

  Color _getCategoryColor(String? categoryName, {Color? defaultColor}) {
    if (categoryName == null) return defaultColor ?? const Color(0xFF507FC3);
    for (final cat in _categories) {
      if (cat.name.toLowerCase() == categoryName.toLowerCase()) {
        if (cat.colorCode != null && cat.colorCode!.isNotEmpty) {
          try {
            final hex = cat.colorCode!.replaceFirst('#', '');
            if (hex.length == 6) {
              return Color(int.parse('0xFF$hex'));
            } else if (hex.length == 8) {
              return Color(int.parse('0x$hex'));
            }
          } catch (_) {}
        }
        break;
      }
    }
    return defaultColor ?? const Color(0xFF507FC3);
  }

  Future<void> _editNote(Note note) async {
    final result = await Navigator.of(context).push(
      MaterialPageRoute(builder: (context) => CreateNoteScreen(note: note)),
    );
    if (mounted) _loadNotes();
  }

  Future<void> _deleteNote(Note note) async {
    final confirmed = await showNotesConfirmation(
      context,
      title: 'Delete note?',
      body:
          'This note will be permanently deleted. This action cannot be undone.',
      confirm: 'Delete note',
      danger: true,
      icon: Icons.delete_outline,
    );

    if (confirmed == true) {
      try {
        await DatabaseService.instance.deleteNote(note.id!);
        if (mounted) await _loadNotes();
      } catch (_) {
        if (mounted)
          await showNotesConfirmation(
            context,
            title: 'Couldn’t delete note',
            body: 'Your note is still here. Please try again.',
            confirm: 'Close',
            icon: Icons.delete_outline,
          );
      }
    }
  }

  Future<void> _togglePin(Note note) async {
    await DatabaseService.instance.toggleNotePin(note.id!, !note.isPinned);
    _loadNotes();
  }

  @override
  Widget build(BuildContext context) {
    final dark = context.watch<UserSettingsProvider>().isDarkMode;
    final surface = dark ? const Color(0xFF19202A) : Colors.white;
    final ink = dark ? const Color(0xFFE0E6EF) : const Color(0xFF202127);
    final muted = dark ? const Color(0xFF9CA8BB) : const Color(0xFF8B929F);
    final soft = dark ? const Color(0xFF283241) : const Color(0xFFF3F4F7);
    final line = dark ? const Color(0xFF303947) : const Color(0xFFEDEDF1);
    final blue = dark ? const Color(0xFF8AAFE4) : const Color(0xFF507FC3);
    final rows = [..._filteredNotes]
      ..sort((a, b) {
        if (a.isPinned != b.isPinned) return a.isPinned ? -1 : 1;
        return b.updatedAt.compareTo(a.updatedAt);
      });
    return Scaffold(
      backgroundColor: surface,
      appBar: widget.embedded
          ? null
          : AppBar(
              title: const Text('Notes'),
              backgroundColor: surface,
              foregroundColor: ink,
              elevation: 0,
              scrolledUnderElevation: 0,
            ),
      floatingActionButton: !_isUnlocked
          ? null
          : SizedBox(
              width: 44,
              height: 44,
              child: FloatingActionButton(
                tooltip: 'New note',
                elevation: 0,
                backgroundColor: dark
                    ? const Color(0xFFDCE6F4)
                    : const Color(0xFF303B4C),
                foregroundColor: dark ? const Color(0xFF243041) : Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15),
                ),
                onPressed: () async {
                  final result = await Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const CreateNoteScreen()),
                  );
                  if (mounted) _loadNotes();
                },
                child: const Icon(Icons.add, size: 23),
              ),
            ),
      body: !_isUnlocked
          ? _buildLockedNotes(dark)
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                  child: SizedBox(
                    height: 36,
                    child: TextField(
                      controller: _searchController,
                      cursorColor: muted,
                      style: TextStyle(fontSize: 13, color: ink),
                      decoration: InputDecoration(
                        hintText: 'Search notes',
                        hintStyle: TextStyle(fontSize: 12, color: muted),
                        prefixIcon: Padding(
                          padding: const EdgeInsets.all(10),
                          child: OpaqueIcon('search', size: 16, color: muted),
                        ),
                        filled: true,
                        fillColor: soft,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(19),
                          borderSide: BorderSide.none,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(19),
                          borderSide: BorderSide.none,
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(19),
                          borderSide: BorderSide(color: muted),
                        ),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Container(
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          color: soft,
                          borderRadius: BorderRadius.circular(17),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            for (final category in <String?>[
                              null,
                              ..._categories.map((c) => c.name),
                            ])
                              Padding(
                                padding: const EdgeInsets.only(right: 2),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(14),
                                  onTap: () {
                                    setState(
                                      () => _selectedCategory = category,
                                    );
                                    _filterNotes();
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      color: _selectedCategory == category
                                          ? surface
                                          : Colors.transparent,
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        if (category != null) ...[
                                          Container(
                                            width: 7,
                                            height: 7,
                                            margin: const EdgeInsets.only(right: 6),
                                            decoration: BoxDecoration(
                                              shape: BoxShape.circle,
                                              color: _getCategoryColor(
                                                category,
                                                defaultColor: blue,
                                              ),
                                            ),
                                          ),
                                        ],
                                        Text(
                                          category ?? 'All',
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight:
                                                _selectedCategory == category
                                                ? FontWeight.w600
                                                : FontWeight.w400,
                                            color: _selectedCategory == category
                                                ? ink
                                                : muted,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            IconButton(
                              tooltip: 'Add category',
                              visualDensity: VisualDensity.compact,
                              constraints: const BoxConstraints(
                                minWidth: 30,
                                minHeight: 27,
                              ),
                              padding: EdgeInsets.zero,
                              icon: Icon(Icons.add, size: 16, color: blue),
                              onPressed: () async {
                                await showNotesCategoryCreation(context);
                                if (mounted) await _loadNotes();
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(22, 5, 16, 0),
                  child: Row(
                    children: [
                      Text(
                        '${rows.length} ${rows.length == 1 ? 'note' : 'notes'}',
                        style: TextStyle(fontSize: 10, color: muted),
                      ),
                      const Spacer(),
                      IconButton(
                        tooltip: 'Notes protection',
                        iconSize: 16,
                        constraints: const BoxConstraints.tightFor(
                          width: 30,
                          height: 30,
                        ),
                        padding: EdgeInsets.zero,
                        onPressed: _showPasswordSettings,
                        icon: Icon(
                          _isPasswordEnabled
                              ? Icons.lock_outline
                              : Icons.lock_open_outlined,
                          color: muted,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: _isLoading
                      ? Center(
                          child: SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              color: blue,
                              strokeWidth: 2,
                            ),
                          ),
                        )
                      : rows.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              OpaqueIcon('notes', size: 32, color: muted),
                              const SizedBox(height: 16),
                              Text(
                                _isSearching
                                    ? 'No matching notes'
                                    : 'Room for your next thought',
                                style: TextStyle(fontSize: 14, color: ink),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                _isSearching
                                    ? 'Try another word or category.'
                                    : 'Tap + to write something down.',
                                style: TextStyle(fontSize: 12, color: muted),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(20, 0, 20, 80),
                          itemCount: rows.length,
                          itemBuilder: (context, index) {
                            final note = rows[index];
                            final heading =
                                index == 0 ||
                                rows[index - 1].isPinned != note.isPinned;
                            final menuKey =
                                GlobalKey<PopupMenuButtonState<String>>();

                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (heading)
                                  Padding(
                                    padding: const EdgeInsets.only(
                                      top: 15,
                                      bottom: 4,
                                    ),
                                    child: Text(
                                      note.isPinned ? 'PINNED' : 'NOTES',
                                      style: TextStyle(
                                        fontSize: 9,
                                        letterSpacing: 1.3,
                                        color: muted,
                                      ),
                                    ),
                                  ),
                                InkWell(
                                  onTap: () => _editNote(note),
                                  onLongPress: () =>
                                      menuKey.currentState?.showButtonMenu(),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 15,
                                    ),
                                    decoration: BoxDecoration(
                                      border: Border(
                                        bottom: BorderSide(color: line),
                                      ),
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                note.title,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  fontSize: 14,
                                                  fontWeight: FontWeight.w600,
                                                  letterSpacing: -.15,
                                                  color: ink,
                                                ),
                                              ),
                                            ),
                                            SizedBox(
                                              width: 28,
                                              height: 24,
                                              child: PopupMenuButton<String>(
                                                key: menuKey,
                                                tooltip: 'Note actions',
                                                padding: EdgeInsets.zero,
                                                color: surface,
                                                elevation: 6,
                                                shape: RoundedRectangleBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(16),
                                                  side: BorderSide(
                                                    color: dark
                                                        ? const Color(
                                                            0xFF2E384D,
                                                          )
                                                        : const Color(
                                                            0xFFE5EAF2,
                                                          ),
                                                  ),
                                                ),
                                                icon: OpaqueIcon(
                                                  'more',
                                                  size: 17,
                                                  color: muted,
                                                ),
                                                onSelected: (action) {
                                                  if (action == 'pin')
                                                    _togglePin(note);
                                                  if (action == 'edit')
                                                    _editNote(note);
                                                  if (action == 'delete')
                                                    _deleteNote(note);
                                                },
                                                itemBuilder: (_) => [
                                                  PopupMenuItem<String>(
                                                    value: 'pin',
                                                    height: 40,
                                                    child: Row(
                                                      children: [
                                                        Icon(
                                                          note.isPinned
                                                              ? Icons
                                                                    .push_pin_outlined
                                                              : Icons.push_pin,
                                                          size: 15,
                                                          color: blue,
                                                        ),
                                                        const SizedBox(
                                                          width: 10,
                                                        ),
                                                        Text(
                                                          note.isPinned
                                                              ? 'Unpin note'
                                                              : 'Pin note',
                                                          style: TextStyle(
                                                            fontSize: 13,
                                                            color: ink,
                                                            fontWeight:
                                                                FontWeight.w500,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                  PopupMenuItem<String>(
                                                    value: 'edit',
                                                    height: 40,
                                                    child: Row(
                                                      children: [
                                                        Icon(
                                                          Icons.edit_outlined,
                                                          size: 15,
                                                          color: muted,
                                                        ),
                                                        const SizedBox(
                                                          width: 10,
                                                        ),
                                                        Text(
                                                          'Edit note',
                                                          style: TextStyle(
                                                            fontSize: 13,
                                                            color: ink,
                                                            fontWeight:
                                                                FontWeight.w500,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                  const PopupMenuDivider(
                                                    height: 1,
                                                  ),
                                                  const PopupMenuItem<String>(
                                                    value: 'delete',
                                                    height: 40,
                                                    child: Row(
                                                      children: [
                                                        Icon(
                                                          Icons.delete_outline,
                                                          size: 15,
                                                          color: Color(
                                                            0xFFE53935,
                                                          ),
                                                        ),
                                                        SizedBox(width: 10),
                                                        Text(
                                                          'Delete note',
                                                          style: TextStyle(
                                                            fontSize: 13,
                                                            color: Color(
                                                              0xFFE53935,
                                                            ),
                                                            fontWeight:
                                                                FontWeight.w500,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 5),
                                        Text(
                                          _extractPlainText(
                                            note.content,
                                          ).trim(),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 12,
                                            height: 1.7,
                                            color: muted,
                                          ),
                                        ),
                                        const SizedBox(height: 10),
                                        Row(
                                          children: [
                                            if (note.category != null) ...[
                                              Builder(
                                                builder: (context) {
                                                  final catColor = _getCategoryColor(
                                                    note.category,
                                                    defaultColor: blue,
                                                  );
                                                  return Container(
                                                    padding:
                                                        const EdgeInsets.symmetric(
                                                          horizontal: 7,
                                                          vertical: 2,
                                                        ),
                                                    decoration: BoxDecoration(
                                                      color: dark
                                                          ? catColor.withOpacity(0.18)
                                                          : catColor.withOpacity(0.12),
                                                      borderRadius:
                                                          BorderRadius.circular(5),
                                                    ),
                                                    child: Text(
                                                      note.category!,
                                                      style: TextStyle(
                                                        fontSize: 10,
                                                        fontWeight: FontWeight.w500,
                                                        color: catColor,
                                                      ),
                                                    ),
                                                  );
                                                },
                                              ),
                                              const SizedBox(width: 7),
                                            ],
                                            Text(
                                              _formatDate(note.updatedAt),
                                              style: TextStyle(
                                                fontSize: 10,
                                                color: muted,
                                              ),
                                            ),
                                            if (note.isPinned) ...[
                                              const SizedBox(width: 7),
                                              Icon(
                                                Icons.push_pin_outlined,
                                                size: 11,
                                                color: muted,
                                              ),
                                            ],
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }

  Widget _buildAppBarAction({
    required IconData icon,
    required VoidCallback onPressed,
    required bool isDark,
    required Color color,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withOpacity(0.05)
            : Colors.black.withOpacity(0.03),
        borderRadius: BorderRadius.circular(12),
      ),
      child: IconButton(
        icon: Icon(icon, color: color, size: 22),
        onPressed: onPressed,
      ),
    );
  }

  Widget _buildCategoryFilter(
    bool isDark,
    Color subtitleColor,
    Color accentColor,
  ) {
    return Container(
      height: 45,
      margin: const EdgeInsets.only(bottom: 10),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: _categories.length + 1,
        itemBuilder: (context, index) {
          final isAllSelected = index == 0 && _selectedCategory == null;
          final String? categoryName = index == 0
              ? null
              : _categories[index - 1].name;
          final isSelected = _selectedCategory == categoryName;

          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(categoryName ?? 'All'),
              selected: isSelected || isAllSelected,
              onSelected: (_) {
                setState(() => _selectedCategory = categoryName);
                _loadNotes();
              },
              backgroundColor: isDark ? const Color(0xFF1C1C1E) : Colors.white,
              selectedColor: accentColor.withOpacity(0.2),
              labelStyle: TextStyle(
                color: (isSelected || isAllSelected)
                    ? accentColor
                    : subtitleColor,
                fontWeight: (isSelected || isAllSelected)
                    ? FontWeight.bold
                    : FontWeight.w500,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(
                  color: (isSelected || isAllSelected)
                      ? accentColor.withOpacity(0.5)
                      : (isDark
                            ? Colors.white10
                            : Colors.black.withOpacity(0.05)),
                ),
              ),
              elevation: 0,
            ),
          );
        },
      ),
    );
  }

  Widget _buildEmptyState(bool isDark, Color subtitleColor) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            _isSearching ? Icons.search_off_rounded : Icons.note_add_rounded,
            size: 80,
            color: subtitleColor.withOpacity(0.2),
          ),
          const SizedBox(height: 16),
          Text(
            _isSearching ? "No matching notes" : "No notes yet",
            style: TextStyle(
              color: subtitleColor,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNoteCard(Note note, bool isDarkTheme, double screenWidth) {
    final textColor = isDarkTheme ? Colors.white : const Color(0xFF1D1D1F);
    final subtitleColor = isDarkTheme
        ? const Color(0xFF8E8E93)
        : const Color(0xFF6E6E73);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      decoration: BoxDecoration(
        color: isDarkTheme ? const Color(0xFF1C1C1E) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: note.isPinned
              ? (isDarkTheme
                    ? Colors.greenAccent.withOpacity(0.3)
                    : Colors.green.withOpacity(0.3))
              : (isDarkTheme
                    ? Colors.white.withOpacity(0.05)
                    : Colors.black.withOpacity(0.03)),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDarkTheme ? 0.4 : 0.05),
            blurRadius: 15,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => _editNote(note),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (note.isPinned)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: Icon(
                            Icons.push_pin_rounded,
                            color: Colors.greenAccent,
                            size: 16,
                          ),
                        ),
                      Expanded(
                        child: Text(
                          note.title,
                          style: TextStyle(
                            color: textColor,
                            fontWeight: FontWeight.w700,
                            fontSize: 18,
                            letterSpacing: -0.2,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      IconButton(
                        icon: Icon(
                          Icons.more_horiz_rounded,
                          color: subtitleColor.withOpacity(0.5),
                        ),
                        onPressed: () =>
                            _showNoteOptions(context, note, isDarkTheme),
                        constraints: const BoxConstraints(),
                        padding: EdgeInsets.zero,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _extractPlainText(note.content),
                    style: TextStyle(
                      fontSize: 15,
                      color: subtitleColor.withOpacity(0.7),
                      height: 1.5,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      if (note.category != null)
                        Builder(
                          builder: (context) {
                            final catColor = _getCategoryColor(
                              note.category,
                              defaultColor: Colors.blue,
                            );
                            return Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: catColor.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                note.category!,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: catColor,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            );
                          },
                        ),
                      const Spacer(),
                      Text(
                        _formatDate(note.updatedAt),
                        style: TextStyle(
                          fontSize: 11,
                          color: subtitleColor.withOpacity(0.4),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showNoteOptions(BuildContext context, Note note, bool isDark) {
    final c = NotesColors(context);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) => NotesSheet(
        title: 'Note actions',
        description: note.title,
        child: Column(
          children: [
            for (final item in [
              (
                Icons.push_pin_outlined,
                note.isPinned ? 'Unpin' : 'Pin note',
                'pin',
              ),
              (Icons.edit_outlined, 'Edit', 'edit'),
              (Icons.delete_outline, 'Delete', 'delete'),
            ])
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  item.$1,
                  size: 19,
                  color: item.$3 == 'delete' ? const Color(0xFFBF6974) : c.blue,
                ),
                title: Text(item.$2, style: c.text(12)),
                onTap: () {
                  Navigator.pop(sheetContext);
                  if (item.$3 == 'pin') _togglePin(note);
                  if (item.$3 == 'edit') _editNote(note);
                  if (item.$3 == 'delete') _deleteNote(note);
                },
              ),
          ],
        ),
      ),
    );
  }

  Future<bool> _showPasswordSheet(NotesPasswordAction action) async {
    final dark = context.read<UserSettingsProvider>().isDarkMode;
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: dark ? const Color(0xFF19202A) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(23)),
      ),
      builder: (_) => NotesPasswordSheet(action: action, isDark: dark),
    );
    if (mounted && result == true) await _updatePasswordStatus();
    return result ?? false;
  }

  Future<void> _showPasswordSettings() async {
    final dark = context.read<UserSettingsProvider>().isDarkMode;
    final ink = dark ? const Color(0xFFE0E6EF) : const Color(0xFF202127);
    final muted = dark ? const Color(0xFF9CA8BB) : const Color(0xFF8B929F);
    final soft = dark ? const Color(0xFF283241) : const Color(0xFFF3F4F7);
    final line = dark ? const Color(0xFF303947) : const Color(0xFFEDEDF1);
    final blue = dark ? const Color(0xFF8AAFE4) : const Color(0xFF507FC3);
    final choice = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: dark ? const Color(0xFF19202A) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(23)),
      ),
      builder: (sheetContext) {
        Widget action(String value, String label, IconData icon) => InkWell(
          onTap: () => Navigator.pop(sheetContext, value),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 15),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: line)),
            ),
            child: Row(
              children: [
                Icon(icon, size: 18, color: muted),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(fontSize: 12, color: ink),
                  ),
                ),
                Icon(Icons.chevron_right, size: 18, color: muted),
              ],
            ),
          ),
        );
        return SafeArea(
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
                      color: line,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: soft,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(Icons.lock_outline, size: 21, color: blue),
                    ),
                    const Spacer(),
                    IconButton(
                      tooltip: 'Close protection settings',
                      onPressed: () => Navigator.pop(sheetContext),
                      icon: Icon(Icons.close, color: muted, size: 20),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  'Notes protection',
                  style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -.4,
                    color: ink,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Choose who can open your notes.',
                  style: TextStyle(fontSize: 12, color: muted),
                ),
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  decoration: BoxDecoration(
                    border: Border(top: BorderSide(color: line)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Password protection',
                          style: TextStyle(fontSize: 12, color: ink),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: soft,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          _isPasswordEnabled ? 'On' : 'Off',
                          style: TextStyle(fontSize: 10, color: blue),
                        ),
                      ),
                    ],
                  ),
                ),
                if (_isPasswordEnabled) ...[
                  action('change', 'Change password', Icons.key_outlined),
                  action(
                    'disable',
                    'Turn off protection',
                    Icons.lock_open_outlined,
                  ),
                  action('lock', 'Lock notes', Icons.lock_outline),
                ] else
                  action('setup', 'Enable protection', Icons.lock_outline),
              ],
            ),
          ),
        );
      },
    );
    if (!mounted || choice == null) return;
    if (choice == 'lock') {
      setState(() => _isUnlocked = false);
      return;
    }
    final mode = choice == 'setup'
        ? NotesPasswordAction.setup
        : choice == 'change'
        ? NotesPasswordAction.change
        : NotesPasswordAction.disable;
    await _showPasswordSheet(mode);
  }

  Widget _buildLockedNotes(bool dark) {
    final muted = dark ? const Color(0xFF9CA8BB) : const Color(0xFF8B929F);
    final ink = dark ? const Color(0xFFE0E6EF) : const Color(0xFF202127);
    final soft = dark ? const Color(0xFF283241) : const Color(0xFFF3F4F7);
    final blue = dark ? const Color(0xFF8AAFE4) : const Color(0xFF507FC3);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: soft,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Icon(Icons.lock_outline, size: 24, color: blue),
            ),
            const SizedBox(height: 19),
            Text(
              'Your notes, kept private',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w500,
                letterSpacing: -.3,
                color: ink,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Enter your password to open Notes.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, height: 1.8, color: muted),
            ),
            const SizedBox(height: 22),
            TextButton(
              style: TextButton.styleFrom(
                backgroundColor: soft,
                foregroundColor: blue,
                padding: const EdgeInsets.symmetric(
                  horizontal: 26,
                  vertical: 10,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: () => _checkPasswordProtection(requestUnlock: true),
              child: const Text('Unlock notes', style: TextStyle(fontSize: 12)),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);
    if (difference.inDays == 0)
      return 'Today ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
    if (difference.inDays == 1) return 'Yesterday';
    if (difference.inDays < 7) return '${difference.inDays} days ago';
    return '${date.day}/${date.month}/${date.year}';
  }
}
