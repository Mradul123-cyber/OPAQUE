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

class _CreateNoteScreenState extends State<CreateNoteScreen> with TickerProviderStateMixin {
  final TextEditingController _titleController = TextEditingController();
  late quill.QuillController _quillController;
  final FocusNode _titleFocusNode = FocusNode();
  final FocusNode _editorFocusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();

  List<NoteCategory> _categories = [];
  String? _selectedCategory;
  bool _isLoading = false;
  bool _hasChanges = false;
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
    return _quillController.document.toPlainText().trim().length;
  }

  @override
  void dispose() {
    _titleController.dispose();
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
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(Icons.warning, color: Colors.white),
              SizedBox(width: 8),
              Text('Please enter a title'),
            ],
          ),
          backgroundColor: Colors.orange,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
      return;
    }

    final contentJson = jsonEncode(_quillController.document.toDelta().toJson());
    final plainText = _quillController.document.toPlainText().trim();
    if (plainText.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(Icons.warning, color: Colors.white),
              SizedBox(width: 8),
              Text('Please enter some content'),
            ],
          ),
          backgroundColor: Colors.orange,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
      return;
    }

    setState(() => _isLoading = true);
    _saveAnimationController.forward();

    try {
      final now = DateTime.now();
      if (widget.note != null) {
        final updatedNote = widget.note!.copyWith(
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.error, color: Colors.white),
                SizedBox(width: 8),
                Text('Failed to save note'),
              ],
            ),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
        _saveAnimationController.reverse();
      }
    }
  }

  void _pickCategory() {
    final userSettings = Provider.of<UserSettingsProvider>(context, listen: false);
    final isDark = userSettings.notesScreenStyle == 'dark';

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(24),
              topRight: Radius.circular(24),
            ),
          ),
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle bar
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: isDark ? Colors.grey.shade700 : Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // Title
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Row(
                  children: [
                    Text(
                      'Category',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                        color: isDark ? Colors.white : Colors.black,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Categories list
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    children: [
                      // No Category option
                      _buildModernCategoryTile(
                        icon: Icons.block_rounded,
                        label: 'No Category',
                        color: isDark ? Colors.grey.shade600 : Colors.grey.shade400,
                        isDark: isDark,
                        isSelected: _selectedCategory == null,
                        onTap: () {
                          setState(() => _selectedCategory = null);
                          Navigator.pop(context);
                        },
                      ),
                      const SizedBox(height: 8),

                      // Existing categories
                      ..._categories.map((cat) {
                        Color color = Colors.blue;
                        if (cat.colorCode != null) {
                          try {
                            color = Color(int.parse(cat.colorCode!.replaceFirst('#', '0xFF')));
                          } catch (_) {}
                        }
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: _buildModernCategoryTile(
                            icon: _getCategoryIcon(cat.name),
                            label: cat.name,
                            color: color,
                            isDark: isDark,
                            isSelected: _selectedCategory == cat.name,
                            onTap: () {
                              setState(() => _selectedCategory = cat.name);
                              Navigator.pop(context);
                            },
                          ),
                        );
                      }),

                      // Add new category
                      _buildModernCategoryTile(
                        icon: Icons.add_rounded,
                        label: 'Create New Category',
                        color: Colors.green,
                        isDark: isDark,
                        isSelected: false,
                        isSpecial: true,
                        onTap: () {
                          Navigator.pop(context);
                          _showAddCategory();
                        },
                      ),
                    ],
                  ),
                ),
              ),
              SizedBox(height: MediaQuery.of(context).padding.bottom + 16),
            ],
          ),
        );
      },
    );
  }

  Widget _buildModernCategoryTile({
    required IconData icon,
    required String label,
    required Color color,
    required bool isDark,
    required bool isSelected,
    required VoidCallback onTap,
    bool isSpecial = false,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        decoration: BoxDecoration(
          color: isSelected
              ? (isDark ? color.withOpacity(0.2) : color.withOpacity(0.1))
              : (isDark ? Colors.white.withOpacity(0.03) : Colors.grey.shade50),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected
                ? color
                : (isDark ? Colors.white.withOpacity(0.1) : Colors.grey.shade200),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: isSpecial
                    ? color.withOpacity(0.15)
                    : (isSelected ? color.withOpacity(0.2) : Colors.transparent),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                icon,
                color: color,
                size: 22,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
            ),
            if (isSelected)
              Icon(
                Icons.check_circle_rounded,
                color: color,
                size: 24,
              ),
          ],
        ),
      ),
    );
  }

  void _showAddCategory() {
    final userSettings = Provider.of<UserSettingsProvider>(context, listen: false);
    final isDark = userSettings.notesScreenStyle == 'dark';
    final customNameController = TextEditingController();
    String selectedColor = '#2196F3';

    final defaultCategories = [
      {'name': 'Personal', 'color': '#4CAF50', 'icon': Icons.person_rounded},
      {'name': 'Work', 'color': '#2196F3', 'icon': Icons.work_rounded},
      {'name': 'Ideas', 'color': '#FFC107', 'icon': Icons.lightbulb_rounded},
      {'name': 'Todo', 'color': '#FF5722', 'icon': Icons.checklist_rounded},
      {'name': 'Important', 'color': '#F44336', 'icon': Icons.priority_high_rounded},
      {'name': 'Study', 'color': '#9C27B0', 'icon': Icons.school_rounded},
    ];

    final colorOptions = [
      '#4CAF50', '#2196F3', '#FFC107', '#FF5722',
      '#F44336', '#9C27B0', '#E91E63', '#00BCD4',
    ];

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Dialog(
              backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Title
                      Text(
                        'Create Category',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: isDark ? Colors.white : Colors.black,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Choose from defaults or create your own',
                        style: TextStyle(
                          fontSize: 13,
                          color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Default Categories
                      Text(
                        'Quick Select',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.grey.shade300 : Colors.grey.shade700,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: defaultCategories.map((cat) {
                          final color = Color(int.parse(
                              (cat['color'] as String).replaceFirst('#', '0xFF')));
                          return InkWell(
                            onTap: () async {
                              try {
                                final exists = await DatabaseService.instance
                                    .getCategoryByName(cat['name'] as String);
                                if (exists == null) {
                                  await DatabaseService.instance.createCategory(
                                    NoteCategory(
                                      name: cat['name'] as String,
                                      colorCode: cat['color'] as String,
                                      createdAt: DateTime.now(),
                                    ),
                                  );
                                  await _loadCategories();
                                }
                                setState(() => _selectedCategory = cat['name'] as String);
                                if (context.mounted) Navigator.pop(context);
                              } catch (e) {
                                debugPrint('Error: $e');
                              }
                            },
                            borderRadius: BorderRadius.circular(10),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: color.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: color.withOpacity(0.3),
                                  width: 1,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    cat['icon'] as IconData,
                                    color: color,
                                    size: 16,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    cat['name'] as String,
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500,
                                      color: isDark ? Colors.white : Colors.black87,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }).toList(),
                      ),

                      const SizedBox(height: 24),
                      Divider(
                        color: isDark ? Colors.grey.shade800 : Colors.grey.shade200,
                      ),
                      const SizedBox(height: 24),

                      // Custom Category
                      Text(
                        'Create Custom',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.grey.shade300 : Colors.grey.shade700,
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Category name input
                      TextField(
                        controller: customNameController,
                        style: TextStyle(
                          color: isDark ? Colors.white : Colors.black,
                          fontSize: 15,
                        ),
                        decoration: InputDecoration(
                          hintText: 'Enter category name',
                          hintStyle: TextStyle(
                            color: isDark ? Colors.grey.shade600 : Colors.grey.shade400,
                          ),
                          filled: true,
                          fillColor: isDark
                              ? Colors.white.withOpacity(0.05)
                              : Colors.grey.shade100,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 14,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Color picker
                      Text(
                        'Choose Color',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: colorOptions.map((colorHex) {
                          final color = Color(int.parse(colorHex.replaceFirst('#', '0xFF')));
                          final isSelected = selectedColor == colorHex;
                          return InkWell(
                            onTap: () {
                              setDialogState(() {
                                selectedColor = colorHex;
                              });
                            },
                            borderRadius: BorderRadius.circular(8),
                            child: Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: color,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: isSelected
                                      ? (isDark ? Colors.white : Colors.black)
                                      : Colors.transparent,
                                  width: 2.5,
                                ),
                              ),
                              child: isSelected
                                  ? const Icon(
                                      Icons.check,
                                      color: Colors.white,
                                      size: 20,
                                    )
                                  : null,
                            ),
                          );
                        }).toList(),
                      ),

                      const SizedBox(height: 24),

                      // Action buttons
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () {
                              Navigator.pop(context);
                            },
                            child: Text(
                              'Cancel',
                              style: TextStyle(
                                color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton(
                            onPressed: () async {
                              final name = customNameController.text.trim();
                              if (name.isEmpty) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Please enter a category name'),
                                  ),
                                );
                                return;
                              }

                              try {
                                final exists = await DatabaseService.instance
                                    .getCategoryByName(name);
                                if (exists == null) {
                                  await DatabaseService.instance.createCategory(
                                    NoteCategory(
                                      name: name,
                                      colorCode: selectedColor,
                                      createdAt: DateTime.now(),
                                    ),
                                  );
                                  await _loadCategories();
                                }
                                setState(() => _selectedCategory = name);
                                if (context.mounted) Navigator.pop(context);
                              } catch (e) {
                                debugPrint('Error: $e');
                              }
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Color(int.parse(
                                  selectedColor.replaceFirst('#', '0xFF'))),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 24,
                                vertical: 12,
                              ),
                            ),
                            child: const Text(
                              'Create',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final userSettings = Provider.of<UserSettingsProvider>(context);
    final isDark = userSettings.notesScreenStyle == 'dark';
    final screenHeight = MediaQuery.of(context).size.height;

    return PopScope(
      canPop: !_hasChanges,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        if (_hasChanges && context.mounted) {
          final shouldPop = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 28),
                  const SizedBox(width: 12),
                  Flexible(
                    child: Text(
                      'Unsaved Changes',
                      style: TextStyle(
                        color: isDark ? Colors.white : Colors.black,
                        fontSize: 18,
                      ),
                    ),
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: Text(
                  'You have unsaved changes. Do you want to discard them?',
                  style: TextStyle(color: isDark ? Colors.white70 : Colors.black87),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: Text('Cancel', style: TextStyle(color: Colors.grey.shade600)),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context, true),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.red,
                  ),
                  child: const Text('Discard'),
                ),
              ],
            ),
          );
          if ((shouldPop ?? false) && context.mounted) {
            Navigator.of(context).pop();
          }
        }
      },
      child: Scaffold(
        backgroundColor: isDark ? const Color(0xFF0a0e27) : const Color(0xFFF5F7FA),
        extendBodyBehindAppBar: true,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: Container(
            margin: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: isDark ? Colors.white.withOpacity(0.1) : Colors.white,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 10,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: IconButton(
              icon: Icon(
                Icons.arrow_back_rounded,
                color: isDark ? Colors.white : const Color(0xFF0a1128),
              ),
              onPressed: () => Navigator.pop(context),
            ),
          ),
          title: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: isDark ? Colors.white.withOpacity(0.1) : Colors.white.withOpacity(0.9),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: Text(
              widget.note != null ? 'Edit Note' : 'Create New Note',
              style: TextStyle(
                color: isDark ? Colors.white : const Color(0xFF0a1128),
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ),
          centerTitle: true,
          actions: [
            // Save indicator
            if (_showSaveIndicator)
              Container(
                margin: const EdgeInsets.only(right: 8),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check, color: Colors.green, size: 20),
              ),
            // Save button
            Container(
              margin: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: _isLoading
                      ? [Colors.grey, Colors.grey.shade700]
                      : [Colors.greenAccent, Colors.green],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.green.withOpacity(0.3),
                    blurRadius: 10,
                    spreadRadius: 1,
                  ),
                ],
              ),
              child: IconButton(
                icon: _isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : const Icon(Icons.check_rounded, color: Colors.white),
                onPressed: _isLoading ? null : _saveNote,
              ),
            ),
          ],
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 8),

                  // Title - Ultra Modern Minimalist Design
                  TextField(
                    controller: _titleController,
                    focusNode: _titleFocusNode,
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.w800,
                      color: isDark ? Colors.white : Colors.black,
                      letterSpacing: -0.5,
                      height: 1.2,
                    ),
                    maxLines: null,
                    decoration: InputDecoration(
                      hintText: 'Title',
                      hintStyle: TextStyle(
                        color: isDark ? Colors.grey.shade700 : Colors.grey.shade300,
                        fontWeight: FontWeight.w800,
                        fontSize: 32,
                        letterSpacing: -0.5,
                      ),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
                    ),
                  ),

                  const SizedBox(height: 12),

                  // Category Selection - Compact
                  InkWell(
                    onTap: _pickCategory,
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isDark
                              ? (_selectedCategory != null
                                  ? _getCategoryColor(_selectedCategory!).withOpacity(0.3)
                                  : Colors.grey.shade700)
                              : (_selectedCategory != null
                                  ? _getCategoryColor(_selectedCategory!).withOpacity(0.2)
                                  : Colors.grey.shade300),
                          width: 1.5,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: isDark
                                ? Colors.black.withOpacity(0.2)
                                : Colors.grey.withOpacity(0.1),
                            blurRadius: 8,
                            spreadRadius: 0,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          Icon(
                            _selectedCategory != null
                                ? _getCategoryIcon(_selectedCategory!)
                                : Icons.folder_outlined,
                            color: _selectedCategory != null
                                ? _getCategoryColor(_selectedCategory!)
                                : (isDark ? Colors.grey.shade500 : Colors.grey.shade600),
                            size: 20,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              _selectedCategory ?? 'Add category',
                              style: TextStyle(
                                fontSize: 15,
                                color: _selectedCategory != null
                                    ? (isDark ? Colors.white : Colors.black87)
                                    : (isDark ? Colors.grey.shade500 : Colors.grey.shade600),
                                fontWeight: _selectedCategory != null
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                              ),
                            ),
                          ),
                          Icon(
                            Icons.arrow_forward_ios_rounded,
                            color: isDark ? Colors.grey.shade600 : Colors.grey.shade400,
                            size: 16,
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Flowchart Indicator
                  if (_flowchartJson != null && _flowchartJson!.isNotEmpty)
                    InkWell(
                      onTap: _openFlowchartEditor,
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 16),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: isDark
                                ? [Colors.blue.withOpacity(0.2), Colors.blueAccent.withOpacity(0.1)]
                                : [Colors.blue.withOpacity(0.1), Colors.lightBlue.withOpacity(0.05)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isDark ? Colors.blueAccent.withOpacity(0.3) : Colors.blue.withOpacity(0.3),
                            width: 1.5,
                          ),
                        ),
                        child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: isDark ? Colors.blueAccent.withOpacity(0.2) : Colors.blue.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(
                              Icons.account_tree_rounded,
                              color: isDark ? Colors.blueAccent : Colors.blue,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Flowchart Attached',
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                    color: isDark ? Colors.white : Colors.black87,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Tap to view or edit',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: Icon(
                              Icons.edit_rounded,
                              color: isDark ? Colors.blueAccent : Colors.blue,
                              size: 20,
                            ),
                            onPressed: _openFlowchartEditor,
                          ),
                          IconButton(
                            icon: Icon(
                              Icons.delete_outline_rounded,
                              color: isDark ? Colors.redAccent : Colors.red,
                              size: 20,
                            ),
                            onPressed: () {
                              setState(() {
                                _flowchartJson = null;
                                _hasChanges = true;
                              });
                            },
                          ),
                        ],
                      ),
                    ),
                    ),

                  // Editor Card
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: isDark
                            ? [const Color(0xFF1a1f3a), const Color(0xFF2d3561)]
                            : [Colors.white, Colors.white],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: isDark
                              ? Colors.green.withOpacity(0.1)
                              : Colors.green.withOpacity(0.08),
                          blurRadius: 20,
                          spreadRadius: 2,
                          offset: const Offset(0, 5),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Toolbar
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: isDark
                                ? Colors.white.withOpacity(0.03)
                                : Colors.grey.shade50,
                            borderRadius: const BorderRadius.only(
                              topLeft: Radius.circular(20),
                              topRight: Radius.circular(20),
                            ),
                          ),
                          child: Column(
                            children: [
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      gradient: const LinearGradient(
                                        colors: [Colors.greenAccent, Colors.green],
                                      ),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: const Icon(
                                      Icons.edit_note_rounded,
                                      color: Colors.white,
                                      size: 20,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Text(
                                    'Content',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                      color: isDark ? Colors.greenAccent : Colors.green,
                                    ),
                                  ),
                                  const Spacer(),
                                  // Word count
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: isDark
                                          ? Colors.white.withOpacity(0.1)
                                          : Colors.grey.shade200,
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.text_fields,
                                          size: 14,
                                          color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                                        ),
                                        const SizedBox(width: 6),
                                        Text(
                                          '${_getWordCount()} words',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              // Format buttons
                              SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: Row(
                                  children: [
                                    _modernFormatButton(
                                      Icons.format_bold_rounded,
                                      'Bold',
                                      isDark,
                                      () => _toggleFormat(quill.Attribute.bold),
                                      attribute: quill.Attribute.bold,
                                    ),
                                    const SizedBox(width: 8),
                                    _modernFormatButton(
                                      Icons.format_italic_rounded,
                                      'Italic',
                                      isDark,
                                      () => _toggleFormat(quill.Attribute.italic),
                                      attribute: quill.Attribute.italic,
                                    ),
                                    const SizedBox(width: 8),
                                    _modernFormatButton(
                                      Icons.format_underline_rounded,
                                      'Underline',
                                      isDark,
                                      () => _toggleFormat(quill.Attribute.underline),
                                      attribute: quill.Attribute.underline,
                                    ),
                                    const SizedBox(width: 8),
                                    _modernFormatButton(
                                      Icons.format_list_bulleted_rounded,
                                      'List',
                                      isDark,
                                      () => _toggleFormat(quill.Attribute.ul),
                                      attribute: quill.Attribute.ul,
                                    ),
                                    const SizedBox(width: 8),
                                    _modernFormatButton(
                                      Icons.checklist_rounded,
                                      'Tasks',
                                      isDark,
                                      () => _toggleFormat(quill.Attribute.checked),
                                      attribute: quill.Attribute.checked,
                                    ),
                                    const SizedBox(width: 8),
                                    _modernFormatButton(
                                      Icons.account_tree_rounded,
                                      'Flowchart',
                                      isDark,
                                      _openFlowchartEditor,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),

                        // Editor
                        SizedBox(
                          height: screenHeight * 0.4,
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Theme(
                              data: ThemeData(
                                useMaterial3: true,
                                brightness: isDark ? Brightness.dark : Brightness.light,
                                colorScheme: ColorScheme(
                                  brightness: isDark ? Brightness.dark : Brightness.light,
                                  primary: Colors.green,
                                  onPrimary: Colors.white,
                                  secondary: Colors.green,
                                  onSecondary: Colors.white,
                                  error: Colors.red,
                                  onError: Colors.white,
                                  surface: isDark ? const Color(0xFF121212) : Colors.white,
                                  onSurface: isDark ? Colors.white : Colors.black,
                                ),
                                checkboxTheme: CheckboxThemeData(
                                  fillColor: WidgetStateProperty.resolveWith<Color>((Set<WidgetState> states) {
                                    if (states.contains(WidgetState.selected)) {
                                      return Colors.green;
                                    }
                                    return Colors.transparent;
                                  }),
                                  checkColor: WidgetStateProperty.all<Color>(Colors.white),
                                  side: WidgetStateBorderSide.resolveWith((states) {
                                    return BorderSide(
                                      color: isDark ? Colors.grey.shade600 : Colors.grey.shade400,
                                      width: 2,
                                    );
                                  }),
                                ),
                              ),
                              child: quill.QuillEditor.basic(
                                controller: _quillController,
                                focusNode: _editorFocusNode,
                                scrollController: _scrollController,
                                config: quill.QuillEditorConfig(
                                  scrollable: true,
                                  autoFocus: false,
                                  expands: false,
                                  padding: EdgeInsets.zero,
                                  placeholder: 'Start writing...',
                                  showCursor: true,
                                  enableInteractiveSelection: true,
                                  enableSelectionToolbar: true,
                                  customStyles: quill.DefaultStyles(
                                    paragraph: quill.DefaultTextBlockStyle(
                                      TextStyle(
                                        color: isDark ? Colors.white : Colors.black,
                                        fontSize: 16,
                                        height: 1.6,
                                      ),
                                      quill.HorizontalSpacing.zero,
                                      quill.VerticalSpacing.zero,
                                      quill.VerticalSpacing.zero,
                                      null,
                                    ),
                                    placeHolder: quill.DefaultTextBlockStyle(
                                      TextStyle(
                                        color: isDark ? Colors.grey.shade600 : Colors.grey.shade400,
                                        fontSize: 16,
                                        height: 1.6,
                                      ),
                                      quill.HorizontalSpacing.zero,
                                      quill.VerticalSpacing.zero,
                                      quill.VerticalSpacing.zero,
                                      null,
                                    ),
                                    lists: quill.DefaultListBlockStyle(
                                      TextStyle(
                                        color: isDark ? Colors.white : Colors.black,
                                        fontSize: 16,
                                        height: 1.6,
                                      ),
                                      quill.HorizontalSpacing.zero,
                                      quill.VerticalSpacing.zero,
                                      quill.VerticalSpacing.zero,
                                      null,
                                      null,
                                    ),
                                    code: quill.DefaultTextBlockStyle(
                                      TextStyle(
                                        color: isDark ? Colors.white : Colors.black,
                                        fontSize: 16,
                                        height: 1.6,
                                        fontFamily: 'monospace',
                                      ),
                                      quill.HorizontalSpacing.zero,
                                      quill.VerticalSpacing.zero,
                                      quill.VerticalSpacing.zero,
                                      null,
                                    ),
                                    color: isDark ? Colors.white : Colors.black,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Stats Footer
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: isDark
                          ? Colors.white.withOpacity(0.05)
                          : Colors.white,
                      borderRadius: BorderRadius.circular(15),
                      border: Border.all(
                        color: isDark
                            ? Colors.white.withOpacity(0.1)
                            : Colors.grey.shade200,
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _buildStatItem(
                          Icons.text_fields,
                          'Characters',
                          _getCharCount().toString(),
                          isDark,
                        ),
                        Container(
                          width: 1,
                          height: 30,
                          color: isDark
                              ? Colors.white.withOpacity(0.1)
                              : Colors.grey.shade300,
                        ),
                        _buildStatItem(
                          Icons.short_text,
                          'Words',
                          _getWordCount().toString(),
                          isDark,
                        ),
                        Container(
                          width: 1,
                          height: 30,
                          color: isDark
                              ? Colors.white.withOpacity(0.1)
                              : Colors.grey.shade300,
                        ),
                        _buildStatItem(
                          Icons.access_time_rounded,
                          'Last Modified',
                          widget.note != null
                              ? _formatTime(widget.note!.updatedAt)
                              : 'New',
                          isDark,
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 100),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatItem(IconData icon, String label, String value, bool isDark) {
    return Column(
      children: [
        Icon(
          icon,
          size: 20,
          color: isDark ? Colors.cyanAccent : Colors.blue,
        ),
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
        builder: (context) => FlowchartEditorScreen(
          initialFlowchartJson: _flowchartJson,
        ),
      ),
    );

    if (result != null && result is String) {
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
    VoidCallback onTap,
    {quill.Attribute? attribute}
  ) {
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
                    ? [Colors.cyanAccent.withOpacity(0.3), Colors.blue.withOpacity(0.2)]
                    : [Colors.blue.withOpacity(0.2), Colors.lightBlue.withOpacity(0.1)])
                : (isDark
                    ? [Colors.white.withOpacity(0.1), Colors.white.withOpacity(0.05)]
                    : [Colors.grey.shade100, Colors.grey.shade50]),
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isActive
                ? (isDark ? Colors.cyanAccent : Colors.blue)
                : (isDark ? Colors.white.withOpacity(0.1) : Colors.grey.shade300),
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
