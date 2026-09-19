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
import 'services/user_settings_provider.dart';
import 'widgets/call_aware_screen.dart';
import 'widgets/opaque_navigation.dart';
import 'package:provider/provider.dart';
import 'providers/home_provider.dart';
import 'chat_screen.dart';
import 'package:zarq_messenger/app_config.dart';

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
  String get primaryDisplay => hasDisplayName ? displayName! : username;
  bool get hasDisplayName => displayName != null && displayName!.isNotEmpty;
}

enum FriendTab { myFriends, receivedRequests, sentRequests, search }

class FindFriendsScreen extends StatefulWidget {
  final FriendTab initialTab;
  final bool embedded;
  final WebSocketChannel channel;
  final VoidCallback? onFriendRequestAccepted;

  const FindFriendsScreen({
    super.key,
    this.embedded = false,
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
  bool _isRefreshingTabs = false;
  bool _hasLoadedTabs = false;
  bool _contactMode = false;
  late int _loadedTab;
  String _statusMessage =
      "Use the search bar or scan contacts to find friends.";
  Timer? _debounce;


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
    _loadedTab = widget.initialTab.index;
    _loadTabContent(widget.initialTab.index);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging && _loadedTab != _tabController.index) {
        _loadedTab = _tabController.index;
        _debounce?.cancel();
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
    if (_isRefreshingTabs) return;
    setState(() {
      _isRefreshingTabs = true;
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

      if (!mounted) return;
      _hasLoadedTabs = true;
      // Use the current tab if the user switched while fetching.
      switch (FriendTab.values[_tabController.index]) {
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
      if (mounted) setState(() => _isRefreshingTabs = false);
    }
  }

  Future<void> _fetchMyFriends(String token) async {
    try {
      final url = Uri.parse('${AppConfig.baseUrl}/friends/list');
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
      final url = Uri.parse('${AppConfig.baseUrl}/friends/sent-requests');
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
      final url = Uri.parse('${AppConfig.baseUrl}/friends/requests');
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
            _receivedRequests = data
                .map((item) => Friend.fromJson(item))
                .toList();
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
    final url = Uri.parse('${AppConfig.baseUrl}/friends/accept');

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
            _receivedRequests.removeWhere(
              (friend) => friend.username == username,
            );
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
    final url = Uri.parse('${AppConfig.baseUrl}/friends/decline');

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
            _receivedRequests.removeWhere(
              (friend) => friend.username == username,
            );
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
    final url = Uri.parse('${AppConfig.baseUrl}/friends/request');

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
    if (_contactMode) { setState(() {}); return; }
    _debounce = Timer(const Duration(milliseconds: 500), () {
      if (_tabController.index != FriendTab.search.index) return;
      _searchUsers(_searchController.text.trim().replaceFirst(RegExp(r'^@'), ''));
    });
  }

  Future<void> _findFriendsInContacts() async {
    // print('[CONTACT_SYNC] ==================== STARTING CONTACT SYNC ====================');
    // print('[CONTACT_SYNC] Platform: ${Platform.operatingSystem}');
    // print('[CONTACT_SYNC] Platform version: ${Platform.operatingSystemVersion}');

    setState(() {
      _isLoading = true;
      _statusMessage = "Asking for permission...";
      _searchResults = [];
    });

    if (kIsWeb || (!Platform.isAndroid && !Platform.isIOS)) {
      // print('[CONTACT_SYNC] ❌ Not a mobile platform');
      setState(() {
        _isLoading = false;
        _statusMessage =
            "Contact scanning is only available on mobile devices.";
      });
      return;
    }

    // print('[CONTACT_SYNC] 📱 Requesting contacts permission...');
    final PermissionStatus permissionStatus = await Permission.contacts
        .request();
    // print('[CONTACT_SYNC] Permission status: $permissionStatus');
    if (permissionStatus.isGranted) {
      // print('[CONTACT_SYNC] ✅ Permission GRANTED');
      setState(
        () => _statusMessage = "Permission granted. Scanning contacts...",
      );

      // print('[CONTACT_SYNC] 📞 Fetching contacts from phone...');
      // print('[CONTACT_SYNC] 🔧 Android 13 Fix: Fetching contacts WITHOUT properties first (faster)');
      final List<Contact> contacts;
      try {
        // ANDROID 13 FIX: Fetch contacts without properties first (much faster)
        // Then only fetch phone numbers for each contact individually
        final List<Contact> contactsWithoutProps =
            await FlutterContacts.getContacts(withProperties: false).timeout(
              const Duration(seconds: 10),
              onTimeout: () {
                // print('[CONTACT_SYNC] ⚠️ TIMEOUT: Fetching contact list took more than 10 seconds');
                throw TimeoutException('Contact list fetch timed out');
              },
            );
        // print('[CONTACT_SYNC] ✅ Successfully fetched ${contactsWithoutProps.length} contact names');

        // Now fetch phone numbers in MAXIMUM parallel batches (optimized for 10,000+ contacts)
        // print('[CONTACT_SYNC] 📞 Fetching phone numbers for ${contactsWithoutProps.length} contacts...');
        contacts = [];

        // Optimize batch size based on total contacts
        // For very large lists, use bigger batches for maximum speed
        int batchSize;
        if (contactsWithoutProps.length <= 5000) {
          // Fetch all at once if <= 5000 contacts (fastest!)
          batchSize = contactsWithoutProps.length;
          // print('[CONTACT_SYNC] ⚡ TURBO MODE: Fetching ALL ${contactsWithoutProps.length} contacts in ONE parallel batch!');
        } else {
          // For 10,000+, use 2000 per batch
          batchSize = 2000;
          // print('[CONTACT_SYNC] ⚡ FAST MODE: Using batches of $batchSize contacts');
        }

        for (int i = 0; i < contactsWithoutProps.length; i += batchSize) {
          int end = (i + batchSize < contactsWithoutProps.length)
              ? i + batchSize
              : contactsWithoutProps.length;
          final batchNumber = (i / batchSize).floor() + 1;
          final totalBatches = (contactsWithoutProps.length / batchSize).ceil();

          // print('[CONTACT_SYNC] 🔄 Processing batch $batchNumber/$totalBatches (${i + 1}-$end) - ${end - i} contacts in PARALLEL...');
          // final startTime = DateTime.now();

          // Fetch all contacts in this batch in parallel
          final batch = contactsWithoutProps.sublist(i, end);
          final fetchFutures = batch
              .map((contact) => FlutterContacts.getContact(contact.id))
              .toList();

          try {
            // Wait for ALL contacts in batch to fetch in parallel (MAXIMUM SPEED!)
            final batchResults = await Future.wait(
              fetchFutures,
              eagerError: false,
            );

            // Add non-null results
            for (var fullContact in batchResults) {
              if (fullContact != null) {
                contacts.add(fullContact);
              }
            }

            // final elapsed = DateTime.now().difference(startTime).inMilliseconds;
            // print('[CONTACT_SYNC] ✅ Batch $batchNumber: Fetched ${batchResults.where((c) => c != null).length}/${batch.length} contacts in ${elapsed}ms');
          } catch (e) {
            // print('[CONTACT_SYNC] ⚠️ Error in batch $batchNumber: $e');
            // Continue with next batch even if this one fails
          }

          // Update progress
          if (mounted) {
            setState(
              () => _statusMessage =
                  "Scanning contacts... ${contacts.length}/${contactsWithoutProps.length}",
            );
          }
        }

        // print('[CONTACT_SYNC] ✅ Successfully fetched phone numbers for ${contacts.length}/${contactsWithoutProps.length} contacts');
      } catch (e, stackTrace) {
        // print('[CONTACT_SYNC] ❌ ERROR fetching contacts: $e');
        // print('[CONTACT_SYNC] Stack trace: $stackTrace');
        setState(() {
          _isLoading = false;
          _statusMessage = "Failed to fetch contacts: $e";
        });
        return;
      }

      // print('[CONTACT_SYNC] 🔄 Processing ${contacts.length} contacts to extract phone numbers...');
      final List<String> hashedContacts = [];
      final List<String> allCleanedPhones = []; // Store all for verification
      final Map<String, String> hashToPhoneMap = {}; // Map hash to phone number
      int phoneCount = 0;
      int contactsWithoutPhones = 0;

      for (var contact in contacts) {
        if (contact.phones.isEmpty) {
          contactsWithoutPhones++;
          continue;
        }

        for (var phone in contact.phones) {
          var cleanedPhone = phone.number.replaceAll(RegExp(r'[^0-9+]'), '');
          if (cleanedPhone.isNotEmpty) {
            // Normalize: Add +91 prefix for Indian numbers if missing
            String normalizedPhone = cleanedPhone;

            if (!cleanedPhone.startsWith('+')) {
              // 10 digits (Indian mobile without country code) → Add +91
              if (cleanedPhone.length == 10 &&
                  cleanedPhone.startsWith(RegExp(r'[6-9]'))) {
                normalizedPhone = '+91$cleanedPhone';
              }
              // 12 digits starting with 91 → Add +
              else if (cleanedPhone.startsWith('91') &&
                  cleanedPhone.length == 12) {
                normalizedPhone = '+$cleanedPhone';
              }
              // 11 digits starting with 0 → Remove 0 and add +91
              else if (cleanedPhone.startsWith('0') &&
                  cleanedPhone.length == 11) {
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
              // print('[CONTACT_SYNC] 📋 Sample #$phoneCount: $cleanedPhone → $normalizedPhone (length: ${normalizedPhone.length})');
              // print('[CONTACT_SYNC]     Hash: ${digest.toString().substring(0, 16)}...');
            }
          }
        }
      }

      // print('[CONTACT_SYNC] 📊 Contact processing summary:');
      // print('[CONTACT_SYNC]    - Total contacts: ${contacts.length}');
      // print('[CONTACT_SYNC]    - Contacts without phone numbers: $contactsWithoutPhones');
      // print('[CONTACT_SYNC]    - Total phone numbers found: $phoneCount');
      // print('[CONTACT_SYNC]    - Hashed contacts to send: ${hashedContacts.length}');

      // Check if user's own number is in contacts (now normalized)
      final numbersContaining877 = allCleanedPhones
          .where((p) => p.contains('877067') || p.contains('980625'))
          .toList();
      if (numbersContaining877.isNotEmpty) {
        // print('[CONTACT_SYNC] 🔍 Found test/registered numbers in contacts: ${numbersContaining877.length} variations');
        for (var num in numbersContaining877) {
          // print('[CONTACT_SYNC]    → $num');
        }
      } else {
        // print('[CONTACT_SYNC] ⚠️ Test numbers (877067, 980625) NOT found in your contacts');
      }

      if (hashedContacts.isEmpty) {
        // print('[CONTACT_SYNC] ❌ No phone numbers found in any contacts!');
        setState(() {
          _isLoading = false;
          _statusMessage = "No phone numbers found in your contacts.";
        });
        return;
      }

      setState(
        () => _statusMessage =
            "Found ${hashedContacts.length} contacts. Checking server...",
      );

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
        // print('[CONTACT_SYNC] 🌐 Sending ${hashedContacts.length} hashed contacts to server...');
        final url = Uri.parse('${AppConfig.baseUrl}/friends/find');

        // print('[CONTACT_SYNC] 📤 Request URL: $url');
        // print('[CONTACT_SYNC] 📤 Payload size: ${json.encode(hashedContacts).length} bytes');

        final response = await http
            .post(
              url,
              headers: {
                'Content-Type': 'application/json',
                'Authorization': 'Bearer $token',
              },
              body: json.encode(hashedContacts),
            )
            .timeout(
              const Duration(seconds: 30),
              onTimeout: () {
                // print('[CONTACT_SYNC] ⚠️ Server request TIMEOUT after 30 seconds');
                throw TimeoutException('Server request timed out');
              },
            );

        // print('[CONTACT_SYNC] 📥 Server response code: ${response.statusCode}');
        if (response.statusCode == 200) {
          // print('[CONTACT_SYNC] ✅ Server responded successfully');
          // print('[CONTACT_SYNC] 📥 Response body length: ${response.body.length} bytes');

          // Decode response, handling null/empty cases
          final decoded = json.decode(response.body);
          final List<dynamic> foundUsers = decoded is List ? decoded : [];

          // print('[CONTACT_SYNC] 👥 Found ${foundUsers.length} matching Zarq users');
          // print('[CONTACT_SYNC] 📊 Match rate: ${foundUsers.length}/${hashedContacts.length} (${(foundUsers.length / hashedContacts.length * 100).toStringAsFixed(1)}%)');

          if (foundUsers.isNotEmpty) {
            // print('[CONTACT_SYNC] 👤 Sample user data type: ${foundUsers[0].runtimeType}');
          }

          // Log each matched user
          for (int i = 0; i < foundUsers.length; i++) {
            // print('[CONTACT_SYNC] 👤 Match #${i + 1}: ${foundUsers[i]}');
          }

          // print('[CONTACT_SYNC] 🔄 Parsing ${foundUsers.length} users into Friend objects...');

          setState(() {
            // Backend returns array of strings (usernames) or objects
            _searchResults = foundUsers.map((data) {
              if (data is String) {
                // Backend returns just username strings
                // print('[CONTACT_SYNC] 👤 Creating Friend from username: $data');
                return Friend(
                  username: data,
                  fromContacts: true, // Mark as from contact scan
                );
              } else if (data is Map<String, dynamic>) {
                // Backend returns full user objects
                // print('[CONTACT_SYNC] 👤 Creating Friend from JSON: ${data['username'] ?? 'unknown'}');

                // Map phoneHash back to actual phone number
                String? phoneNumber;
                if (data['phoneHash'] != null) {
                  phoneNumber = hashToPhoneMap[data['phoneHash']];
                  if (phoneNumber != null) {
                    // print('[CONTACT_SYNC]    ✓ Mapped hash to phone: ${phoneNumber.substring(0, 6)}...');
                  }
                }

                return Friend.fromJson({
                  ...data,
                  'phoneNumber': phoneNumber ?? data['phoneNumber'], // Preserve server-provided numbers too.
                  'fromContacts': true, // Mark as from contact scan
                });
              } else {
                // print('[CONTACT_SYNC] ⚠️ Unexpected data type: ${data.runtimeType}');
                return Friend(username: 'Unknown');
              }
            }).toList();
            _isLoading = false;
            _statusMessage = _searchResults.isEmpty
                ? "No Zarq users found from your contacts."
                : "Found ${_searchResults.length} Zarq users from your contacts!";
          });

          // print('[CONTACT_SYNC] ✅ Successfully created ${_searchResults.length} Friend objects');

          // Save username → phone number mapping to local storage
          await _saveContactPhoneMapping(_searchResults);
          // print('[CONTACT_SYNC] ==================== CONTACT SYNC COMPLETED ====================');
        } else {
          // print('[CONTACT_SYNC] ❌ Server error: ${response.statusCode}');
          // print('[CONTACT_SYNC] Error body: ${response.body}');
          setState(() {
            _statusMessage =
                "Error from server (${response.statusCode}): ${response.body}";
            _isLoading = false;
          });
        }
      } catch (e, stackTrace) {
        // print('[CONTACT_SYNC] ❌ ERROR during server communication: $e');
        // print('[CONTACT_SYNC] Stack trace: $stackTrace');
        setState(() {
          _statusMessage = "Failed to connect to server: $e";
          _isLoading = false;
        });
      }
    } else {
      // print('[CONTACT_SYNC] ❌ Permission DENIED');
      // print('[CONTACT_SYNC] Permission details: $permissionStatus');
      // print('[CONTACT_SYNC] isPermanentlyDenied: ${permissionStatus.isPermanentlyDenied}');
      // print('[CONTACT_SYNC] isDenied: ${permissionStatus.isDenied}');
      // print('[CONTACT_SYNC] isRestricted: ${permissionStatus.isRestricted}');

      setState(() {
        _isLoading = false;
        _statusMessage = permissionStatus.isPermanentlyDenied
            ? "Contact permission permanently denied. Please enable it in Settings."
            : "Contact permission denied.";
      });

      // Show dialog for permanently denied permissions
      if (permissionStatus.isPermanentlyDenied && mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Permission Required'),
            content: const Text(
              'Contact permission is required to find friends. Please enable it in your device settings.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  openAppSettings();
                },
                child: const Text('Open Settings'),
              ),
            ],
          ),
        );
      }
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
      final url = Uri.parse('${AppConfig.baseUrl}/users/search?q=$query');
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
    final initial = name.isEmpty ? '?' : name.characters.first.toUpperCase();
    final fallback = Container(width: 40, height: 40, alignment: Alignment.center,
      decoration: const BoxDecoration(shape: BoxShape.circle, gradient: LinearGradient(colors: [Color(0xFFF0F3FA), Color(0xFFE7ECF5)])),
      child: Text(initial, style: const TextStyle(fontSize: 14, color: Color(0xFF7A8BA7))));
    if (avatarUrl == null || avatarUrl.isEmpty) return fallback;
    return ClipOval(child: CachedNetworkImage(imageUrl: avatarUrl, width: 40, height: 40, fit: BoxFit.cover,
      placeholder: (_, _) => fallback, errorWidget: (_, _, _) => fallback));
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
                        style: TextStyle(
                          fontSize: modalAvatarFontSize,
                          color: Colors.white,
                        ),
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
                      subtitle:
                          'Start chatting with ${friend.displayName ?? friend.username}',
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
              SizedBox(
                height: MediaQuery.of(context).padding.bottom + spacing1,
              ),
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
          border: Border.all(color: color.withOpacity(0.3), width: 1),
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
            Icon(
              Icons.arrow_forward_ios,
              color: Colors.grey[600],
              size: arrowSize,
            ),
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
        title: const Text(
          'Remove Friend?',
          style: TextStyle(color: Colors.white),
        ),
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
            child: const Text(
              'Remove',
              style: TextStyle(color: Colors.redAccent),
            ),
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
        Uri.parse('${AppConfig.baseUrl}/friends/remove'),
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
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _openConversationWithFriend(String username) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      // Get WebSocket service
      final websocketService = Provider.of<WebSocketService>(
        context,
        listen: false,
      );
      if (!websocketService.isConnected || websocketService.channel == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Connecting... Please wait a moment.')),
        );
        return;
      }

      // Start or get conversation
      final token = await user.getIdToken();
      final response = await http.post(
        Uri.parse('${AppConfig.baseUrl}/conversations/start'),
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
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Widget _buildTabContent(List<Friend> listData, FriendTab currentTab, bool dark) {
    final muted = dark ? const Color(0xFF9CA8BB) : const Color(0xFF919AAA);
    Widget action(String icon, String label, VoidCallback? callback, {Color color = const Color(0xFF607DA5)}) => IconButton(
      tooltip: label, onPressed: callback, constraints: const BoxConstraints(minWidth: 40, minHeight: 44),
      padding: const EdgeInsets.all(8), icon: OpaqueIcon(icon, size: 22, color: color));
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (currentTab != FriendTab.search) Padding(
        padding: const EdgeInsets.fromLTRB(22, 7, 22, 5),
        child: Text('${currentTab == FriendTab.myFriends ? 'Total friends' : currentTab == FriendTab.receivedRequests ? 'Received requests' : 'Sent requests'} · ${listData.length}', style: TextStyle(fontSize: 11, color: muted))),
      Expanded(child: (currentTab == FriendTab.search ? _isLoading : _isRefreshingTabs && !_hasLoadedTabs) ? const Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF607DA5)))) : listData.isEmpty
        ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(currentTab == FriendTab.search ? _statusMessage : currentTab == FriendTab.myFriends ? "You don't have any friends yet." : currentTab == FriendTab.receivedRequests ? 'No pending friend requests.' : 'No pending requests sent by you.', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: muted))))
        : ListView.builder(padding: const EdgeInsets.symmetric(horizontal: 15), itemCount: listData.length, itemBuilder: (context, index) {
          final friend = listData[index];
          final mine = currentTab == FriendTab.myFriends || _myFriends.any((f) => f.username == friend.username);
          final pending = currentTab == FriendTab.sentRequests || _pendingRequests.contains(friend.username);
          return InkWell(
            onTap: mine ? () => _openConversationWithFriend(friend.username) : null,
            onLongPress: mine ? () => _showFriendOptions(friend) : null,
            child: Container(padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 15),
              decoration: BoxDecoration(border: Border(bottom: BorderSide(color: dark ? const Color(0xFF303947) : const Color(0xFFF0F1F4)))),
              child: Row(children: [
                _buildAvatar(friend.primaryDisplay, friend.avatarUrl), const SizedBox(width: 10),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(friend.primaryDisplay, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: dark ? const Color(0xFFE0E6EF) : const Color(0xFF343D4C))),
                  const SizedBox(height: 3), Text('@${friend.username}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: muted)),
                  if (friend.fromContacts && friend.phoneNumber != null) Padding(padding: const EdgeInsets.only(top: 5), child: Text(friend.phoneNumber!, style: TextStyle(fontSize: 11, letterSpacing: .15, color: muted))),
                ])),
                if (mine) action('chats', 'Message ${friend.primaryDisplay}', () => _openConversationWithFriend(friend.username))
                else if (currentTab == FriendTab.receivedRequests) ...[
                  action('check', 'Accept request from ${friend.primaryDisplay}', () => _acceptRequest(friend.username), color: const Color(0xFF45966E)),
                  action('close', 'Decline request from ${friend.primaryDisplay}', () => _declineRequest(friend.username), color: const Color(0xFFAC8C8B)),
                ] else if (pending) Tooltip(message: 'Request pending', child: Padding(padding: const EdgeInsets.all(11), child: OpaqueIcon('pending', color: const Color(0xFFC39154))))
                else action('add', 'Add ${friend.primaryDisplay}', () => _sendFriendRequest(friend.username)),
              ]),
            ),
          );
        })),
    ]);
  }

  @override
  Widget build(BuildContext context) => Consumer<UserSettingsProvider>(builder: (context, settings, _) {
    final dark = settings.isDarkMode;
    final surface = dark ? const Color(0xFF19202A) : Colors.white;
    return CallAwareScreen(screenName: 'FindFriendsScreen', child: Scaffold(
      backgroundColor: surface,
      appBar: widget.embedded ? null : AppBar(backgroundColor: surface, elevation: 0, scrolledUnderElevation: 0, foregroundColor: dark ? Colors.white : const Color(0xFF424D60)),
      body: Column(children: [
        OpaqueFriendTabs(controller: _tabController, isDark: dark),
        Expanded(child: TabBarView(controller: _tabController, children: [
          _buildTabContent(_myFriends, FriendTab.myFriends, dark),
          _buildTabContent(_receivedRequests, FriendTab.receivedRequests, dark),
          _buildTabContent(_sentRequests, FriendTab.sentRequests, dark),
          _buildSearchTab(dark),
        ])),
      ]),
    ));
  });

  Widget _buildSearchTab(bool dark) {
    final query = _searchController.text.trim().toLowerCase().replaceFirst(RegExp(r'^@'), '');
    final filtered = _searchResults.where((f) => f.username.toLowerCase().contains(query) || (_contactMode && (f.primaryDisplay.toLowerCase().contains(query) || (f.phoneNumber ?? '').contains(query)))).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(padding: const EdgeInsets.fromLTRB(20, 0, 20, 13), child: Row(children: [
        Expanded(child: SizedBox(height: 40, child: TextField(
          controller: _searchController, style: TextStyle(fontSize: 16, color: dark ? Colors.white : const Color(0xFF4A5568)),
          decoration: InputDecoration(hintText: _contactMode ? 'Search contacts' : 'Search by username',
            hintStyle: const TextStyle(fontSize: 12, color: Color(0xFF979FAD)),
            prefixIcon: const Padding(padding: EdgeInsets.all(11), child: OpaqueIcon('search', size: 18, color: Color(0xFF919CAD))),
            filled: true, fillColor: dark ? const Color(0xFF283241) : const Color(0xFFF3F5F8), contentPadding: const EdgeInsets.symmetric(horizontal: 11),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: const BorderSide(color: Color(0xFFC6CBD3))),
          ),
        ))),
        if (!kIsWeb) ...[const SizedBox(width: 8), Container(
          decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: _contactMode ? const [Color(0xFF608BD0), Color(0xFF416DB0)] : const [Color(0xFF719CDD), Color(0xFF507FC3)]), borderRadius: BorderRadius.circular(14)),
          child: IconButton(tooltip: _contactMode ? 'Return to username search' : 'Find friends in contacts',
            onPressed: _isLoading ? null : () {
              _debounce?.cancel();
              setState(() { _contactMode = !_contactMode; _searchResults = []; });
              _searchController.clear();
              if (_contactMode) { _findFriendsInContacts(); } else { _searchUsers(''); }
            },
            icon: OpaqueIcon(_contactMode ? 'friends' : 'calls', size: 24, color: Colors.white), constraints: const BoxConstraints(minWidth: 42, minHeight: 40)),
        )],
      ])),
      Padding(padding: const EdgeInsets.fromLTRB(22, 7, 22, 5), child: Text(_statusMessage, style: const TextStyle(fontSize: 11, color: Color(0xFF929BA9)))),
      Expanded(child: _buildTabContent(filtered, FriendTab.search, dark)),
    ]);
  }
}
