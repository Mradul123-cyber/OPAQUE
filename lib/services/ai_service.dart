import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:zarq_messenger/app_config.dart';

/// Secure AI Service - Calls backend (API key safely stored on server)
///
/// This service provides:
/// - Secure AI processing through backend
/// - Daily usage limits (5 messages/day - tracked on server)
/// - No API key exposure in client app
/// - Firebase authentication for security
class AIService {
  static final AIService _instance = AIService._internal();
  factory AIService() => _instance;
  AIService._internal();

  bool _isInitialized = false;

  // Daily message limit (enforced on backend)
  static const int dailyMessageLimit = 5;

  /// Initialize the AI service
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      _isInitialized = true;
      debugPrint('[AIService] Initialized - using secure backend');
    } catch (e) {
      debugPrint('[AIService] Initialization error: $e');
      _isInitialized = true;
    }
  }

  /// Get Firebase auth token
  Future<String?> _getAuthToken() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        debugPrint('[AIService] No authenticated user');
        return null;
      }
      return await user.getIdToken();
    } catch (e) {
      debugPrint('[AIService] Error getting auth token: $e');
      return null;
    }
  }

  /// Call secure backend API
  Future<AIResponse> _callBackendAI({
    required String action,
    required String text,
    String? targetLanguage,
    String? style,
  }) async {
    try {
      final token = await _getAuthToken();
      if (token == null) {
        return AIResponse(
          content: "Authentication error. Please sign in again.",
          isOnDevice: false,
          success: false,
          error: "No auth token",
        );
      }

      final url = Uri.parse('${AppConfig.baseUrl}/v1/ai/process');

      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'action': action,
          'text': text,
          if (targetLanguage != null) 'targetLanguage': targetLanguage,
          if (style != null) 'style': style,
        }),
      ).timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          throw Exception('Request timeout');
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final success = data['success'] ?? false;
        final content = data['content'] ?? 'No response';
        final error = data['error'];

        // Check if this is ANY limit error (per-user, global, token, or RPM)
        final isLimitError = !success && (
          error != null && (
            error.toString().contains('limit') ||
            error.toString().contains('Daily limit') ||
            error.toString().contains('Global daily limit') ||
            error.toString().contains('Rate limit') ||
            error.toString().contains('RPM')
          ) ||
          content.contains('Limit Reached') ||
          content.contains('Temporarily Unavailable') ||
          content.contains('Too Many Requests')
        );

        if (isLimitError) {
          // Unified error message for ALL limit types
          return AIResponse(
            content: "🔒 AI Feature Temporarily Unavailable\n\n"
                "Our AI service has reached its capacity for now.\n\n"
                "✨ Need more AI access?\n"
                "Upgrade to Premium for higher limits!\n\n"
                "Try again later or upgrade now.",
            isOnDevice: false,
            success: false,
            error: "Limit reached",
          );
        }

        return AIResponse(
          content: content,
          isOnDevice: false,
          success: success,
          error: error,
        );
      } else if (response.statusCode == 429) {
        // Any 429 status = limit reached (unified message)
        return AIResponse(
          content: "🔒 AI Feature Temporarily Unavailable\n\n"
              "Our AI service has reached its capacity for now.\n\n"
              "✨ Need more AI access?\n"
              "Upgrade to Premium for higher limits!\n\n"
              "Try again later or upgrade now.",
          isOnDevice: false,
          success: false,
          error: "Limit reached",
        );
      } else {
        debugPrint('[AIService] Backend error: ${response.statusCode} - ${response.body}');
        return AIResponse(
          content: "Sorry, the AI service is temporarily unavailable. Please try again later.",
          isOnDevice: false,
          success: false,
          error: "Backend error: ${response.statusCode}",
        );
      }
    } catch (e) {
      debugPrint('[AIService] Network error: $e');
      return AIResponse(
        content: "Sorry, I encountered an error connecting to AI service.\n\n"
            "Error: ${e.toString()}\n\n"
            "Please check your internet connection and try again.",
        isOnDevice: false,
        success: false,
        error: e.toString(),
      );
    }
  }

  /// Get remaining messages for today (estimated client-side)
  /// Note: Actual limit is enforced on backend
  Future<int> getRemainingMessages() async {
    // This is just for UI display - backend handles actual tracking
    return dailyMessageLimit;
  }

  /// Translate text to target language
  /// Securely processed on backend - API key never exposed
  Future<AIResponse> translateMessage(String text, String targetLanguage) async {
    return _callBackendAI(
      action: 'translate',
      text: text,
      targetLanguage: targetLanguage,
    );
  }

  /// Summarize text
  /// Securely processed on backend - API key never exposed
  Future<AIResponse> summarizeMessage(String text, {String? targetLanguage}) async {
    return _callBackendAI(
      action: 'summarize',
      text: text,
      targetLanguage: targetLanguage,
    );
  }

  /// Enhance/rewrite message
  /// Securely processed on backend - API key never exposed
  Future<AIResponse> enhanceMessage(String text, String style, {String? targetLanguage}) async {
    return _callBackendAI(
      action: 'enhance',
      text: text,
      style: style,
      targetLanguage: targetLanguage,
    );
  }

  /// Explain message content
  /// Securely processed on backend - API key never exposed
  Future<AIResponse> explainMessage(String text, {String? targetLanguage}) async {
    return _callBackendAI(
      action: 'explain',
      text: text,
      targetLanguage: targetLanguage,
    );
  }

  /// General AI chat for AI Chat Screen
  /// Securely processed on backend - API key never exposed
  Future<AIResponse> processChat(String text) async {
    return _callBackendAI(
      action: 'chat',
      text: text,
    );
  }

  /// Check if AI service is available
  bool get isCloudAvailable => _isInitialized;

  /// Get AI service status
  String get status {
    if (!_isInitialized) return "Not initialized";
    return "Secure backend AI ready";
  }
}

/// Response from AI processing
class AIResponse {
  final String content;
  final bool isOnDevice;
  final bool success;
  final String? error;

  AIResponse({
    required this.content,
    required this.isOnDevice,
    required this.success,
    this.error,
  });

  factory AIResponse.fromJson(Map<String, dynamic> json) {
    return AIResponse(
      content: json['content'] ?? '',
      isOnDevice: json['isOnDevice'] ?? false,
      success: json['success'] ?? false,
      error: json['error'],
    );
  }
}
