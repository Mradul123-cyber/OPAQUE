import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
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
  final _groupNameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _searchController = TextEditingController();
  List<Friend> _friendsList = [];
  final Set<String> _selectedFriends = {};
  bool _isLoading = true;
  bool _isCreatingGroup = false;
  bool _descriptionOpen = false;
  bool _leaving = false;
  bool _askingToLeave = false;
  String? _loadError;
  bool get _canCreate =>
      !_isCreatingGroup &&
      !_descriptionOpen &&
      _groupNameController.text.trim().isNotEmpty &&
      _selectedFriends.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _groupNameController.addListener(_refresh);
    _searchController.addListener(_refresh);
    _fetchFriendsList();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _groupNameController.dispose();
    _descriptionController.dispose();
    _searchController.dispose();
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
      if (response.statusCode != 200)
        throw StateError('Could not load friends');
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
      if (mounted)
        setState(
          () => _loadError = 'Couldn’t load your friends. Please try again.',
        );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _leave() async {
    if (_isCreatingGroup || _askingToLeave) return;
    _askingToLeave = true;
    final changed =
        _groupNameController.text.isNotEmpty ||
        _selectedFriends.isNotEmpty ||
        _descriptionController.text.isNotEmpty;
    final discard =
        !changed ||
        await showNotesConfirmation(
          context,
          title: 'Discard this group?',
          body:
              'Your group hasn’t been created yet. Leave without keeping these details?',
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
    if (_isCreatingGroup) return;
    if (!_selectedFriends.contains(friend.username) &&
        _selectedFriends.length >= 99) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Maximum 100 members allowed, including you.'),
        ),
      );
      return;
    }
    setState(() {
      if (!_selectedFriends.remove(friend.username))
        _selectedFriends.add(friend.username);
    });
  }

  Future<void> _createGroup() async {
    if (!_canCreate) return;
    setState(() => _descriptionOpen = true);
    final description = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final c = NotesColors(sheetContext);
        return NotesSheet(
          title: 'Add a description',
          description: 'A little context for everyone. This is optional.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('DESCRIPTION', style: c.text(10, muted: true)),
              const SizedBox(height: 8),
              TextField(
                controller: _descriptionController,
                minLines: 3,
                maxLines: 5,
                style: c.text(12).copyWith(height: 1.8),
                decoration: c.field('What’s this group for?'),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: NotesButton(
                      label: 'Skip',
                      onPressed: () => Navigator.pop(sheetContext, ''),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: NotesButton(
                      label: 'Add & create',
                      primary: true,
                      onPressed: () => Navigator.pop(
                        sheetContext,
                        _descriptionController.text.trim(),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
    if (!mounted) return;
    setState(() => _descriptionOpen = false);
    if (description != null) await _createGroupWithDescription(description);
  }

  Future<void> _createGroupWithDescription(String description) async {
    if (_isCreatingGroup ||
        _selectedFriends.isEmpty ||
        _selectedFriends.length > 99 ||
        _groupNameController.text.trim().isEmpty)
      return;
    setState(() => _isCreatingGroup = true);
    String? error;
    ConversationInfo? conversation;
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        error = 'Please sign in again before creating a group.';
      } else {
        final token = await user.getIdToken();
        final response = await http.post(
          Uri.parse('${AppConfig.baseUrl}/conversations/create-group'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
          body: json.encode({
            'groupName': _groupNameController.text.trim(),
            'description': description,
            'memberUsernames': _selectedFriends.toList(),
          }),
        );
        if (response.statusCode == 201) {
          final data = json.decode(response.body) as Map<String, dynamic>;
          conversation = ConversationInfo(
            conversationId: data['conversationId'] as int,
            chatTitle: data['groupName'] as String,
            isGroup: true,
            creatorUid: data['creatorUid'] as String,
            partnerUid: null,
          );
        } else if (response.statusCode == 409) {
          error = 'A group with this name already exists. Choose another name.';
        } else {
          error =
              'Your name and selected members are still here. Please try again in a moment.';
        }
      }
    } catch (_) {
      error =
          'We couldn’t confirm whether the group was created. Check your conversations before trying again.';
    } finally {
      if (mounted) setState(() => _isCreatingGroup = false);
    }
    if (!mounted) return;
    if (conversation != null) {
      // Keep the existing callback and direct transition to the new group chat.
      widget.onGroupCreated();
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => ChatScreen(
            channel: widget.channel,
            conversationInfo: conversation!,
          ),
        ),
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
              label: 'Back to editing',
              primary: true,
              onPressed: () => Navigator.pop(ctx),
            ),
          ],
        ),
      );
    }
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
    return PopScope(
      canPop: _leaving,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _leave();
      },
      child: CallAwareScreen(
        screenName: 'CreateGroupScreen',
        child: Stack(
          children: [
            Scaffold(
              backgroundColor: c.surface,
              appBar: const BackupHeader(),
              body: SafeArea(
                child: Column(
                  children: [
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(22, 22, 22, 0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Create group',
                              style: c
                                  .text(22, bold: true)
                                  .copyWith(letterSpacing: -.6),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              'Bring your people together.',
                              style: c.text(12, muted: true),
                            ),
                            const SizedBox(height: 24),
                            Text(
                              'GROUP NAME',
                              style: c
                                  .text(9, muted: true)
                                  .copyWith(letterSpacing: 1.2),
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: _groupNameController,
                              enabled: !_isCreatingGroup,
                              style: c.text(19).copyWith(letterSpacing: -.35),
                              decoration: InputDecoration(
                                hintText: 'Give your group a name',
                                hintStyle: c.text(19, muted: true),
                                isDense: true,
                                contentPadding: const EdgeInsets.only(
                                  bottom: 12,
                                ),
                                enabledBorder: UnderlineInputBorder(
                                  borderSide: BorderSide(color: c.line),
                                ),
                                focusedBorder: UnderlineInputBorder(
                                  borderSide: BorderSide(color: c.blue),
                                ),
                              ),
                            ),
                            const SizedBox(height: 18),
                            SizedBox(
                              height: 36,
                              child: TextField(
                                controller: _searchController,
                                enabled: !_isCreatingGroup,
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
                            if (selected.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 12),
                                child: SingleChildScrollView(
                                  scrollDirection: Axis.horizontal,
                                  child: Row(
                                    children: [
                                      for (final friend in selected)
                                        Padding(
                                          padding: const EdgeInsets.only(
                                            right: 6,
                                          ),
                                          child: Semantics(
                                            label:
                                                'Remove ${friend.displayNameOrUsername}',
                                            button: true,
                                            child: InkWell(
                                              onTap: () =>
                                                  _toggleFriend(friend),
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                              child: Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 9,
                                                      vertical: 5,
                                                    ),
                                                decoration: BoxDecoration(
                                                  color: c.soft,
                                                  borderRadius:
                                                      BorderRadius.circular(12),
                                                ),
                                                child: Row(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  children: [
                                                    Text(
                                                      friend
                                                          .displayNameOrUsername
                                                          .split(' ')
                                                          .first,
                                                      style: c
                                                          .text(10)
                                                          .copyWith(
                                                            color: c.blue,
                                                          ),
                                                    ),
                                                    const SizedBox(width: 6),
                                                    Icon(
                                                      Icons.close,
                                                      size: 11,
                                                      color: c.blue,
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
                            Padding(
                              padding: const EdgeInsets.only(
                                top: 21,
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
                                    '${_selectedFriends.length + 1} / 100 · including you',
                                    style: c.text(10, muted: true),
                                  ),
                                ],
                              ),
                            ),
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
                                    )
                                  : filtered.isEmpty
                                  ? Center(
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const BackupSymbol(
                                            icon: Icons.group_outlined,
                                          ),
                                          const SizedBox(height: 15),
                                          Text(
                                            _friendsList.isEmpty
                                                ? 'A group starts with friends'
                                                : 'No matching friends',
                                            style: c.text(14, bold: true),
                                          ),
                                          const SizedBox(height: 8),
                                          Text(
                                            _friendsList.isEmpty
                                                ? 'Add friends first, then choose who\nyou’d like to bring together.'
                                                : 'Try a different name or username.',
                                            textAlign: TextAlign.center,
                                            style: c
                                                .text(12, muted: true)
                                                .copyWith(height: 1.8),
                                          ),
                                        ],
                                      ),
                                    )
                                  : ListView.builder(
                                      itemCount: filtered.length,
                                      itemBuilder: (_, index) {
                                        final friend = filtered[index];
                                        final checked = _selectedFriends
                                            .contains(friend.username);
                                        return Semantics(
                                          button: true,
                                          selected: checked,
                                          child: InkWell(
                                            onTap: () => _toggleFriend(friend),
                                            child: Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    vertical: 14,
                                                  ),
                                              decoration: BoxDecoration(
                                                border: Border(
                                                  bottom: BorderSide(
                                                    color: c.line,
                                                  ),
                                                ),
                                              ),
                                              child: Row(
                                                children: [
                                                  _avatar(friend, c),
                                                  const SizedBox(width: 11),
                                                  Expanded(
                                                    child: Column(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .start,
                                                      children: [
                                                        Text(
                                                          friend
                                                              .displayNameOrUsername,
                                                          style: c.text(12),
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
                                                    width: 17,
                                                    height: 17,
                                                    decoration: BoxDecoration(
                                                      shape: BoxShape.circle,
                                                      color: checked
                                                          ? const Color(
                                                              0xFF507FC3,
                                                            )
                                                          : Colors.transparent,
                                                      border: Border.all(
                                                        color: checked
                                                            ? const Color(
                                                                0xFF507FC3,
                                                              )
                                                            : c.line,
                                                        width: 1.3,
                                                      ),
                                                    ),
                                                    child: checked
                                                        ? const Icon(
                                                            Icons.check,
                                                            color: Colors.white,
                                                            size: 11,
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
                    ),
                    Container(
                      padding: const EdgeInsets.fromLTRB(22, 14, 22, 10),
                      decoration: BoxDecoration(
                        border: Border(top: BorderSide(color: c.line)),
                      ),
                      child: Column(
                        children: [
                          SizedBox(
                            width: double.infinity,
                            child: NotesButton(
                              label: 'Create group',
                              primary: true,
                              onPressed: _canCreate ? _createGroup : null,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _groupNameController.text.trim().isNotEmpty &&
                                    _selectedFriends.isNotEmpty
                                ? '${_selectedFriends.length + 1} members · You’ll be the group admin.'
                                : 'Add a name and choose at least one friend.',
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
            if (_isCreatingGroup) ...[
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
      ),
    );
  }
}
