import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'device_service.dart';

class TurnService {
  static Map<String, dynamic>? _cachedCredentials;
  static DateTime? _cacheExpiry;

  /// Fetch TURN credentials from backend
  /// Credentials are cached for 23 hours (slightly less than the 24-hour TTL)
  static Future<Map<String, dynamic>?> getTurnCredentials() async {
    try {
      // Check if we have valid cached credentials
      if (_cachedCredentials != null &&
          _cacheExpiry != null &&
          DateTime.now().isBefore(_cacheExpiry!)) {
        print('[TurnService] Using cached TURN credentials');
        return _cachedCredentials;
      }

      // Get Firebase auth token
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        print('[TurnService] No authenticated user');
        return null;
      }

      final idToken = await user.getIdToken();

      // Fetch fresh credentials from backend
      final response = await http.get(
        Uri.parse('${DeviceService.baseUrl}/v1/turn/credentials'),
        headers: {
          'Authorization': 'Bearer $idToken',
          'Content-Type': 'application/json',
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final credentials = json.decode(response.body);

        // Cache the credentials for 23 hours
        _cachedCredentials = credentials;
        _cacheExpiry = DateTime.now().add(const Duration(hours: 23));

        print('[TurnService] ✅ Fetched fresh TURN credentials');
        print('[TurnService] Username: ${credentials['username']}');
        print('[TurnService] ICE servers count: ${credentials['ice_servers']?.length ?? 0}');

        return credentials;
      } else {
        print('[TurnService] ❌ Failed to fetch TURN credentials: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      print('[TurnService] ❌ Error fetching TURN credentials: $e');

      // Fallback to default configuration if backend fails
      // This ensures the app still works during backend issues
      return _getFallbackConfiguration();
    }
  }

  /// Clear cached credentials (useful on logout)
  static void clearCache() {
    _cachedCredentials = null;
    _cacheExpiry = null;
  }

  /// Fallback configuration for development/testing
  /// In production, this should fail rather than use insecure defaults
  static Map<String, dynamic> _getFallbackConfiguration() {
    print('[TurnService] ⚠️ Using fallback configuration - backend unreachable');

    return {
      'ice_servers': [
        // Google STUN servers (always available)
        {'urls': 'stun:stun.l.google.com:19302'},
        {'urls': 'stun:stun1.l.google.com:19302'},

        // Public TURN server (remove in production)
        {
          'urls': 'turn:openrelay.metered.ca:80',
          'username': 'openrelayproject',
          'credential': 'openrelayproject',
        },
      ],
    };
  }
}