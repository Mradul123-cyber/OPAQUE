import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:uuid/uuid.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import 'home_screen.dart';
import 'chat_screen.dart';
import 'app_config.dart';
import 'services/user_settings_provider.dart';
import 'widgets/call_aware_screen.dart';
import 'widgets/backup_design.dart';
import 'widgets/notes_design.dart';
import 'widgets/opaque_toast.dart';

class Friend {
  final String username;
  final String? avatarUrl;
  final String? displayName;
  Friend({required this.username, this.avatarUrl, this.displayName});
  factory Friend.fromJson(Map<String, dynamic> json) => Friend(
    username: json['username'] ?? 'Unknown User',
    avatarUrl: json['avatarUrl'],
    displayName: json['displayName'],
  );
  String get displayNameOrUsername =>
      displayName?.trim().isNotEmpty == true ? displayName! : username;
}

// ─────────────────────────────────────────────────────────────────────────────
// STEP 1: SELECT MEMBERS SCREEN
// ─────────────────────────────────────────────────────────────────────────────

class CreateGroupScreen extends StatefulWidget {
  final WebSocketChannel channel;
  final VoidCallback onGroupCreated;
  const CreateGroupScreen({
    super.key,
    required this.channel,
    required this.onGroupCreated,
  });
  @override
  State<CreateGroupScreen> createState() => _CreateGroupScreenState();
}

class _CreateGroupScreenState extends State<CreateGroupScreen> {
  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();
  List<Friend> _friendsList = [];
  final Set<String> _selectedFriends = {};
  bool _isLoading = true;
  bool _leaving = false;
  bool _askingToLeave = false;
  String? _loadError;

  bool get _canContinue => _selectedFriends.isNotEmpty && !_isLoading;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_refresh);
    _fetchFriendsList();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  Future<void> _fetchFriendsList() async {
    setState(() {
      _isLoading = true;
      _loadError = null;
    });
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw StateError('Sign in required');
      final token = await user.getIdToken();
      final response = await http
          .get(
            Uri.parse('${AppConfig.baseUrl}/friends/list'),
            headers: {'Authorization': 'Bearer $token'},
          )
          .timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) {
        throw StateError('Could not load friends');
      }
      final rows = json.decode(response.body) as List<dynamic>;
      final seen = <String>{};
      final friends = rows
          .map((row) => Friend.fromJson(row as Map<String, dynamic>))
          .where(
            (friend) =>
                friend.username.trim().isNotEmpty && seen.add(friend.username),
          )
          .toList();
      if (mounted) setState(() => _friendsList = friends);
    } catch (_) {
      if (mounted) {
        setState(
          () => _loadError = 'Couldn’t load your friends. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _leave() async {
    if (_askingToLeave) return;
    _askingToLeave = true;
    final changed = _selectedFriends.isNotEmpty;
    final discard =
        !changed ||
        await showNotesConfirmation(
          context,
          title: 'Discard selection?',
          body:
              'You have selected members. Leave without creating the group?',
          confirm: 'Discard',
          danger: true,
          icon: Icons.group_outlined,
        );
    _askingToLeave = false;
    if (!mounted || !discard) return;
    setState(() => _leaving = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.pop(context);
    });
  }

  void _toggleFriend(Friend friend) {
    if (!_selectedFriends.contains(friend.username) &&
        _selectedFriends.length >= 99) {
      OpaqueToast.warning(context, 'Maximum 100 members allowed, including you.');
      return;
    }
    setState(() {
      if (!_selectedFriends.remove(friend.username)) {
        _selectedFriends.add(friend.username);
      }
    });
  }

  void _onContinue() {
    if (!_canContinue) return;
    final chosen = _friendsList
        .where((f) => _selectedFriends.contains(f.username))
        .toList();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => GroupDetailsScreen(
          channel: widget.channel,
          onGroupCreated: widget.onGroupCreated,
          selectedFriends: chosen,
        ),
      ),
    );
  }

  Widget _avatar(Friend friend, NotesColors c) {
    final name = friend.displayNameOrUsername;
    final initials = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((s) => s.isNotEmpty)
        .take(2)
        .map((s) => s.characters.first.toUpperCase())
        .join();
    final fallback = Center(
      child: Text(
        initials.isEmpty ? '?' : initials,
        style: c.text(12, muted: true),
      ),
    );
    return Container(
      width: 38,
      height: 38,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(shape: BoxShape.circle, color: c.soft),
      child: friend.avatarUrl?.isNotEmpty == true
          ? CachedNetworkImage(
              imageUrl: friend.avatarUrl!,
              fit: BoxFit.cover,
              placeholder: (_, __) => fallback,
              errorWidget: (_, __, ___) => fallback,
            )
          : fallback,
    );
  }

  @override
  Widget build(BuildContext context) {
    context.watch<UserSettingsProvider>();
    final neutralDark = context.read<UserSettingsProvider>().isDarkMode;
    final selectedSurface = neutralDark ? const Color(0xFFE3E5E9) : const Color(0xFF303238);
    final selectedInk = neutralDark ? const Color(0xFF25272C) : const Color(0xFFF8F8FA);
    final c = NotesColors(context);
    final query = _searchController.text.trim().toLowerCase();
    final filtered = _friendsList
        .where(
          (f) => '${f.displayNameOrUsername} ${f.username}'
              .toLowerCase()
              .contains(query),
        )
        .toList();
    final selected = _friendsList
        .where((f) => _selectedFriends.contains(f.username))
        .toList();
    final isKeyboardOpen = MediaQuery.of(context).viewInsets.bottom > 0;

    return PopScope(
      canPop: _leaving,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _leave();
      },
      child: CallAwareScreen(
        screenName: 'CreateGroupScreen',
        child: Scaffold(
          backgroundColor: c.surface,
          appBar: const BackupHeader(),
          body: SafeArea(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
              child: Column(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(22, 16, 22, 0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'New group',
                                style: c
                                    .text(22, bold: true)
                                    .copyWith(letterSpacing: -.6),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Select members to add to your group.',
                                style: c.text(12, muted: true),
                              ),
                              const SizedBox(height: 16),
                              // Search bar
                              SizedBox(
                                height: 38,
                                child: TextField(
                                  controller: _searchController,
                                  focusNode: _searchFocusNode,
                                  onTapOutside: (_) => _searchFocusNode.unfocus(),
                                  style: c.text(12),
                                decoration: InputDecoration(
                                  hintText: 'Search friends',
                                  hintStyle: c.text(12, muted: true),
                                  filled: true,
                                  fillColor: c.soft,
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                  ),
                                  prefixIcon: Icon(
                                    Icons.search,
                                    size: 16,
                                    color: c.muted,
                                  ),
                                  suffixIcon: query.isEmpty
                                      ? null
                                      : IconButton(
                                          tooltip: 'Clear search',
                                          onPressed: _searchController.clear,
                                          icon: Icon(
                                            Icons.close,
                                            size: 16,
                                            color: c.muted,
                                          ),
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
                                    borderSide: BorderSide(color: c.blue),
                                  ),
                                ),
                              ),
                            ),
                            // Selected chips
                            if (selected.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 10),
                                child: SingleChildScrollView(
                                  scrollDirection: Axis.horizontal,
                                  child: Row(
                                    children: [
                                      for (final friend in selected)
                                        Padding(
                                          padding: const EdgeInsets.only(right: 6),
                                          child: Semantics(
                                            label:
                                                'Remove ${friend.displayNameOrUsername}',
                                            button: true,
                                            child: InkWell(
                                              onTap: () => _toggleFriend(friend),
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                              child: Container(
                                                padding: const EdgeInsets.symmetric(
                                                  horizontal: 9,
                                                  vertical: 5,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: selectedSurface,
                                                  borderRadius:
                                                      BorderRadius.circular(12),
                                                ),
                                                child: Row(
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    Text(
                                                      friend
                                                          .displayNameOrUsername
                                                          .split(' ')
                                                          .first,
                                                      style: c
                                                          .text(10)
                                                          .copyWith(
                                                            color: selectedInk,
                                                          ),
                                                    ),
                                                    const SizedBox(width: 6),
                                                    Icon(
                                                      Icons.close,
                                                      size: 11,
                                                      color: selectedInk,
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            // Header row
                            Padding(
                              padding: EdgeInsets.only(
                                top: isKeyboardOpen ? 10 : 16,
                                bottom: 8,
                              ),
                              child: Row(
                                children: [
                                  Text(
                                    'ADD MEMBERS',
                                    style: c
                                        .text(9, muted: true)
                                        .copyWith(letterSpacing: 1.2),
                                  ),
                                  const Spacer(),
                                  Text(
                                    '${_selectedFriends.length} / 99 selected',
                                    style: c.text(10, muted: true),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Expanded list of friends with edge-to-edge full width layout
                      Expanded(
                        child: _isLoading
                            ? Center(
                                child: CircularProgressIndicator(
                                  color: c.blue,
                                  strokeWidth: 2,
                                ),
                              )
                            : _loadError != null
                            ? Center(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 22),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        _loadError!,
                                        textAlign: TextAlign.center,
                                        style: c.text(12, muted: true),
                                      ),
                                      const SizedBox(height: 12),
                                      NotesButton(
                                        label: 'Try again',
                                        onPressed: _fetchFriendsList,
                                      ),
                                    ],
                                  ),
                                ),
                              )
                            : filtered.isEmpty
                            ? LayoutBuilder(
                                builder: (context, constraints) {
                                  final isCompact =
                                      constraints.maxHeight < 150 || isKeyboardOpen;
                                  return SingleChildScrollView(
                                    physics: const BouncingScrollPhysics(),
                                    child: ConstrainedBox(
                                      constraints: BoxConstraints(
                                        minHeight: constraints.maxHeight,
                                      ),
                                      child: Center(
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 22,
                                            vertical: 4,
                                          ),
                                          child: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              if (!isCompact) ...[
                                                const BackupSymbol(
                                                  icon: Icons.group_outlined,
                                                ),
                                                const SizedBox(height: 12),
                                              ] else ...[
                                                Icon(
                                                  Icons.search_off_rounded,
                                                  size: 20,
                                                  color: c.muted,
                                                ),
                                                const SizedBox(height: 4),
                                              ],
                                              Text(
                                                _friendsList.isEmpty
                                                    ? 'A group starts with friends'
                                                    : 'No matching friends',
                                                style: c.text(
                                                  isCompact ? 12 : 14,
                                                  bold: true,
                                                ),
                                              ),
                                              const SizedBox(height: 3),
                                              Text(
                                                _friendsList.isEmpty
                                                    ? 'Add friends first, then choose who\nyou’d like to bring together.'
                                                    : 'Try a different name or username.',
                                                textAlign: TextAlign.center,
                                                style: c
                                                    .text(
                                                      isCompact ? 10 : 12,
                                                      muted: true,
                                                    )
                                                    .copyWith(
                                                      height: isCompact ? 1.3 : 1.6,
                                                    ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              )
                            : ListView.builder(
                                itemCount: filtered.length,
                                padding: EdgeInsets.zero,
                                keyboardDismissBehavior:
                                    ScrollViewKeyboardDismissBehavior.onDrag,
                                itemBuilder: (_, index) {
                                  final friend = filtered[index];
                                  final checked = _selectedFriends
                                      .contains(friend.username);
                                  return Material(
                                    color: checked
                                        ? (neutralDark
                                            ? const Color(0xFF16A34A).withOpacity(0.12)
                                            : const Color(0xFF16A34A).withOpacity(0.08))
                                        : Colors.transparent,
                                    child: InkWell(
                                      onTap: () => _toggleFriend(friend),
                                      child: Container(
                                        width: double.infinity,
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 22,
                                          vertical: 13,
                                        ),
                                        decoration: BoxDecoration(
                                          border: Border(
                                            bottom: BorderSide(
                                              color: c.line,
                                              width: 0.5,
                                            ),
                                          ),
                                        ),
                                        child: Row(
                                          children: [
                                            _avatar(friend, c),
                                            const SizedBox(width: 12),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    friend
                                                        .displayNameOrUsername,
                                                    style: c.text(12, bold: checked),
                                                    maxLines: 1,
                                                    overflow: TextOverflow
                                                        .ellipsis,
                                                  ),
                                                  const SizedBox(
                                                    height: 3,
                                                  ),
                                                  Text(
                                                    '@${friend.username}',
                                                    style: c.text(
                                                      10,
                                                      muted: true,
                                                    ),
                                                    maxLines: 1,
                                                    overflow: TextOverflow
                                                        .ellipsis,
                                                  ),
                                                ],
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Container(
                                              width: 18,
                                              height: 18,
                                              decoration: BoxDecoration(
                                                shape: BoxShape.circle,
                                                color: checked
                                                    ? const Color(0xFF16A34A)
                                                    : Colors.transparent,
                                                border: Border.all(
                                                  color: checked
                                                      ? const Color(0xFF16A34A)
                                                      : c.line,
                                                  width: 1.4,
                                                ),
                                              ),
                                              child: checked
                                                  ? const Icon(
                                                      Icons.check,
                                                      color: Colors.white,
                                                      size: 12,
                                                    )
                                                  : null,
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                ),
                // Bottom continue bar
                Container(
                  padding: EdgeInsets.fromLTRB(
                    22,
                    isKeyboardOpen ? 8 : 14,
                    22,
                    isKeyboardOpen ? 6 : 10,
                  ),
                  decoration: BoxDecoration(
                    border: Border(top: BorderSide(color: c.line)),
                  ),
                  child: Column(
                    children: [
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: _canContinue ? _onContinue : null,
                          style: FilledButton.styleFrom(
                            backgroundColor: selectedSurface,
                            foregroundColor: selectedInk,
                            disabledBackgroundColor: c.soft,
                            disabledForegroundColor: c.muted,
                            minimumSize: const Size.fromHeight(46),
                            textStyle: c.text(13, bold: true),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text('Continue'),
                        ),
                      ),
                      if (!isKeyboardOpen) ...[
                        const SizedBox(height: 8),
                        Text(
                          _selectedFriends.isNotEmpty
                              ? '${_selectedFriends.length} friend${_selectedFriends.length > 1 ? 's' : ''} selected'
                              : 'Choose at least one friend to continue',
                          textAlign: TextAlign.center,
                          style: c.text(10, muted: true),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
}

// ─────────────────────────────────────────────────────────────────────────────
// STEP 2: GROUP DETAILS SCREEN (NAME MUST, PHOTO & DESCRIPTION OPTIONAL)
// ─────────────────────────────────────────────────────────────────────────────

class GroupDetailsScreen extends StatefulWidget {
  final WebSocketChannel channel;
  final VoidCallback onGroupCreated;
  final List<Friend> selectedFriends;

  const GroupDetailsScreen({
    super.key,
    required this.channel,
    required this.onGroupCreated,
    required this.selectedFriends,
  });

  @override
  State<GroupDetailsScreen> createState() => _GroupDetailsScreenState();
}

class _GroupDetailsScreenState extends State<GroupDetailsScreen> {
  final _groupNameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _nameFocusNode = FocusNode();
  final _descriptionFocusNode = FocusNode();
  File? _selectedImageFile;
  bool _isCreating = false;

  bool get _canCreate =>
      !_isCreating && _groupNameController.text.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    _groupNameController.addListener(_refresh);
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _groupNameController.dispose();
    _descriptionController.dispose();
    _nameFocusNode.dispose();
    _descriptionFocusNode.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    if (_isCreating) return;
    final c = NotesColors(context);
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: c.line,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 16),
                Text('Group photo', style: c.text(16, bold: true)),
                const SizedBox(height: 16),
                ListTile(
                  leading: Icon(Icons.photo_library_outlined, color: c.blue),
                  title: Text('Choose from Gallery', style: c.text(14)),
                  onTap: () => Navigator.pop(ctx, ImageSource.gallery),
                ),
                ListTile(
                  leading: Icon(Icons.camera_alt_outlined, color: c.blue),
                  title: Text('Take Photo', style: c.text(14)),
                  onTap: () => Navigator.pop(ctx, ImageSource.camera),
                ),
                if (_selectedImageFile != null)
                  ListTile(
                    leading: const Icon(Icons.delete_outline, color: Colors.red),
                    title: Text(
                      'Remove Photo',
                      style: c.text(14).copyWith(color: Colors.red),
                    ),
                    onTap: () {
                      Navigator.pop(ctx);
                      setState(() => _selectedImageFile = null);
                    },
                  ),
              ],
            ),
          ),
        );
      },
    );

    if (source == null) return;

    try {
      final ImagePicker picker = ImagePicker();
      final XFile? picked = await picker.pickImage(
        source: source,
        maxWidth: 600,
        maxHeight: 600,
        imageQuality: 80,
      );
      if (picked != null) {
        setState(() {
          _selectedImageFile = File(picked.path);
        });
      }
    } catch (e) {
      if (mounted) {
        OpaqueToast.error(context, 'Could not select photo');
      }
    }
  }

  Future<void> _createGroup() async {
    final name = _groupNameController.text.trim();
    if (name.isEmpty || _isCreating) return;

    setState(() => _isCreating = true);
    String? error;
    ConversationInfo? conversation;

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        error = 'Please sign in again before creating a group.';
      } else {
        final token = await user.getIdToken();

        // 1. Upload photo if selected
        String? avatarUrl;
        if (_selectedImageFile != null && _selectedImageFile!.existsSync()) {
          try {
            final avatarId = const Uuid().v4();
            final storageRef = FirebaseStorage.instance
                .ref()
                .child('group_avatars/$avatarId.jpg');
            final metadata = SettableMetadata(
              contentType: 'image/jpeg',
              cacheControl: 'public, max-age=31536000',
            );
            final uploadTask =
                storageRef.putFile(_selectedImageFile!, metadata);
            final snapshot = await uploadTask.whenComplete(() => {});
            avatarUrl = await snapshot.ref.getDownloadURL();
          } catch (e) {
            // Photo upload failure should not block group creation
          }
        }

        // 2. Call backend to create group
        final bodyData = <String, dynamic>{
          'groupName': name,
          'description': _descriptionController.text.trim(),
          'memberUsernames':
              widget.selectedFriends.map((f) => f.username).toList(),
        };
        if (avatarUrl != null) {
          bodyData['avatarUrl'] = avatarUrl;
        }

        final response = await http.post(
          Uri.parse('${AppConfig.baseUrl}/conversations/create-group'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
          body: json.encode(bodyData),
        );

        if (response.statusCode == 201) {
          final data = json.decode(response.body) as Map<String, dynamic>;
          final conversationId = data['conversationId'] as int;

          // If avatar was uploaded, update group avatar endpoint as well
          if (avatarUrl != null) {
            try {
              await http.post(
                Uri.parse(
                    '${AppConfig.baseUrl}/groups/$conversationId/avatar'),
                headers: {
                  'Content-Type': 'application/json',
                  'Authorization': 'Bearer $token',
                },
                body: json.encode({'avatarUrl': avatarUrl}),
              );
            } catch (_) {}
          }

          conversation = ConversationInfo(
            conversationId: conversationId,
            chatTitle: data['groupName'] as String,
            isGroup: true,
            creatorUid: data['creatorUid'] as String,
            avatarUrl: avatarUrl ?? data['avatarUrl'] as String?,
            partnerUid: null,
          );
        } else if (response.statusCode == 409) {
          error =
              'A group with this name already exists. Choose another name.';
        } else {
          error = 'Could not create group. Please try again in a moment.';
        }
      }
    } catch (_) {
      error =
          'Could not confirm group creation. Please check your connection.';
    } finally {
      if (mounted) setState(() => _isCreating = false);
    }

    if (!mounted) return;

    if (conversation != null) {
      widget.onGroupCreated();
      if (!mounted) return;
      // Navigate cleanly into the new group chat
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => ChatScreen(
            channel: widget.channel,
            conversationInfo: conversation!,
          ),
        ),
        (route) => route.isFirst,
      );
    } else {
      await showDialog<void>(
        context: context,
        builder: (ctx) => NotesDialog(
          title: 'Couldn’t create group',
          icon: Icons.group_outlined,
          body: Text(
            error ?? 'Please try again.',
            style: NotesColors(ctx).text(12, muted: true).copyWith(height: 1.8),
          ),
          actions: [
            NotesButton(
              label: 'Back',
              primary: true,
              onPressed: () => Navigator.pop(ctx),
            ),
          ],
        ),
      );
    }
  }

  Widget _memberAvatar({
    required String? avatarUrl,
    required String name,
    required NotesColors c,
  }) {
    final initials = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((s) => s.isNotEmpty)
        .take(2)
        .map((s) => s.characters.first.toUpperCase())
        .join();
    final fallback = Center(
      child: Text(
        initials.isEmpty ? '?' : initials,
        style: c.text(12, muted: true),
      ),
    );
    return Container(
      width: 38,
      height: 38,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(shape: BoxShape.circle, color: c.soft),
      child: avatarUrl?.isNotEmpty == true
          ? CachedNetworkImage(
              imageUrl: avatarUrl!,
              fit: BoxFit.cover,
              placeholder: (_, __) => fallback,
              errorWidget: (_, __, ___) => fallback,
            )
          : fallback,
    );
  }

  @override
  Widget build(BuildContext context) {
    context.watch<UserSettingsProvider>();
    final neutralDark = context.read<UserSettingsProvider>().isDarkMode;
    final selectedSurface = neutralDark ? const Color(0xFFE3E5E9) : const Color(0xFF303238);
    final selectedInk = neutralDark ? const Color(0xFF25272C) : const Color(0xFFF8F8FA);
    final c = NotesColors(context);

    return CallAwareScreen(
      screenName: 'GroupDetailsScreen',
      child: Stack(
        children: [
          Scaffold(
            backgroundColor: c.surface,
            appBar: AppBar(
              backgroundColor: c.surface,
              foregroundColor: c.ink,
              surfaceTintColor: Colors.transparent,
              elevation: 0,
              scrolledUnderElevation: 0,
              leading: IconButton(
                tooltip: 'Back',
                icon: const Icon(Icons.arrow_back, size: 20),
                onPressed: _isCreating ? null : () => Navigator.pop(context),
              ),
              title: Text('New group', style: c.text(18, bold: true)),
              centerTitle: true,
              bottom: PreferredSize(
                preferredSize: const Size.fromHeight(1),
                child: Divider(height: 1, color: c.line),
              ),
            ),
            body: SafeArea(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
                child: Column(
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                        keyboardDismissBehavior:
                            ScrollViewKeyboardDismissBehavior.onDrag,
                        padding: const EdgeInsets.fromLTRB(22, 24, 22, 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Group Photo Picker (Optional)
                            Center(
                              child: Stack(
                                children: [
                                  GestureDetector(
                                    onTap: _pickPhoto,
                                    child: Container(
                                      width: 96,
                                      height: 96,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: c.soft,
                                        border: Border.all(
                                          color: c.line,
                                          width: 1.5,
                                        ),
                                        image: _selectedImageFile != null
                                            ? DecorationImage(
                                                image: FileImage(
                                                  _selectedImageFile!,
                                                ),
                                                fit: BoxFit.cover,
                                              )
                                            : null,
                                      ),
                                      child: _selectedImageFile == null
                                          ? Icon(
                                              Icons.camera_alt_outlined,
                                              size: 34,
                                              color: c.muted,
                                            )
                                          : null,
                                    ),
                                  ),
                                  Positioned(
                                    bottom: 2,
                                    right: 2,
                                    child: GestureDetector(
                                      onTap: _pickPhoto,
                                      child: Container(
                                        width: 28,
                                        height: 28,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: c.blue,
                                          border: Border.all(
                                            color: c.surface,
                                            width: 2,
                                          ),
                                        ),
                                        child: const Icon(
                                          Icons.add_a_photo_rounded,
                                          size: 14,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 8),
                            Center(
                              child: Text(
                                _selectedImageFile != null
                                    ? 'Tap photo to change'
                                    : 'Group photo (optional)',
                                style: c.text(11, muted: true),
                              ),
                            ),
                            const SizedBox(height: 28),

                            // Group Name Input (Required / Must)
                            Row(
                              children: [
                                Text(
                                  'GROUP NAME',
                                  style: c
                                      .text(10, muted: true)
                                      .copyWith(letterSpacing: 1.2),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  '*',
                                  style: TextStyle(
                                    color: Colors.red[400],
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: _groupNameController,
                              focusNode: _nameFocusNode,
                              onTapOutside: (_) => _nameFocusNode.unfocus(),
                              enabled: !_isCreating,
                              maxLength: 50,
                              style: c.text(16, bold: true),
                              decoration: InputDecoration(
                                hintText: 'Enter group name',
                                hintStyle: c.text(16, muted: true),
                                isDense: true,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 14,
                                ),
                                filled: true,
                                fillColor: c.soft,
                                counterText: '',
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(color: c.line),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(color: c.line),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide:
                                      BorderSide(color: c.blue, width: 1.5),
                                ),
                              ),
                            ),
                            const SizedBox(height: 20),

                            // Description Input (Optional)
                            Text(
                              'DESCRIPTION',
                              style: c
                                  .text(10, muted: true)
                                  .copyWith(letterSpacing: 1.2),
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: _descriptionController,
                              focusNode: _descriptionFocusNode,
                              onTapOutside: (_) => _descriptionFocusNode.unfocus(),
                              enabled: !_isCreating,
                              minLines: 2,
                              maxLines: 4,
                              maxLength: 250,
                              style: c.text(13),
                              decoration: InputDecoration(
                                hintText: 'What’s this group about? (optional)',
                                hintStyle: c.text(13, muted: true),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 12,
                                ),
                                filled: true,
                                fillColor: c.soft,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(color: c.line),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(color: c.line),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide:
                                      BorderSide(color: c.blue, width: 1.5),
                                ),
                              ),
                            ),
                            const SizedBox(height: 24),

                            // Selected Members Preview (including current user "You")
                            Row(
                              children: [
                                Text(
                                  'MEMBERS',
                                  style: c
                                      .text(10, muted: true)
                                      .copyWith(letterSpacing: 1.2),
                                ),
                                const Spacer(),
                                Text(
                                  '${widget.selectedFriends.length + 1} members · including you',
                                  style: c.text(10, muted: true),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            SizedBox(
                              height: 62,
                              child: ListView.separated(
                                scrollDirection: Axis.horizontal,
                                itemCount: widget.selectedFriends.length + 1,
                                separatorBuilder: (_, __) =>
                                    const SizedBox(width: 10),
                                itemBuilder: (context, index) {
                                  if (index == 0) {
                                    final currentUser =
                                        FirebaseAuth.instance.currentUser;
                                    final myName = currentUser
                                                ?.displayName
                                                ?.trim()
                                                .isNotEmpty ==
                                            true
                                        ? currentUser!.displayName!
                                        : 'You';
                                    return Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        _memberAvatar(
                                          avatarUrl: currentUser?.photoURL,
                                          name: myName,
                                          c: c,
                                        ),
                                        const SizedBox(height: 4),
                                        SizedBox(
                                          width: 52,
                                          child: Text(
                                            'You',
                                            textAlign: TextAlign.center,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: c.text(10, bold: true),
                                          ),
                                        ),
                                      ],
                                    );
                                  }
                                  final friend =
                                      widget.selectedFriends[index - 1];
                                  return Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      _memberAvatar(
                                        avatarUrl: friend.avatarUrl,
                                        name: friend.displayNameOrUsername,
                                        c: c,
                                      ),
                                      const SizedBox(height: 4),
                                      SizedBox(
                                        width: 52,
                                        child: Text(
                                          friend.displayNameOrUsername
                                              .split(' ')
                                              .first,
                                          textAlign: TextAlign.center,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: c.text(10, muted: true),
                                        ),
                                      ),
                                    ],
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    // Bottom Create Group Bar
                    Container(
                      padding: const EdgeInsets.fromLTRB(22, 14, 22, 10),
                      decoration: BoxDecoration(
                        border: Border(top: BorderSide(color: c.line)),
                      ),
                      child: Column(
                        children: [
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton(
                              onPressed: _canCreate ? _createGroup : null,
                              style: FilledButton.styleFrom(
                                backgroundColor: selectedSurface,
                                foregroundColor: selectedInk,
                                disabledBackgroundColor: c.soft,
                                disabledForegroundColor: c.muted,
                                minimumSize: const Size.fromHeight(46),
                                textStyle: c.text(13, bold: true),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: _isCreating
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Text('Create group'),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _groupNameController.text.trim().isNotEmpty
                               ? 'You’ll be the group admin.'
                                : 'Group name is required to create group.',
                            textAlign: TextAlign.center,
                            style: c.text(10, muted: true),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (_isCreating) ...[
            const Positioned.fill(
              child: ModalBarrier(
                dismissible: false,
                color: Color(0x55101826),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Material(
                color: Colors.transparent,
                child: Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: c.surface,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(24),
                    ),
                  ),
                  child: SafeArea(
                    top: false,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const BackupSymbol(icon: Icons.group_outlined),
                        const SizedBox(height: 16),
                        Text(
                          'Creating your group…',
                          style: c.text(20, bold: true),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Bringing everyone together.',
                          style: c.text(12, muted: true),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(25),
                          child: Center(
                            child: SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                color: c.blue,
                                strokeWidth: 2,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
