class MessageReaction {
  final int id;
  final int messageId;
  final String userUid;
  final String emoji;
  final DateTime createdAt;

  // Optional: username for display purposes (fetched from profiles)
  final String? username;

  MessageReaction({
    required this.id,
    required this.messageId,
    required this.userUid,
    required this.emoji,
    required this.createdAt,
    this.username,
  });

  factory MessageReaction.fromJson(Map<String, dynamic> json) {
    return MessageReaction(
      id: json['id'] as int,
      messageId: json['message_id'] as int,
      userUid: json['user_uid'] as String,
      emoji: json['emoji'] as String,
      createdAt: json['created_at'] is String
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.now(),
      username: json['username'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'message_id': messageId,
      'user_uid': userUid,
      'emoji': emoji,
      'created_at': createdAt.toIso8601String(),
      if (username != null) 'username': username,
    };
  }

  MessageReaction copyWith({
    int? id,
    int? messageId,
    String? userUid,
    String? emoji,
    DateTime? createdAt,
    String? username,
  }) {
    return MessageReaction(
      id: id ?? this.id,
      messageId: messageId ?? this.messageId,
      userUid: userUid ?? this.userUid,
      emoji: emoji ?? this.emoji,
      createdAt: createdAt ?? this.createdAt,
      username: username ?? this.username,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MessageReaction &&
          runtimeType == other.runtimeType &&
          messageId == other.messageId &&
          userUid == other.userUid &&
          emoji == other.emoji;

  @override
  int get hashCode => messageId.hashCode ^ userUid.hashCode ^ emoji.hashCode;
}

/// Grouped reactions for a message (for UI display)
class ReactionGroup {
  final String emoji;
  final int count;
  final List<String> userUids;
  final bool currentUserReacted;

  ReactionGroup({
    required this.emoji,
    required this.count,
    required this.userUids,
    required this.currentUserReacted,
  });

  /// Create reaction groups from list of reactions
  static Map<String, ReactionGroup> groupReactions(
    List<MessageReaction> reactions,
    String currentUserUid,
  ) {
    final Map<String, ReactionGroup> groups = {};

    for (final reaction in reactions) {
      if (!groups.containsKey(reaction.emoji)) {
        groups[reaction.emoji] = ReactionGroup(
          emoji: reaction.emoji,
          count: 0,
          userUids: [],
          currentUserReacted: false,
        );
      }

      final existingGroup = groups[reaction.emoji]!;
      groups[reaction.emoji] = ReactionGroup(
        emoji: reaction.emoji,
        count: existingGroup.count + 1,
        userUids: [...existingGroup.userUids, reaction.userUid],
        currentUserReacted: existingGroup.currentUserReacted ||
            reaction.userUid == currentUserUid,
      );
    }

    return groups;
  }
}
