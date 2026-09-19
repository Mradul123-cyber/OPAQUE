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
import 'package:zarq_messenger/screens/customization_screen.dart';
import 'package:zarq_messenger/widgets/call_aware_screen.dart';
import 'package:zarq_messenger/services/overlay_permission_helper.dart';

import 'package:zarq_messenger/app_config.dart';

// ─── Brand Colours ────────────────────────────────────────────────────────────
const Color _kIndigo = Color(0xFF3D00B8);
const Color _kIndigoLight = Color(0xFF5C1EE0);
const Color _kBg = Color(0xFFF7F7FB);
const Color _kWhite = Colors.white;
const Color _kTextDark = Color(0xFF1A1A2E);
const Color _kTextGrey = Color(0xFF8A8A9A);
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
  bool _isGroupSelectionMode = false;
  ConversationInfo? _selectedConversation;

  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  List<ConversationInfo> _filteredConversations = [];
  bool _isSearching = false;
  final Set<String> _blockedUsers = {};

  // Bottom nav index: 0=Chats, 1=Calls, 2=Style, 3=Groups, 4=Settings
  int _currentNavIndex = 0;

  StreamSubscription? _websocketSubscription;

  // ─── Lifecycle ─────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeUser();
    _loadBlockedUsers();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _checkPendingNavigation();

      final homeProvider = Provider.of<HomeProvider>(context, listen: false);
      if (homeProvider.conversations.isEmpty) {
        homeProvider.fetchInitialConversations();
      }

      OverlayPermissionHelper.checkAndRequestPermission(context);

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
    final homeProvider = Provider.of<HomeProvider>(context, listen: false);
    final query = _searchController.text.toLowerCase();
    setState(() {
      _isSearching = query.isNotEmpty;
      _filteredConversations = homeProvider.conversations.where((convo) {
        return convo.chatTitle.toLowerCase().contains(query);
      }).toList();
    });
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
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Still connecting… Please wait a moment.'),
            ),
          );
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
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Conversation not found or no longer exists'),
                backgroundColor: Colors.orange,
              ),
            );
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

  void _showLogoutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          backgroundColor: _kWhite,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Row(
            children: [
              const Icon(Icons.logout_rounded, color: Colors.orange),
              const SizedBox(width: 10),
              Text(
                'Logout',
                style: GoogleFonts.poppins(
                  fontWeight: FontWeight.w600,
                  color: _kTextDark,
                ),
              ),
            ],
          ),
          content: Text(
            'You will be logged out but your messages will stay on this phone.\n\nYou can login again anytime.',
            style: GoogleFonts.inter(
              color: _kTextGrey,
              fontSize: 14,
              height: 1.5,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(
                'Cancel',
                style: GoogleFonts.inter(color: _kTextGrey),
              ),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
                _performLogout(clearData: false);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: _kWhite,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text('Logout', style: GoogleFonts.inter()),
            ),
          ],
        );
      },
    );
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

  // ─── Group selection ───────────────────────────────────────────────────────

  void _enterGroupSelectionMode(ConversationInfo conversation) {
    setState(() {
      _isGroupSelectionMode = true;
      _selectedConversation = conversation;
    });
  }

  void _exitGroupSelectionMode() {
    setState(() {
      _isGroupSelectionMode = false;
      _selectedConversation = null;
    });
  }

  Future<void> _showGroupActionDialog({required String action}) async {
    if (_selectedConversation == null) return;
    final conversationId = _selectedConversation!.conversationId;
    final chatTitle = _selectedConversation!.chatTitle;

    final title = action == 'delete' ? 'Delete Group?' : 'Leave Group?';
    final content = action == 'delete'
        ? 'Are you sure you want to permanently delete "$chatTitle"? This cannot be undone.'
        : 'Are you sure you want to leave "$chatTitle"?';

    return showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: _kWhite,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Text(
            title,
            style: GoogleFonts.poppins(
              fontWeight: FontWeight.w600,
              color: _kTextDark,
            ),
          ),
          content: Text(
            content,
            style: GoogleFonts.inter(color: _kTextGrey, fontSize: 14),
          ),
          actions: [
            TextButton(
              child: Text(
                'Cancel',
                style: GoogleFonts.inter(color: _kTextGrey),
              ),
              onPressed: () => Navigator.of(context).pop(),
            ),
            TextButton(
              child: Text(
                action == 'delete' ? 'Delete' : 'Leave',
                style: GoogleFonts.inter(
                  color: action == 'delete' ? Colors.red : Colors.orange,
                  fontWeight: FontWeight.w600,
                ),
              ),
              onPressed: () async {
                Navigator.of(context).pop();
                if (action == 'delete') {
                  await _deleteGroup(conversationId);
                } else {
                  await _leaveGroup(conversationId);
                }
                _exitGroupSelectionMode();
              },
            ),
          ],
        );
      },
    );
  }

  Future<void> _deleteGroup(int conversationId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final token = await user.getIdToken();
    try {
      final response = await http.delete(
        Uri.parse('${AppConfig.baseUrl}/groups/delete/$conversationId'),
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
        Uri.parse('${AppConfig.baseUrl}/groups/leave/$conversationId'),
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: GoogleFonts.inter()),
        backgroundColor: isError ? Colors.red[700] : _kIndigo,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
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
    const double size = 52.0;
    return Stack(
      children: [
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(isDark ? 0.25 : 0.10),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: convo.avatarUrl != null && convo.avatarUrl!.isNotEmpty
              ? CircleAvatar(
                  radius: size / 2,
                  backgroundImage: CachedNetworkImageProvider(convo.avatarUrl!),
                  backgroundColor: isDark ? Colors.white10 : Colors.grey[200],
                )
              : CircleAvatar(
                  radius: size / 2,
                  backgroundColor: _getAvatarColor(convo.chatTitle),
                  child: Text(
                    convo.chatTitle.isNotEmpty
                        ? convo.chatTitle[0].toUpperCase()
                        : '?',
                    style: GoogleFonts.poppins(
                      color: _kWhite,
                      fontWeight: FontWeight.bold,
                      fontSize: 20,
                    ),
                  ),
                ),
        ),
        if (convo.isOnline)
          Positioned(
            right: 1,
            bottom: 1,
            child: Container(
              width: 13,
              height: 13,
              decoration: BoxDecoration(
                color: _kOnlineGreen,
                shape: BoxShape.circle,
                border: Border.all(
                  color: isDark ? cardColor : _kWhite,
                  width: 2,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Color _getAvatarColor(String title) {
    const colors = [
      Color(0xFF6366F1),
      Color(0xFF8B5CF6),
      Color(0xFF3D00B8),
      Color(0xFF0EA5E9),
      Color(0xFF10B981),
      Color(0xFFF59E0B),
    ];
    return colors[title.length % colors.length];
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
        _isGroupSelectionMode &&
        _selectedConversation != null &&
        _selectedConversation!.creatorUid == user?.uid;

    if (_isGroupSelectionMode) {
      return AppBar(
        backgroundColor: _kIndigo,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded, color: _kWhite),
          onPressed: _exitGroupSelectionMode,
        ),
        title: Text(
          _selectedConversation!.chatTitle,
          style: GoogleFonts.poppins(
            color: _kWhite,
            fontWeight: FontWeight.w600,
          ),
        ),
        actions: [
          if (isCreatorOfSelectedGroup)
            IconButton(
              icon: const Icon(Icons.delete_outline_rounded, color: _kWhite),
              onPressed: () => _showGroupActionDialog(action: 'delete'),
            )
          else
            IconButton(
              icon: const Icon(Icons.exit_to_app_rounded, color: _kWhite),
              onPressed: () => _showGroupActionDialog(action: 'leave'),
            ),
        ],
      );
    }

    // Normal AppBar
    return PreferredSize(
      preferredSize: const Size.fromHeight(66),
      child: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
          child: Container(
            decoration: BoxDecoration(
              color: isDark
                  ? cardColor.withOpacity(0.85)
                  : Colors.white.withOpacity(0.72),
              border: Border(
                bottom: BorderSide(
                  color: isDark
                      ? Colors.white.withOpacity(0.08)
                      : Colors.white.withOpacity(0.4),
                  width: 0.5,
                ),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.04),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: SafeArea(
              bottom: false,
              child: SizedBox(
                height: 66,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Row(
                    children: [
                      // ── Left: User avatar ──────────────────────────────────
                      GestureDetector(
                        onTap: () async {
                          await Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (context) => const SettingsScreen(),
                            ),
                          );
                          _refreshUserData();
                        },
                        child: Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: isDark ? Colors.white24 : Colors.black,
                              width: 2,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.18),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: ClipOval(
                            child: user?.photoURL != null
                                ? CachedNetworkImage(
                                    imageUrl: user!.photoURL!,
                                    fit: BoxFit.cover,
                                    placeholder: (_, __) => Container(
                                      color: isDark
                                          ? Colors.white10
                                          : Colors.black.withOpacity(0.12),
                                    ),
                                    errorWidget: (_, __, ___) =>
                                        _buildDefaultUserAvatar(
                                          user,
                                          isDark,
                                          textColor,
                                        ),
                                  )
                                : _buildDefaultUserAvatar(
                                    user,
                                    isDark,
                                    textColor,
                                  ),
                          ),
                        ),
                      ),

                      // ── Centre: Brand title ────────────────────────────────
                      Expanded(
                        child: Center(
                          child: Text(
                            'Indus',
                            style: GoogleFonts.outfit(
                              color: isDark ? Colors.white : Colors.black,
                              fontWeight: FontWeight.w800,
                              fontSize: 28,
                              letterSpacing: -0.5,
                            ),
                          ),
                        ),
                      ),

                      // ── Right: More options (same width as avatar for symmetry) ──
                      SizedBox(
                        width: 42,
                        child: PopupMenuButton<String>(
                          icon: Icon(
                            Icons.more_vert_rounded,
                            color: isDark ? Colors.white : _kTextDark,
                            size: 22,
                          ),
                          color: isDark ? cardColor : _kWhite,
                          elevation: 8,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          itemBuilder: (context) => [
                            _popupItem(
                              value: 'settings',
                              icon: Icons.settings_outlined,
                              label: 'Settings',
                              color: isDark ? Colors.white : _kTextDark,
                            ),
                            _popupItem(
                              value: 'call_history',
                              icon: Icons.history_rounded,
                              label: 'Call History',
                              color: Colors.green,
                            ),
                            _popupItem(
                              value: 'about',
                              icon: Icons.info_outline_rounded,
                              label: 'About',
                              color: Colors.cyan,
                            ),
                            const PopupMenuDivider(),
                            _popupItem(
                              value: 'logout',
                              icon: Icons.logout_rounded,
                              label: 'Logout',
                              color: Colors.orange,
                            ),
                          ],
                          onSelected: (result) async {
                            if (result == 'logout') {
                              _showLogoutDialog(context);
                            } else if (result == 'settings') {
                              await Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => const SettingsScreen(),
                                ),
                              );
                              _refreshUserData();
                            } else if (result == 'call_history') {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => const CallHistoryScreen(),
                                ),
                              );
                            } else if (result == 'about') {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => const AboutScreen(),
                                ),
                              );
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
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
  }) {
    return PopupMenuItem<String>(
      value: value,
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 12),
          Text(
            label,
            style: GoogleFonts.inter(color: _kTextDark, fontSize: 14),
          ),
        ],
      ),
    );
  }

  // ─── Search Bar ────────────────────────────────────────────────────────────

  Widget _buildSearchBar(
    bool isDark,
    Color cardColor,
    Color textColor,
    Color textGreyColor,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Container(
        height: 48,
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF161b36) : _kWhite,
          borderRadius: BorderRadius.circular(30),
          border: Border.all(
            color: isDark
                ? Colors.white.withOpacity(0.08)
                : const Color(0xFFE0E0E0),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(isDark ? 0.2 : 0.06),
              blurRadius: 12,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: TextField(
          key: const ValueKey('home_search_bar'),
          controller: _searchController,
          focusNode: _searchFocusNode,
          cursorColor: _kIndigo,
          style: GoogleFonts.inter(color: textColor, fontSize: 14),
          decoration: InputDecoration(
            hintText: 'Search conversations...',
            hintStyle: GoogleFonts.inter(color: textGreyColor, fontSize: 14),
            prefixIcon: Icon(
              Icons.search_rounded,
              color: textGreyColor,
              size: 20,
            ),
            suffixIcon: _isSearching
                ? GestureDetector(
                    onTap: () {
                      _searchController.clear();
                      _searchFocusNode.unfocus();
                    },
                    child: Icon(
                      Icons.close_rounded,
                      color: textGreyColor,
                      size: 18,
                    ),
                  )
                : null,
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(
              vertical: 12,
              horizontal: 4,
            ),
          ),
        ),
      ),
    );
  }

  // ─── Conversation List ─────────────────────────────────────────────────────

  Widget _buildConversationList(
    List<ConversationInfo> conversations,
    bool isReady,
    bool isDark,
    Color cardColor,
    Color textColor,
    Color textGreyColor,
    Color dividerColor,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSearchBar(isDark, cardColor, textColor, textGreyColor),
        Expanded(
          child: conversations.isEmpty
              ? _buildEmptyState(_isSearching, isDark, textColor, textGreyColor)
              : ListView.builder(
                  padding: const EdgeInsets.only(top: 4, bottom: 12),
                  itemCount: conversations.length,
                  itemBuilder: (context, index) {
                    final convo = conversations[index];
                    return _buildConversationTile(
                      convo,
                      isDark,
                      cardColor,
                      textColor,
                      textGreyColor,
                      dividerColor,
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildConversationTile(
    ConversationInfo convo,
    bool isDark,
    Color cardColor,
    Color textColor,
    Color textGreyColor,
    Color dividerColor,
  ) {
    final bool hasUnread = convo.unreadCount > 0;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _navigateToChat(convo),
        onLongPress: convo.isGroup
            ? () => _enterGroupSelectionMode(convo)
            : null,
        splashColor: _kIndigo.withOpacity(0.06),
        highlightColor: _kIndigo.withOpacity(0.04),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Avatar
              _buildAvatar(convo, isDark, cardColor),
              const SizedBox(width: 14),

              // Text content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Name + timestamp row
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            convo.chatTitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.inter(
                              color: textColor,
                              fontWeight: hasUnread
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                              fontSize: 15.5,
                            ),
                          ),
                        ),
                        if (convo.lastMessageTimestamp != null) ...[
                          const SizedBox(width: 8),
                          Text(
                            _formatTimestamp(convo.lastMessageTimestamp!),
                            style: GoogleFonts.inter(
                              color: hasUnread ? _kIndigo : textGreyColor,
                              fontSize: 12,
                              fontWeight: hasUnread
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),

                    // Last message + badge row
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            convo.isTyping
                                ? 'typing...'
                                : (convo.lastMessage ?? 'No messages yet'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.inter(
                              color: convo.isTyping ? _kIndigo : textGreyColor,
                              fontSize: 13.5,
                              fontStyle: convo.isTyping
                                  ? FontStyle.italic
                                  : FontStyle.normal,
                              fontWeight: hasUnread
                                  ? FontWeight.w500
                                  : FontWeight.w400,
                            ),
                          ),
                        ),
                        if (hasUnread) ...[
                          const SizedBox(width: 8),
                          _buildUnreadBadge(convo.unreadCount),
                        ],
                      ],
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

  Widget _buildUnreadBadge(int count) {
    return Container(
      constraints: const BoxConstraints(minWidth: 22, minHeight: 22),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: _kIndigo,
        borderRadius: BorderRadius.circular(30),
      ),
      child: Text(
        count > 99 ? '99+' : count.toString(),
        style: GoogleFonts.inter(
          color: _kWhite,
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }

  // ─── Empty State ───────────────────────────────────────────────────────────

  Widget _buildEmptyState(
    bool isSearching,
    bool isDark,
    Color textColor,
    Color textGreyColor,
  ) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: isSearching
                    ? (isDark
                          ? [const Color(0xFF004D40), const Color(0xFF00796B)]
                          : [const Color(0xFFE0F2F1), const Color(0xFFB2DFDB)])
                    : (isDark
                          ? [const Color(0xFF1E1E2E), const Color(0xFF2D2D44)]
                          : [const Color(0xFFE8EAF6), const Color(0xFFC5CAE9)]),
              ),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color:
                      (isSearching
                              ? (isDark ? Colors.teal : const Color(0xFFB2DFDB))
                              : (isDark
                                    ? Colors.indigo
                                    : const Color(0xFFC5CAE9)))
                          .withOpacity(0.4),
                  blurRadius: 15,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Icon(
              isSearching ? Icons.person_search_rounded : Icons.forum_rounded,
              size: 44,
              color: isSearching
                  ? (isDark ? Colors.tealAccent : const Color(0xFF00796B))
                  : (isDark ? Colors.indigoAccent : _kIndigo.withOpacity(0.8)),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            isSearching ? 'No matches found' : 'No conversations yet',
            style: GoogleFonts.poppins(
              color: textColor,
              fontSize: 17,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          if (!isSearching) ...[
            const SizedBox(height: 28),
            ElevatedButton.icon(
              onPressed: () {
                final ws = Provider.of<WebSocketService>(
                  context,
                  listen: false,
                );
                if (ws.isConnected && ws.channel != null) {
                  Navigator.of(context)
                      .push(
                        MaterialPageRoute(
                          builder: (_) =>
                              FindFriendsScreen(channel: ws.channel!),
                        ),
                      )
                      .then(
                        (_) => Provider.of<HomeProvider>(
                          context,
                          listen: false,
                        ).fetchInitialConversations(),
                      );
                }
              },
              icon: const Icon(Icons.person_add_rounded, size: 20),
              label: const Text('Add Friends'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _kIndigo,
                foregroundColor: _kWhite,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(30),
                ),
                elevation: 4,
                shadowColor: _kIndigo.withOpacity(0.3),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ─── Bottom Navigation ─────────────────────────────────────────────────────

  Widget _buildBottomNavigationBar(
    bool isReady,
    bool isDark,
    Color cardColor,
    Color textColor,
  ) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? cardColor : _kWhite,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.3 : 0.07),
            blurRadius: 16,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 62,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildNavItem(
                index: 0,
                icon: Icons.chat_rounded,
                activeIcon: Icons.chat_rounded,
                label: 'Chats',
                isDark: isDark,
                onTap: () => setState(() => _currentNavIndex = 0),
              ),
              _buildNavItem(
                index: 1,
                icon: Icons.call_outlined,
                activeIcon: Icons.call_rounded,
                label: 'Calls',
                isDark: isDark,
                onTap: () => setState(() => _currentNavIndex = 1),
              ),
              _buildNavItem(
                index: 2,
                icon: Icons.person_add_outlined,
                activeIcon: Icons.person_add_rounded,
                label: 'Friends',
                isDark: isDark,
                onTap: () => setState(() => _currentNavIndex = 2),
              ),
              _buildNavItem(
                index: 3,
                icon: Icons.palette_outlined,
                activeIcon: Icons.palette_rounded,
                label: 'Style',
                isDark: isDark,
                onTap: () => setState(() => _currentNavIndex = 3),
              ),
              _buildNavItem(
                index: 4,
                icon: Icons.groups_outlined,
                activeIcon: Icons.groups_rounded,
                label: 'Groups',
                isDark: isDark,
                onTap: () => setState(() => _currentNavIndex = 4),
              ),
              _buildNavItem(
                index: 5,
                icon: Icons.edit_note_outlined,
                activeIcon: Icons.edit_note_rounded,
                label: 'Notes',
                isDark: isDark,
                onTap: () => setState(() => _currentNavIndex = 5),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem({
    required int index,
    required IconData icon,
    required IconData activeIcon,
    required String label,
    required bool isDark,
    required VoidCallback onTap,
  }) {
    final bool isActive = _currentNavIndex == index;
    final inactiveColor = isDark ? Colors.white38 : _kTextGrey;
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isActive ? activeIcon : icon,
              color: isActive
                  ? (isDark ? Colors.cyanAccent : _kIndigo)
                  : inactiveColor,
              size: 24,
            ),
            const SizedBox(height: 3),
            Text(
              label,
              style: GoogleFonts.inter(
                color: isActive
                    ? (isDark ? Colors.cyanAccent : _kIndigo)
                    : inactiveColor,
                fontSize: 10.5,
                fontWeight: isActive ? FontWeight.w700 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
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
        final Color bgColor = isDark ? const Color(0xFF0a0e21) : _kBg;
        final Color cardColor = isDark ? const Color(0xFF161b36) : _kWhite;
        final Color textColor = isDark ? Colors.white : _kTextDark;
        final Color textGreyColor = isDark ? Colors.white60 : _kTextGrey;
        final Color dividerColor = isDark ? Colors.white10 : _kDivider;

        return CallAwareScreen(
          screenName: 'HomeScreen',
          child: Scaffold(
            backgroundColor: bgColor,
            appBar: _currentNavIndex == 0
                ? _buildAppBar(isDark, cardColor, textColor)
                : null,
            body: IndexedStack(
              index: _currentNavIndex,
              children: [
                // Index 0: Chats
                Consumer<HomeProvider>(
                  builder: (context, homeProvider, _) {
                    final conversations = _isSearching
                        ? _filteredConversations
                        : homeProvider.conversations;
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
                const CallHistoryScreen(),

                // Index 2: Friends
                if (websocketService.channel != null)
                  FindFriendsScreen(
                    channel: websocketService.channel!,
                    onFriendRequestAccepted: () => Provider.of<HomeProvider>(
                      context,
                      listen: false,
                    ).fetchInitialConversations(),
                  )
                else
                  const Center(child: CircularProgressIndicator()),

                // Index 3: Style
                const CustomizationScreen(),

                // Index 4: Groups
                if (websocketService.channel != null)
                  CreateGroupScreen(
                    channel: websocketService.channel!,
                    onGroupCreated: () => Provider.of<HomeProvider>(
                      context,
                      listen: false,
                    ).fetchInitialConversations(),
                  )
                else
                  const Center(child: CircularProgressIndicator()),

                // Index 5: Notes
                const NotesScreen(),
              ],
            ),
            bottomNavigationBar: _isGroupSelectionMode
                ? null
                : _buildBottomNavigationBar(
                    isReady,
                    isDark,
                    cardColor,
                    textColor,
                  ),
          ),
        );
      },
    );
  }
}
