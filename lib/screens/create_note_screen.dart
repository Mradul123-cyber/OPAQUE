import '../widgets/notes_design.dart';
import '../widgets/opaque_navigation.dart';
import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import '../services/database_service.dart';
import '../services/user_settings_provider.dart';
import '../models/note_model.dart';
import 'flowchart_editor_screen.dart';

class CreateNoteScreen extends StatefulWidget {
  final Note? note;

  const CreateNoteScreen({super.key, this.note});

  @override
  State<CreateNoteScreen> createState() => _CreateNoteScreenState();
}

class _CreateNoteScreenState extends State<CreateNoteScreen>
    with TickerProviderStateMixin {
  final TextEditingController _titleController = TextEditingController();
  late quill.QuillController _quillController;
  final FocusNode _titleFocusNode = FocusNode();
  final FocusNode _editorFocusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();

  List<NoteCategory> _categories = [];
  String? _selectedCategory;
  bool _isLoading = false;
  bool _hasChanges = false;
  StreamSubscription? _contentSubscription;
  bool _showSaveIndicator = false;
  late AnimationController _saveAnimationController;
  String? _flowchartJson; // Store flowchart data

  // Category icon mapping
  static const Map<String, IconData> _categoryIcons = {
    'Personal': Icons.person_rounded,
    'Work': Icons.work_rounded,
    'Ideas': Icons.lightbulb_rounded,
    'Todo': Icons.checklist_rounded,
    'Important': Icons.priority_high_rounded,
    'Study': Icons.school_rounded,
  };

  IconData _getCategoryIcon(String categoryName) {
    return _categoryIcons[categoryName] ?? Icons.folder_rounded;
  }

  Color _getCategoryColor(String categoryName) {
    // Find the category in the list to get its color
    final category = _categories.firstWhere(
      (cat) => cat.name == categoryName,
      orElse: () => NoteCategory(
        name: categoryName,
        colorCode: '#2196F3',
        createdAt: DateTime.now(),
      ),
    );

    if (category.colorCode != null) {
      try {
        return Color(int.parse(category.colorCode!.replaceFirst('#', '0xFF')));
      } catch (_) {
        return Colors.blue;
      }
    }
    return Colors.blue;
  }

  @override
  void initState() {
    super.initState();
    _loadCategories();
    _initializeEditor();
    _contentSubscription = _quillController.document.changes.listen((_) {
      if (mounted) _onContentChanged();
    });

    // Initialize save animation
    _saveAnimationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    // Listen to changes
    _titleController.addListener(_onContentChanged);
  }

  void _initializeEditor() {
    if (widget.note != null) {
      _titleController.text = widget.note!.title;
      _selectedCategory = widget.note!.category;
      _flowchartJson = widget.note!.flowchartJson;

      try {
        final doc = quill.Document.fromJson(jsonDecode(widget.note!.content));
        _quillController = quill.QuillController(
          document: doc,
          selection: const TextSelection.collapsed(offset: 0),
        );
      } catch (_) {
        _quillController = quill.QuillController.basic();
        if (widget.note!.content.isNotEmpty) {
          _quillController.document.insert(0, widget.note!.content);
        }
      }
    } else {
      _quillController = quill.QuillController.basic();
    }
  }

  void _onContentChanged() {
    setState(() {
      _hasChanges = true;
    });
  }

  int _getWordCount() {
    final text = _quillController.document.toPlainText().trim();
    if (text.isEmpty) return 0;
    return text.split(RegExp(r'\s+')).length;
  }

  int _getCharCount() {
    final text = _quillController.document.toPlainText();
    // Quill's final newline is a document terminator, not user content.
    return (text.endsWith('\n') ? text.substring(0, text.length - 1) : text)
        .characters
        .length;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _contentSubscription?.cancel();
    _quillController.dispose();
    _titleFocusNode.dispose();
    _editorFocusNode.dispose();
    _scrollController.dispose();
    _saveAnimationController.dispose();
    super.dispose();
  }

  Future<void> _loadCategories() async {
    try {
      final categories = await DatabaseService.instance.getAllCategories();
      if (mounted) {
        setState(() => _categories = categories);
      }
    } catch (e) {
      debugPrint('[CreateNoteScreen] Error loading categories: $e');
    }
  }

  Future<void> _saveNote({bool showSnackbar = true}) async {
    if (_isLoading) return;
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      await showNotesConfirmation(
        context,
        title: 'Add a title',
        body: 'Give this note a title before saving.',
        confirm: 'Continue editing',
      );
      return;
    }

    final contentJson = jsonEncode(
      _quillController.document.toDelta().toJson(),
    );
    final plainText = _quillController.document.toPlainText().trim();
    if (plainText.isEmpty) {
      await showNotesConfirmation(
        context,
        title: 'Add some content',
        body: 'Write something in your note before saving.',
        confirm: 'Continue editing',
      );
      return;
    }

    setState(() => _isLoading = true);
    _saveAnimationController.forward();

    try {
      final now = DateTime.now();
      if (widget.note != null) {
        final updatedNote = Note(
          id: widget.note!.id,
          createdAt: widget.note!.createdAt,
          isPinned: widget.note!.isPinned,
          isLocked: widget.note!.isLocked,
          title: title,
          content: contentJson,
          category: _selectedCategory,
          flowchartJson: _flowchartJson,
          updatedAt: now,
        );
        await DatabaseService.instance.updateNote(updatedNote);
      } else {
        final newNote = Note(
          title: title,
          content: contentJson,
          category: _selectedCategory,
          flowchartJson: _flowchartJson,
          createdAt: now,
          updatedAt: now,
        );
        await DatabaseService.instance.createNote(newNote);
      }

      if (!mounted) return;
      setState(() {
        _hasChanges = false;
        _showSaveIndicator = true;
      });

      // Show save indicator briefly
      await Future.delayed(const Duration(milliseconds: 500));

      if (mounted && showSnackbar) {
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        final retry = await showNotesConfirmation(
          context,
          title: 'Couldn’t save your note',
          body: 'Your changes are still here. Try saving again.',
          confirm: 'Try again',
        );
        if (mounted && retry) await _saveNote(showSnackbar: showSnackbar);
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
        _saveAnimationController.reverse();
      }
    }
  }

  Future<void> _pickCategory() async {
    final c = NotesColors(context);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => NotesSheet(
        title: 'Category',
        description: 'Keep related notes together.',
        child: Column(
          children: [
            for (final name in <String?>[
              null,
              ..._categories.map((cat) => cat.name),
            ])
              Semantics(
                selected: _selectedCategory == name,
                button: true,
                child: InkWell(
                  onTap: () {
                    setState(() {
                      _selectedCategory = name;
                      _hasChanges = true;
                    });
                    Navigator.pop(sheetContext);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      border: Border(bottom: BorderSide(color: c.line)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 9,
                          height: 9,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: name == null
                                ? c.muted
                                : _getCategoryColor(name),
                          ),
                        ),
                        const SizedBox(width: 11),
                        Expanded(
                          child: Text(name ?? 'No category', style: c.text(12)),
                        ),
                        Icon(
                          _selectedCategory == name
                              ? Icons.radio_button_checked
                              : Icons.radio_button_off,
                          size: 17,
                          color: _selectedCategory == name ? c.blue : c.muted,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            TextButton.icon(
              onPressed: () {
                Navigator.pop(sheetContext);
                _showAddCategory();
              },
              icon: const Icon(Icons.add, size: 17),
              label: const Text('Add category'),
              style: TextButton.styleFrom(
                foregroundColor: c.blue,
                textStyle: const TextStyle(fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showAddCategory() async {
    final category = await showNotesCategoryCreation(context);
    if (!mounted || category == null) return;
    await _loadCategories();
    if (mounted)
      setState(() {
        _selectedCategory = category.name;
        _hasChanges = true;
      });
  }

  Future<void> _removeFlowchart() async {
    final remove = await showNotesConfirmation(
      context,
      title: 'Remove flowchart?',
      body:
          'Remove the attached flowchart from this note? The note’s text will stay.',
      confirm: 'Remove',
      danger: true,
      icon: Icons.account_tree_outlined,
    );
    if (mounted && remove)
      setState(() {
        _flowchartJson = null;
        _hasChanges = true;
      });
  }

  @override
  Widget build(BuildContext context) {
    final userSettings = Provider.of<UserSettingsProvider>(context);
    final isDark = userSettings.isDarkMode;
    final surface = isDark ? const Color(0xFF19202A) : Colors.white;
    final ink = isDark ? const Color(0xFFE0E6EF) : const Color(0xFF202127);
    final muted = isDark ? const Color(0xFF9CA8BB) : const Color(0xFF8B929F);
    final soft = isDark ? const Color(0xFF283241) : const Color(0xFFF3F4F7);
    final line = isDark ? const Color(0xFF303947) : const Color(0xFFEDEDF1);
    final blue = isDark ? const Color(0xFF8AAFE4) : const Color(0xFF507FC3);

    return PopScope(
      canPop: !_hasChanges,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        if (_hasChanges && context.mounted) {
          final shouldPop = await showNotesConfirmation(
            context,
            title: 'Discard changes?',
            body:
                'Your latest changes haven’t been saved. Leave this note without saving them?',
            confirm: 'Discard',
            danger: true,
          );
          if (shouldPop && context.mounted) {
            setState(() => _hasChanges = false);
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) Navigator.of(context).pop();
            });
          }
        }
      },
      child: Scaffold(
        backgroundColor: surface,
        appBar: AppBar(
          backgroundColor: surface,
          foregroundColor: ink,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
          leading: IconButton(
            tooltip: 'Back to notes',
            icon: OpaqueIcon('back', color: muted, size: 20),
            onPressed: () => Navigator.maybePop(context),
          ),
          title: Text(
            widget.note == null ? 'New note' : 'Edit note',
            style: TextStyle(fontSize: 12, color: muted),
          ),
          centerTitle: true,
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(1),
            child: Divider(height: 1, color: line),
          ),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: TextButton(
                style: TextButton.styleFrom(
                  backgroundColor: soft,
                  foregroundColor: blue,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: _isLoading ? null : _saveNote,
                child: Text(
                  _isLoading ? 'Saving…' : 'Save',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ),
          ],
        ),
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 18, 22, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: _titleController,
                      focusNode: _titleFocusNode,
                      cursorColor: muted,
                      maxLines: 2,
                      style: TextStyle(
                        fontSize: 23,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -.6,
                        color: ink,
                      ),
                      decoration: InputDecoration(
                        hintText: 'Title',
                        hintStyle: TextStyle(color: muted),
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 10,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        TextButton(
                          style: TextButton.styleFrom(
                            backgroundColor: _selectedCategory != null
                                ? _getCategoryColor(_selectedCategory!).withOpacity(isDark ? 0.18 : 0.12)
                                : soft,
                            foregroundColor: _selectedCategory != null
                                ? _getCategoryColor(_selectedCategory!)
                                : blue,
                            minimumSize: const Size(0, 28),
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(6),
                            ),
                          ),
                          onPressed: _pickCategory,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (_selectedCategory != null) ...[
                                Container(
                                  width: 7,
                                  height: 7,
                                  margin: const EdgeInsets.only(right: 6),
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: _getCategoryColor(_selectedCategory!),
                                  ),
                                ),
                              ],
                              Text(
                                _selectedCategory ?? 'No category',
                                style: const TextStyle(fontSize: 11),
                              ),
                              const SizedBox(width: 6),
                              const Icon(Icons.keyboard_arrow_down, size: 13),
                            ],
                          ),
                        ),
                        Text(
                          widget.note == null
                              ? 'New thought'
                              : 'Edited ${_formatTime(widget.note!.updatedAt)}',
                          style: TextStyle(fontSize: 10, color: muted),
                        ),
                      ],
                    ),
                    if (_flowchartJson != null)
                      Row(
                        children: [
                          Expanded(
                            child: TextButton.icon(
                              onPressed: _openFlowchartEditor,
                              icon: Icon(
                                Icons.account_tree_outlined,
                                size: 16,
                                color: blue,
                              ),
                              label: Text(
                                'Flowchart',
                                style: TextStyle(fontSize: 12, color: blue),
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Remove flowchart',
                            icon: Icon(Icons.close, size: 18, color: muted),
                            onPressed: _removeFlowchart,
                          ),
                        ],
                      ),
                  ],
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(22, 16, 22, 12),
                  child: quill.QuillEditor.basic(
                    controller: _quillController,
                    focusNode: _editorFocusNode,
                    scrollController: _scrollController,
                    config: quill.QuillEditorConfig(
                      scrollable: true,
                      autoFocus: false,
                      expands: true,
                      padding: EdgeInsets.zero,
                      placeholder: 'Start writing…',
                      showCursor: true,
                      enableInteractiveSelection: true,
                      enableSelectionToolbar: true,
                      customStyles: quill.DefaultStyles(
                        paragraph: quill.DefaultTextBlockStyle(
                          TextStyle(color: ink, fontSize: 14, height: 1.9),
                          quill.HorizontalSpacing.zero,
                          quill.VerticalSpacing.zero,
                          quill.VerticalSpacing.zero,
                          null,
                        ),
                        placeHolder: quill.DefaultTextBlockStyle(
                          TextStyle(color: muted, fontSize: 14, height: 1.9),
                          quill.HorizontalSpacing.zero,
                          quill.VerticalSpacing.zero,
                          quill.VerticalSpacing.zero,
                          null,
                        ),
                        lists: quill.DefaultListBlockStyle(
                          TextStyle(color: ink, fontSize: 14, height: 1.9),
                          quill.HorizontalSpacing.zero,
                          quill.VerticalSpacing.zero,
                          quill.VerticalSpacing.zero,
                          null,
                          null,
                        ),
                        code: quill.DefaultTextBlockStyle(
                          TextStyle(
                            color: ink,
                            fontSize: 14,
                            height: 1.9,
                            fontFamily: 'monospace',
                          ),
                          quill.HorizontalSpacing.zero,
                          quill.VerticalSpacing.zero,
                          quill.VerticalSpacing.zero,
                          null,
                        ),
                        color: ink,
                      ),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 4, 22, 9),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '${_getWordCount()} words · ${_getCharCount()} characters',
                    style: TextStyle(fontSize: 10, color: muted),
                  ),
                ),
              ),
              Container(
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: line)),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    for (final item in [
                      (Icons.format_bold, 'Bold', quill.Attribute.bold),
                      (Icons.format_italic, 'Italic', quill.Attribute.italic),
                      (
                        Icons.format_underlined,
                        'Underline',
                        quill.Attribute.underline,
                      ),
                      (Icons.format_list_bulleted, 'List', quill.Attribute.ul),
                      (Icons.checklist, 'Tasks', quill.Attribute.checked),
                    ])
                      IconButton(
                        tooltip: item.$2,
                        visualDensity: VisualDensity.compact,
                        icon: Icon(
                          item.$1,
                          size: 19,
                          color:
                              _quillController
                                      .getSelectionStyle()
                                      .attributes[item.$3.key]
                                      ?.value ==
                                  item.$3.value
                              ? blue
                              : muted,
                        ),
                        onPressed: () => _toggleFormat(item.$3),
                      ),
                    IconButton(
                      tooltip: 'Flowchart',
                      visualDensity: VisualDensity.compact,
                      icon: Icon(
                        Icons.account_tree_outlined,
                        size: 19,
                        color: muted,
                      ),
                      onPressed: _openFlowchartEditor,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatItem(
    IconData icon,
    String label,
    String value,
    bool isDark,
  ) {
    return Column(
      children: [
        Icon(icon, size: 20, color: isDark ? Colors.cyanAccent : Colors.blue),
        const SizedBox(height: 6),
        Text(
          value,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: isDark ? Colors.white : Colors.black,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: isDark ? Colors.grey.shade500 : Colors.grey.shade600,
          ),
        ),
      ],
    );
  }

  String _formatTime(DateTime dateTime) {
    final now = DateTime.now();
    final diff = now.difference(dateTime);

    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${dateTime.day}/${dateTime.month}';
  }

  bool _isFormatActive(quill.Attribute attribute) {
    try {
      final style = _quillController.getSelectionStyle();
      return style.attributes.containsKey(attribute.key);
    } catch (e) {
      return false;
    }
  }

  void _toggleFormat(quill.Attribute attribute) {
    final isCurrentlyActive = _isFormatActive(attribute);

    if (isCurrentlyActive) {
      // Remove the format by applying the attribute with null value
      _quillController.formatSelection(quill.Attribute.clone(attribute, null));
    } else {
      // Apply the format
      _quillController.formatSelection(attribute);
    }

    setState(() {}); // Refresh to show updated state
  }

  Future<void> _openFlowchartEditor() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) =>
            FlowchartEditorScreen(initialFlowchartJson: _flowchartJson),
      ),
    );

    if (mounted && result != null && result is String) {
      setState(() {
        _flowchartJson = result;
        _hasChanges = true;
      });
    }
  }

  Widget _modernFormatButton(
    IconData icon,
    String label,
    bool isDark,
    VoidCallback onTap, {
    quill.Attribute? attribute,
  }) {
    final isActive = attribute != null && _isFormatActive(attribute);

    return InkWell(
      onTap: () {
        onTap();
        setState(() {}); // Refresh to show active state
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: isActive
                ? (isDark
                      ? [
                          Colors.cyanAccent.withOpacity(0.3),
                          Colors.blue.withOpacity(0.2),
                        ]
                      : [
                          Colors.blue.withOpacity(0.2),
                          Colors.lightBlue.withOpacity(0.1),
                        ])
                : (isDark
                      ? [
                          Colors.white.withOpacity(0.1),
                          Colors.white.withOpacity(0.05),
                        ]
                      : [Colors.grey.shade100, Colors.grey.shade50]),
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isActive
                ? (isDark ? Colors.cyanAccent : Colors.blue)
                : (isDark
                      ? Colors.white.withOpacity(0.1)
                      : Colors.grey.shade300),
            width: isActive ? 2 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 18,
              color: isActive
                  ? (isDark ? Colors.cyanAccent : Colors.blue)
                  : (isDark ? Colors.white : Colors.black87),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                color: isActive
                    ? (isDark ? Colors.cyanAccent : Colors.blue)
                    : (isDark ? Colors.white : Colors.black87),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
