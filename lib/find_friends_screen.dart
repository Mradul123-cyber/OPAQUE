// lib/find_friends_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:io' show Platform;
import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'dart:math' as math;
import 'services/websocket_service.dart';

class Friend {
  final String username;
  final String? avatarUrl;

  Friend({required this.username, this.avatarUrl});

  factory Friend.fromJson(Map<String, dynamic> json) {
    // --- CHANGE ---
    // Updated the key to match the Go backend's JSON struct tag.
    return Friend(
      username: json['username'] ?? 'Unknown',
      avatarUrl: json['avatarUrl'],
    );
  }
}

enum FriendTab { myFriends, sentRequests, receivedRequests, search }

// A class to hold the properties of a single star
class _Star {
  final math.Random random;
  final double size;
  final double initialX;
  final double initialY;
  double opacity;
  final int offset;

  _Star(this.random, double screenWidth, double screenHeight)
    : size = 2.0 + random.nextDouble() * 3,
      initialX = random.nextDouble() * screenWidth,
      initialY = random.nextDouble() * screenHeight,
      opacity = random.nextDouble(),
      offset = random.nextInt(1000);

  void updateOpacity(double animationValue) {
    final t = (animationValue + offset / 1000) % 1.0;
    opacity = math.sin(t * math.pi * 2) * 0.5 + 0.5;
  }
}

// CustomPainter to draw all the stars efficiently on a single canvas
class _StarPainter extends CustomPainter {
  final List<_Star> stars;
  final Animation<double> animation;

  _StarPainter(this.stars, this.animation) : super(repaint: animation);

  @override
  void paint(Canvas canvas, Size size) {
    for (final star in stars) {
      final paint = Paint()..color = Colors.white.withOpacity(star.opacity);
      canvas.drawCircle(
        Offset(star.initialX, star.initialY),
        star.size / 2,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class FindFriendsScreen extends StatefulWidget {
  final FriendTab initialTab;
  final WebSocketChannel channel;
  final VoidCallback? onFriendRequestAccepted;

  const FindFriendsScreen({
    super.key,
    this.initialTab = FriendTab.search,
    required this.channel,
    this.onFriendRequestAccepted,
  });

  @override
  State<FindFriendsScreen> createState() => _FindFriendsScreenState();
}

class _FindFriendsScreenState extends State<FindFriendsScreen>
    with TickerProviderStateMixin {
  late TabController _tabController;
  final _searchController = TextEditingController();
  bool _isLoading = false;
  String _statusMessage =
      "Use the search bar or scan contacts to find friends.";
  Timer? _debounce;
  final _scrollController = ScrollController();

  List<Friend> _myFriends = [];
  // --- CHANGE ---
  // Changed from List<String> to List<Friend> to hold avatar URLs.
  List<Friend> _sentRequests = [];
  List<Friend> _receivedRequests = [];
  List<Friend> _searchResults = [];

  final Set<String> _pendingRequests = {};

  late final AnimationController _animationController;
  late final Animation<Color?> _colorAnimation;
  final List<_Star> _stars = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 4,
      vsync: this,
      initialIndex: widget.initialTab.index,
    );
    _searchController.addListener(_onSearchChanged);
    _loadTabContent(widget.initialTab.index);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        _loadTabContent(_tabController.index);
        _searchController.clear();
      }
    });

    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 15),
    )..repeat();

    _colorAnimation =
        ColorTween(
          begin: const Color(0xFF0F0038),
          end: const Color(0xFF2E2E6B),
        ).animate(
          CurvedAnimation(
            parent: _animationController,
            curve: Curves.easeInOut,
          ),
        );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_stars.isEmpty) {
      final random = math.Random();
      final screenWidth = MediaQuery.of(context).size.width;
      final screenHeight = MediaQuery.of(context).size.height;
      for (int i = 0; i < 50; i++) {
        _stars.add(_Star(random, screenWidth, screenHeight));
      }
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _debounce?.cancel();
    _animationController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _updateUsernameInState(String oldUsername, String newUsername) {
    setState(() {
      final friendIndex = _myFriends.indexWhere(
        (f) => f.username == oldUsername,
      );
      if (friendIndex != -1) {
        _myFriends[friendIndex] = Friend(
          username: newUsername,
          avatarUrl: _myFriends[friendIndex].avatarUrl,
        );
      }

      // --- CHANGE ---
      // Updated logic to work with List<Friend>.
      final sentRequestIndex = _sentRequests.indexWhere(
        (f) => f.username == oldUsername,
      );
      if (sentRequestIndex != -1) {
        _sentRequests[sentRequestIndex] = Friend(
          username: newUsername,
          avatarUrl: _sentRequests[sentRequestIndex].avatarUrl,
        );
      }

      // --- CHANGE ---
      // Updated logic to work with List<Friend>.
      final receivedRequestIndex = _receivedRequests.indexWhere(
        (f) => f.username == oldUsername,
      );
      if (receivedRequestIndex != -1) {
        _receivedRequests[receivedRequestIndex] = Friend(
          username: newUsername,
          avatarUrl: _receivedRequests[receivedRequestIndex].avatarUrl,
        );
      }

      final searchResultIndex = _searchResults.indexWhere(
        (f) => f.username == oldUsername,
      );
      if (searchResultIndex != -1) {
        _searchResults[searchResultIndex] = Friend(
          username: newUsername,
          avatarUrl: _searchResults[searchResultIndex].avatarUrl,
        );
      }
    });
  }

  Future<void> _loadTabContent(int tabIndex) async {
    setState(() {
      _isLoading = true;
      _statusMessage = "Loading...";
      if (FriendTab.values[tabIndex] != FriendTab.search) {
        _searchResults = [];
      }
    });

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception("Not logged in.");
      final token = await user.getIdToken();
      if (token == null) throw Exception("Authentication token not available.");

      // Fetch all necessary data in parallel for a faster experience
      await Future.wait([
        _fetchMyFriends(token),
        _fetchSentRequests(token),
        _fetchReceivedRequests(token),
      ]);

      // Update status message based on the currently viewed tab
      switch (FriendTab.values[tabIndex]) {
        case FriendTab.myFriends:
          _statusMessage = _myFriends.isEmpty
              ? "You don't have any friends yet."
              : "You have ${_myFriends.length} friends.";
          break;
        case FriendTab.sentRequests:
          _statusMessage = _sentRequests.isEmpty
              ? "No pending requests sent by you."
              : "You have sent ${_sentRequests.length} pending requests.";
          break;
        case FriendTab.receivedRequests:
          _statusMessage = _receivedRequests.isEmpty
              ? "No pending friend requests."
              : "You have ${_receivedRequests.length} pending requests.";
          break;
        case FriendTab.search:
          _statusMessage = "Search for friends by their username.";
          break;
      }
    } catch (e) {
      if (mounted) _statusMessage = "Failed to load data: $e";
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _fetchMyFriends(String token) async {
    try {
      final url = Uri.parse('http://192.168.29.81:8080/friends/list');
      final response = await http.get(
        url,
        headers: {'Authorization': 'Bearer $token'},
      );
      if (response.statusCode == 200) {
        final List<dynamic> friendsFromServer = json.decode(response.body);
        if (mounted) {
          setState(() {
            _myFriends = friendsFromServer
                .map((data) => Friend.fromJson(data))
                .toList();
          });
        }
      } else {
        throw Exception('Failed to load friends: ${response.body}');
      }
    } catch (e) {
      throw Exception('Error fetching my friends: $e');
    }
  }

  Future<void> _fetchSentRequests(String token) async {
    try {
      final url = Uri.parse('http://192.168.29.81:8080/friends/sent-requests');
      final response = await http.get(
        url,
        headers: {'Authorization': 'Bearer $token'},
      );
      if (response.statusCode == 200) {
        final List<dynamic> requestsFromServer = json.decode(response.body);
        if (mounted) {
          setState(() {
            // --- CHANGE ---
            // Now parsing a list of Friend objects directly from JSON.
            _sentRequests = requestsFromServer
                .map((data) => Friend.fromJson(data))
                .toList();

            // Rebuild the set of pending usernames from the new list.
            _pendingRequests.clear();
            _pendingRequests.addAll(_sentRequests.map((f) => f.username));
          });
        }
      } else {
        throw Exception('Failed to load sent requests: ${response.body}');
      }
    } catch (e) {
      throw Exception('Error fetching sent requests: $e');
    }
  }

  Future<void> _fetchReceivedRequests(String token) async {
    try {
      final url = Uri.parse('http://192.168.29.81:8080/friends/requests');
      final response = await http.get(
        url,
        headers: {'Authorization': 'Bearer $token'},
      );
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        if (mounted) {
          setState(() {
            // --- CHANGE ---
            // Now parsing a list of Friend objects directly from JSON.
            _receivedRequests =
                data.map((item) => Friend.fromJson(item)).toList();
          });
        }
      } else {
        throw Exception(
          'Failed to load received friend requests: ${response.body}',
        );
      }
    } catch (e) {
      throw Exception('Error fetching received requests: $e');
    }
  }

  Future<void> _acceptRequest(String username) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final token = await user.getIdToken();
    final url = Uri.parse('http://192.168.29.81:8080/friends/accept');

    try {
      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: json.encode({'targetUsername': username}),
      );

      if (mounted) {
        if (response.statusCode == 200) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Accepted friend request from $username!'),
              backgroundColor: Colors.green,
            ),
          );
          // --- CHANGE ---
          // Optimistic UI update: remove the request immediately using the correct method.
          setState(() {
            _receivedRequests
                .removeWhere((friend) => friend.username == username);
          });
          // This call is for data integrity, to refresh the full list.
          _loadTabContent(FriendTab.receivedRequests.index);

          // Call the callback to trigger a refresh on the home screen.
          widget.onFriendRequestAccepted?.call();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to accept request: ${response.body}'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to connect to server.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _sendFriendRequest(String targetUsername) async {
    if (_pendingRequests.contains(targetUsername) ||
        _myFriends.any((f) => f.username == targetUsername)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Request already sent or already friends with $targetUsername!',
          ),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() {
      _pendingRequests.add(targetUsername);
    });

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Error: Not logged in.'),
            backgroundColor: Colors.red,
          ),
        );
        setState(() {
          _pendingRequests.remove(targetUsername);
        });
      }
      return;
    }

    final token = await user.getIdToken();
    final url = Uri.parse('http://192.168.29.81:8080/friends/request');

    try {
      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: json.encode({'targetUsername': targetUsername}),
      );

      if (mounted) {
        if (response.statusCode == 201) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Friend request sent to $targetUsername!'),
              backgroundColor: Colors.green,
            ),
          );
          _loadTabContent(FriendTab.sentRequests.index);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed: ${response.body}'),
              backgroundColor: Colors.red,
            ),
          );
          setState(() {
            _pendingRequests.remove(targetUsername);
          });
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to connect to server.'),
            backgroundColor: Colors.red,
          ),
        );
        setState(() {
          _pendingRequests.remove(targetUsername);
        });
      }
    }
  }

  void _onSearchChanged() {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      _searchUsers(_searchController.text);
    });
  }

  Future<void> _findFriendsInContacts() async {
    setState(() {
      _isLoading = true;
      _statusMessage = "Asking for permission...";
      _searchResults = [];
    });

    if (kIsWeb || (!Platform.isAndroid && !Platform.isIOS)) {
      setState(() {
        _isLoading = false;
        _statusMessage =
            "Contact scanning is only available on mobile devices.";
      });
      return;
    }

    final PermissionStatus permissionStatus = await Permission.contacts.request();
    if (permissionStatus.isGranted) {
      setState(() => _statusMessage = "Permission granted. Scanning contacts...");

      final List<Contact> contacts = await FlutterContacts.getContacts(withProperties: true);
      final List<String> hashedContacts = [];
      for (var contact in contacts) {
        for (var phone in contact.phones) {
          final cleanedPhone = phone.number.replaceAll(RegExp(r'[^0-9+]'), '');
          if (cleanedPhone.isNotEmpty) {
            final bytes = utf8.encode(cleanedPhone);
            final digest = sha256.convert(bytes);
            hashedContacts.add(digest.toString());
          }
        }
      }

      if (hashedContacts.isEmpty) {
        setState(() {
          _isLoading = false;
          _statusMessage = "No phone numbers found in your contacts.";
        });
        return;
      }

      setState(() => _statusMessage = "Found ${hashedContacts.length} contacts. Checking server...");

      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        setState(() {
          _isLoading = false;
          _statusMessage = "Error: Not logged in.";
        });
        return;
      }
      final token = await user.getIdToken();

      try {
        final url = Uri.parse('http://192.168.29.81:8080/friends/find');
        final response = await http.post(
          url,
          headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'},
          body: json.encode(hashedContacts),
        );

        if (response.statusCode == 200) {
          final List<dynamic> foundUsers = json.decode(response.body);
          setState(() {
            _searchResults = foundUsers.map((data) => Friend.fromJson(data)).toList();
            _isLoading = false;
            _statusMessage = _searchResults.isEmpty
                ? "No Zarq users found from your contacts."
                : "Found ${_searchResults.length} Zarq users from your contacts!";
          });
        } else {
          setState(() => _statusMessage = "Error from server: ${response.body}");
        }
      } catch (e) {
        setState(() => _statusMessage = "Failed to connect to server.");
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
    } else {
      setState(() {
        _isLoading = false;
        _statusMessage = "Contact permission denied.";
      });
    }
  }

  Future<void> _searchUsers(String query) async {
    if (query.trim().isEmpty) {
      if (mounted) {
        setState(() {
          _searchResults = [];
          _statusMessage = "Search for friends by their username.";
        });
      }
      return;
    }

    if (mounted) {
      setState(() {
        _isLoading = true;
        _statusMessage = "Searching for '$query'...";
      });
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (mounted)
        setState(() {
          _isLoading = false;
          _statusMessage = "Error: Not logged in.";
        });
      return;
    }
    final token = await user.getIdToken();

    try {
      final url = Uri.parse('http://192.168.29.81:8080/users/search?q=$query');
      final response = await http.get(
        url,
        headers: {'Authorization': 'Bearer $token'},
      );

      if (mounted && response.statusCode == 200) {
        final List<dynamic> foundUsersJson = json.decode(response.body);
        setState(() {
          _searchResults = foundUsersJson
              .map((data) => Friend.fromJson(data))
              .toList();
          _statusMessage = _searchResults.isEmpty
              ? "No users found matching '$query'."
              : "Found ${_searchResults.length} users.";
        });
      } else if (mounted) {
        setState(() {
          _statusMessage = "Error from server: ${response.body}";
        });
      }
    } catch (e) {
      if (mounted)
        setState(() {
          _statusMessage = "Failed to connect to server.";
        });
    } finally {
      if (mounted)
        setState(() {
          _isLoading = false;
        });
    }
  }

  Widget _buildAvatar(String name, String? avatarUrl) {
    final hasImage = avatarUrl != null && avatarUrl.isNotEmpty;
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
    final randomColor = Color(name.hashCode | 0xFF000000).withOpacity(1.0);

    return CircleAvatar(
      backgroundColor: hasImage ? Colors.grey[200] : randomColor,
      backgroundImage: hasImage ? NetworkImage(avatarUrl!) : null,
      child: hasImage
          ? null
          : Text(
              initial,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
    );
  }

  Widget _buildTabContent(List<Friend> listData, FriendTab currentTab) {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.lightBlueAccent),
      );
    }
    if (listData.isEmpty) {
      return Center(
        child: Text(
          _statusMessage,
          style: TextStyle(color: Colors.white.withOpacity(0.7)),
        ),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      itemCount: listData.length,
      itemBuilder: (context, index) {
        final friend = listData[index];
        final isMyFriend = _myFriends.any((f) => f.username == friend.username);
        final isPending = _pendingRequests.contains(friend.username);

        Widget trailingWidget;
        if (isMyFriend) {
          trailingWidget = Chip(
            label: Text(
              'Friends',
              style: TextStyle(color: Colors.white, fontSize: 12),
            ),
            backgroundColor: Colors.lightBlueAccent.withOpacity(0.4),
          );
        } else if (isPending) {
          trailingWidget = Chip(
            label: Text(
              'Pending',
              style: TextStyle(color: Colors.white, fontSize: 12),
            ),
            backgroundColor: Colors.orange.withOpacity(0.4),
          );
        } else if (currentTab == FriendTab.receivedRequests) {
          trailingWidget = Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(
                  Icons.check_circle,
                  color: Colors.lightBlueAccent,
                ),
                tooltip: 'Accept Request',
                onPressed: _isLoading
                    ? null
                    : () => _acceptRequest(friend.username),
              ),
              IconButton(
                icon: const Icon(Icons.cancel, color: Colors.red),
                tooltip: 'Decline Request',
                onPressed: _isLoading
                    ? null
                    : () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'Decline for ${friend.username} not implemented yet',
                            ),
                          ),
                        );
                      },
              ),
            ],
          );
        } else {
          trailingWidget = IconButton(
            icon: const Icon(
              Icons.person_add_alt_1_outlined,
              color: Colors.white,
            ),
            tooltip: 'Send Friend Request',
            onPressed: _isLoading
                ? null
                : () => _sendFriendRequest(friend.username),
          );
        }

        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 6.0),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12.0),
            border: Border.all(color: Colors.white12, width: 1.0),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.3),
                blurRadius: 5,
                spreadRadius: 1,
              ),
            ],
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16.0,
              vertical: 8.0,
            ),
            leading: _buildAvatar(friend.username, friend.avatarUrl),
            title: Text(
              friend.username,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
            trailing: trailingWidget,
            onTap: currentTab == FriendTab.receivedRequests
                ? null
                : () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Tapped on ${friend.username}')),
                    );
                  },
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_stars.isEmpty) {
      final random = math.Random();
      final screenWidth = MediaQuery.of(context).size.width;
      final screenHeight = MediaQuery.of(context).size.height;
      for (int i = 0; i < 50; i++) {
        _stars.add(_Star(random, screenWidth, screenHeight));
      }
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text(
          'Find Friends',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.lightBlueAccent,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.lightBlueAccent,
          tabs: const [
            Tab(text: 'My Friends', icon: Icon(Icons.people)),
            Tab(text: 'Sent', icon: Icon(Icons.outbox)),
            Tab(text: 'Received', icon: Icon(Icons.inbox)),
            Tab(text: 'Search', icon: Icon(Icons.search)),
          ],
        ),
      ),
      body: Stack(
        children: [
          AnimatedBuilder(
            animation: _colorAnimation,
            builder: (BuildContext context, Widget? child) {
              return Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [_colorAnimation.value!, const Color(0xFF0D0B2A)],
                  ),
                ),
              );
            },
          ),
          AnimatedBuilder(
            animation: _animationController,
            builder: (context, child) {
              return CustomPaint(
                painter: _StarPainter(_stars, _animationController),
                child: Container(),
              );
            },
          ),
          SafeArea(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildTabContent(_myFriends, FriendTab.myFriends),
                // --- CHANGE ---
                // No longer need to map the list, as it's already List<Friend>.
                _buildTabContent(_sentRequests, FriendTab.sentRequests),
                // --- CHANGE ---
                // No longer need to map the list, as it's already List<Friend>.
                _buildTabContent(_receivedRequests, FriendTab.receivedRequests),
                _buildSearchTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchTab() {
    final filteredFriends = _searchResults.where((friend) {
      final usernameLower = friend.username.toLowerCase();
      final queryLower = _searchController.text.toLowerCase();
      return usernameLower.contains(queryLower);
    }).toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 16.0),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'Search by Username',
                    labelStyle: TextStyle(color: Colors.white.withOpacity(0.7)),
                    hintStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
                    prefixIcon: const Icon(Icons.search, color: Colors.white54),
                    filled: true,
                    fillColor: Colors.white.withOpacity(0.1),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(30.0),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(30.0),
                      borderSide: const BorderSide(
                        color: Colors.white24,
                        width: 1.0,
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(30.0),
                      borderSide: const BorderSide(
                        color: Colors.lightBlueAccent,
                        width: 2.0,
                      ),
                    ),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(
                              Icons.clear,
                              color: Colors.white54,
                            ),
                            onPressed: () => _searchController.clear(),
                          )
                        : null,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              if (!kIsWeb)
                ElevatedButton(
                  onPressed: _isLoading ? null : _findFriendsInContacts,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.lightBlue[900],
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 12,
                    ),
                  ),
                  child: const Icon(Icons.contacts, color: Colors.white),
                ),
            ],
          ),
        ),
        _isLoading
            ? const Padding(
                padding: EdgeInsets.all(20.0),
                child: CircularProgressIndicator(color: Colors.lightBlueAccent),
              )
            : Padding(
                padding: const EdgeInsets.all(8.0),
                child: Text(
                  _statusMessage,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.7),
                    fontSize: 14,
                  ),
                ),
              ),
        Expanded(
          child: filteredFriends.isEmpty
              ? Center(
                  child: Text(
                    _searchController.text.isNotEmpty
                        ? "No users found."
                        : "Enter a username or scan contacts to search.",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.7),
                      fontSize: 16,
                    ),
                  ),
                )
              : _buildTabContent(filteredFriends, FriendTab.search),
        ),
      ],
    );
  }
}
