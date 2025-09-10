import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'dart:ui';

// Import Providers
import 'providers/home_provider.dart';
import 'providers/chat_provider.dart';
import 'services/websocket_service.dart';

// Import Screens and Widgets
import 'expandable_fab.dart';
import 'login_screen.dart';
import 'setting_screen.dart';
import 'find_friends_screen.dart';
import 'chat_screen.dart';
import 'home_background.dart';
import 'create_group_screen.dart';


class ConversationInfo {
  final int conversationId;
  final String chatTitle;
  final bool isGroup;
  final String? creatorUid;
  final String? avatarUrl;
  final String? partnerUid;

  ConversationInfo({
    required this.conversationId,
    required this.chatTitle,
    required this.isGroup,
    this.creatorUid,
    this.avatarUrl,
    this.partnerUid,
  });

  factory ConversationInfo.fromJson(Map<String, dynamic> json) {
    return ConversationInfo(
      conversationId: json['conversationId'] as int,
      chatTitle: json['chatTitle'] ?? 'Unknown',
      isGroup: json['isGroup'],
      creatorUid: json['creatorUid'] as String?,
      avatarUrl: json['avatarUrl'] as String?,
      partnerUid: json['partnerUid'] as String?,
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String _displayName = "User";
  String? _currentUserAvatarUrl;
  String? _currentUserUid;

  bool _isGroupSelectionMode = false;
  ConversationInfo? _selectedConversation;

  final TextEditingController _searchController = TextEditingController();
  List<ConversationInfo> _filteredConversations = [];
  bool _isSearching = false;

  bool _isAvatarHovering = false;
  bool _isDeleteHovering = false;
  bool _isLeaveHovering = false;

@override
void initState() {
  super.initState();
  _initializeUser();
  Provider.of<HomeProvider>(context, listen: false).fetchInitialConversations();
  _searchController.addListener(_onSearchChanged);
}

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
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

  Future<void> _logout(BuildContext context) async {
    final user = FirebaseAuth.instance.currentUser;
    
    final websocketService = Provider.of<WebSocketService>(context, listen: false);
    websocketService.disconnect();
    await FirebaseAuth.instance.signOut();

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
      final url = Uri.parse('http://192.168.29.81:8080/groups/delete/$conversationId');
      final response = await http.delete(url, headers: {'Authorization': 'Bearer $token'});
      if (mounted) {
        if (response.statusCode == 200) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Group deleted successfully!')));
          Provider.of<HomeProvider>(context, listen: false).fetchInitialConversations();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to delete group: ${response.body}'), backgroundColor: Colors.red));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error deleting group: $e'), backgroundColor: Colors.red));
      }
    }
  }

  Future<void> _leaveGroup(int conversationId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final token = await user.getIdToken();
    try {
      final url = Uri.parse('http://192.168.29.81:8080/groups/leave/$conversationId');
      final response = await http.post(url, headers: {'Authorization': 'Bearer $token'});
      if (mounted) {
        if (response.statusCode == 200) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Successfully left group!')));
          Provider.of<HomeProvider>(context, listen: false).fetchInitialConversations();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to leave group: ${response.body}'), backgroundColor: Colors.red));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error leaving group: $e'), backgroundColor: Colors.red));
      }
    }
  }

  Widget _buildAvatar(ConversationInfo convo) {
    final hasImage = convo.avatarUrl != null && convo.avatarUrl!.isNotEmpty;
    final title = convo.chatTitle;
    final initial = title.isNotEmpty ? title[0].toUpperCase() : '?';
    final colorSeed = title.hashCode;
    final color = Color(colorSeed).withOpacity(1.0).withBlue(200).withGreen(150);

    return CircleAvatar(
      backgroundColor: hasImage ? Colors.transparent : color,
      backgroundImage: hasImage ? NetworkImage(convo.avatarUrl!) : null,
      child: hasImage ? null : Text(initial, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 20)),
    );
  }


  PreferredSizeWidget _buildAppBar() {
    final bool isCreatorOfSelectedGroup = _isGroupSelectionMode && _selectedConversation != null && _selectedConversation!.creatorUid == _currentUserUid;
    final bool currentUserHasImage = _currentUserAvatarUrl != null && _currentUserAvatarUrl!.isNotEmpty;

    return PreferredSize(
      preferredSize: const Size.fromHeight(kToolbarHeight),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          gradient: _isGroupSelectionMode
              ? const LinearGradient(colors: [Colors.green, Colors.teal], begin: Alignment.topLeft, end: Alignment.bottomRight)
              : null,
        ),
        child: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          titleTextStyle: Theme.of(context).textTheme.titleLarge?.copyWith(color: Colors.white, fontWeight: FontWeight.bold),
          iconTheme: const IconThemeData(color: Colors.white),
          leading: _isGroupSelectionMode
              ? IconButton(icon: const Icon(Icons.close), onPressed: _exitGroupSelectionMode)
              : MouseRegion(
                  onEnter: (_) => setState(() => _isAvatarHovering = true),
                  onExit: (_) => setState(() => _isAvatarHovering = false),
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    onTap: () async {
                      await Navigator.of(context).push(MaterialPageRoute(builder: (context) => const SettingsScreen()));
                      _refreshUserData();
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.all(8.0),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withOpacity(0.1),
                        border: Border.all(color: Colors.white.withOpacity(0.3), width: 1.5),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.cyanAccent.withOpacity(_isAvatarHovering ? 0.8 : 0.5),
                            blurRadius: _isAvatarHovering ? 8 : 5,
                          ),
                        ],
                      ),
                      child: CircleAvatar(
                        radius: 30,
                        backgroundColor: Colors.transparent,
                        backgroundImage: currentUserHasImage ? NetworkImage(_currentUserAvatarUrl!) : null,
                        child: !currentUserHasImage
                            ? Text(
                                _displayName.isNotEmpty ? _displayName[0].toUpperCase() : '?',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 18,
                                  shadows: [Shadow(blurRadius: 3.0, color: Colors.cyanAccent)],
                                ),
                              )
                            : null,
                      ),
                    ),
                  ),
                ),
          title: Text(_isGroupSelectionMode ? _selectedConversation!.chatTitle : 'Zarq'),
          centerTitle: true,
          actions: [
            if (_isGroupSelectionMode) ...[
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
                          margin: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: const LinearGradient(colors: [Color(0xFFE57373), Color(0xFFD32F2F)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.red.withOpacity(_isDeleteHovering ? 0.7 : 0.3),
                                spreadRadius: _isDeleteHovering ? 3 : 1,
                                blurRadius: _isDeleteHovering ? 5 : 3,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: const Icon(Icons.delete_outline, color: Colors.white, size: 24),
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
                          margin: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: const LinearGradient(colors: [Color(0xFFFFB74D), Color(0xFFF57C00)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.orange.withOpacity(_isLeaveHovering ? 0.7 : 0.3),
                                spreadRadius: _isLeaveHovering ? 3 : 1,
                                blurRadius: _isLeaveHovering ? 5 : 3,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: const Icon(Icons.exit_to_app, color: Colors.white, size: 24),
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
                    value: 'p2p_chat',
                    child: Row(
                      children: [
                        Icon(Icons.video_call_outlined, color: Colors.cyanAccent.withOpacity(0.8)),
                        const SizedBox(width: 10),
                        const Text('Start P2P Chat', style: TextStyle(color: Colors.white)),
                      ],
                    ),
                  ),
                  PopupMenuItem<String>(
                    value: 'logout',
                    child: Row(
                      children: [
                        Icon(Icons.logout, color: Colors.redAccent.withOpacity(0.8)),
                        const SizedBox(width: 10),
                        const Text('Logout', style: TextStyle(color: Colors.white)),
                      ],
                    ),
                  ),
                ],
                onSelected: (String result) {
                  final websocketService = Provider.of<WebSocketService>(context, listen: false);
                  switch (result) {
                    case 'p2p_chat':
                      if (websocketService.isConnected && websocketService.channel != null) {
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('WebSocket not connected. Cannot start P2P chat.')));
                      }
                      break;
                    case 'logout':
                      _logout(context);
                      break;
                  }
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildConversationList(List<ConversationInfo> conversations, bool isReady) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16.0, 8.0, 16.0, 8.0),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(30.0),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 3, sigmaY: 3),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(30.0),
                  border: Border.all(color: Colors.white.withOpacity(0.2)),
                ),
                child: TextField(
                  controller: _searchController,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'Search chats...',
                    hintStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
                    prefixIcon: Icon(Icons.search, color: Colors.white.withOpacity(0.7)),
                    suffixIcon: _isSearching
                        ? IconButton(
                            icon: const Icon(Icons.clear, color: Colors.white70),
                            onPressed: () {
                              _searchController.clear();
                              FocusScope.of(context).unfocus();
                            },
                          )
                        : null,
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                  ),
                ),
              ),
            ),
          ),
        ),
        Expanded(
          child: conversations.isEmpty
              ? Center(
                  child: Text(
                    _isSearching ? "No results found for '${_searchController.text}'" : "You have no conversations yet.",
                    style: const TextStyle(color: Colors.white70, fontSize: 16),
                  ),
                )
              : ListView.builder(
                  itemCount: conversations.length,
                  itemBuilder: (context, index) {
                    final convo = conversations[index];
                    final isSelected = _isGroupSelectionMode && _selectedConversation?.conversationId == convo.conversationId;
                    return Card(
                      color: isSelected ? Colors.teal.withOpacity(0.3) : Colors.transparent,
                      elevation: 0,
                      child: ListTile(
                        leading: _buildAvatar(convo),
                        title: Text(convo.chatTitle, style: const TextStyle(color: Colors.white)),
                        onTap: isReady
                            ? () {
                                if (_isGroupSelectionMode) {
                                  _exitGroupSelectionMode();
                                } else {
                                  final websocketService = Provider.of<WebSocketService>(context, listen: false);
                                  if (websocketService.isConnected && websocketService.channel != null) {
                                    Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (context) => ChatScreen(
                                          channel: websocketService.channel!,
                                          conversationInfo: convo,
                                        ),
                                      ),
                                    );
                                  }
                                }
                              }
                            : null,
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
    if (_isGroupSelectionMode) return null;

    return ExpandableFab(
      distance: 112.0,
      children: [
        ActionButton(
          onPressed: isReady ? () {
            final websocketService = Provider.of<WebSocketService>(context, listen: false);
            if (websocketService.isConnected && websocketService.channel != null) {
              Navigator.of(context)
                  .push(MaterialPageRoute(builder: (context) => FindFriendsScreen(channel: websocketService.channel!)))
                  .then((_) => Provider.of<HomeProvider>(context, listen: false).fetchInitialConversations());
            } else {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Still connecting... Please wait a moment.')));
            }
          } : null,
          icon: const Icon(Icons.person_add, color: Colors.white),
        ),
        ActionButton(
          onPressed: isReady ? () {
            final websocketService = Provider.of<WebSocketService>(context, listen: false);
            if (websocketService.isConnected && websocketService.channel != null) {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => CreateGroupScreen(
                    channel: websocketService.channel!,
                    onGroupCreated: () => Provider.of<HomeProvider>(context, listen: false).fetchInitialConversations(),
                  ),
                ),
              );
            } else {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Still connecting... Please wait a moment.')));
            }
          } : null,
          icon: const Icon(Icons.group_add, color: Colors.white),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Home Screen"),
      ),
      body: Center(
        child: Text("✅ HomeScreen loaded after registration"),
      ),
    );
  }
}
