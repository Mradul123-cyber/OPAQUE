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
  const NotesScreen({super.key});

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

  @override
  void initState() {
    super.initState();
    _checkPasswordProtection();
    _searchController.addListener(_filterNotes);
  }

  Future<void> _checkPasswordProtection() async {
    final isEnabled = await NotesPasswordService.instance.isPasswordEnabled();

    if (isEnabled && mounted) {
      // Show password verification dialog
      final unlocked = await _showUnlockDialog();

      if (unlocked) {
        setState(() {
          _isUnlocked = true;
        });
        _loadNotes();
      } else {
        // User cancelled or entered wrong password, go back
        if (mounted) {
          Navigator.of(context).pop();
        }
      }
    } else {
      // No password protection, load notes directly
      setState(() {
        _isUnlocked = true;
      });
      _loadNotes();
    }
  }

  Future<bool> _showUnlockDialog() async {
    final passwordController = TextEditingController();
    bool obscurePassword = true;

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => WillPopScope(
          onWillPop: () async => false,
          child: AlertDialog(
            backgroundColor: const Color(0xFF1E1E1E),
            title: Row(
              children: const [
                Icon(Icons.lock, color: Colors.cyanAccent),
                SizedBox(width: 12),
                Text('Enter Password', style: TextStyle(color: Colors.white)),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Enter your password to access Notes',
                  style: TextStyle(color: Colors.white70),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: passwordController,
                  obscureText: obscurePassword,
                  autofocus: true,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'Password',
                    hintStyle: TextStyle(color: Colors.grey.shade400),
                    filled: true,
                    fillColor: Colors.grey.shade900,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide.none,
                    ),
                    suffixIcon: IconButton(
                      icon: Icon(
                        obscurePassword ? Icons.visibility_off : Icons.visibility,
                        color: Colors.grey.shade400,
                      ),
                      onPressed: () => setState(() => obscurePassword = !obscurePassword),
                    ),
                  ),
                  onSubmitted: (_) async {
                    final password = passwordController.text;
                    final isValid = await NotesPasswordService.instance.verifyPassword(password);

                    if (isValid && context.mounted) {
                      Navigator.of(context).pop(true);
                    } else if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Incorrect password'),
                          backgroundColor: Colors.red,
                          duration: Duration(seconds: 2),
                        ),
                      );
                      passwordController.clear();
                    }
                  },
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
              ),
              ElevatedButton(
                onPressed: () async {
                  final password = passwordController.text;
                  final isValid = await NotesPasswordService.instance.verifyPassword(password);

                  if (isValid && context.mounted) {
                    Navigator.of(context).pop(true);
                  } else if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Incorrect password'),
                        backgroundColor: Colors.red,
                        duration: Duration(seconds: 2),
                      ),
                    );
                    passwordController.clear();
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.cyanAccent,
                  foregroundColor: Colors.black,
                ),
                child: const Text('Unlock'),
              ),
            ],
          ),
        ),
      ),
    );

    return result ?? false;
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadNotes() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final dbService = DatabaseService.instance;
      final notes = _selectedCategory == null
          ? await dbService.getAllNotes()
          : await dbService.getNotesByCategory(_selectedCategory);
      final categories = await dbService.getAllCategories();

      setState(() {
        _notes = notes;
        _filteredNotes = notes;
        _categories = categories;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('[NotesScreen] Error loading notes: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _filterNotes() {
    final query = _searchController.text.toLowerCase();

    setState(() {
      if (query.isEmpty) {
        _filteredNotes = _notes;
        _isSearching = false;
      } else {
        _filteredNotes = _notes
            .where((note) {
              final plainText = _extractPlainText(note.content);
              return note.title.toLowerCase().contains(query) ||
                  plainText.toLowerCase().contains(query);
            })
            .toList();
        _isSearching = true;
      }
    });
  }

  /// Extract plain text from Quill JSON or return as-is if plain text
  String _extractPlainText(String content) {
    try {
      final doc = quill.Document.fromJson(jsonDecode(content));
      return doc.toPlainText();
    } catch (e) {
      // If not JSON, return as plain text
      return content;
    }
  }

  Future<void> _createNewNote() async {
    final result = await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => const CreateNoteScreen(),
      ),
    );

    if (result == true) {
      _loadNotes(); // Reload notes after creating
    }
  }

  Future<void> _editNote(Note note) async {
    // If note is locked, require password verification
    if (note.isLocked) {
      final unlocked = await _verifyPasswordForLockedNote();
      if (!unlocked) return;
    }

    final result = await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => CreateNoteScreen(note: note),
      ),
    );

    if (result == true) {
      _loadNotes(); // Reload notes after editing
    }
  }

  Future<bool> _verifyPasswordForLockedNote() async {
    final passwordController = TextEditingController();
    bool obscurePassword = true;

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          backgroundColor: const Color(0xFF1E1E1E),
          title: Row(
            children: const [
              Icon(Icons.lock, color: Colors.orange),
              SizedBox(width: 12),
              Text('Locked Note', style: TextStyle(color: Colors.white)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'This note is locked. Enter your password to view it.',
                style: TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: passwordController,
                obscureText: obscurePassword,
                autofocus: true,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'Password',
                  hintStyle: TextStyle(color: Colors.grey.shade400),
                  filled: true,
                  fillColor: Colors.grey.shade900,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none,
                  ),
                  suffixIcon: IconButton(
                    icon: Icon(
                      obscurePassword ? Icons.visibility_off : Icons.visibility,
                      color: Colors.grey.shade400,
                    ),
                    onPressed: () => setState(() => obscurePassword = !obscurePassword),
                  ),
                ),
                onSubmitted: (_) async {
                  final password = passwordController.text;
                  final isValid = await NotesPasswordService.instance.verifyPassword(password);

                  if (isValid && context.mounted) {
                    Navigator.of(context).pop(true);
                  } else if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Incorrect password'),
                        backgroundColor: Colors.red,
                        duration: Duration(seconds: 2),
                      ),
                    );
                    passwordController.clear();
                  }
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              onPressed: () async {
                final password = passwordController.text;
                final isValid = await NotesPasswordService.instance.verifyPassword(password);

                if (isValid && context.mounted) {
                  Navigator.of(context).pop(true);
                } else if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Incorrect password'),
                      backgroundColor: Colors.red,
                      duration: Duration(seconds: 2),
                    ),
                  );
                  passwordController.clear();
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.cyanAccent,
                foregroundColor: Colors.black,
              ),
              child: const Text('Unlock'),
            ),
          ],
        ),
      ),
    );

    return result ?? false;
  }

  Future<void> _deleteNote(Note note) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Note'),
        content: Text('Are you sure you want to delete "${note.title}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await DatabaseService.instance.deleteNote(note.id!);
        _loadNotes();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Note deleted')),
          );
        }
      } catch (e) {
        debugPrint('[NotesScreen] Error deleting note: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to delete note')),
          );
        }
      }
    }
  }

  Future<void> _togglePin(Note note) async {
    try {
      await DatabaseService.instance.toggleNotePin(note.id!, !note.isPinned);
      _loadNotes();
    } catch (e) {
      debugPrint('[NotesScreen] Error toggling pin: $e');
    }
  }

  Future<void> _toggleNoteLock(Note note) async {
    // Check if screen-level password is enabled first
    final isPasswordEnabled = await NotesPasswordService.instance.isPasswordEnabled();

    if (!isPasswordEnabled) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please enable Screen Lock first in password settings'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 3),
          ),
        );
      }
      return;
    }

    // If locking the note, verify password first
    if (!note.isLocked) {
      final verified = await _verifyPasswordForNoteLock();
      if (!verified) return;
    }

    try {
      await DatabaseService.instance.toggleNoteLock(note.id!, !note.isLocked);
      _loadNotes();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(note.isLocked ? 'Note unlocked' : 'Note locked'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      debugPrint('[NotesScreen] Error toggling note lock: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to toggle lock')),
        );
      }
    }
  }

  Future<bool> _verifyPasswordForNoteLock() async {
    final passwordController = TextEditingController();
    bool obscurePassword = true;

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          backgroundColor: const Color(0xFF1E1E1E),
          title: Row(
            children: const [
              Icon(Icons.lock, color: Colors.cyanAccent),
              SizedBox(width: 12),
              Text('Verify Password', style: TextStyle(color: Colors.white)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Enter your password to lock this note',
                style: TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: passwordController,
                obscureText: obscurePassword,
                autofocus: true,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'Password',
                  hintStyle: TextStyle(color: Colors.grey.shade400),
                  filled: true,
                  fillColor: Colors.grey.shade900,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none,
                  ),
                  suffixIcon: IconButton(
                    icon: Icon(
                      obscurePassword ? Icons.visibility_off : Icons.visibility,
                      color: Colors.grey.shade400,
                    ),
                    onPressed: () => setState(() => obscurePassword = !obscurePassword),
                  ),
                ),
                onSubmitted: (_) async {
                  final password = passwordController.text;
                  final isValid = await NotesPasswordService.instance.verifyPassword(password);

                  if (isValid && context.mounted) {
                    Navigator.of(context).pop(true);
                  } else if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Incorrect password'),
                        backgroundColor: Colors.red,
                        duration: Duration(seconds: 2),
                      ),
                    );
                    passwordController.clear();
                  }
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              onPressed: () async {
                final password = passwordController.text;
                final isValid = await NotesPasswordService.instance.verifyPassword(password);

                if (isValid && context.mounted) {
                  Navigator.of(context).pop(true);
                } else if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Incorrect password'),
                      backgroundColor: Colors.red,
                      duration: Duration(seconds: 2),
                    ),
                  );
                  passwordController.clear();
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.cyanAccent,
                foregroundColor: Colors.black,
              ),
              child: const Text('Verify'),
            ),
          ],
        ),
      ),
    );

    return result ?? false;
  }

  void _showCategoryFilter(bool isDarkTheme) {
    showModalBottomSheet(
      context: context,
      backgroundColor: isDarkTheme ? const Color(0xFF1E1E1E) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      isScrollControlled: true,
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom + MediaQuery.of(context).padding.bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: EdgeInsets.all(MediaQuery.of(context).size.width * 0.04),
                child: Text(
                  'Filter by Category',
                  style: TextStyle(
                    fontSize: (MediaQuery.of(context).size.width * 0.045).clamp(16.0, 20.0),
                    fontWeight: FontWeight.bold,
                    color: isDarkTheme ? Colors.white : Colors.black,
                  ),
                ),
              ),
            ListTile(
              leading: Icon(
                Icons.all_inclusive,
                color: isDarkTheme ? Colors.cyanAccent : Colors.blue,
              ),
              title: Text(
                'All Notes',
                style: TextStyle(
                  color: isDarkTheme ? Colors.white : Colors.black,
                ),
              ),
              selected: _selectedCategory == null,
              onTap: () {
                setState(() {
                  _selectedCategory = null;
                });
                Navigator.pop(context);
                _loadNotes();
              },
            ),
            ..._categories.map((category) {
              return ListTile(
                leading: Icon(
                  Icons.folder,
                  color: category.colorCode != null
                      ? Color(int.parse(category.colorCode!.replaceFirst('#', '0xFF')))
                      : (isDarkTheme ? Colors.cyanAccent : Colors.blue),
                ),
                title: Text(
                  category.name,
                  style: TextStyle(
                    color: isDarkTheme ? Colors.white : Colors.black,
                  ),
                ),
                selected: _selectedCategory == category.name,
                onTap: () {
                  setState(() {
                    _selectedCategory = category.name;
                  });
                  Navigator.pop(context);
                  _loadNotes();
                },
              );
            }),
            const SizedBox(height: 16),
          ],
        ),
        );
      },
    );
  }

  void _showPasswordSettings(bool isDarkTheme) {
    showModalBottomSheet(
      context: context,
      backgroundColor: isDarkTheme ? const Color(0xFF1E1E1E) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      isScrollControlled: true,
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom + MediaQuery.of(context).padding.bottom,
          ),
          child: FutureBuilder<bool>(
            future: NotesPasswordService.instance.isPasswordEnabled(),
            builder: (context, snapshot) {
              final isEnabled = snapshot.data ?? false;

              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Icon(Icons.lock, color: isDarkTheme ? Colors.cyanAccent : Colors.blue),
                        const SizedBox(width: 12),
                        Text(
                          'Password Protection',
                          style: TextStyle(
                            fontSize: (MediaQuery.of(context).size.width * 0.045).clamp(16.0, 20.0),
                            fontWeight: FontWeight.bold,
                            color: isDarkTheme ? Colors.white : Colors.black,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),

                  // App Lock Toggle
                  ListTile(
                    leading: Icon(
                      isEnabled ? Icons.lock : Icons.lock_open,
                      color: isEnabled ? Colors.green : (isDarkTheme ? Colors.cyanAccent : Colors.blue),
                    ),
                    title: Text(
                      isEnabled ? 'Notes Lock Enabled' : 'Notes Lock Disabled',
                      style: TextStyle(
                        color: isDarkTheme ? Colors.white : Colors.black,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: Text(
                      isEnabled ? 'Password required to access Notes screen' : 'Tap to enable screen protection',
                      style: TextStyle(
                        color: isDarkTheme ? Colors.white70 : Colors.black54,
                      ),
                    ),
                    trailing: Icon(
                      Icons.arrow_forward_ios,
                      size: 16,
                      color: isDarkTheme ? Colors.white54 : Colors.black54,
                    ),
                    onTap: () {
                      Navigator.pop(context);
                      _handleAppLockToggle(isEnabled, isDarkTheme);
                    },
                  ),

                  const Divider(height: 1),

                  // Info section
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Protection Levels:',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: isDarkTheme ? Colors.white : Colors.black,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '• Screen Lock: Password required to access Notes screen',
                          style: TextStyle(
                            color: isDarkTheme ? Colors.white70 : Colors.black54,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '• Individual Lock: Lock specific notes separately',
                          style: TextStyle(
                            color: isDarkTheme ? Colors.white70 : Colors.black54,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),
                ],
              );
            },
          ),
        );
      },
    );
  }

  void _handleAppLockToggle(bool isCurrentlyEnabled, bool isDarkTheme) async {
    if (isCurrentlyEnabled) {
      // Show options: Change Password or Disable
      await _showPasswordManagementDialog(isDarkTheme);
    } else {
      // Setup new password
      await _showPasswordSetupDialog(isDarkTheme);
    }
  }

  Future<void> _showPasswordSetupDialog(bool isDarkTheme) async {
    final passwordController = TextEditingController();
    final confirmController = TextEditingController();
    bool obscurePassword = true;
    bool obscureConfirm = true;

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          backgroundColor: isDarkTheme ? const Color(0xFF1E1E1E) : Colors.white,
          title: Text(
            'Setup Notes Password',
            style: TextStyle(color: isDarkTheme ? Colors.white : Colors.black),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: passwordController,
                obscureText: obscurePassword,
                style: TextStyle(color: isDarkTheme ? Colors.white : Colors.black),
                decoration: InputDecoration(
                  hintText: 'Enter password (min 4 characters)',
                  hintStyle: TextStyle(color: isDarkTheme ? Colors.grey.shade400 : Colors.grey.shade600),
                  suffixIcon: IconButton(
                    icon: Icon(
                      obscurePassword ? Icons.visibility_off : Icons.visibility,
                      color: isDarkTheme ? Colors.grey.shade400 : Colors.grey.shade600,
                    ),
                    onPressed: () => setState(() => obscurePassword = !obscurePassword),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: confirmController,
                obscureText: obscureConfirm,
                style: TextStyle(color: isDarkTheme ? Colors.white : Colors.black),
                decoration: InputDecoration(
                  hintText: 'Confirm password',
                  hintStyle: TextStyle(color: isDarkTheme ? Colors.grey.shade400 : Colors.grey.shade600),
                  suffixIcon: IconButton(
                    icon: Icon(
                      obscureConfirm ? Icons.visibility_off : Icons.visibility,
                      color: isDarkTheme ? Colors.grey.shade400 : Colors.grey.shade600,
                    ),
                    onPressed: () => setState(() => obscureConfirm = !obscureConfirm),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              onPressed: () async {
                final password = passwordController.text;
                final confirm = confirmController.text;

                if (password.length < 4) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Password must be at least 4 characters'),
                      backgroundColor: Colors.red,
                    ),
                  );
                  return;
                }

                if (password != confirm) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Passwords do not match'),
                      backgroundColor: Colors.red,
                    ),
                  );
                  return;
                }

                final success = await NotesPasswordService.instance.setPassword(password);

                if (mounted) {
                  Navigator.pop(context);

                  if (success) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Notes password enabled successfully!'),
                        backgroundColor: Colors.green,
                      ),
                    );
                    setState(() {}); // Refresh
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Failed to set password'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.cyanAccent,
                foregroundColor: Colors.black,
              ),
              child: const Text('Set Password'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showPasswordManagementDialog(bool isDarkTheme) async {
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: isDarkTheme ? const Color(0xFF1E1E1E) : Colors.white,
        title: Text(
          'Manage Password',
          style: TextStyle(color: isDarkTheme ? Colors.white : Colors.black),
        ),
        content: Text(
          'What would you like to do?',
          style: TextStyle(color: isDarkTheme ? Colors.white70 : Colors.black54),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _showChangePasswordDialog(isDarkTheme);
            },
            child: const Text('Change Password', style: TextStyle(color: Colors.cyanAccent)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _showDisablePasswordDialog(isDarkTheme);
            },
            child: const Text('Disable', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Future<void> _showChangePasswordDialog(bool isDarkTheme) async {
    final oldPasswordController = TextEditingController();
    final newPasswordController = TextEditingController();
    final confirmController = TextEditingController();

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: isDarkTheme ? const Color(0xFF1E1E1E) : Colors.white,
        title: Text('Change Password', style: TextStyle(color: isDarkTheme ? Colors.white : Colors.black)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: oldPasswordController,
              obscureText: true,
              style: TextStyle(color: isDarkTheme ? Colors.white : Colors.black),
              decoration: InputDecoration(
                hintText: 'Current password',
                hintStyle: TextStyle(color: isDarkTheme ? Colors.grey.shade400 : Colors.grey.shade600),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: newPasswordController,
              obscureText: true,
              style: TextStyle(color: isDarkTheme ? Colors.white : Colors.black),
              decoration: InputDecoration(
                hintText: 'New password (min 4 characters)',
                hintStyle: TextStyle(color: isDarkTheme ? Colors.grey.shade400 : Colors.grey.shade600),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: confirmController,
              obscureText: true,
              style: TextStyle(color: isDarkTheme ? Colors.white : Colors.black),
              decoration: InputDecoration(
                hintText: 'Confirm new password',
                hintStyle: TextStyle(color: isDarkTheme ? Colors.grey.shade400 : Colors.grey.shade600),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () async {
              final oldPassword = oldPasswordController.text;
              final newPassword = newPasswordController.text;
              final confirm = confirmController.text;

              if (newPassword.length < 4) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('New password must be at least 4 characters'), backgroundColor: Colors.red),
                );
                return;
              }

              if (newPassword != confirm) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Passwords do not match'), backgroundColor: Colors.red),
                );
                return;
              }

              final success = await NotesPasswordService.instance.changePassword(oldPassword, newPassword);

              if (mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(success ? 'Password changed successfully!' : 'Incorrect current password'),
                    backgroundColor: success ? Colors.green : Colors.red,
                  ),
                );
                if (success) setState(() {});
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.cyanAccent,
              foregroundColor: Colors.black,
            ),
            child: const Text('Change'),
          ),
        ],
      ),
    );
  }

  Future<void> _showDisablePasswordDialog(bool isDarkTheme) async {
    final passwordController = TextEditingController();

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: isDarkTheme ? const Color(0xFF1E1E1E) : Colors.white,
        title: Text('Disable Password', style: TextStyle(color: isDarkTheme ? Colors.white : Colors.black)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Enter your password to disable protection',
              style: TextStyle(color: isDarkTheme ? Colors.white70 : Colors.black54),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: passwordController,
              obscureText: true,
              style: TextStyle(color: isDarkTheme ? Colors.white : Colors.black),
              decoration: InputDecoration(
                hintText: 'Current password',
                hintStyle: TextStyle(color: isDarkTheme ? Colors.grey.shade400 : Colors.grey.shade600),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () async {
              final password = passwordController.text;
              final isValid = await NotesPasswordService.instance.verifyPassword(password);

              if (isValid) {
                await NotesPasswordService.instance.disablePassword();

                if (mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Password protection disabled'), backgroundColor: Colors.orange),
                  );
                  setState(() {});
                }
              } else {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Incorrect password'), backgroundColor: Colors.red),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Disable'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Use Notes screen theme setting from user preferences
    final userSettings = Provider.of<UserSettingsProvider>(context);
    final isDarkTheme = userSettings.notesScreenStyle == 'dark';

    // Responsive sizing (exact same as HomeScreen)
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final searchPadding = EdgeInsets.fromLTRB(
      screenWidth * 0.04,
      screenHeight * 0.01,
      screenWidth * 0.04,
      screenHeight * 0.01,
    );
    final searchFontSize = (screenWidth * 0.04).clamp(14.0, 18.0);
    final searchIconSize = (screenWidth * 0.06).clamp(20.0, 26.0);
    final titleFontSize = (screenWidth * 0.05).clamp(18.0, 24.0);

    // Theme colors (exact same as HomeScreen)
    final Color searchBgColor = isDarkTheme ? const Color(0xFF1E1E1E) : const Color(0xFFF0F2F5);
    final Color searchTextColor = isDarkTheme ? Colors.white : Colors.black87;
    final Color searchHintColor = isDarkTheme ? Colors.grey.shade400 : Colors.grey.shade500;
    final Color searchIconColor = isDarkTheme ? Colors.grey.shade400 : Colors.grey.shade600;
    final Color noResultsColor = isDarkTheme ? Colors.grey.shade400 : Colors.grey.shade600;
    final Color textColor = isDarkTheme ? Colors.white : Colors.black87;
    final Color iconColor = isDarkTheme ? Colors.white : Colors.black87;
    final Color appBarBgColor = isDarkTheme ? const Color(0xFF0a1128) : Colors.white;

    return Scaffold(
      backgroundColor: isDarkTheme ? const Color(0xFF121212) : Colors.white,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(kToolbarHeight),
        child: Container(
          decoration: BoxDecoration(
            color: appBarBgColor,
          ),
          child: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            centerTitle: true,
            titleTextStyle: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: textColor,
                  fontWeight: FontWeight.bold,
                  fontSize: titleFontSize,
                ),
            iconTheme: IconThemeData(color: iconColor),
            title: Text(
              'Zarq Notes',
              style: TextStyle(
                color: textColor,
                fontWeight: FontWeight.bold,
                fontSize: titleFontSize,
              ),
            ),
            actions: [
              // Password lock settings button
              IconButton(
                icon: Icon(Icons.lock_outline, color: iconColor),
                onPressed: () => _showPasswordSettings(isDarkTheme),
                tooltip: 'Password Lock',
              ),
              // Category filter button
              IconButton(
                icon: Icon(Icons.filter_list, color: iconColor),
                onPressed: () => _showCategoryFilter(isDarkTheme),
                tooltip: 'Filter by Category',
              ),
            ],
          ),
        ),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Search bar (exact same styling as HomeScreen)
          Padding(
            padding: searchPadding,
            child: Container(
              decoration: BoxDecoration(
                color: searchBgColor,
                borderRadius: BorderRadius.circular(10.0),
                border: Border.all(color: Colors.transparent),
              ),
              child: TextField(
                controller: _searchController,
                style: TextStyle(
                  color: searchTextColor,
                  fontSize: searchFontSize,
                ),
                decoration: InputDecoration(
                  hintText: 'Search notes...',
                  hintStyle: TextStyle(
                    color: searchHintColor,
                    fontSize: searchFontSize,
                  ),
                  prefixIcon: Icon(
                    Icons.search,
                    color: searchIconColor,
                    size: searchIconSize,
                  ),
                  suffixIcon: _isSearching
                      ? IconButton(
                          icon: Icon(
                            Icons.clear,
                            color: searchIconColor,
                            size: searchIconSize,
                          ),
                          onPressed: () {
                            _searchController.clear();
                            FocusScope.of(context).unfocus();
                          },
                        )
                      : null,
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: screenWidth * 0.05,
                    vertical: screenHeight * 0.017,
                  ),
                ),
              ),
            ),
          ),

          // Category indicator
          if (_selectedCategory != null)
            Padding(
              padding: EdgeInsets.symmetric(horizontal: screenWidth * 0.04),
              child: Chip(
                label: Text(_selectedCategory!),
                deleteIcon: Icon(Icons.close, size: (screenWidth * 0.04).clamp(14.0, 18.0)),
                onDeleted: () {
                  setState(() {
                    _selectedCategory = null;
                  });
                  _loadNotes();
                },
              ),
            ),

          // Notes list
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _filteredNotes.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              _isSearching ? Icons.search_off : Icons.note_add,
                              size: (screenWidth * 0.16).clamp(48.0, 80.0),
                              color: noResultsColor,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              _isSearching
                                  ? "No results found for '${_searchController.text}'"
                                  : "No notes yet.\nTap + to create your first note",
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: noResultsColor,
                                fontSize: searchFontSize,
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        itemCount: _filteredNotes.length,
                        itemBuilder: (context, index) {
                          final note = _filteredNotes[index];
                          return _buildNoteCard(
                            note,
                            isDarkTheme,
                            screenWidth,
                            screenHeight,
                          );
                        },
                      ),
          ),
        ],
      ),
      floatingActionButton: Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            colors: isDarkTheme
                ? [Colors.cyanAccent, Colors.blue]
                : [Colors.blue, Colors.lightBlue],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: [
            BoxShadow(
              color: (isDarkTheme ? Colors.cyanAccent : Colors.blue).withOpacity(0.5),
              blurRadius: 12,
              spreadRadius: 2,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: FloatingActionButton(
          onPressed: _createNewNote,
          backgroundColor: Colors.transparent,
          elevation: 0,
          child: Icon(
            Icons.add,
            color: Colors.white,
            size: (screenWidth * 0.08).clamp(28.0, 36.0),
          ),
        ),
      ),
    );
  }

  Widget _buildNoteCard(
    Note note,
    bool isDarkTheme,
    double screenWidth,
    double screenHeight,
  ) {
    // Responsive sizing (exact same as HomeScreen)
    final listItemMargin = EdgeInsets.symmetric(
      horizontal: screenWidth * 0.03,
      vertical: screenHeight * 0.008,
    );
    final listItemTitleSize = (screenWidth * 0.04).clamp(14.0, 18.0);

    // Theme colors - Green for pinned notes with black borders
    final Color cardBgColor = note.isPinned
        ? (isDarkTheme ? const Color(0xFF1B5E20) : Colors.green[100]!) // Green for pinned
        : (isDarkTheme ? const Color(0xFF2B2B2B) : Colors.lightBlue[50]!); // Dark grey in dark theme, Blue in light theme for normal
    final Color cardBorderColor = isDarkTheme ? Colors.cyanAccent.withOpacity(0.3) : Colors.black;
    final Color titleColor = isDarkTheme ? Colors.white : Colors.black;
    final Color subtitleColor = isDarkTheme ? Colors.grey[400]! : Colors.grey[600]!;

    // Get category color and icon if exists
    Color? categoryColor;
    IconData categoryIcon = Icons.note; // Default icon

    // Map of predefined category names to icons
    final Map<String, IconData> categoryIcons = {
      'Personal': Icons.person,
      'Work': Icons.work,
      'Ideas': Icons.lightbulb,
      'Todo': Icons.check_circle,
      'Important': Icons.priority_high,
      'Study': Icons.school,
      'Shopping': Icons.shopping_cart,
      'Health': Icons.health_and_safety,
    };

    if (note.category != null) {
      final category = _categories.firstWhere(
        (cat) => cat.name == note.category,
        orElse: () => NoteCategory(
          name: note.category!,
          createdAt: DateTime.now(),
        ),
      );
      if (category.colorCode != null) {
        try {
          categoryColor = Color(int.parse(category.colorCode!.replaceFirst('#', '0xFF')));
        } catch (e) {
          categoryColor = null;
        }
      }
      // Get icon for category (use default if not found)
      categoryIcon = categoryIcons[note.category] ?? Icons.folder;
    }

    return Container(
      margin: listItemMargin,
      decoration: BoxDecoration(
        color: cardBgColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: cardBorderColor,
          width: 2.0,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 5,
            spreadRadius: 1,
          ),
        ],
      ),
      child: ListTile(
        leading: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              padding: EdgeInsets.all(screenWidth * 0.02),
              decoration: BoxDecoration(
                color: note.isPinned
                    ? Colors.green.withOpacity(0.2)
                    : (isDarkTheme ? Colors.cyanAccent.withOpacity(0.1) : Colors.blue.withOpacity(0.1)),
                shape: BoxShape.circle,
              ),
              child: Icon(
                note.isPinned ? Icons.push_pin : categoryIcon,
                color: note.isPinned
                    ? Colors.green
                    : (categoryColor ?? (isDarkTheme ? Colors.cyanAccent : Colors.blue)),
                size: (screenWidth * 0.05).clamp(18.0, 24.0),
              ),
            ),
            // Lock badge for locked notes
            if (note.isLocked)
              Positioned(
                right: -4,
                top: -4,
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: Colors.orange,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isDarkTheme ? const Color(0xFF121212) : Colors.white,
                      width: 1.5,
                    ),
                  ),
                  child: Icon(
                    Icons.lock,
                    color: Colors.white,
                    size: (screenWidth * 0.03).clamp(10.0, 14.0),
                  ),
                ),
              ),
          ],
        ),
        title: Text(
          note.title,
          style: TextStyle(
            color: titleColor,
            fontWeight: FontWeight.bold,
            fontSize: listItemTitleSize,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _extractPlainText(note.content),
              style: TextStyle(
                fontSize: listItemTitleSize * 0.875,
                color: subtitleColor,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                if (note.category != null) ...[
                  Icon(Icons.folder, size: (screenWidth * 0.03).clamp(10.0, 14.0), color: categoryColor ?? subtitleColor),
                  SizedBox(width: screenWidth * 0.01),
                  Text(
                    note.category!,
                    style: TextStyle(fontSize: (screenWidth * 0.028).clamp(10.0, 12.0), color: subtitleColor),
                  ),
                  SizedBox(width: screenWidth * 0.02),
                ],
                Icon(Icons.access_time, size: (screenWidth * 0.03).clamp(10.0, 14.0), color: subtitleColor),
                SizedBox(width: screenWidth * 0.01),
                Text(
                  _formatDate(note.updatedAt),
                  style: TextStyle(fontSize: (screenWidth * 0.028).clamp(10.0, 12.0), color: subtitleColor),
                ),
              ],
            ),
          ],
        ),
        trailing: PopupMenuButton<String>(
          icon: Icon(Icons.more_vert, color: titleColor),
          onSelected: (value) {
            if (value == 'edit') {
              _editNote(note);
            } else if (value == 'delete') {
              _deleteNote(note);
            } else if (value == 'pin') {
              _togglePin(note);
            } else if (value == 'lock') {
              _toggleNoteLock(note);
            }
          },
          itemBuilder: (context) => [
            PopupMenuItem(
              value: 'pin',
              child: Row(
                children: [
                  Icon(note.isPinned ? Icons.push_pin_outlined : Icons.push_pin),
                  const SizedBox(width: 8),
                  Text(note.isPinned ? 'Unpin' : 'Pin'),
                ],
              ),
            ),
            PopupMenuItem(
              value: 'lock',
              child: Row(
                children: [
                  Icon(
                    note.isLocked ? Icons.lock_open : Icons.lock,
                    color: note.isLocked ? Colors.orange : null,
                  ),
                  const SizedBox(width: 8),
                  Text(note.isLocked ? 'Unlock Note' : 'Lock Note'),
                ],
              ),
            ),
            const PopupMenuItem(
              value: 'edit',
              child: Row(
                children: [
                  Icon(Icons.edit),
                  SizedBox(width: 8),
                  Text('Edit'),
                ],
              ),
            ),
            const PopupMenuItem(
              value: 'delete',
              child: Row(
                children: [
                  Icon(Icons.delete, color: Colors.red),
                  SizedBox(width: 8),
                  Text('Delete', style: TextStyle(color: Colors.red)),
                ],
              ),
            ),
          ],
        ),
        onTap: () => _editNote(note),
      ),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays == 0) {
      return 'Today ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
    } else if (difference.inDays == 1) {
      return 'Yesterday';
    } else if (difference.inDays < 7) {
      return '${difference.inDays} days ago';
    } else {
      return '${date.day}/${date.month}/${date.year}';
    }
  }
}
