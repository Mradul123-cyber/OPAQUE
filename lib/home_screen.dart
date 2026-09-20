import 'models/home_chat_order.dart';
import 'widgets/opaque_chat_surfaces.dart';
import 'package:zarq_messenger/screens/backup_management_screen.dart';
import 'widgets/opaque_navigation.dart';
import 'widgets/opaque_toast.dart';
import 'widgets/home_logout_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'dart:async';
import 'dart:ui';
import 'dart:convert';

import 'package:zarq_messenger/providers/home_provider.dart';
import 'package:zarq_messenger/services/websocket_service.dart';
import 'package:zarq_messenger/services/user_settings_provider.dart';
import 'package:zarq_messenger/services/database_service.dart';
import 'package:zarq_messenger/services/SignalService.dart';
import 'package:zarq_messenger/services/navigation_handler.dart';

// Import Screens and Widgets
import 'package:zarq_messenger/login_screen.dart';
import 'package:zarq_messenger/setting_screen.dart';
import 'package:zarq_messenger/find_friends_screen.dart';
import 'package:zarq_messenger/chat_screen.dart';
import 'package:zarq_messenger/create_group_screen.dart';
import 'package:zarq_messenger/screens/notes_screen.dart';
import 'package:zarq_messenger/about_screen.dart';
import 'package:zarq_messenger/screens/call_history_screen.dart';
import 'package:zarq_messenger/screens/style_screen.dart';
import 'package:zarq_messenger/widgets/call_aware_screen.dart';

import 'package:zarq_messenger/app_config.dart';
import 'package:zarq_messenger/widgets/opaque_header.dart';
import 'models/chat_payloads.dart';

// ─── Brand Colours ────────────────────────────────────────────────────────────






const Color _kDivider = Color(0xFFEEEEF4);
const Color _kOnlineGreen = Color(0xFF22C55E);
// ─────────────────────────────────────────────────────────────────────────────

class ConversationInfo {
  final int conversationId;
  final String chatTitle;
  final bool isGroup;
  final String? creatorUid;
  final String? avatarUrl;
  final String? partnerUid;
  final bool isFriend;
  final bool hasUnreadMessages;
  final DateTime? lastMessageTimestamp;
  final int unreadCount;
  final String? lastMessage;
  final bool isTyping;
  final bool isOnline;

  ConversationInfo({
    required this.conversationId,
    required this.chatTitle,
    required this.isGroup,
    this.creatorUid,
    this.avatarUrl,
    this.partnerUid,
    this.isFriend = false,
    this.hasUnreadMessages = false,
    this.lastMessageTimestamp,
    this.unreadCount = 0,
    this.lastMessage,
    this.isTyping = false,
    this.isOnline = false,
  });

  factory ConversationInfo.fromJson(Map<String, dynamic> json) {
    return ConversationInfo(
      conversationId: json['conversationId'] as int,
      chatTitle: json['chatTitle'] ?? 'Unknown',
      isGroup: json['isGroup'],
      creatorUid: json['creatorUid'] as String?,
      avatarUrl: json['avatarUrl'] as String?,
      partnerUid: json['partnerUid'] as String?,
      isFriend: json['isFriend'] == true,
      lastMessageTimestamp: json['lastMessageTimestamp'] != null
          ? DateTime.parse(json['lastMessageTimestamp'] as String)
          : null,
      lastMessage: json['lastMessage'] as String?,
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  bool _isChatSelectionMode = false;
  Set<String> _pinnedChats = {};
  Map<String, int> _hiddenChats = {};
  bool _selectionBusy = false;
  String get _homePreferenceKey => 'opaque_home_${FirebaseAuth.instance.currentUser?.uid}';
  final Map<int, ConversationInfo> _selectedChats = {};
  ConversationInfo? get _selectedConversation =>
      _selectedChats.length == 1 ? _selectedChats.values.single : null;

  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  String _conversationFilter = 'All';
  bool _isSearching = false;
  final Set<String> _blockedUsers = {};

  // Bottom nav index: 0=Chats, 1=Calls, 2=Friends, 3=Style, 4=Notes
  int _currentNavIndex = 0;
  int _friendsOpenRequest = 0;
  FriendTab _friendsInitialTab = FriendTab.myFriends;
  bool _addMenuOpen = false;

  StreamSubscription? _websocketSubscription;

  // ─── Lifecycle ─────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeUser();
    _loadBlockedUsers();
    _loadHomeSelectionPreferences();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _checkPendingNavigation();

      final homeProvider = Provider.of<HomeProvider>(context, listen: false);
      if (homeProvider.conversations.isEmpty) {
        homeProvider.fetchInitialConversations();
      }

      final websocketService = Provider.of<WebSocketService>(
        context,
        listen: false,
      );
      _websocketSubscription = websocketService.stream.listen((data) {
        if (!mounted) return;
        if (data is Map<String, dynamic>) {
          if (data['type'] == 'conversation_update') {
            Provider.of<HomeProvider>(
              context,
              listen: false,
            ).fetchInitialConversations();
          } else if (data['type'] == 'group_deleted') {
            final conversationId = data['conversationId'];
            if (conversationId != null) {
              Provider.of<HomeProvider>(
                context,
                listen: false,
              ).removeConversation(conversationId);
            }
          }
        }
      });
    });

    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _websocketSubscription?.cancel();
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  // ─── Search ────────────────────────────────────────────────────────────────

  void _onSearchChanged() {
    setState(() { _isSearching = _searchController.text.trim().isNotEmpty; _addMenuOpen = false; });
  }

  // ─── Blocked users ─────────────────────────────────────────────────────────

  Future<void> _loadBlockedUsers() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final blockedUsers = prefs.getStringList('blocked_users') ?? [];
      setState(() {
        _blockedUsers.clear();
        _blockedUsers.addAll(blockedUsers);
      });
    } catch (_) {}
  }

  // ─── Navigation helpers ────────────────────────────────────────────────────

  Future<void> _checkPendingNavigation() async {
    final targetConversationId = NavigationHandler.getPendingConversationId();
    if (targetConversationId != null) {
      final homeProvider = Provider.of<HomeProvider>(context, listen: false);
      if (homeProvider.conversations.isEmpty) {
        await homeProvider.fetchInitialConversations();
      }
      await Future.delayed(const Duration(milliseconds: 300));
      await _openConversationById(targetConversationId);
    }
  }

  Future<void> _openConversationById(int conversationId) async {
    try {
      if (!mounted) return;
      final homeProvider = Provider.of<HomeProvider>(context, listen: false);
      final websocketService = Provider.of<WebSocketService>(
        context,
        listen: false,
      );

      if (!websocketService.isConnected || websocketService.channel == null) {
        if (mounted) {
          OpaqueToast.info(context, 'Still connecting… Please wait a moment.');
        }
        return;
      }

      final targetConversation = homeProvider.conversations.firstWhere(
        (convo) => convo.conversationId == conversationId,
        orElse: () => throw Exception('Conversation not found'),
      );

      if (mounted) _navigateToChat(targetConversation);
    } catch (e) {
      if (e.toString().contains('Conversation not found')) {
        try {
          final homeProvider = Provider.of<HomeProvider>(
            context,
            listen: false,
          );
          await homeProvider.fetchInitialConversations();
          final refreshedConvo = homeProvider.conversations.firstWhere(
            (convo) => convo.conversationId == conversationId,
          );
          if (mounted) _navigateToChat(refreshedConvo);
        } catch (_) {
          if (mounted) {
            OpaqueToast.warning(context, 'Conversation not found or no longer exists');
          }
        }
      }
    }
  }

  Future<void> _initializeUser() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      await user.reload();
      if (!mounted) return;
    }
  }

  Future<void> _refreshUserData() async => _initializeUser();

  // ─── Logout ────────────────────────────────────────────────────────────────

  void _showLogoutDialog(BuildContext context) async {
    final isDark = context.read<UserSettingsProvider>().isDarkMode;
    final confirmed = await showDialog<bool>(
      context: context,
      barrierColor: const Color(0x650B101A),
      builder: (_) => HomeLogoutDialog(isDark: isDark),
    );
    if (confirmed == true && mounted) {
      await _performLogout(clearData: false);
    }
  }

  Future<void> _performLogout({required bool clearData}) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        try {
          final token = await user.getIdToken();
          final url = Uri.parse('${AppConfig.baseUrl}/v1/fcm/token');
          await http.post(
            url,
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
            },
            body: json.encode({'fcm_token': '', 'device_id': 1}),
          );
        } catch (_) {}
      }

      if (clearData) {
        await SignalService.resetUserContext();
        final dbService = Provider.of<DatabaseService>(context, listen: false);
        await dbService.resetDatabase();
      } else {
        await SignalService.resetUserContext();
      }

      final websocketService = Provider.of<WebSocketService>(
        context,
        listen: false,
      );
      websocketService.disconnect();

      await FirebaseAuth.instance.signOut();
    } catch (_) {}

    if (context.mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => const LoginScreen()),
        (Route<dynamic> route) => false,
      );
    }
  }

  // ─── Chat selection ───────────────────────────────────────────────────────

  void _enterChatSelectionMode(ConversationInfo conversation) {
    setState(() {
      if (_selectedChats.containsKey(conversation.conversationId)) {
        _selectedChats.remove(conversation.conversationId);
      } else {
        _selectedChats[conversation.conversationId] = conversation;
      }
      _isChatSelectionMode = _selectedChats.isNotEmpty;
    });
  }

  void _exitChatSelectionMode() {
    if (!mounted) return;
    setState(() {
      _isChatSelectionMode = false;
      _selectedChats.clear();
    });
  }

  Future<void> _showGroupActionDialog({required String action}) async {
    final conversation = _selectedConversation;
    if (conversation == null || _selectionBusy) return;
    final deleting = action == 'delete';
    final confirmed = await _confirmHomeAction(
      deleting ? 'Delete group?' : 'Leave group?',
      deleting ? 'Permanently delete “${conversation.chatTitle}” for all members.'
        : 'Leave “${conversation.chatTitle}” and stop participating in this group.',
      deleting ? 'This cannot be undone.' : 'You will need an invitation to join again.',
      deleting ? 'Delete group' : 'Leave group',
      deleting ? Icons.delete_outline : Icons.logout_rounded);
    if (!mounted || !confirmed) return;
    setState(() => _selectionBusy = true);
    try {
      if (deleting) { await _deleteGroup(conversation.conversationId); }
      else { await _leaveGroup(conversation.conversationId); }
    } finally {
      if (mounted) { setState(() => _selectionBusy = false); _exitChatSelectionMode(); }
    }
  }

  Future<bool> _confirmHomeAction(String title, String description, String note,
      String label, IconData icon) async => await showDialog<bool>(context: context,
    builder: (ctx) => OpaqueChatConfirmation(icon: icon, title: title,
      description: description, note: note, actionLabel: label,
      onConfirm: () => Navigator.pop(ctx, true))) ?? false;

  Future<void> _loadHomeSelectionPreferences() async {
    final key = _homePreferenceKey;
    final prefs = await SharedPreferences.getInstance();
    try {
      final hidden = jsonDecode(prefs.getString('${key}_hidden') ?? '{}') as Map<String, dynamic>;
      if (!mounted || key != _homePreferenceKey) return;
      setState(() {
        _pinnedChats = (prefs.getStringList('${key}_pins') ?? []).toSet();
        _hiddenChats = hidden.map((k, v) => MapEntry(k, (v as num).toInt()));
      });
    } catch (_) { /* Ignore malformed local preferences. */ }
  }

  Future<void> _toggleSelectedPin() async {
    if (_selectedChats.isEmpty || _selectionBusy) return;
    final ids = _selectedChats.keys.map((id) => '$id').toSet();
    final unpin = ids.every(_pinnedChats.contains);
    final pins = {..._pinnedChats};
    if (unpin) { pins.removeAll(ids); } else { pins.addAll(ids); }
    setState(() => _selectionBusy = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList('${_homePreferenceKey}_pins', pins.toList());
      if (!mounted) return;
      setState(() => _pinnedChats = pins);
      _showSnack('${ids.length} ${ids.length == 1 ? 'chat' : 'chats'} ${unpin ? 'unpinned' : 'pinned'}');
      _exitChatSelectionMode();
    } catch (_) { if (mounted) _showSnack('Could not update pin', isError: true); }
    finally { if (mounted) setState(() => _selectionBusy = false); }
  }

  Future<void> _deleteSelectedChat() async {
    if (_selectedChats.isEmpty || _selectionBusy) return;
    final selected = _selectedChats.values.toList();
    final label = selected.length == 1 ? 'Delete chat' : 'Delete ${selected.length} chats';
    final names = selected.map((chat) => '• ${chat.chatTitle}').join('\n');
    if (!await _confirmHomeAction('$label?',
      'Delete the saved message history on this device for:\n$names',
      'Other people keep their copies. Chats return when newer messages arrive. This does not remove friends, leave groups or delete groups.',
      label, Icons.delete_outline)) { return; }
    if (!mounted) return;
    setState(() => _selectionBusy = true);
    final completed = <int>{};
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final conversation in selected) {
        await DatabaseService.deleteAllMessagesInConversation(conversation.conversationId);
        final hidden = {..._hiddenChats, '${conversation.conversationId}':
          conversation.lastMessageTimestamp?.millisecondsSinceEpoch ?? 0};
        if (!await prefs.setString('${_homePreferenceKey}_hidden', jsonEncode(hidden))) {
          throw StateError('Could not save chat visibility');
        }
        _hiddenChats = hidden;
        completed.add(conversation.conversationId);
      }
      if (mounted) { _showSnack('${completed.length} ${completed.length == 1 ? 'chat deleted' : 'chats deleted'} from this device'); }
    } catch (_) {
      if (mounted) _showSnack('Deleted ${completed.length} of ${selected.length} chats. Please retry the remaining selection.', isError: true);
    } finally {
      if (mounted) { setState(() {
        _selectedChats.removeWhere((id, _) => completed.contains(id));
        _isChatSelectionMode = _selectedChats.isNotEmpty;
        _selectionBusy = false;
      }); }
    }
  }

  Future<void> _toggleSelectedBlock() async {
    final conversation = _selectedConversation;
    final uid = conversation?.partnerUid;
    if (_selectionBusy || conversation == null || conversation.isGroup || uid == null || uid.isEmpty) return;
    final unblock = _blockedUsers.contains(uid);
    final action = unblock ? 'Unblock friend' : 'Block friend';
    if (!await _confirmHomeAction('$action?',
      unblock ? 'Allow messages from ${conversation.chatTitle} to appear in this chat again.'
        : 'Hide messages from ${conversation.chatTitle} in this chat and prevent sending messages to them on this device.',
      'Your saved chat history is kept. You can change this from the chat menu anytime.',
      action, unblock ? Icons.do_not_disturb_off_rounded : Icons.block_rounded)) { return; }
    if (!mounted) return;
    setState(() => _selectionBusy = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final blocked = (prefs.getStringList('blocked_users') ?? []).toSet();
      if (unblock) { blocked.remove(uid); } else { blocked.add(uid); }
      if (!await prefs.setStringList('blocked_users', blocked.toList())) {
        throw StateError('Could not save blocked users');
      }
      if (!mounted) return;
      setState(() { _blockedUsers.clear(); _blockedUsers.addAll(blocked); });
      _showSnack(unblock ? 'Friend unblocked' : 'Friend blocked');
      _exitChatSelectionMode();
    } catch (_) {
      if (mounted) _showSnack('Could not update blocking. Please try again.', isError: true);
    } finally {
      if (mounted) setState(() => _selectionBusy = false);
    }
  }

  Future<void> _removeSelectedFriend() async {
    final conversation = _selectedConversation;
    final uid = conversation?.partnerUid;
    if (_selectionBusy || conversation == null || conversation.isGroup) return;
    if (uid == null || uid.isEmpty) {
      _showSnack('Refresh your chats and try again.', isError: true);
      return;
    }
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    if (!await _confirmHomeAction('Remove friend?',
      'Remove ${conversation.chatTitle} from your friends?',
      'This does not delete saved messages or block this person.',
      'Remove friend', Icons.person_remove_outlined)) { return; }
    if (!mounted) return;
    setState(() => _selectionBusy = true);
    try {
      final token = await user.getIdToken();
      final result = await http.post(Uri.parse('${AppConfig.baseUrl}/friends/remove'),
        headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'},
        body: jsonEncode({'targetUid': uid}));
      if (!mounted) return;
      if (result.statusCode == 404 && result.body.trim() == 'Friendship not found') {
        context.read<HomeProvider>().markFriendRemoved(uid);
        _showSnack('This person is no longer in your friends.');
        _exitChatSelectionMode();
        return;
      }
      if (result.statusCode != 200) {
        _showSnack('Could not remove friend. Please try again.', isError: true);
        return;
      }
      context.read<HomeProvider>().markFriendRemoved(uid);
      setState(() => _friendsOpenRequest++);
      _showSnack('Friend removed');
      _exitChatSelectionMode();
      context.read<HomeProvider>().fetchInitialConversations();
    } catch (_) { if (mounted) _showSnack('Could not remove friend', isError: true); }
    finally { if (mounted) setState(() => _selectionBusy = false); }
  }

  Future<void> _deleteGroup(int conversationId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final token = await user.getIdToken();
    try {
      final response = await http.delete(
        Uri.parse('${AppConfig.baseUrl}/groups/$conversationId/delete'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (mounted) {
        if (response.statusCode == 200) {
          _showSnack('Group deleted successfully!');
          Provider.of<HomeProvider>(
            context,
            listen: false,
          ).fetchInitialConversations();
        } else {
          _showSnack('Failed to delete group', isError: true);
        }
      }
    } catch (e) {
      if (mounted) _showSnack('Error: $e', isError: true);
    }
  }

  Future<void> _leaveGroup(int conversationId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final token = await user.getIdToken();
    try {
      final response = await http.post(
        Uri.parse('${AppConfig.baseUrl}/groups/$conversationId/leave'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (mounted) {
        if (response.statusCode == 200) {
          _showSnack('Successfully left group!');
          Provider.of<HomeProvider>(
            context,
            listen: false,
          ).fetchInitialConversations();
        } else {
          _showSnack('Failed to leave group', isError: true);
        }
      }
    } catch (e) {
      if (mounted) _showSnack('Error: $e', isError: true);
    }
  }

  void _showSnack(String msg, {bool isError = false}) {
    if (isError) {
      OpaqueToast.error(context, msg);
    } else {
      OpaqueToast.info(context, msg);
    }
  }

  // ─── Chat navigation ───────────────────────────────────────────────────────

  void _navigateToChat(ConversationInfo convo) async {
    final websocketService = Provider.of<WebSocketService>(
      context,
      listen: false,
    );
    WebSocketChannel? channel = websocketService.channel;

    if (channel == null) {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        try {
          final token = await user.getIdToken();
          if (!mounted) return;
          await websocketService.connect(token);
          if (!mounted) return;
          channel = websocketService.channel;
        } catch (_) {}
      }
    }

    Provider.of<HomeProvider>(
      context,
      listen: false,
    ).markConversationAsRead(convo.conversationId);

    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (context) =>
                ChatScreen(channel: channel, conversationInfo: convo),
          ),
        )
        .then((_) => _loadBlockedUsers());

    if (channel == null) {
      _showSnack('📴 Offline mode — Viewing cached messages', isError: false);
    }
  }

  // ─── Avatar ────────────────────────────────────────────────────────────────

  Widget _buildAvatar(ConversationInfo convo, bool isDark, Color cardColor) {
    final words = convo.chatTitle.trim().split(RegExp(r'\s+')).where((s) => s.isNotEmpty).take(2);
    final initials = words.map((s) => s.characters.first.toUpperCase()).join();
    final radius = BorderRadius.circular(convo.isGroup ? 13 : 22);
    final fallback = Center(child: Text(initials.isEmpty ? '?' : initials, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w500, color: isDark ? const Color(0xFFBCC7D8) : const Color(0xFF4C4F58))));
    return Stack(children: [
      Container(width: 44, height: 44, clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(borderRadius: radius, border: Border.all(color: isDark ? const Color(0xFF354256) : const Color(0xFFE6E7ED)),
          gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: isDark ? const [Color(0xFF303947), Color(0xFF283241)] : const [Color(0xFFF5F5F7), Color(0xFFE5E6EB)])),
        child: convo.avatarUrl != null && convo.avatarUrl!.isNotEmpty ? CachedNetworkImage(imageUrl: convo.avatarUrl!, fit: BoxFit.cover, placeholder: (_, _) => fallback, errorWidget: (_, _, _) => fallback) : fallback),
      if (convo.isOnline && !convo.isGroup) Positioned(right: 0, bottom: 0, child: Semantics(label: 'Online', child: Container(width: 9, height: 9,
        decoration: BoxDecoration(shape: BoxShape.circle, color: _kOnlineGreen, border: Border.all(color: cardColor, width: 2))))),
    ]);
  }
  // ─── Timestamp ─────────────────────────────────────────────────────────────

  String _formatTimestamp(DateTime timestamp) {
    final now = DateTime.now();
    final difference = now.difference(timestamp);
    if (difference.inDays == 0) {
      final h = timestamp.hour;
      final m = timestamp.minute.toString().padLeft(2, '0');
      final suffix = h >= 12 ? 'PM' : 'AM';
      final hour = h > 12 ? h - 12 : (h == 0 ? 12 : h);
      return '$hour:$m $suffix';
    } else if (difference.inDays < 7) {
      return [
        'Mon',
        'Tue',
        'Wed',
        'Thu',
        'Fri',
        'Sat',
        'Sun',
      ][timestamp.weekday - 1];
    } else {
      return '${timestamp.day}/${timestamp.month}/${timestamp.year % 100}';
    }
  }

  // ─── AppBar ────────────────────────────────────────────────────────────────

  PreferredSizeWidget _buildAppBar(
    bool isDark,
    Color cardColor,
    Color textColor,
  ) {
    final user = FirebaseAuth.instance.currentUser;
    final bool isCreatorOfSelectedGroup =
        _isChatSelectionMode &&
        _selectedConversation != null &&
        _selectedConversation!.creatorUid == user?.uid;

    if (_isChatSelectionMode) {
      final selected = _selectedConversation;
      final canRemoveFriend = selected != null && !selected.isGroup &&
        context.watch<HomeProvider>().conversations.any((chat) =>
          chat.conversationId == selected.conversationId && chat.isFriend);
      final pinned = _selectedChats.keys.every((id) => _pinnedChats.contains('$id'));
      return AppBar(
        backgroundColor: isDark ? const Color(0xFF19202A) : Colors.white,
        foregroundColor: textColor, surfaceTintColor: Colors.transparent,
        elevation: 0, toolbarHeight: 60, titleSpacing: 0,
        leading: IconButton(tooltip: 'Cancel selection', icon: const Icon(Icons.close_rounded, size: 21),
          onPressed: _selectionBusy ? null : _exitChatSelectionMode),
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${_selectedChats.length} selected', style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w600)),
          Text(selected?.chatTitle ?? 'Tap chats to add or remove', maxLines: 1, overflow: TextOverflow.ellipsis,
            style: GoogleFonts.inter(fontSize: 11, color: isDark ? const Color(0xFF97A3B6) : const Color(0xFF73747C))),
        ]),
        actions: [
          if (_selectionBusy) const Padding(padding: EdgeInsets.all(16),
            child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)))
          else ...[
            if (selected != null && !selected.isGroup)
              IconButton(
                tooltip: _blockedUsers.contains(selected.partnerUid) ? 'Unblock friend' : 'Block friend',
                icon: Icon(_blockedUsers.contains(selected.partnerUid)
                  ? Icons.do_not_disturb_off_rounded : Icons.block_rounded, size: 20),
                onPressed: selected.partnerUid == null || selected.partnerUid!.isEmpty
                  ? null : _toggleSelectedBlock),
            IconButton(tooltip: pinned ? 'Unpin selected chats' : 'Pin selected chats',
              icon: Icon(pinned ? Icons.push_pin : Icons.push_pin_outlined, size: 20), onPressed: _toggleSelectedPin),
            PopupMenuButton<String>(tooltip: 'Selected chat actions',
              color: isDark ? const Color(0xFF19202A) : Colors.white,
              surfaceTintColor: Colors.transparent,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              icon: const Icon(Icons.more_vert_rounded, size: 21),
              onSelected: (action) {
                if (action == 'open' && selected != null) { _exitChatSelectionMode(); _navigateToChat(selected); }
                if (action == 'remove') _removeSelectedFriend();
                if (action == 'chat_delete') _deleteSelectedChat();
                if (action == 'delete' || action == 'leave') _showGroupActionDialog(action: action);
              },
              itemBuilder: (_) => [
                if (selected != null) _popupItem(value: 'open', icon: Icons.chat_bubble_outline, label: 'Open chat', color: textColor, textColor: textColor),
                if (canRemoveFriend) ...[
                  _popupItem(value: 'remove', icon: Icons.person_remove_outlined, label: 'Remove friend', color: textColor, textColor: textColor),
                ],
                _popupItem(value: 'chat_delete', icon: Icons.delete_outline, label: _selectedChats.length == 1 ? 'Delete chat' : 'Delete chats', color: const Color(0xFFCE7480), textColor: textColor),
                if (selected != null && selected.isGroup)
                  _popupItem(value: isCreatorOfSelectedGroup ? 'delete' : 'leave',
                    icon: isCreatorOfSelectedGroup ? Icons.delete_outline : Icons.logout_rounded,
                    label: isCreatorOfSelectedGroup ? 'Delete group' : 'Leave group',
                    color: const Color(0xFFCE7480), textColor: textColor),
              ]),
          ],
        ],
      );
    }

    return OpaqueHeader(
      isDark: isDark,
      profile: user?.photoURL != null
          ? CachedNetworkImage(
              imageUrl: user!.photoURL!,
              fit: BoxFit.cover,
              errorWidget: (_, __, ___) =>
                  _buildDefaultUserAvatar(user, isDark, textColor),
            )
          : _buildDefaultUserAvatar(user, isDark, textColor),
      onProfile: () async {
        final result = await Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const SettingsScreen()));
        if (result == 'open_style') {
          if (mounted) setState(() => _currentNavIndex = 3);
        } else if (mounted) {
          _refreshUserData();
        }
      },
      menuItems: [
        _popupItem(
          textColor: textColor,
          value: 'settings',
          icon: Icons.tune_rounded,
          label: 'Settings',
          color: isDark ? const Color(0xFFA0ADBF) : const Color(0xFF7B808B),
        ),
        _popupItem(
          textColor: textColor,
          value: 'backup_restore',
          icon: Icons.backup_outlined,
          label: 'Backup / Restore',
          color: isDark ? const Color(0xFFA0ADBF) : const Color(0xFF7B808B),
        ),
        _popupItem(
          textColor: textColor,
          value: 'about',
          icon: Icons.info_outline_rounded,
          label: 'About',
          color: isDark ? const Color(0xFFA0ADBF) : const Color(0xFF7B808B),
        ),
        const PopupMenuDivider(),
        _popupItem(
          textColor: isDark ? const Color(0xFFE09A9D) : const Color(0xFFB54D52),
          value: 'logout',
          icon: Icons.logout_rounded,
          label: 'Log out',
          color: isDark ? const Color(0xFFE09A9D) : const Color(0xFFB54D52),
        ),
      ],
      onMenuSelected: (result) async {
        if (result == 'logout') {
          _showLogoutDialog(context);
        } else if (result == 'settings') {
          final res = await Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => const SettingsScreen()));
          if (res == 'open_style') {
            if (mounted) setState(() => _currentNavIndex = 3);
          } else if (mounted) {
            _refreshUserData();
          }
        } else if (result == 'backup_restore') {
          Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => const BackupManagementScreen()));
        } else if (result == 'about') {
          Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => const AboutScreen()));
        }
      },
    );
  }

  Widget _buildDefaultUserAvatar(User? user, bool isDark, Color textColor) {
    final initial = (user?.displayName?.isNotEmpty == true)
        ? user!.displayName![0].toUpperCase()
        : (user?.email?.isNotEmpty == true)
        ? user!.email![0].toUpperCase()
        : 'U';
    return Container(
      color: isDark ? Colors.white10 : Colors.black.withOpacity(0.15),
      child: Center(
        child: Text(
          initial,
          style: GoogleFonts.poppins(
            color: isDark ? Colors.white : Colors.black,
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
      ),
    );
  }

  PopupMenuItem<String> _popupItem({
    required String value,
    required IconData icon,
    required String label,
    required Color color,
    required Color textColor,
  }) {
    return PopupMenuItem<String>(
      value: value,
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 11),
      child: Row(
        children: [
          Icon(icon, color: color, size: 19),
          const SizedBox(width: 12),
          Expanded(child: Text(
            label,
            style: GoogleFonts.inter(color: textColor, fontSize: 13, fontWeight: FontWeight.w500),
          )),
        ],
      ),
    );
  }

  // ─── Search Bar ────────────────────────────────────────────────────────────

  Widget _buildSearchBar(bool isDark, Color cardColor, Color textColor, Color textGreyColor) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
    child: SizedBox(height: 36, child: TextField(
      key: const ValueKey('home_search_bar'), controller: _searchController, focusNode: _searchFocusNode,
      onTapOutside: (_) => _searchFocusNode.unfocus(),
      onTap: () {
        if (!_searchFocusNode.hasFocus) {
          _searchFocusNode.requestFocus();
        }
      },
      cursorColor: const Color(0xFF73747C), style: GoogleFonts.inter(color: textColor, fontSize: 16),
      decoration: InputDecoration(
        hintText: 'Search conversations', hintStyle: GoogleFonts.inter(color: textGreyColor, fontSize: 12),
        filled: true, fillColor: isDark ? const Color(0xFF283241) : const Color(0xFFF5F5F7),
        prefixIcon: Padding(padding: const EdgeInsets.all(10), child: OpaqueIcon('search', size: 16, color: textGreyColor)),
        suffixIcon: _isSearching ? IconButton(tooltip: 'Clear search', padding: EdgeInsets.zero, iconSize: 16,
          onPressed: () { _searchController.clear(); _searchFocusNode.unfocus(); }, icon: Icon(Icons.close, color: textGreyColor)) : null,
        contentPadding: const EdgeInsets.symmetric(horizontal: 13),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(19), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(19), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(19), borderSide: const BorderSide(color: Color(0xFFC6CBD3))),
      ),
    )),
  );

  Widget _buildConversationList(List<ConversationInfo> conversations, bool isReady, bool isDark, Color cardColor, Color textColor, Color textGreyColor, Color dividerColor) {
    final query = _searchController.text.trim().toLowerCase();
    final visible = conversations.where((convo) => (query.isNotEmpty || !isHomeChatHidden(convo.lastMessageTimestamp, _hiddenChats['${convo.conversationId}'])) && convo.chatTitle.toLowerCase().contains(query)
      && (_conversationFilter == 'All' || (_conversationFilter == 'Unread' && (convo.unreadCount > 0 || convo.hasUnreadMessages)) || (_conversationFilter == 'Groups' && convo.isGroup))).toList();
    visible.sort((a, b) {
      return compareHomeChats(
        aId: a.conversationId, bId: b.conversationId,
        aTime: a.lastMessageTimestamp, bTime: b.lastMessageTimestamp,
        aPinned: _pinnedChats.contains('${a.conversationId}'),
        bPinned: _pinnedChats.contains('${b.conversationId}'));
    });
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () {
        if (_searchFocusNode.hasFocus) {
          _searchFocusNode.unfocus();
        }
      },
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _buildSearchBar(isDark, cardColor, textColor, textGreyColor),
        Container(margin: const EdgeInsets.fromLTRB(20, 12, 20, 8), padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(color: isDark ? const Color(0xFF283241) : const Color(0xFFF1F2F5), borderRadius: BorderRadius.circular(16)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [for (final filter in ['All', 'Unread', 'Groups']) Padding(
            padding: const EdgeInsets.symmetric(horizontal: .5), child: Semantics(selected: _conversationFilter == filter, button: true,
              child: InkWell(borderRadius: BorderRadius.circular(14), onTap: () => setState(() { _conversationFilter = filter; _addMenuOpen = false; }),
                child: Container(constraints: const BoxConstraints(minHeight: 27, minWidth: 47), padding: const EdgeInsets.symmetric(horizontal: 12), alignment: Alignment.center,
                  decoration: BoxDecoration(color: _conversationFilter == filter ? (isDark ? const Color(0xFF354256) : Colors.white) : null, borderRadius: BorderRadius.circular(14)),
                  child: Text(filter, style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w500, color: _conversationFilter == filter ? textColor : textGreyColor))),
              ),
            ),
          )]),
        ),
        Expanded(child: Stack(children: [
          Positioned.fill(child: visible.isEmpty
            ? Center(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 32), child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(query.isNotEmpty ? 'No matching conversations' : _conversationFilter == 'Unread' ? 'You’re all caught up' : _conversationFilter == 'Groups' ? 'Bring everyone together' : 'Your conversations start here',
                    textAlign: TextAlign.center, style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w600, color: textColor)),
                  const SizedBox(height: 8),
                  Text(query.isNotEmpty ? 'Try searching for a different name.' : _conversationFilter == 'Unread' ? 'New unread messages will appear here.' : _conversationFilter == 'Groups' ? 'Tap + to create a group and start chatting.' : 'Tap + to find a friend and start chatting.',
                    textAlign: TextAlign.center, style: GoogleFonts.inter(fontSize: 12, height: 1.7, color: textGreyColor)),
                ],
              )))
            : ListView.builder(
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                padding: EdgeInsets.fromLTRB(MediaQuery.sizeOf(context).width < 350 ? 9 : 15, 0, MediaQuery.sizeOf(context).width < 350 ? 9 : 15, 80),
                itemCount: visible.length, itemBuilder: (context, index) => _buildConversationTile(visible[index], isDark, cardColor, textColor, textGreyColor, dividerColor))),
          if (_addMenuOpen) Positioned.fill(child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: () => setState(() => _addMenuOpen = false))),
        ])),
      ]),
    );
  }

  Widget _buildConversationTile(ConversationInfo convo, bool isDark, Color cardColor, Color textColor, Color textGreyColor, Color dividerColor) {
    final unread = convo.unreadCount > 0 || convo.hasUnreadMessages;
    return Material(color: _isChatSelectionMode && _selectedChats.containsKey(convo.conversationId)
      ? (isDark ? const Color(0xFF283241) : const Color(0xFFF1F2F5)) : Colors.transparent,
      borderRadius: BorderRadius.circular(12), child: InkWell(
        borderRadius: BorderRadius.circular(12), onTap: () { setState(() => _addMenuOpen = false); if (_isChatSelectionMode) { if (!_selectionBusy) _enterChatSelectionMode(convo); } else { _navigateToChat(convo); } },
        onLongPress: _selectionBusy ? null : () { _searchFocusNode.unfocus(); setState(() => _addMenuOpen = false); _enterChatSelectionMode(convo); },
        child: Padding(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 16), child: Row(children: [
          Stack(children: [_buildAvatar(convo, isDark, cardColor),
            if (_isChatSelectionMode && _selectedChats.containsKey(convo.conversationId))
              Positioned(right: 0, bottom: 0, child: Container(
                width: 18, height: 18,
                decoration: BoxDecoration(
                  color: const Color(0xFF258447), shape: BoxShape.circle,
                  border: Border.all(color: Colors.black, width: 1.2)),
                child: const Icon(Icons.check_rounded, size: 13, color: Colors.black))),
          ]), SizedBox(width: MediaQuery.sizeOf(context).width < 350 ? 9 : 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(convo.chatTitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: GoogleFonts.inter(fontSize: 14, letterSpacing: -.15, fontWeight: unread ? FontWeight.w600 : FontWeight.w500, color: textColor)),
            const SizedBox(height: 5),
            Text(convo.isTyping ? 'typing...' : ChatPayloadParser.getPreviewText(convo.lastMessage), maxLines: 1, overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(fontSize: 12, color: convo.isTyping ? const Color(0xFF6087BD) : unread ? (isDark ? const Color(0xFFDCE3EF) : const Color(0xFF4E515C)) : textGreyColor)),
          ])),
          const SizedBox(width: 8),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            if (_pinnedChats.contains('${convo.conversationId}')) Padding(
              padding: const EdgeInsets.only(bottom: 5), child: Icon(Icons.push_pin_rounded, size: 12, color: textGreyColor)),
            if (convo.lastMessageTimestamp != null) Text(_formatTimestamp(convo.lastMessageTimestamp!.toLocal()), style: GoogleFonts.inter(fontSize: 10, color: textGreyColor)),
            if (unread) ...[const SizedBox(height: 12), Semantics(label: '${convo.unreadCount > 0 ? convo.unreadCount : ''} unread messages', child: Container(width: 7, height: 7, decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFF335FE8))))],
          ]),
        ])),
      ),
    );
  }

  Widget _buildBottomNavigationBar(bool isReady, bool isDark, Color cardColor, Color textColor) => OpaqueBottomNavigation(
    index: _currentNavIndex, isDark: isDark,
    onSelected: (index) => setState(() { _currentNavIndex = index; _addMenuOpen = false; }),
  );

  Future<void> _openAddDestination(bool group) async {
    final ws = context.read<WebSocketService>();
    setState(() => _addMenuOpen = false);
    if (!ws.isConnected || ws.channel == null) {
      OpaqueToast.info(context, 'Connecting... Please wait a moment.');
      return;
    }
    if (!group) {
      setState(() {
        _friendsInitialTab = FriendTab.search;
        _friendsOpenRequest++;
        _currentNavIndex = 2;
      });
      return;
    }
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => CreateGroupScreen(channel: ws.channel!, onGroupCreated: () => context.read<HomeProvider>().fetchInitialConversations())));
    if (mounted) context.read<HomeProvider>().fetchInitialConversations();
  }

  Widget _buildAddMenu(bool dark) {
    final ink = dark ? const Color(0xFFE0E6EF) : const Color(0xFF343D4C);
    Widget option(String label, String icon, bool group) => InkWell(
      borderRadius: BorderRadius.circular(12), onTap: () => _openAddDestination(group),
      child: Padding(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7), child: Row(children: [
        Container(width: 30, height: 30, alignment: Alignment.center, decoration: BoxDecoration(color: dark ? const Color(0xFF354256) : const Color(0xFFF0F2F6), borderRadius: BorderRadius.circular(10)), child: OpaqueIcon(icon, size: 18, color: ink)),
        const SizedBox(width: 10), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w500, color: ink)),
        ])), const Icon(Icons.chevron_right, size: 14, color: Color(0xFF9399A5)),
      ])),
    );
    return TapRegion(onTapOutside: (_) { if (_addMenuOpen && mounted) setState(() => _addMenuOpen = false); }, child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, children: [
      AnimatedSize(duration: const Duration(milliseconds: 220), alignment: Alignment.bottomRight, curve: Curves.easeOutCubic,
        child: _addMenuOpen ? Container(width: 216, margin: const EdgeInsets.only(bottom: 12), padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(color: dark ? const Color(0xFF283241) : Colors.white, borderRadius: BorderRadius.circular(18), border: Border.all(color: dark ? const Color(0xFF354256) : const Color(0xFFE9EAF0)), boxShadow: const [BoxShadow(color: Color(0x14202127), blurRadius: 24, offset: Offset(0, 8))]),
          child: Column(mainAxisSize: MainAxisSize.min, children: [option('Add new friend', 'add', false),
            const Padding(padding: EdgeInsets.symmetric(vertical: 4), child: Divider(height: 1, indent: 48, endIndent: 8, color: Color(0xFFE9EBF0))),
            option('New group', 'users', true),
          ]),
        ) : const SizedBox.shrink()),
      SizedBox(width: 44, height: 44, child: FloatingActionButton(heroTag: 'opaque-add', tooltip: _addMenuOpen ? 'Close add options' : 'Add friend or group',
        elevation: _addMenuOpen ? 0 : 2, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        backgroundColor: _addMenuOpen ? const Color(0xFF3B4050) : const Color(0xFF252832), foregroundColor: Colors.white,
        onPressed: () { _searchFocusNode.unfocus(); setState(() => _addMenuOpen = !_addMenuOpen); },
        child: AnimatedRotation(turns: _addMenuOpen ? .125 : 0, duration: const Duration(milliseconds: 220), child: const Icon(Icons.add, size: 22)))),
    ]));
  }

  // ─── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Consumer2<WebSocketService, UserSettingsProvider>(
      builder: (context, websocketService, userSettings, child) {
        final isReady = websocketService.isConnected;
        final isDark = userSettings.isDarkMode;

        // Force appropriate status bar icons based on theme
        SystemChrome.setSystemUIOverlayStyle(
          SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness: isDark
                ? Brightness.light
                : Brightness.dark,
          ),
        );

        // Theme-aware colors
        final Color bgColor = isDark ? const Color(0xFF19202A) : Colors.white;
        final Color cardColor = bgColor;
        final Color textColor = isDark ? const Color(0xFFDCE3EF) : const Color(0xFF202127);
        final Color textGreyColor = isDark ? const Color(0xFF97A3B6) : const Color(0xFF7C7D85);
        final Color dividerColor = isDark ? Colors.white10 : _kDivider;

        return PopScope(canPop: !_isChatSelectionMode, onPopInvokedWithResult: (didPop, result) {
          if (!didPop && !_selectionBusy) _exitChatSelectionMode();
        }, child: CallAwareScreen(
          screenName: 'HomeScreen',
          child: Scaffold(
            backgroundColor: bgColor,
            appBar: _currentNavIndex <= 4
                ? _buildAppBar(isDark, cardColor, textColor)
                : null,
            body: IndexedStack(
              index: _currentNavIndex,
              children: [
                // Index 0: Chats
                Consumer<HomeProvider>(
                  builder: (context, homeProvider, _) {
                    final conversations = homeProvider.conversations;
                    return _buildConversationList(
                      conversations,
                      isReady,
                      isDark,
                      cardColor,
                      textColor,
                      textGreyColor,
                      dividerColor,
                    );
                  },
                ),

                // Index 1: Calls
                const CallHistoryScreen(embedded: true),

                // Index 2: Friends
                if (websocketService.channel != null)
                  FindFriendsScreen(
                    embedded: true,
                    key: ValueKey(_friendsOpenRequest), initialTab: _friendsInitialTab,
                    channel: websocketService.channel!,
                    onFriendRequestAccepted: () => Provider.of<HomeProvider>(
                      context,
                      listen: false,
                    ).fetchInitialConversations(),
                  )
                else
                  const Center(child: CircularProgressIndicator()),

                // Index 3: Style
                const StyleScreen(embedded: true),

                // Index 4: Notes
                const NotesScreen(embedded: true),
              ],
            ),
            floatingActionButton: _currentNavIndex == 0 && !_isChatSelectionMode ? _buildAddMenu(isDark) : null,
            bottomNavigationBar: _isChatSelectionMode
                ? null
                : _buildBottomNavigationBar(
                    isReady,
                    isDark,
                    cardColor,
                    textColor,
                  ),
          ),
        ));
      },
    );
  }
}
