import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'widgets/call_aware_screen.dart';

class FriendRequestModel {
  final String username;
  final String? avatarUrl;
  final String? displayName;

  FriendRequestModel({
    required this.username,
    this.avatarUrl,
    this.displayName,
  });

  factory FriendRequestModel.fromJson(Map<String, dynamic> json) {
    return FriendRequestModel(
      username: json['username'] ?? '',
      avatarUrl: json['avatarUrl'],
      displayName: json['displayName'],
    );
  }

  String get displayNameOrUsername => displayName ?? username;
}

class FriendRequestsScreen extends StatefulWidget {
  const FriendRequestsScreen({super.key});

  @override
  State<FriendRequestsScreen> createState() => _FriendRequestsScreenState();
}

class _FriendRequestsScreenState extends State<FriendRequestsScreen> {
  Future<List<FriendRequestModel>>? _requestsFuture;
  Set<String> _processingRequests = {};

  @override
  void initState() {
    super.initState();
    _requestsFuture = _fetchFriendRequests();
  }

  Future<List<FriendRequestModel>> _fetchFriendRequests() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return [];

    final token = await user.getIdToken();
    final url = Uri.parse('http://192.168.29.81:8080/friends/requests');

    final response = await http.get(
      url,
      headers: {'Authorization': 'Bearer $token'},
    );

    if (response.statusCode == 200) {
      final List<dynamic> data = json.decode(response.body);
      return data.map((item) => FriendRequestModel.fromJson(item as Map<String, dynamic>)).toList();
    } else {
      throw Exception('Failed to load friend requests');
    }
  }

  Future<void> _acceptRequest(String username) async {
    // Prevent multiple taps - check and add synchronously
    if (_processingRequests.contains(username)) {
      // print('[FriendRequests] Already processing request for $username, ignoring tap');
      return;
    }

    _processingRequests.add(username);
    setState(() {}); // Just trigger rebuild to show loading state

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final token = await user.getIdToken();
      final url = Uri.parse('http://192.168.29.81:8080/friends/accept');

      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: json.encode({'targetUsername': username}),
      );

      if (!mounted) return;

      if (response.statusCode == 200) {
        // Refresh the list
        setState(() {
          _requestsFuture = _fetchFriendRequests();
        });
      } else {
        // print('[FriendRequests] Failed to accept request: ${response.statusCode} - ${response.body}');
      }
    } finally {
      if (mounted) {
        _processingRequests.remove(username);
        setState(() {}); // Just trigger rebuild
      }
    }
  }

  Future<void> _declineRequest(String username) async {
    // Prevent multiple taps - check and add synchronously
    if (_processingRequests.contains(username)) {
      // print('[FriendRequests] Already processing request for $username, ignoring tap');
      return;
    }

    _processingRequests.add(username);
    setState(() {}); // Just trigger rebuild to show loading state

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        // print('[FriendRequests] No user logged in');
        return;
      }

      final token = await user.getIdToken();
      final url = Uri.parse('http://192.168.29.81:8080/friends/decline');

      // print('[FriendRequests] Sending decline request for $username to $url');
      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: json.encode({'targetUsername': username}),
      );

      // print('[FriendRequests] Decline response: ${response.statusCode} - ${response.body}');

      if (!mounted) return;

      if (response.statusCode == 200) {
        // print('[FriendRequests] Successfully declined request from $username');
        // Refresh the list
        setState(() {
          _requestsFuture = _fetchFriendRequests();
        });
      } else {
        // print('[FriendRequests] Failed to decline request: ${response.statusCode} - ${response.body}');
      }
    } finally {
      if (mounted) {
        _processingRequests.remove(username);
        setState(() {}); // Just trigger rebuild
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return CallAwareScreen(
      screenName: 'FriendRequestsScreen',
      child: Scaffold(
        appBar: AppBar(title: const Text('Friend Requests')),
        body: FutureBuilder<List<FriendRequestModel>>(
          future: _requestsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(child: Text('No pending friend requests.'));
          }

          final requests = snapshot.data!;
          return ListView.builder(
            itemCount: requests.length,
            itemBuilder: (context, index) {
              final request = requests[index];
              final isProcessing = _processingRequests.contains(request.username);

              return Card(
                child: ListTile(
                  leading: CircleAvatar(
                    child: Text(request.displayNameOrUsername[0].toUpperCase()),
                  ),
                  title: Text(request.displayNameOrUsername),
                  subtitle: request.displayName != null
                      ? Text('@${request.username}', style: const TextStyle(fontSize: 12, color: Colors.grey))
                      : null,
                  trailing: isProcessing
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(
                                Icons.check_circle,
                                color: Colors.green,
                              ),
                              tooltip: 'Accept',
                              onPressed: _processingRequests.isEmpty
                                  ? () => _acceptRequest(request.username)
                                  : null,
                            ),
                            IconButton(
                              icon: const Icon(Icons.cancel, color: Colors.red),
                              tooltip: 'Decline',
                              onPressed: _processingRequests.isEmpty
                                  ? () => _declineRequest(request.username)
                                  : null,
                            ),
                          ],
                        ),
                ),
              );
            },
          );
        },
      ),
    )
    );
  }
}
