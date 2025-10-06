// ============================================================================
// DEPRECATED FILE - NO LONGER IN USE
// ============================================================================
// This file contained API service for fetching user customization settings
// from the backend server. These features are now handled client-side using
// local storage (SharedPreferences) to eliminate server load.
//
// Replaced by: user_settings_local_service.dart
//
// This file can be safely deleted.
// Kept for reference only.
// ============================================================================

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';

// --- Existing Model for available styles ---
class BubbleOption {
  final int id;
  final String name;
  final String resourceKey;

  BubbleOption({required this.id, required this.name, required this.resourceKey});

  factory BubbleOption.fromJson(Map<String, dynamic> json) {
    return BubbleOption(
      id: json['id'],
      name: json['name'],
      resourceKey: json['resource_key'],
    );
  }
}

// --- MODIFIED: Model for the user's saved settings (now includes colors and home screen) ---
class UserSettings {
  final String bubbleStyle;
  final String myBubbleColorStart;
  final String myBubbleColorEnd;
  final String homeScreenStyle; // 'current' or 'default'

  UserSettings({
    required this.bubbleStyle,
    required this.myBubbleColorStart,
    required this.myBubbleColorEnd,
    this.homeScreenStyle = 'current', // Default to current design
  });
}

class UserSettingsService {
  final String _baseUrl = 'http://192.168.29.81:8080';

  Future<String> _getToken() async {
    final token = await FirebaseAuth.instance.currentUser?.getIdToken();
    if (token == null) {
      throw Exception("User not authenticated.");
    }
    return token;
  }

  // 1. Fetch all available bubble styles from the backend (GET)
  Future<List<BubbleOption>> fetchBubbleOptions() async {
    final url = Uri.parse('$_baseUrl/v1/customization/options/bubble');
    final response = await http.get(url);

    if (response.statusCode == 200) {
      final List<dynamic> jsonList = json.decode(response.body);
      return jsonList.map((json) => BubbleOption.fromJson(json)).toList();
    } else {
      throw Exception('Failed to load bubble options: ${response.body}');
    }
  }

  // --- NEW/REPLACED: Fetch all current user settings (including colors) ---
  Future<UserSettings> fetchAllUserSettings() async {
    final token = await _getToken();
    final url = Uri.parse('$_baseUrl/v1/user/settings');

    final response = await http.get(
      url,
      headers: {'Authorization': 'Bearer $token'},
    );

    if (response.statusCode == 200) {
      final Map<String, dynamic> jsonResponse = json.decode(response.body);

      return UserSettings(
        bubbleStyle: jsonResponse['bubble_style'] ?? 'default_rounded',
        myBubbleColorStart: jsonResponse['my_bubble_color_start'] ?? '667EEA',
        myBubbleColorEnd: jsonResponse['my_bubble_color_end'] ?? '764BA2',
        homeScreenStyle: jsonResponse['home_screen_style'] ?? 'current',
      );
    } else {
      // Return safe defaults on error
      // print('Failed to fetch user settings: ${response.body}');
      return UserSettings(
        bubbleStyle: 'default_rounded',
        myBubbleColorStart: '667EEA',
        myBubbleColorEnd: '764BA2',
        homeScreenStyle: 'current',
      );
    }
  }

  // --- NEW/REPLACED: Save all settings (style, colors, and home screen) ---
  Future<void> saveUserSettings({
    String? styleKey,
    String? colorStart,
    String? colorEnd,
    String? homeScreenStyle,
  }) async {
    final token = await _getToken();
    final url = Uri.parse('$_baseUrl/v1/user/settings');

    // Build the request body with only provided non-null fields
    final Map<String, String> body = {};
    if (styleKey != null) body['bubble_style'] = styleKey;
    if (colorStart != null) body['my_bubble_color_start'] = colorStart;
    if (homeScreenStyle != null) body['home_screen_style'] = homeScreenStyle;
    if (colorEnd != null) body['my_bubble_color_end'] = colorEnd;

    // Check if we actually have anything to send
    if (body.isEmpty) return;

    final response = await http.post(
      url,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: json.encode(body),
    );

    if (response.statusCode != 204) { // Expecting 204 No Content on success
      throw Exception('Failed to save settings: ${response.body}');
    }
  }
}