import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart';
import 'package:zarq_messenger/app_config.dart';

class PaymentService {
  static const String baseUrl = '${AppConfig.baseUrl}';
  static const MethodChannel _paymentChannel = MethodChannel('com.zarq/payment');

  // Create Razorpay order
  static Future<Map<String, dynamic>> createOrder(String planId) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw Exception('User not authenticated');
      }

      final token = await user.getIdToken();
      final response = await http.post(
        Uri.parse('$baseUrl/payment/create-order'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'plan_id': planId,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          return data;
        } else {
          throw Exception(data['error'] ?? 'Failed to create order');
        }
      } else {
        throw Exception('Server error: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Failed to create order: $e');
    }
  }

  // Verify payment
  static Future<Map<String, dynamic>> verifyPayment({
    required String orderId,
    required String paymentId,
    required String signature,
    required String planId,
  }) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw Exception('User not authenticated');
      }

      final token = await user.getIdToken();
      final response = await http.post(
        Uri.parse('$baseUrl/payment/verify'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'order_id': orderId,
          'payment_id': paymentId,
          'signature': signature,
          'plan_id': planId,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          return data;
        } else {
          throw Exception(data['error'] ?? 'Payment verification failed');
        }
      } else {
        throw Exception('Server error: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Failed to verify payment: $e');
    }
  }

  // Get subscription status
  static Future<Map<String, dynamic>> getSubscriptionStatus() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw Exception('User not authenticated');
      }

      final token = await user.getIdToken();
      final response = await http.get(
        Uri.parse('$baseUrl/payment/subscription-status'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw Exception('Server error: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Failed to get subscription status: $e');
    }
  }

  // Start native Razorpay payment (using Kotlin implementation)
  static Future<Map<String, dynamic>> startNativeRazorpayPayment({
    required String keyId,
    required int amount,
    required String currency,
    required String orderId,
    required String name,
    required String description,
  }) async {
    try {
      final result = await _paymentChannel.invokeMethod('startRazorpayPayment', {
        'key_id': keyId,
        'amount': amount,
        'currency': currency,
        'order_id': orderId,
        'name': name,
        'description': description,
      });

      // Result will be a Map with payment_id, order_id, signature
      return Map<String, dynamic>.from(result);
    } on PlatformException catch (e) {
      if (e.code == 'PAYMENT_ERROR') {
        // User cancelled or payment failed
        throw Exception('Payment failed: ${e.message}');
      } else {
        throw Exception('Payment initialization failed: ${e.message}');
      }
    } catch (e) {
      throw Exception('Native payment error: $e');
    }
  }

  // Get subscription plans dynamically from backend
  static Future<List<Map<String, dynamic>>> getSubscriptionPlans() async {
    try {
      // Get auth token if user is logged in (optional for this endpoint)
      final user = FirebaseAuth.instance.currentUser;
      final headers = {
        'Content-Type': 'application/json',
      };

      // Add auth token if user is authenticated to track trial usage
      if (user != null) {
        final token = await user.getIdToken();
        headers['Authorization'] = 'Bearer $token';
      }

      final response = await http.get(
        Uri.parse('$baseUrl/payment/plans'),
        headers: headers,
      );

      if (response.statusCode == 200) {
        final List<dynamic> plansData = jsonDecode(response.body);
        return plansData.cast<Map<String, dynamic>>();
      } else {
        throw Exception('Failed to load plans: ${response.statusCode}');
      }
    } catch (e) {
      // Return empty list on error - UI will show loading error
      throw Exception('Failed to fetch subscription plans: $e');
    }
  }
}
