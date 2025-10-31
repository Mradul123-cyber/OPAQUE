import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:zarq_messenger/screens/call_history_screen.dart';
import 'package:zarq_messenger/screens/customization_screen.dart';
import 'package:zarq_messenger/screens/notes_screen.dart';
import 'package:zarq_messenger/services/SignalService.dart';
import 'package:zarq_messenger/services/database_service.dart';
import 'package:zarq_messenger/services/navigation_handler.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'dart:async';
import 'dart:ui';
import 'dart:convert';

import 'providers/home_provider.dart';
import 'providers/chat_provider.dart';
import 'services/websocket_service.dart';
import 'services/user_settings_provider.dart';

// Import Screens and Widgets
import 'expandable_fab.dart';
import 'login_screen.dart';
import 'setting_screen.dart';
import 'find_friends_screen.dart';
import 'chat_screen.dart';
import 'create_group_screen.dart';
import 'widgets/call_aware_screen.dart';
import 'widgets/animated_profile_avatar.dart';
import 'services/overlay_permission_helper.dart';
import 'about_screen.dart';
import 'package:zarq_messenger/widgets/breathing_unread_badge.dart';
import 'package:zarq_messenger/screens/ai_chat_screen.dart';
// import 'screens/tasks_screen.dart';
// import 'screens/moments_main_screen.dart';

class ConversationInfo {
  final int conversationId;
  final String chatTitle;
  final bool isGroup;
  final String? creatorUid;
  final String? avatarUrl;
  final String? partnerUid;
  final bool hasUnreadMessages;
  final DateTime? lastMessageTimestamp; // For sorting
  final int unreadCount; // Number of unread messages

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
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  String _displayName = "User";
  String? _currentUserAvatarUrl;
  String? _currentUserUid;

  bool _isGroupSelectionMode = false;
  ConversationInfo? _selectedConversation;

  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  List<ConversationInfo> _filteredConversations = [];
  bool _isSearching = false;
  double _previousKeyboardHeight = 0;

  bool _isAvatarHovering = false;
  bool _isDeleteHovering = false;
  bool _isLeaveHovering = false;

  StreamSubscription? _websocketSubscription;

  // Blocked users
  List<String> _blockedUsers = [];

  // AI button position
  double _aiButtonX = 0.0;
  double _aiButtonY = 0.0;
  bool _aiButtonPositionLoaded = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _loadBlockedUsers();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadAIButtonPosition();
      _checkPendingNavigation();

      // Only fetch if not already fetched by _checkPendingNavigation
      final homeProvider = Provider.of<HomeProvider>(context, listen: false);
      if (homeProvider.conversations.isEmpty) {
        homeProvider.fetchInitialConversations();
      }

      // Request overlay permission for floating call window
      OverlayPermissionHelper.checkAndRequestPermission(context);

      // Listen for conversation updates
      final websocketService = Provider.of<WebSocketService>(context, listen: false);
      _websocketSubscription = websocketService.stream.listen((data) {
        if (data is Map<String, dynamic>) {
          if (data['type'] == 'conversation_update') {
            // print('[HomeScreen] 🔄 Conversation update received, refreshing...');
            Provider.of<HomeProvider>(context, listen: false).fetchInitialConversations();
          } else if (data['type'] == 'group_deleted') {
            // print('[HomeScreen] 🗑️ Group deleted notification received');
            final conversationId = data['conversationId'];
            if (conversationId != null) {
              Provider.of<HomeProvider>(context, listen: false).removeConversation(conversationId);
            }
          }
        }
      });
    });

    _initializeUser();
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

  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    final currentKeyboardHeight = MediaQuery.of(context).viewInsets.bottom;

    // If keyboard was visible and now it's closed, unfocus the search field
    if (_previousKeyboardHeight > 0 && currentKeyboardHeight == 0) {
      if (_searchFocusNode.hasFocus) {
        _searchFocusNode.unfocus();
      }
    }

    _previousKeyboardHeight = currentKeyboardHeight;
  }

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

  /// Load blocked users from SharedPreferences
  Future<void> _loadBlockedUsers() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final blockedUsers = prefs.getStringList('blocked_users') ?? [];

      setState(() {
        _blockedUsers = blockedUsers;
      });
    } catch (e) {
      // print('[HomeScreen] Error loading blocked users: $e');
    }
  }

  /// Load AI button position from SharedPreferences
  Future<void> _loadAIButtonPosition() async {
    try {
      print('[HomeScreen] Loading AI button position...');
      final prefs = await SharedPreferences.getInstance();
      final x = prefs.getDouble('ai_button_x');
      final y = prefs.getDouble('ai_button_y');
      print('[HomeScreen] Loaded position: x=$x, y=$y');

      if (mounted) {
        setState(() {
          if (x != null && y != null) {
            _aiButtonX = x;
            _aiButtonY = y;
            print('[HomeScreen] Using saved position: $_aiButtonX, $_aiButtonY');
          } else {
            // Set default position on first load
            final screenWidth = MediaQuery.of(context).size.width;
            final screenHeight = MediaQuery.of(context).size.height;
            final bottomPadding = MediaQuery.of(context).padding.bottom;
            final buttonSize = (screenWidth * 0.16).clamp(60.0, 72.0);

            // Calculate bottom nav height: icon (22-28) + spacing (4-8) + label (10-13) + vertical padding (screenHeight * 0.012 * 2)
            // Plus the EdgeInsets padding: top (screenHeight * 0.015) + bottom (bottomPadding + screenHeight * 0.015)
            final navIconSize = (screenWidth * 0.06).clamp(22.0, 28.0);
            final navLabelSize = (screenWidth * 0.028).clamp(10.0, 13.0);
            final navSpacing = (screenHeight * 0.007).clamp(4.0, 8.0);
            final navVerticalPadding = screenHeight * 0.012;
            final navContainerPadding = screenHeight * 0.015;

            final bottomNavHeight = navIconSize + navSpacing + navLabelSize + (navVerticalPadding * 2) + navContainerPadding + bottomPadding + navContainerPadding;

            _aiButtonX = screenWidth - buttonSize - 16.0;
            _aiButtonY = screenHeight - bottomNavHeight - buttonSize - 16.0; // 16px gap above bottom nav
            print('[HomeScreen] Set default position: $_aiButtonX, $_aiButtonY (screen: $screenWidth x $screenHeight, bottom: $bottomPadding, bottomNavHeight: $bottomNavHeight, buttonSize: $buttonSize)');
          }
          _aiButtonPositionLoaded = true;
          print('[HomeScreen] AI button position loaded: $_aiButtonPositionLoaded');
        });
      }
    } catch (e) {
      print('[HomeScreen] ERROR loading AI button position: $e');
      if (mounted) {
        setState(() {
          _aiButtonPositionLoaded = true;
        });
      }
    }
  }

  /// Save AI button position to SharedPreferences
  Future<void> _saveAIButtonPosition(double x, double y) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble('ai_button_x', x);
      await prefs.setDouble('ai_button_y', y);
    } catch (e) {
      // print('[HomeScreen] Error saving AI button position: $e');
    }
  }

  Future<void> _checkPendingNavigation() async {
    final targetConversationId = NavigationHandler.getPendingConversationId();
    if (targetConversationId != null) {
      // print('[HomeScreen] Found pending navigation to conversation: $targetConversationId');

      // Wait for conversations to load
      final homeProvider = Provider.of<HomeProvider>(context, listen: false);

      // If conversations are empty, wait for fetch to complete
      if (homeProvider.conversations.isEmpty) {
        // print('[HomeScreen] Waiting for conversations to load...');
        await homeProvider.fetchInitialConversations();
      }

      // Small delay for UI to settle
      await Future.delayed(Duration(milliseconds: 300));

      // Now open the conversation
      await _openConversationById(targetConversationId);
    }
  }

  Future<void> _openConversationById(int conversationId) async {
    try {
      // print('[HomeScreen] Attempting to open conversation: $conversationId');

      // Get the home provider to access conversations
      final homeProvider = Provider.of<HomeProvider>(context, listen: false);
      final websocketService = Provider.of<WebSocketService>(context, listen: false);

      // Check if WebSocket is connected
      if (!websocketService.isConnected || websocketService.channel == null) {
        // print('[HomeScreen] WebSocket not connected, cannot open conversation');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Still connecting... Please wait a moment.')),
        );
        return;
      }

      // Find the conversation by ID
      final targetConversation = homeProvider.conversations.firstWhere(
            (convo) => convo.conversationId == conversationId,
        orElse: () => throw Exception('Conversation not found'),
      );

      // print('[HomeScreen] Found conversation: ${targetConversation.chatTitle}');

      // Navigate to ChatScreen using the same method as your onTap
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => ChatScreen(
            channel: websocketService.channel!,
            conversationInfo: targetConversation,
          ),
        ),
      );

      // print('[HomeScreen] Successfully navigated to conversation: $conversationId');

    } catch (e) {
      // print('[HomeScreen] Error opening conversation $conversationId: $e');

      // If conversation not found in current list, refresh and try again
      if (e.toString().contains('Conversation not found')) {
        // print('[HomeScreen] Conversation not in current list, refreshing...');

        final homeProvider = Provider.of<HomeProvider>(context, listen: false);
        await homeProvider.fetchInitialConversations();

        // Try one more time after refresh
        try {
          final targetConversation = homeProvider.conversations.firstWhere(
                (convo) => convo.conversationId == conversationId,
          );

          final websocketService = Provider.of<WebSocketService>(context, listen: false);
          if (websocketService.isConnected && websocketService.channel != null) {
            await Navigator.of(context).push(
              MaterialPageRoute(
                builder: (context) => ChatScreen(
                  channel: websocketService.channel!,
                  conversationInfo: targetConversation,
                ),
              ),
            );
            // print('[HomeScreen] Successfully navigated after refresh');
          }
        } catch (e2) {
          // print('[HomeScreen] Still could not find conversation after refresh: $e2');
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

  Future<void> _initializeUser() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      await user.reload();
      final refreshedUser = FirebaseAuth.instance.currentUser;
      if (!mounted) return;
      setState(() {
        _displayName = refreshedUser?.displayName ?? user.email ?? "User";
        _currentUserUid = refreshedUser?.uid;
        _currentUserAvatarUrl = refreshedUser?.photoURL;
      });
    }
  }

  Future<void> _refreshUserData() async {
    await _initializeUser();
  }



  // Show dialog for simple logout (keeps data)
  void _showLogoutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          backgroundColor: Colors.grey[900],
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.logout, color: Colors.orange),
              SizedBox(width: 10),
              Text('Logout', style: TextStyle(color: Colors.white)),
            ],
          ),
          content: const Text(
            'You will be logged out but your messages will stay on this phone.\n\nYou can login again anytime to see your messages.',
            style: TextStyle(color: Colors.white70, fontSize: 15),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
                _performLogout(clearData: false);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
              ),
              child: const Text('Logout'),
            ),
          ],
        );
      },
    );
  }

  // Show dialog for logout with data clear
  void _showLogoutWithClearDataDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          backgroundColor: Colors.grey[900],
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.warning, color: Colors.redAccent),
              SizedBox(width: 10),
              Text('Clear All Data?', style: TextStyle(color: Colors.white)),
            ],
          ),
          content: const Text(
            '⚠️ All your messages will be deleted from this phone.\n\nYou won\'t be able to see them again!\n\nUse this if:\n• You share this phone with others\n• You want to start fresh\n• You\'re switching to a new phone',
            style: TextStyle(color: Colors.white70, fontSize: 15),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
                _performLogout(clearData: true);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
                foregroundColor: Colors.white,
              ),
              child: const Text('Delete & Logout'),
            ),
          ],
        );
      },
    );
  }

  // Perform logout with optional data clearing
  Future<void> _performLogout({required bool clearData}) async {
    // print("[HomeScreen] _performLogout triggered (clearData: $clearData) at ${DateTime.now().toUtc()}");

    try {
      // 1. Clear FCM token from backend (so no more notifications)
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        try {
          final token = await user.getIdToken();
          final url = Uri.parse('https://api.zarqmessenger.com/v1/fcm/token');
          await http.post(
            url,
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
            },
            body: json.encode({
              'fcm_token': '', // Empty string to clear
              'device_id': 1,
            }),
          );
          // print("[HomeScreen] FCM token cleared from backend");
        } catch (e) {
          // print("[HomeScreen] Error clearing FCM token: $e");
          // Continue with logout even if this fails
        }
      }

      if (clearData) {
        // 2. Reset Signal Protocol user context (only if clearing data)
        // print("[HomeScreen] Resetting Signal Protocol user context...");
        final signalResetSuccess = await SignalService.resetUserContext();
        if (signalResetSuccess) {
          // print("[HomeScreen] Signal Protocol context reset successfully");
        } else {
          // print("[HomeScreen] Warning: Signal Protocol context reset failed");
        }

        // 3. Reset database (only if clearing data)
        final dbService = Provider.of<DatabaseService>(context, listen: false);
        await dbService.resetDatabase();
        // print("[HomeScreen] Database reset");
      } else {
        // Just reset in-memory state without clearing persistent data
        // print("[HomeScreen] Keeping Signal Protocol keys and database");
        await SignalService.resetUserContext(); // Reset in-memory state only
      }

      // 4. Disconnect WebSocket (always)
      final websocketService = Provider.of<WebSocketService>(context, listen: false);
      websocketService.disconnect();

      // 5. Firebase logout (always)
      await FirebaseAuth.instance.signOut();
      // print("[HomeScreen] Firebase logout completed");

    } catch (e) {
      // print("[HomeScreen] Error during logout: $e");
      // Continue with navigation even if some cleanup fails
    }

    // 6. Navigate to login screen
    if (context.mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => const LoginScreen()),
            (Route<dynamic> route) => false,
      );
    }
  }



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
      _isDeleteHovering = false;
      _isLeaveHovering = false;
    });
  }

  Future<void> _showGroupActionDialog({required String action}) async {
    if (_selectedConversation == null) return;

    final conversationId = _selectedConversation!.conversationId;
    final chatTitle = _selectedConversation!.chatTitle;

    String title = '';
    String content = '';

    if (action == 'delete') {
      title = 'Delete Group?';
      content = 'Are you sure you want to permanently delete "$chatTitle"? This action cannot be undone.';
    } else if (action == 'leave') {
      title = 'Leave Group?';
      content = 'Are you sure you want to leave "$chatTitle"? You will no longer receive messages from this group.';
    }

    return showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(title),
          content: Text(content),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancel'),
              onPressed: () => Navigator.of(context).pop(),
            ),
            TextButton(
              child: Text(
                action == 'delete' ? 'Delete' : 'Leave',
                style: TextStyle(color: action == 'delete' ? Colors.red : Colors.orange),
              ),
              onPressed: () async {
                Navigator.of(context).pop();
                if (action == 'delete') {
                  await _deleteGroup(conversationId);
                } else if (action == 'leave') {
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
      final url = Uri.parse('https://api.zarqmessenger.com/groups/delete/$conversationId');
      final response = await http.delete(url, headers: {'Authorization': 'Bearer $token'});
      if (mounted) {
        if (response.statusCode == 200) {
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Group deleted successfully!')));
          Provider.of<HomeProvider>(context, listen: false).fetchInitialConversations();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('Failed to delete group: ${response.body}'),
              backgroundColor: Colors.red));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Error deleting group: $e'), backgroundColor: Colors.red));
      }
    }
  }

  Future<void> _leaveGroup(int conversationId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final token = await user.getIdToken();
    try {
      final url = Uri.parse('https://api.zarqmessenger.com/groups/leave/$conversationId');
      final response = await http.post(url, headers: {'Authorization': 'Bearer $token'});
      if (mounted) {
        if (response.statusCode == 200) {
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Successfully left group!')));
          Provider.of<HomeProvider>(context, listen: false).fetchInitialConversations();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('Failed to leave group: ${response.body}'),
              backgroundColor: Colors.red));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Error leaving group: $e'), backgroundColor: Colors.red));
      }
    }
  }

  Widget _buildAvatar(ConversationInfo convo) {
    final hasImage = convo.avatarUrl != null && convo.avatarUrl!.isNotEmpty;
    final title = convo.chatTitle;
    final initial = title.isNotEmpty ? title[0].toUpperCase() : '?';
    final colorSeed = title.hashCode;
    final color = Color(colorSeed).withOpacity(1.0).withBlue(200).withGreen(150);

    // Responsive sizing
    final screenWidth = MediaQuery.of(context).size.width;
    final avatarSize = (screenWidth * 0.12).clamp(40.0, 56.0);
    final fontSize = (screenWidth * 0.05).clamp(18.0, 22.0);
    final progressSize = (screenWidth * 0.05).clamp(18.0, 24.0);
    final unreadBadgeSize = (screenWidth * 0.03).clamp(10.0, 14.0);

    return Stack(
      children: [
        Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: Colors.black,
              width: 2.0,
            ),
          ),
          child: hasImage
              ? CachedNetworkImage(
                  imageUrl: convo.avatarUrl!,
                  imageBuilder: (context, imageProvider) => CircleAvatar(
                    radius: avatarSize / 2,
                    backgroundImage: imageProvider,
                    backgroundColor: Colors.transparent,
                  ),
                  placeholder: (context, url) => CircleAvatar(
                    radius: avatarSize / 2,
                    backgroundColor: color,
                    child: SizedBox(
                      width: progressSize,
                      height: progressSize,
                      child: const CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    ),
                  ),
                  errorWidget: (context, url, error) => CircleAvatar(
                    radius: avatarSize / 2,
                    backgroundColor: color,
                    child: Text(
                      initial,
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: fontSize,
                      ),
                    ),
                  ),
                )
              : CircleAvatar(
                  radius: avatarSize / 2,
                  backgroundColor: color,
                  child: Text(
                    initial,
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: fontSize,
                    ),
                  ),
                ),
        ),
        if (convo.hasUnreadMessages)
          Positioned(
            right: 0,
            top: 0,
            child: BreathingUnreadBadge(size: unreadBadgeSize),
          ),
      ],
    );
  }

  PreferredSizeWidget _buildAppBar({required bool isDarkTheme}) {
    final bool isCreatorOfSelectedGroup = _isGroupSelectionMode &&
        _selectedConversation != null &&
        _selectedConversation!.creatorUid == _currentUserUid;
    final bool currentUserHasImage = _currentUserAvatarUrl != null &&
        _currentUserAvatarUrl!.isNotEmpty;

    // Responsive sizing
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final userAvatarRadius = (screenWidth * 0.075).clamp(25.0, 35.0);
    final userAvatarFontSize = (screenWidth * 0.045).clamp(16.0, 20.0);
    final actionButtonSize = (screenWidth * 0.1).clamp(36.0, 44.0);
    final actionIconSize = (screenWidth * 0.06).clamp(22.0, 26.0);
    final titleFontSize = (screenWidth * 0.05).clamp(18.0, 24.0);

    // Theme colors
    final Color textColor = isDarkTheme ? Colors.white : Colors.black87;
    final Color iconColor = isDarkTheme ? Colors.white : Colors.black87;
    final Color appBarBgColor = isDarkTheme ? const Color(0xFF0a1128) : Colors.white;

    return PreferredSize(
      preferredSize: const Size.fromHeight(kToolbarHeight),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: _isGroupSelectionMode ? null : appBarBgColor,
          gradient: _isGroupSelectionMode
              ? const LinearGradient(colors: [Colors.green, Colors.teal],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight)
              : null,
        ),
        child: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          titleTextStyle: Theme.of(context).textTheme.titleLarge?.copyWith(
            color: textColor,
            fontWeight: FontWeight.bold,
            fontSize: titleFontSize,
          ),
          iconTheme: IconThemeData(color: _isGroupSelectionMode ? Colors.white : iconColor),
          leading: _isGroupSelectionMode
              ? IconButton(icon: const Icon(Icons.close), onPressed: _exitGroupSelectionMode)
              : MouseRegion(
            onEnter: (_) => setState(() => _isAvatarHovering = true),
            onExit: (_) => setState(() => _isAvatarHovering = false),
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: () async {
                await Navigator.of(context).push(MaterialPageRoute(
                    builder: (context) => const SettingsScreen()));
                _refreshUserData();
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: EdgeInsets.all(screenWidth * 0.02),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFFF0F2F5),
                  border: Border.all(
                    color: Colors.black,
                    width: 2.0
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.lightBlueAccent.withOpacity(_isAvatarHovering ? 0.6 : 0.3),
                      blurRadius: _isAvatarHovering ? 8 : 5,
                    ),
                  ],
                ),
                child: AnimatedProfileAvatar(
                  imageUrl: currentUserHasImage ? _currentUserAvatarUrl : null,
                  size: userAvatarRadius * 2,
                  enableAnimation: true,
                  flipDuration: const Duration(milliseconds: 800),
                  displayDuration: const Duration(seconds: 4),
                ),
              ),
            ),
          ),
          title: Text(_isGroupSelectionMode ? _selectedConversation!.chatTitle : 'Zarq'),
          centerTitle: true,
          actions: [
            if (_isGroupSelectionMode) ...[
              // Group actions remain the same...
              if (isCreatorOfSelectedGroup)
                MouseRegion(
                  onEnter: (_) => setState(() => _isDeleteHovering = true),
                  onExit: (_) => setState(() => _isDeleteHovering = false),
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    onTap: () => _showGroupActionDialog(action: 'delete'),
                    child: AnimatedScale(
                      scale: _isDeleteHovering ? 1.1 : 1.0,
                      duration: const Duration(milliseconds: 200),
                      child: Tooltip(
                        message: 'Delete Group',
                        child: Container(
                          margin: EdgeInsets.symmetric(
                            horizontal: screenWidth * 0.03,
                            vertical: screenHeight * 0.01,
                          ),
                          width: actionButtonSize,
                          height: actionButtonSize,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: const LinearGradient(
                                colors: [Color(0xFFE57373), Color(0xFFD32F2F)],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.red.withOpacity(_isDeleteHovering ? 0.7 : 0.3),
                                spreadRadius: _isDeleteHovering ? 3 : 1,
                                blurRadius: _isDeleteHovering ? 5 : 3,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Icon(Icons.delete_outline, color: Colors.white, size: actionIconSize),
                        ),
                      ),
                    ),
                  ),
                ),
              if (!isCreatorOfSelectedGroup)
                MouseRegion(
                  onEnter: (_) => setState(() => _isLeaveHovering = true),
                  onExit: (_) => setState(() => _isLeaveHovering = false),
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    onTap: () => _showGroupActionDialog(action: 'leave'),
                    child: AnimatedScale(
                      scale: _isLeaveHovering ? 1.1 : 1.0,
                      duration: const Duration(milliseconds: 200),
                      child: Tooltip(
                        message: 'Leave Group',
                        child: Container(
                          margin: EdgeInsets.symmetric(
                            horizontal: screenWidth * 0.03,
                            vertical: screenHeight * 0.01,
                          ),
                          width: actionButtonSize,
                          height: actionButtonSize,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: const LinearGradient(
                                colors: [Color(0xFFFFB74D), Color(0xFFF57C00)],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.orange.withOpacity(_isLeaveHovering ? 0.7 : 0.3),
                                spreadRadius: _isLeaveHovering ? 3 : 1,
                                blurRadius: _isLeaveHovering ? 5 : 3,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Icon(Icons.exit_to_app, color: Colors.white, size: actionIconSize),
                        ),
                      ),
                    ),
                  ),
                ),
            ] else ...[
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert),
                color: const Color(0xFF1b263b).withOpacity(0.8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15.0),
                  side: BorderSide(color: Colors.white.withOpacity(0.2)),
                ),
                itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                  PopupMenuItem<String>(
                    value: 'settings',
                    child: Row(
                      children: [
                        const Icon(Icons.settings, color: Colors.white),
                        const SizedBox(width: 10),
                        const Text('Settings', style: TextStyle(color: Colors.white)),
                      ],
                    ),
                  ),
                  PopupMenuItem<String>(
                    value: 'call_history',
                    child: Row(
                      children: [
                        const Icon(Icons.history, color: Colors.green),
                        const SizedBox(width: 10),
                        const Text('Call History', style: TextStyle(color: Colors.white)),
                      ],
                    ),
                  ),
                  PopupMenuItem<String>(
                    value: 'about',
                    child: Row(
                      children: [
                        const Icon(Icons.info_outline, color: Colors.cyanAccent),
                        const SizedBox(width: 10),
                        const Text('About', style: TextStyle(color: Colors.white)),
                      ],
                    ),
                  ),
                  const PopupMenuDivider(),
                  PopupMenuItem<String>(
                    value: 'logout',
                    child: Row(
                      children: [
                        const Icon(Icons.logout, color: Colors.orange),
                        const SizedBox(width: 10),
                        const Text('Logout', style: TextStyle(color: Colors.white)),
                      ],
                    ),
                  ),
                  PopupMenuItem<String>(
                    value: 'logout_clear',
                    child: Row(
                      children: [
                        Icon(Icons.delete_forever, color: Colors.redAccent.withOpacity(0.8)),
                        const SizedBox(width: 10),
                        const Text('Logout & Clear Data', style: TextStyle(color: Colors.white)),
                      ],
                    ),
                  ),
                ],
                onSelected: (String result) async {
                  if (result == 'logout') {
                    _showLogoutDialog(context);
                  } else if (result == 'logout_clear') {
                    _showLogoutWithClearDataDialog(context);
                  } else if (result == 'settings') {
                    await Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) => const SettingsScreen(),
                      ),
                    );
                    _refreshUserData();
                  } else if (result == 'call_history') {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) => const CallHistoryScreen(),
                      ),
                    );
                  } else if (result == 'about') {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) => const AboutScreen(),
                      ),
                    );
                  }
                },
              ),
            ],
          ],
        ),
      ),
    );
  }


  Widget _buildConversationList(List<ConversationInfo> conversations, bool isReady, bool isDarkTheme) {
    // Responsive sizing
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
    final listItemMargin = EdgeInsets.symmetric(
      horizontal: screenWidth * 0.03,
      vertical: screenHeight * 0.008,
    );
    final listItemTitleSize = (screenWidth * 0.04).clamp(14.0, 18.0);
    final badgeFontSize = (screenWidth * 0.025).clamp(9.0, 12.0);
    final badgeIconSize = (screenWidth * 0.03).clamp(11.0, 14.0);

    // Theme colors
    final Color searchBgColor = isDarkTheme ? const Color(0xFF1E1E1E) : const Color(0xFFF0F2F5);
    final Color searchTextColor = isDarkTheme ? Colors.white : Colors.black87;
    final Color searchHintColor = isDarkTheme ? Colors.grey.shade400 : Colors.grey.shade500;
    final Color searchIconColor = isDarkTheme ? Colors.grey.shade400 : Colors.grey.shade600;
    final Color cardBgColor = isDarkTheme ? const Color(0xFF1E1E1E) : Colors.lightBlue[50]!;
    final Color cardBorderColor = isDarkTheme ? Colors.cyanAccent.withOpacity(0.3) : Colors.lightBlue[200]!;
    final Color titleColor = isDarkTheme ? Colors.white : Colors.black;
    final Color noResultsColor = isDarkTheme ? Colors.grey.shade400 : Colors.grey.shade600;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: searchPadding,
          child: Container(
            decoration: BoxDecoration(
              color: searchBgColor,
              borderRadius: BorderRadius.circular(10.0),
              border: Border.all(
                color: Colors.transparent
              ),
            ),
            child: TextField(
              controller: _searchController,
              focusNode: _searchFocusNode,
              cursorColor: isDarkTheme ? Colors.white : Colors.black,
              style: TextStyle(
                color: searchTextColor,
                fontSize: searchFontSize,
              ),
              decoration: InputDecoration(
                hintText: 'Search chats...',
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
        Expanded(
          child: conversations.isEmpty
              ? Center(
            child: Text(
              _isSearching
                  ? "No results found for '${_searchController.text}'"
                  : "You have no conversations yet.",
              style: TextStyle(
                color: noResultsColor,
                fontSize: searchFontSize,
              ),
            ),
          )
              : ListView.builder(
            itemCount: conversations.length,
            itemBuilder: (context, index) {
              final convo = conversations[index];
              final isSelected = _isGroupSelectionMode &&
                  _selectedConversation?.conversationId == convo.conversationId;
              return Container(
                margin: listItemMargin,
                decoration: BoxDecoration(
                  color: isSelected
                      ? Colors.teal.withOpacity(0.3)
                      : cardBgColor,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isSelected
                        ? Colors.teal
                        : cardBorderColor,
                    width: 1.0,
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
                  leading: _buildAvatar(convo),
                  title: Row(
                    children: [
                      Expanded(
                        child: Text(
                          convo.chatTitle,
                          style: TextStyle(
                            color: titleColor,
                            fontWeight: FontWeight.bold,
                            fontSize: listItemTitleSize,
                          ),
                        ),
                      ),
                      // Show blocked badge for blocked users
                      if (!convo.isGroup && convo.partnerUid != null && _blockedUsers.contains(convo.partnerUid))
                        Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: screenWidth * 0.02,
                            vertical: screenHeight * 0.005,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.red[100],
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.red[300]!, width: 1),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.block, size: badgeIconSize, color: Colors.red[700]),
                              SizedBox(width: screenWidth * 0.01),
                              Text(
                                'Blocked',
                                style: TextStyle(
                                  color: Colors.red[900],
                                  fontSize: badgeFontSize,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                  trailing: convo.unreadCount > 0
                      ? Container(
                          width: (screenWidth * 0.08).clamp(28.0, 36.0),
                          height: (screenWidth * 0.08).clamp(28.0, 36.0),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Colors.black,
                              width: 2.0,
                            ),
                          ),
                          child: Center(
                            child: Text(
                              convo.unreadCount > 99 ? '99+' : '${convo.unreadCount}',
                              style: TextStyle(
                                color: Colors.black,
                                fontSize: (screenWidth * 0.035).clamp(11.0, 14.0),
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.5,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        )
                      : null,
                  onTap: () async {
                    if (_isGroupSelectionMode) {
                      _exitGroupSelectionMode();
                    } else {
                      final websocketService = Provider.of<WebSocketService>(context, listen: false);

                      // 🚀 OFFLINE MODE: Try to get or create WebSocket channel
                      WebSocketChannel? channel = websocketService.channel;

                        if (channel == null) {
                          // Try to connect with current user's token
                          final user = FirebaseAuth.instance.currentUser;
                          if (user != null) {
                            try {
                              final token = await user.getIdToken();
                              await websocketService.connect(token);
                              channel = websocketService.channel;
                            } catch (e) {
                              // Offline mode - can't connect
                              print('[HomeScreen] ⚠️ Could not connect WebSocket (offline?): $e');
                            }
                          }
                        }

                      // Mark conversation as read
                      Provider.of<HomeProvider>(context, listen: false)
                          .markConversationAsRead(convo.conversationId);

                      // Navigate to chat screen (works online and offline!)
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (context) => ChatScreen(
                            channel: channel, // Can be null in offline mode
                            conversationInfo: convo,
                          ),
                        ),
                      ).then((_) {
                        // Reload blocked users when coming back from chat
                        _loadBlockedUsers();
                      });

                      // Show offline indicator if no channel
                      if (channel == null) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('📴 Offline mode - Viewing cached messages'),
                            duration: Duration(seconds: 2),
                            backgroundColor: Colors.orange,
                          ),
                        );
                      }
                    }
                  },
                  onLongPress: () {
                    if (convo.isGroup) {
                      _enterGroupSelectionMode(convo);
                    }
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget? _buildFab(bool isReady) {
    if (_isGroupSelectionMode) return null; // FAB disappears completely

    const isLightTheme = true; // Always light theme

    return ExpandableFab(
      distance: 112.0,
      isLightTheme: isLightTheme,
      children: [
        ActionButton(
          onPressed: isReady
              ? () {
            final websocketService = Provider.of<WebSocketService>(context, listen: false);
            if (websocketService.isConnected && websocketService.channel != null) {
              Navigator.of(context)
                  .push(MaterialPageRoute(
                  builder: (context) => FindFriendsScreen(
                    channel: websocketService.channel!,
                  )))
                  .then((_) => Provider.of<HomeProvider>(context, listen: false)
                  .fetchInitialConversations());
            } else {
              ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Still connecting... Please wait a moment.')));
            }
          }
              : null,
          icon: const Icon(Icons.person_add, color: Colors.white),
          isLightTheme: isLightTheme,
        ),
        ActionButton(
          onPressed: isReady
              ? () {
            final websocketService = Provider.of<WebSocketService>(context, listen: false);
            if (websocketService.isConnected && websocketService.channel != null) {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => CreateGroupScreen(
                    channel: websocketService.channel!,
                    onGroupCreated: () => Provider.of<HomeProvider>(context, listen: false)
                        .fetchInitialConversations(),
                  ),
                ),
              );
            } else {
              ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Still connecting... Please wait a moment.')));
            }
          }
              : null,
          icon: const Icon(Icons.group_add, color: Colors.white),
          isLightTheme: isLightTheme,
        ),
      ],
    );
  }


  @override
  Widget build(BuildContext context) {
    return Consumer<UserSettingsProvider>(
      builder: (context, userSettings, child) {
        final isDarkTheme = userSettings.homeScreenStyle == 'dark';

        return CallAwareScreen(
          screenName: 'HomeScreen',
          child: Scaffold(
            backgroundColor: isDarkTheme ? const Color(0xFF121212) : Colors.white,
            appBar: _buildAppBar(isDarkTheme: isDarkTheme),
        body: Builder(
          builder: (context) {
            print('[HomeScreen] Building body, _isGroupSelectionMode: $_isGroupSelectionMode');
            return Stack(
              children: [
                // Main conversation list
                Consumer2<HomeProvider, WebSocketService>(
                  builder: (context, homeProvider, websocketService, child) {
                    final conversations = _isSearching ? _filteredConversations : homeProvider.conversations;
                    final isReady = websocketService.isConnected;

                    return _buildConversationList(conversations, isReady, isDarkTheme);
                  },
                ),

                // Floating AI button (only show when not in group selection mode) - MUST be after conversation list to appear on top
                if (!_isGroupSelectionMode) ...[
                  Builder(
                    builder: (context) {
                      print('[HomeScreen] Building AI button in Stack');
                      return _buildFloatingAIButton(isDarkTheme);
                    },
                  ),
                ],
              ],
            );
          },
        ),
            bottomNavigationBar: _isGroupSelectionMode ? null : Consumer<WebSocketService>(
              builder: (context, websocketService, child) {
                return _buildBottomNavBar(websocketService.isConnected, isDarkTheme);
              },
            ),
          ),
        );
      },
    );
  }

  Widget _buildFloatingAIButton(bool isDarkTheme) {
    print('[HomeScreen] _buildFloatingAIButton called');

    final bottomPadding = MediaQuery.of(context).padding.bottom;

    // Adjust this number to move button up/down
    // Higher number = button goes UP (away from bottom)
    final bottomPosition = 50.0 - bottomPadding;

    // Theme colors
    final Color buttonBgColor = isDarkTheme ? const Color(0xFF1E1E1E) : Colors.white;
    final Color buttonTextColor = isDarkTheme ? Colors.cyanAccent : Colors.black;
    final Color buttonBorderColor = isDarkTheme ? Colors.cyanAccent : Colors.black;

    return Positioned(
      right: 16,
      bottom: bottomPosition,
      child: GestureDetector(
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => const AIChatScreen(),
            ),
          );
        },
        child: Container(
          width: 60,
          height: 60,
          decoration: BoxDecoration(
            color: buttonBgColor,
            shape: BoxShape.circle,
            border: Border.all(
              color: buttonBorderColor,
              width: 2.5,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.2),
                blurRadius: 12,
                spreadRadius: 1,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Center(
            child: Text(
              'AI',
              style: TextStyle(
                color: buttonTextColor,
                fontSize: 24,
                fontWeight: FontWeight.w900,
                letterSpacing: 1,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBottomNavBar(bool isReady, bool isDarkTheme) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    // Theme colors
    final Color navBgColor = isDarkTheme ? const Color(0xFF0a1128) : Colors.white;
    final Color navBorderColor = isDarkTheme ? Colors.cyanAccent.withOpacity(0.3) : Colors.black;

    return Container(
      padding: EdgeInsets.only(
        left: screenWidth * 0.02,
        right: screenWidth * 0.02,
        top: screenHeight * 0.015,
        bottom: MediaQuery.of(context).padding.bottom + screenHeight * 0.015,
      ),
      decoration: BoxDecoration(
        color: navBgColor,
        border: Border(
          top: BorderSide(
            color: navBorderColor,
            width: 1,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildNavCard(
            icon: Icons.history,
            label: 'Calls',
            isDarkTheme: isDarkTheme,
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => const CallHistoryScreen(),
                ),
              );
            },
          ),
          _buildNavCard(
            icon: Icons.person_add,
            label: 'Friends',
            isDarkTheme: isDarkTheme,
            onTap: () {
              if (!isReady) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Still connecting... Please wait a moment.')),
                );
                return;
              }
              final websocketService = Provider.of<WebSocketService>(context, listen: false);
              if (websocketService.isConnected && websocketService.channel != null) {
                Navigator.of(context)
                    .push(MaterialPageRoute(
                        builder: (context) => FindFriendsScreen(
                          channel: websocketService.channel!,
                        )))
                    .then((_) => Provider.of<HomeProvider>(context, listen: false)
                        .fetchInitialConversations());
              }
            },
          ),
          _buildNavCard(
            icon: Icons.group_add,
            label: 'Groups',
            isDarkTheme: isDarkTheme,
            onTap: () {
              if (!isReady) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Still connecting... Please wait a moment.')),
                );
                return;
              }
              final websocketService = Provider.of<WebSocketService>(context, listen: false);
              if (websocketService.isConnected && websocketService.channel != null) {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => CreateGroupScreen(
                      channel: websocketService.channel!,
                      onGroupCreated: () => Provider.of<HomeProvider>(context, listen: false)
                          .fetchInitialConversations(),
                    ),
                  ),
                );
              }
            },
          ),
          _buildNavCard(
            icon: Icons.note,
            label: 'Notes',
            isDarkTheme: isDarkTheme,
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => const NotesScreen(),
                ),
              );
            },
          ),
          _buildNavCard(
            icon: Icons.palette,
            label: 'Personalize',
            isDarkTheme: isDarkTheme,
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => const CustomizationScreen(),
                ),
              );
            },
          ),
        ],
      ),
    );
  }


  Widget _buildNavCard({
    required IconData icon,
    required String label,
    required bool isDarkTheme,
    required VoidCallback onTap,
  }) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final navIconSize = (screenWidth * 0.06).clamp(22.0, 28.0);
    final navLabelSize = (screenWidth * 0.028).clamp(10.0, 13.0);
    final navSpacing = (screenHeight * 0.007).clamp(4.0, 8.0);

    // Theme colors
    final Color iconColor = isDarkTheme ? Colors.cyanAccent : Colors.black;
    final Color textColor = isDarkTheme ? Colors.white : Colors.black87;

    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          margin: EdgeInsets.symmetric(horizontal: screenWidth * 0.005),
          padding: EdgeInsets.symmetric(vertical: screenHeight * 0.012),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: iconColor, size: navIconSize),
              SizedBox(height: navSpacing),
              Text(
                label,
                style: TextStyle(
                  color: textColor,
                  fontSize: navLabelSize,
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ],
          ),
        ),
      ),
    );
  }
}