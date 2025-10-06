import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class FriendInfoScreen extends StatefulWidget {
  final String username;
  final String? displayName;
  final String? avatarUrl;
  final String? phoneNumber;
  final bool fromContacts;

  const FriendInfoScreen({
    super.key,
    required this.username,
    this.displayName,
    this.avatarUrl,
    this.phoneNumber,
    this.fromContacts = false,
  });

  @override
  State<FriendInfoScreen> createState() => _FriendInfoScreenState();
}

class _FriendInfoScreenState extends State<FriendInfoScreen> {
  String? _bio;
  String? _realPhoneNumber;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadFriendInfo();
  }

  Future<void> _loadFriendInfo() async {
    try {
      // First, use phone number from widget if already available
      if (widget.phoneNumber != null && widget.phoneNumber!.isNotEmpty) {
        _realPhoneNumber = widget.phoneNumber;
        setState(() => _isLoading = false);
        return;
      }

      // Look up phone number from local storage (saved during contact fetch)
      final prefs = await SharedPreferences.getInstance();
      final mappingJson = prefs.getString('contact_phone_mapping');

      if (mappingJson != null) {
        final Map<String, dynamic> mapping = json.decode(mappingJson);
        final phoneNumber = mapping[widget.username];

        if (phoneNumber != null) {
          // print('[FriendInfoScreen] Found phone number in local storage for ${widget.username}');
          setState(() {
            _realPhoneNumber = phoneNumber;
          });
        } else {
          // print('[FriendInfoScreen] No phone number found for ${widget.username}');
        }
      }

      setState(() => _isLoading = false);
    } catch (e) {
      // print('[FriendInfoScreen] Error loading info: $e');
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final displayName = widget.displayName ?? widget.username;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Friend Info'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              child: Column(
                children: [
                  const SizedBox(height: 32),
                  // Avatar
                  CircleAvatar(
                    radius: 60,
                    backgroundColor: Colors.grey[800],
                    backgroundImage: widget.avatarUrl != null
                        ? NetworkImage(widget.avatarUrl!)
                        : null,
                    child: widget.avatarUrl == null
                        ? Text(
                            displayName[0].toUpperCase(),
                            style: const TextStyle(
                              fontSize: 48,
                              color: Colors.white,
                            ),
                          )
                        : null,
                  ),
                  const SizedBox(height: 24),

                  // Display Name
                  Text(
                    displayName,
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 8),

                  // Username
                  Text(
                    '@${widget.username}',
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.grey[400],
                    ),
                  ),
                  const SizedBox(height: 32),

                  // Info Cards
                  // Only show phone number if available (only passed when from contacts)
                  if (_realPhoneNumber != null && _realPhoneNumber!.isNotEmpty)
                    _buildInfoCard(
                      icon: Icons.phone,
                      label: 'Phone Number',
                      value: _realPhoneNumber!,
                    ),

                  _buildInfoCard(
                    icon: Icons.info_outline,
                    label: 'Bio',
                    value: _bio ?? 'No bio yet',
                  ),

                  const SizedBox(height: 32),
                ],
              ),
            ),
    );
  }

  Widget _buildInfoCard({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12.0),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.lightBlueAccent, size: 24),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: Colors.grey[400],
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
