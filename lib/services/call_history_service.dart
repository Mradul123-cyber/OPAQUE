import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:zarq_messenger/app_config.dart';

class CallLogModel {
  final int id;
  final String callerUid;
  final String receiverUid;
  final String callType; // 'voice' or 'video'
  final String callStatus; // 'completed', 'rejected', 'missed', etc.
  final int? conversationId;
  final DateTime startedAt;
  final DateTime? endedAt;
  final int? durationSeconds;

  // Additional fields
  final String otherUserUid;
  final String otherUserName;
  final String? otherUserAvatar;
  final String direction; // 'incoming' or 'outgoing'

  CallLogModel({
    required this.id,
    required this.callerUid,
    required this.receiverUid,
    required this.callType,
    required this.callStatus,
    this.conversationId,
    required this.startedAt,
    this.endedAt,
    this.durationSeconds,
    required this.otherUserUid,
    required this.otherUserName,
    this.otherUserAvatar,
    required this.direction,
  });

  factory CallLogModel.fromJson(Map<String, dynamic> json) {
    return CallLogModel(
      id: json['id'],
      callerUid: json['caller_uid'],
      receiverUid: json['receiver_uid'],
      callType: json['call_type'],
      callStatus: json['call_status'],
      conversationId: json['conversation_id'],
      startedAt: DateTime.parse(json['started_at']).toLocal(),
      endedAt: json['ended_at'] != null ? DateTime.parse(json['ended_at']).toLocal() : null,
      durationSeconds: json['duration_seconds'],
      otherUserUid: json['other_user_uid'],
      otherUserName: json['other_user_name'],
      otherUserAvatar: json['other_user_avatar'],
      direction: json['direction'],
    );
  }

  String get formattedDuration {
    if (durationSeconds == null) return '';

    final duration = Duration(seconds: durationSeconds!);
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);

    if (hours > 0) {
      return '${hours}h ${minutes}m';
    } else if (minutes > 0) {
      return '${minutes}m ${seconds}s';
    } else {
      return '${seconds}s';
    }
  }

  String get statusText {
    switch (callStatus) {
      case 'completed':
        return formattedDuration;
      case 'missed':
        return direction == 'incoming' ? 'Missed' : 'Cancelled';
      case 'rejected':
        return 'Declined';
      default:
        return callStatus;
    }
  }
}

class CallHistoryService {
  static const String baseUrl = '${AppConfig.baseUrl}'; // Update with your server URL

  static Future<List<CallLogModel>> getCallHistory({int limit = 50}) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw Exception('User not authenticated');
      }

      final response = await http.get(
        Uri.parse('$baseUrl/v1/calls/history?uid=${user.uid}&limit=$limit'),
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        return data.map((json) => CallLogModel.fromJson(json)).toList();
      } else {
        throw Exception('Failed to load call history: ${response.statusCode}');
      }
    } catch (e) {
      // print('[CallHistoryService] Error fetching call history: $e');
      rethrow;
    }
  }
}
