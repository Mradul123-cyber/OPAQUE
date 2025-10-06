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
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'services/websocket_service.dart';
import 'widgets/call_aware_screen.dart';
import 'friend_info_screen.dart';
import 'package:provider/provider.dart';
import 'providers/home_provider.dart';
import 'chat_screen.dart';

class Friend {
  final String username;
  final String? avatarUrl;
  final String? displayName;
  final String? phoneNumber;
  final bool fromContacts;

  Friend({
    required this.username,
    this.avatarUrl,
    this.displayName,
    this.phoneNumber,
    this.fromContacts = false,
  });

  factory Friend.fromJson(Map<String, dynamic> json) {
    return Friend(
      username: json['username'] ?? 'Unknown',
      avatarUrl: json['avatarUrl'],
      displayName: json['displayName'],
      phoneNumber: json['phoneNumber'],
      fromContacts: json['fromContacts'] ?? false,
    );
  }

  String get displayNameOrUsername => displayName ?? username;
  String get primaryDisplay => displayName ?? username;
  bool get hasDisplayName => displayName != null && displayName!.isNotEmpty;
}

enum FriendTab { myFriends, sentRequests, receivedRequests, search }

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
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _debounce?.cancel();
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
          // print('[FindFriends] Failed to accept request: ${response.statusCode} - ${response.body}');
        }
      }
    } catch (e) {
      if (mounted) {
        // print('[FindFriends] Error accepting request: $e');
      }
    }
  }

  Future<void> _declineRequest(String username) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final token = await user.getIdToken();
    final url = Uri.parse('http://192.168.29.81:8080/friends/decline');

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
          // Optimistic UI update: remove the request immediately
          setState(() {
            _receivedRequests
                .removeWhere((friend) => friend.username == username);
          });
          // Refresh the list
          _loadTabContent(FriendTab.receivedRequests.index);
        } else {
          // print('[FindFriends] Failed to decline request: ${response.statusCode} - ${response.body}');
        }
      }
    } catch (e) {
      if (mounted) {
        // print('[FindFriends] Error declining request: $e');
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
      // print('[FindFriends] Found ${contacts.length} contacts in phone');

      final List<String> hashedContacts = [];
      final List<String> allCleanedPhones = []; // Store all for verification
      final Map<String, String> hashToPhoneMap = {}; // Map hash to phone number
      int phoneCount = 0;
      for (var contact in contacts) {
        for (var phone in contact.phones) {
          var cleanedPhone = phone.number.replaceAll(RegExp(r'[^0-9+]'), '');
          if (cleanedPhone.isNotEmpty) {
            // Normalize: Add +91 prefix for Indian numbers if missing
            String normalizedPhone = cleanedPhone;

            if (!cleanedPhone.startsWith('+')) {
              // 10 digits (Indian mobile without country code) → Add +91
              if (cleanedPhone.length == 10 && cleanedPhone.startsWith(RegExp(r'[6-9]'))) {
                normalizedPhone = '+91$cleanedPhone';
              }
              // 12 digits starting with 91 → Add +
              else if (cleanedPhone.startsWith('91') && cleanedPhone.length == 12) {
                normalizedPhone = '+$cleanedPhone';
              }
              // 11 digits starting with 0 → Remove 0 and add +91
              else if (cleanedPhone.startsWith('0') && cleanedPhone.length == 11) {
                normalizedPhone = '+91${cleanedPhone.substring(1)}';
              }
            }

            final bytes = utf8.encode(normalizedPhone);
            final digest = sha256.convert(bytes);
            final hashStr = digest.toString();
            hashedContacts.add(hashStr);
            hashToPhoneMap[hashStr] = normalizedPhone; // Store mapping
            allCleanedPhones.add(normalizedPhone);
            phoneCount++;

            // Log first 5 for debugging
            if (phoneCount <= 5) {
              // print('[FindFriends] Sample #$phoneCount: $cleanedPhone → $normalizedPhone (length: ${normalizedPhone.length})');
              // print('[FindFriends] Hash: ${digest.toString().substring(0, 16)}...');
            }
          }
        }
      }
      // print('[FindFriends] Total phone numbers to check: $phoneCount');

      // Check if user's own number is in contacts (now normalized)
      final numbersContaining877 = allCleanedPhones.where((p) => p.contains('877067') || p.contains('980625')).toList();
      if (numbersContaining877.isNotEmpty) {
        // print('[FindFriends] 🔍 Found registered numbers in contacts: ${numbersContaining877.length} variations');
        for (var num in numbersContaining877) {
          // print('[FindFriends]    → $num');
        }
      } else {
        // print('[FindFriends] ⚠️ Registered numbers NOT found in your contacts!');
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
        // print('[FindFriends] Sending ${hashedContacts.length} hashed contacts to server...');
        final url = Uri.parse('http://192.168.29.81:8080/friends/find');
        final response = await http.post(
          url,
          headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'},
          body: json.encode(hashedContacts),
        );

        // print('[FindFriends] Server response: ${response.statusCode}');
        if (response.statusCode == 200) {
          // print('[FindFriends] RAW RESPONSE: ${response.body}');

          // Decode response, handling null/empty cases
          final decoded = json.decode(response.body);
          final List<dynamic> foundUsers = decoded is List ? decoded : [];

          // print('[FindFriends] Found ${foundUsers.length} matching users');
          // print('[FindFriends] Response data type: ${foundUsers.isNotEmpty ? foundUsers[0].runtimeType : 'empty'}');

          // Log each matched user
          for (int i = 0; i < foundUsers.length; i++) {
            // print('[FindFriends] Match #${i + 1}: ${foundUsers[i]}');
          }

          setState(() {
            // Backend returns array of strings (usernames) or objects
            _searchResults = foundUsers.map((data) {
              if (data is String) {
                // Backend returns just username strings
                // print('[FindFriends] Creating Friend from username: $data');
                return Friend(
                  username: data,
                  fromContacts: true, // Mark as from contact scan
                );
              } else if (data is Map<String, dynamic>) {
                // Backend returns full user objects
                // print('[FindFriends] Creating Friend from JSON: $data');

                // Map phoneHash back to actual phone number
                String? phoneNumber;
                if (data['phoneHash'] != null) {
                  phoneNumber = hashToPhoneMap[data['phoneHash']];
                  // print('[FindFriends] Mapped hash ${data['phoneHash']?.substring(0, 16)}... to phone: $phoneNumber');
                }

                return Friend.fromJson({
                  ...data,
                  'phoneNumber': phoneNumber, // Add the actual phone number
                  'fromContacts': true, // Mark as from contact scan
                });
              } else {
                // print('[FindFriends] Unexpected data type: ${data.runtimeType}');
                return Friend(username: 'Unknown');
              }
            }).toList();
            _isLoading = false;
            _statusMessage = _searchResults.isEmpty
                ? "No Zarq users found from your contacts."
                : "Found ${_searchResults.length} Zarq users from your contacts!";
          });

          // Save username → phone number mapping to local storage
          await _saveContactPhoneMapping(_searchResults);
        } else {
          // print('[FindFriends] Error response: ${response.body}');
          setState(() {
            _statusMessage = "Error from server (${response.statusCode}): ${response.body}";
            _isLoading = false;
          });
        }
      } catch (e, stackTrace) {
        // print('[FindFriends] Connection error: $e');
        // print('[FindFriends] Stack trace: $stackTrace');
        setState(() {
          _statusMessage = "Failed to connect to server: $e";
          _isLoading = false;
        });
      }
    } else {
      setState(() {
        _isLoading = false;
        _statusMessage = "Contact permission denied.";
      });
    }
  }

  Future<void> _saveContactPhoneMapping(List<Friend> friends) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final Map<String, String> mapping = {};

      // Build mapping of username → phone number
      for (var friend in friends) {
        if (friend.phoneNumber != null && friend.phoneNumber!.isNotEmpty) {
          mapping[friend.username] = friend.phoneNumber!;
        }
      }

      // Save as JSON string
      final jsonString = json.encode(mapping);
      await prefs.setString('contact_phone_mapping', jsonString);
      // print('[FindFriends] Saved ${mapping.length} username→phone mappings to local storage');
    } catch (e) {
      // print('[FindFriends] Error saving phone mapping: $e');
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
    final screenWidth = MediaQuery.of(context).size.width;
    final avatarRadius = (screenWidth * 0.06).clamp(20.0, 28.0);
    final avatarFontSize = (screenWidth * 0.05).clamp(18.0, 22.0);
    final progressSize = (screenWidth * 0.05).clamp(18.0, 24.0);

    final hasImage = avatarUrl != null && avatarUrl.isNotEmpty;
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
    final randomColor = Color(name.hashCode | 0xFF000000).withOpacity(1.0);

    if (hasImage) {
      return CachedNetworkImage(
        imageUrl: avatarUrl!,
        imageBuilder: (context, imageProvider) => CircleAvatar(
          radius: avatarRadius,
          backgroundImage: imageProvider,
          backgroundColor: Colors.grey[200],
        ),
        placeholder: (context, url) => CircleAvatar(
          radius: avatarRadius,
          backgroundColor: randomColor,
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
          radius: avatarRadius,
          backgroundColor: randomColor,
          child: Text(
            initial,
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: avatarFontSize,
            ),
          ),
        ),
      );
    }

    return CircleAvatar(
      radius: avatarRadius,
      backgroundColor: randomColor,
      child: Text(
        initial,
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: avatarFontSize,
        ),
      ),
    );
  }

  void _showFriendOptions(Friend friend) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    final modalAvatarRadius = (screenWidth * 0.088).clamp(30.0, 40.0);
    final modalAvatarFontSize = (screenWidth * 0.07).clamp(24.0, 32.0);
    final modalNameSize = (screenWidth * 0.05).clamp(18.0, 24.0);
    final modalUsernameSize = (screenWidth * 0.035).clamp(12.0, 16.0);
    final handleWidth = (screenWidth * 0.1).clamp(35.0, 50.0);
    final handleHeight = (screenHeight * 0.005).clamp(3.0, 5.0);
    final spacing1 = (screenHeight * 0.015).clamp(10.0, 16.0);
    final spacing2 = (screenHeight * 0.03).clamp(20.0, 30.0);

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
            SizedBox(height: spacing1),
            // Drag handle
            Container(
              width: handleWidth,
              height: handleHeight,
              decoration: BoxDecoration(
                color: Colors.grey[400],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            SizedBox(height: spacing2),

            // Profile Section
            CircleAvatar(
              radius: modalAvatarRadius,
              backgroundColor: Colors.grey[800],
              backgroundImage: friend.avatarUrl != null
                  ? NetworkImage(friend.avatarUrl!)
                  : null,
              child: friend.avatarUrl == null
                  ? Text(
                      friend.primaryDisplay[0].toUpperCase(),
                      style: TextStyle(fontSize: modalAvatarFontSize, color: Colors.white),
                    )
                  : null,
            ),
            SizedBox(height: spacing1),
            Text(
              friend.primaryDisplay,
              style: TextStyle(
                color: Colors.black,
                fontSize: modalNameSize,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              '@${friend.username}',
              style: TextStyle(
                color: Colors.black87,
                fontSize: modalUsernameSize,
              ),
            ),
            SizedBox(height: spacing2),

            // Action Cards
            Padding(
              padding: EdgeInsets.symmetric(horizontal: screenWidth * 0.04),
              child: Column(
                children: [
                  _buildActionCard(
                    icon: Icons.chat_bubble_outline,
                    title: 'Open Conversation',
                    subtitle: 'Start chatting with ${friend.displayName ?? friend.username}',
                    color: Colors.lightBlueAccent,
                    onTap: () {
                      Navigator.pop(context);
                      _openConversationWithFriend(friend.username);
                    },
                  ),
                  SizedBox(height: spacing1),
                  _buildActionCard(
                    icon: Icons.person_remove_outlined,
                    title: 'Remove Friend',
                    subtitle: 'Remove from your friends list',
                    color: Colors.redAccent,
                    onTap: () {
                      Navigator.pop(context);
                      _confirmRemoveFriend(friend);
                    },
                  ),
                ],
              ),
            ),
            SizedBox(height: MediaQuery.of(context).padding.bottom + spacing1),
          ],
        ),
        ),
      ),
    );
  }

  Widget _buildActionCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    final cardPadding = (screenWidth * 0.04).clamp(14.0, 20.0);
    final iconPadding = (screenWidth * 0.03).clamp(10.0, 14.0);
    final iconSize = (screenWidth * 0.06).clamp(22.0, 28.0);
    final titleSize = (screenWidth * 0.04).clamp(14.0, 18.0);
    final subtitleSize = (screenWidth * 0.03).clamp(11.0, 14.0);
    final arrowSize = (screenWidth * 0.04).clamp(14.0, 18.0);
    final spacing1 = (screenWidth * 0.04).clamp(12.0, 18.0);
    final spacing2 = (screenHeight * 0.0025).clamp(2.0, 4.0);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: EdgeInsets.all(cardPadding),
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: color.withOpacity(0.3),
            width: 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: EdgeInsets.all(iconPadding),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: iconSize),
            ),
            SizedBox(width: spacing1),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: titleSize,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  SizedBox(height: spacing2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: Colors.white60,
                      fontSize: subtitleSize,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios, color: Colors.grey[600], size: arrowSize),
          ],
        ),
      ),
    );
  }

  void _confirmRemoveFriend(Friend friend) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: const Text('Remove Friend?', style: TextStyle(color: Colors.white)),
        content: Text(
          'Are you sure you want to remove ${friend.primaryDisplay} from your friends?',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _removeFriend(friend.username);
            },
            child: const Text('Remove', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
  }

  Future<void> _removeFriend(String username) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final token = await user.getIdToken();
      final response = await http.post(
        Uri.parse('http://192.168.29.81:8080/friends/remove'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: json.encode({'targetUsername': username}),
      );

      if (response.statusCode == 200) {
        setState(() {
          _myFriends.removeWhere((f) => f.username == username);
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Removed $username from friends')),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to remove friend: ${response.body}'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _openConversationWithFriend(String username) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      // Get WebSocket service
      final websocketService = Provider.of<WebSocketService>(context, listen: false);
      if (!websocketService.isConnected || websocketService.channel == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Connecting... Please wait a moment.')),
        );
        return;
      }

      // Start or get conversation
      final token = await user.getIdToken();
      final response = await http.post(
        Uri.parse('http://192.168.29.81:8080/conversations/start'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: json.encode({'targetUsername': username}),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final conversationId = data['conversationId'] as int;

        // Refresh conversations to get the new/existing conversation
        final homeProvider = Provider.of<HomeProvider>(context, listen: false);
        await homeProvider.fetchInitialConversations();

        // Find the conversation
        final conversation = homeProvider.conversations.firstWhere(
          (c) => c.conversationId == conversationId,
          orElse: () => throw Exception('Conversation not found'),
        );

        // Navigate to chat screen
        if (mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ChatScreen(
                channel: websocketService.channel!,
                conversationInfo: conversation,
              ),
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to open conversation: ${response.body}'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Widget _buildTabContent(List<Friend> listData, FriendTab currentTab) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    // Responsive sizing for list items
    final itemMargin = EdgeInsets.symmetric(
      horizontal: screenWidth * 0.04,
      vertical: screenHeight * 0.008,
    );
    final itemPadding = EdgeInsets.symmetric(
      horizontal: screenWidth * 0.04,
      vertical: screenHeight * 0.01,
    );
    final nameFontSize = (screenWidth * 0.04).clamp(14.0, 18.0);
    final usernameFontSize = (screenWidth * 0.03).clamp(11.0, 14.0);
    final phoneFontSize = (screenWidth * 0.0275).clamp(10.0, 13.0);
    final chipFontSize = (screenWidth * 0.03).clamp(11.0, 14.0);
    final phoneIconSize = (screenWidth * 0.03).clamp(11.0, 14.0);
    final actionIconSize = (screenWidth * 0.06).clamp(22.0, 26.0);
    final spacing1 = (screenHeight * 0.005).clamp(3.0, 6.0);
    final spacing2 = (screenHeight * 0.0025).clamp(2.0, 4.0);
    final spacing3 = (screenWidth * 0.01).clamp(3.0, 6.0);
    final spacing4 = (screenWidth * 0.015).clamp(4.0, 8.0);

    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.lightBlueAccent),
      );
    }

    return Column(
      children: [
        // Friend counter - ALWAYS show for My Friends tab (even with 0 friends)
        if (currentTab == FriendTab.myFriends)
          Container(
            margin: EdgeInsets.all(16),
            padding: EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.blue[50],
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.blue[200]!, width: 2),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Total Friends',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.blue[600],
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${listData.length} / 500',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
        Expanded(
          child: listData.isEmpty
              ? Center(
                  child: Text(
                    _statusMessage,
                    style: TextStyle(
                      color: Colors.black87,
                      fontSize: nameFontSize,
                    ),
                  ),
                )
              : ListView.builder(
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
              style: TextStyle(
                color: Colors.lightBlueAccent,
                fontSize: chipFontSize,
                fontWeight: FontWeight.bold,
              ),
            ),
            backgroundColor: Colors.white,
            side: BorderSide(color: Colors.black, width: 1.0),
          );
        } else if (isPending) {
          trailingWidget = Chip(
            label: Text(
              'Pending',
              style: TextStyle(color: Colors.white, fontSize: chipFontSize),
            ),
            backgroundColor: Colors.orange.withOpacity(0.4),
          );
        } else if (currentTab == FriendTab.receivedRequests) {
          trailingWidget = Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: Icon(
                  Icons.check_circle,
                  color: Colors.lightBlueAccent,
                  size: actionIconSize,
                ),
                tooltip: 'Accept Request',
                onPressed: _isLoading
                    ? null
                    : () => _acceptRequest(friend.username),
              ),
              IconButton(
                icon: Icon(Icons.cancel, color: Colors.red, size: actionIconSize),
                tooltip: 'Decline Request',
                onPressed: _isLoading
                    ? null
                    : () => _declineRequest(friend.username),
              ),
            ],
          );
        } else {
          trailingWidget = IconButton(
            icon: Icon(
              Icons.person_add_alt_1_outlined,
              color: Colors.white,
              size: actionIconSize,
            ),
            tooltip: 'Send Friend Request',
            onPressed: _isLoading
                ? null
                : () => _sendFriendRequest(friend.username),
          );
        }

        return Container(
          margin: itemMargin,
          decoration: BoxDecoration(
            color: Colors.lightBlue[50],
            borderRadius: BorderRadius.circular(12.0),
            border: Border.all(color: Colors.lightBlue[200]!, width: 1.0),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 5,
                spreadRadius: 1,
              ),
            ],
          ),
          child: ListTile(
            contentPadding: itemPadding,
            leading: _buildAvatar(friend.primaryDisplay, friend.avatarUrl),
            title: Text(
              friend.primaryDisplay,
              style: TextStyle(
                color: Colors.black,
                fontWeight: FontWeight.bold,
                fontSize: nameFontSize,
              ),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(height: spacing1),
                // Always show username
                Text(
                  '@${friend.username}',
                  style: TextStyle(
                    color: Colors.black87,
                    fontSize: usernameFontSize,
                  ),
                ),
                // Show phone number if from contacts
                if (friend.fromContacts && friend.phoneNumber != null) ...[
                  SizedBox(height: spacing2),
                  Row(
                    children: [
                      Icon(
                        Icons.phone,
                        size: phoneIconSize,
                        color: Colors.grey[600],
                      ),
                      SizedBox(width: spacing3),
                      Flexible(
                        child: Text(
                          friend.phoneNumber!.replaceFirst('+91', ''),
                          style: TextStyle(
                            color: Colors.grey[700],
                            fontSize: phoneFontSize,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      SizedBox(width: spacing4),
                      Text(
                        '· From Contacts',
                        style: TextStyle(
                          color: Colors.lightBlueAccent,
                          fontSize: phoneFontSize,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
            trailing: trailingWidget,
            onTap: currentTab == FriendTab.receivedRequests
                ? null
                : () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Tapped on ${friend.primaryDisplay}')),
                    );
                  },
            onLongPress: currentTab == FriendTab.myFriends
                ? () => _showFriendOptions(friend)
                : null,
          ),
        );
      },
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final appBarTitleSize = (screenWidth * 0.05).clamp(18.0, 24.0);
    final tabFontSize = (screenWidth * 0.03).clamp(11.0, 14.0);
    final tabIconSize = (screenWidth * 0.06).clamp(20.0, 26.0);

    return CallAwareScreen(
      screenName: 'FindFriendsScreen',
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
        title: Text(
          'Find Friends',
          style: TextStyle(
            color: Colors.black,
            fontWeight: FontWeight.bold,
            fontSize: appBarTitleSize,
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black),
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.black,
          unselectedLabelColor: Colors.black54,
          indicatorColor: Colors.black,
          labelStyle: TextStyle(fontSize: tabFontSize),
          unselectedLabelStyle: TextStyle(fontSize: tabFontSize),
          tabs: [
            Tab(text: 'My Friends', icon: Icon(Icons.people, size: tabIconSize)),
            Tab(text: 'Sent', icon: Icon(Icons.outbox, size: tabIconSize)),
            Tab(text: 'Received', icon: Icon(Icons.inbox, size: tabIconSize)),
            Tab(text: 'Search', icon: Icon(Icons.search, size: tabIconSize)),
          ],
        ),
      ),
      body: SafeArea(
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
      )
    );
  }

  Widget _buildSearchTab() {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    final searchPadding = EdgeInsets.symmetric(
      horizontal: screenWidth * 0.04,
      vertical: screenHeight * 0.02,
    );
    final searchFontSize = (screenWidth * 0.04).clamp(14.0, 18.0);
    final searchIconSize = (screenWidth * 0.06).clamp(20.0, 26.0);
    final buttonIconSize = (screenWidth * 0.06).clamp(20.0, 26.0);
    final buttonPadding = EdgeInsets.symmetric(
      horizontal: screenWidth * 0.03,
      vertical: screenHeight * 0.015,
    );
    final statusFontSize = (screenWidth * 0.035).clamp(12.0, 16.0);
    final emptyTextSize = (screenWidth * 0.04).clamp(14.0, 18.0);
    final spacing1 = (screenWidth * 0.025).clamp(8.0, 12.0);
    final spacing2 = (screenHeight * 0.025).clamp(16.0, 24.0);
    final spacing3 = (screenHeight * 0.01).clamp(6.0, 10.0);

    final filteredFriends = _searchResults.where((friend) {
      final usernameLower = friend.username.toLowerCase();
      final queryLower = _searchController.text.toLowerCase();
      return usernameLower.contains(queryLower);
    }).toList();

    return Column(
      children: [
        Padding(
          padding: searchPadding,
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  style: TextStyle(color: Colors.black87, fontSize: searchFontSize),
                  decoration: InputDecoration(
                    labelText: 'Search by Username',
                    labelStyle: TextStyle(color: Colors.black54, fontSize: searchFontSize),
                    hintStyle: TextStyle(color: Colors.black38, fontSize: searchFontSize),
                    prefixIcon: Icon(Icons.search, color: Colors.black54, size: searchIconSize),
                    filled: true,
                    fillColor: Colors.lightBlue[50],
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(30.0),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(30.0),
                      borderSide: BorderSide(
                        color: Colors.lightBlue[200]!,
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
                            icon: Icon(
                              Icons.clear,
                              color: Colors.black54,
                              size: searchIconSize,
                            ),
                            onPressed: () => _searchController.clear(),
                          )
                        : null,
                  ),
                ),
              ),
              SizedBox(width: spacing1),
              if (!kIsWeb)
                GestureDetector(
                  onLongPress: () {
                    showDialog(
                      context: context,
                      builder: (context) => AlertDialog(
                        backgroundColor: Colors.white,
                        title: Text(
                          'Find from Contacts',
                          style: TextStyle(color: Colors.black, fontSize: emptyTextSize),
                        ),
                        content: Text(
                          'This scans your phone contacts to find friends who are already using Zarq Messenger.',
                          style: TextStyle(color: Colors.black87, fontSize: statusFontSize),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('Got it'),
                          ),
                        ],
                      ),
                    );
                  },
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _findFriendsInContacts,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.lightBlue[900],
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30),
                      ),
                      padding: buttonPadding,
                    ),
                    child: Icon(Icons.contacts, color: Colors.white, size: buttonIconSize),
                  ),
                ),
            ],
          ),
        ),
        _isLoading
            ? Padding(
                padding: EdgeInsets.all(spacing2),
                child: const CircularProgressIndicator(color: Colors.lightBlueAccent),
              )
            : Padding(
                padding: EdgeInsets.all(spacing3),
                child: Text(
                  _statusMessage,
                  style: TextStyle(
                    color: Colors.black87,
                    fontSize: statusFontSize,
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
                      color: Colors.black87,
                      fontSize: emptyTextSize,
                    ),
                  ),
                )
              : _buildTabContent(filteredFriends, FriendTab.search),
        ),
      ],
    );
  }
}
