// lib/message_model.dart

class Message {
  final int id;
  final String username;
  final String content;
  final DateTime timestamp;
  final String? senderUid;

  Message({
    required this.id,
    required this.username,
    required this.content,
    required this.timestamp,
    this.senderUid,
  });

  factory Message.fromJson(Map<String, dynamic> json) {
    print('DEBUG: Message.fromJson received JSON: $json');

    final int parsedId = json['id'] as int;
    final dynamic usernameValue = json['username'];
    final String parsedUsername = (usernameValue is String) ? usernameValue : 'Unknown User';
    final dynamic contentValue = json['content'];
    final String parsedContent = (contentValue is String) ? contentValue : '--- Invalid Content ---';

    final dynamic timestampValue = json['timestamp'];
    DateTime parsedTimestamp;
    if (timestampValue is String) {
      try {
        parsedTimestamp = DateTime.parse(timestampValue);
      } catch (e) {
        print("WARNING: Message.fromJson - Invalid timestamp format for message ID $parsedId: $timestampValue. Using current time. Error: $e");
        parsedTimestamp = DateTime.now();
      }
    } else {
      print("WARNING: Message.fromJson - 'timestamp' is null or not a String for message ID $parsedId. Value: $timestampValue. Using current time.");
      parsedTimestamp = DateTime.now();
    }

    final String? parsedSenderUid = json['senderUid'] as String?;
    if (parsedSenderUid == null) {
      print('WARNING: Message.fromJson - "senderUid" is missing for message ID $parsedId.');
    }

    return Message(
      id: parsedId,
      username: parsedUsername,
      content: parsedContent,
      timestamp: parsedTimestamp,
      senderUid: parsedSenderUid,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'username': username,
      'content': content,
      'timestamp': timestamp.toIso8601String(),
      'senderUid': senderUid,
    };
  }

  Message copyWith({
    int? id,
    String? username,
    String? content,
    DateTime? timestamp,
    String? senderUid,
  }) {
    return Message(
      id: id ?? this.id,
      username: username ?? this.username,
      content: content ?? this.content,
      timestamp: timestamp ?? this.timestamp,
      senderUid: senderUid ?? this.senderUid,
    );
  }
}