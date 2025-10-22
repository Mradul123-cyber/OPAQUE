import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import '../models/message_reaction.dart';
import '../services/websocket_service.dart';

class MessageReactionsWidget extends StatelessWidget {
  final int messageId;
  final List<dynamic>? reactions; // MessageReaction objects
  final bool isMe;

  const MessageReactionsWidget({
    Key? key,
    required this.messageId,
    required this.reactions,
    required this.isMe,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (reactions == null || reactions!.isEmpty) {
      return const SizedBox.shrink();
    }

    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return const SizedBox.shrink();

    // Group reactions by emoji
    final reactionGroups = ReactionGroup.groupReactions(
      reactions!.cast<MessageReaction>(),
      currentUser.uid,
    );

    if (reactionGroups.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 4.0),
      child: Wrap(
        spacing: 4,
        runSpacing: 4,
        children: reactionGroups.entries.map((entry) {
          final group = entry.value;
          return _buildReactionChip(context, group);
        }).toList(),
      ),
    );
  }

  Widget _buildReactionChip(BuildContext context, ReactionGroup group) {
    final wsService = Provider.of<WebSocketService>(context, listen: false);

    return GestureDetector(
      onTap: () {
        // Toggle reaction: if user already reacted, remove it; otherwise add it
        if (group.currentUserReacted) {
          wsService.removeReaction(messageId: messageId, emoji: group.emoji);
        } else {
          wsService.addReaction(messageId: messageId, emoji: group.emoji);
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: group.currentUserReacted
              ? Colors.blue.withOpacity(0.2)
              : Colors.grey.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: group.currentUserReacted
                ? Colors.blue.withOpacity(0.5)
                : Colors.grey.withOpacity(0.3),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              group.emoji,
              style: const TextStyle(fontSize: 14),
            ),
            if (group.count > 1) ...[
              const SizedBox(width: 4),
              Text(
                '${group.count}',
                style: TextStyle(
                  fontSize: 12,
                  color: group.currentUserReacted
                      ? Colors.blue[700]
                      : Colors.grey[700],
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Reaction picker bottom sheet
class ReactionPicker extends StatelessWidget {
  final int messageId;
  final Function(String emoji) onReactionSelected;

  const ReactionPicker({
    Key? key,
    required this.messageId,
    required this.onReactionSelected,
  }) : super(key: key);

  static const List<String> availableEmojis = [
    '👍', // Thumbs up
    '❤️', // Heart
    '😂', // Laughing
    '😮', // Wow
    '😢', // Sad
    '🔥', // Fire
  ];

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final bottomPadding = MediaQuery.of(context).viewInsets.bottom + MediaQuery.of(context).padding.bottom;

    final padding = (screenWidth * 0.04).clamp(16.0, 24.0);
    final titleSize = (screenWidth * 0.04).clamp(14.0, 18.0);
    final emojiSize = (screenWidth * 0.12).clamp(45.0, 60.0);
    final emojiFontSize = (screenWidth * 0.07).clamp(26.0, 32.0);
    final spacing = (screenHeight * 0.025).clamp(15.0, 25.0);

    return Container(
      padding: EdgeInsets.fromLTRB(
        padding,
        spacing,
        padding,
        bottomPadding + spacing,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          SizedBox(height: spacing * 0.8),
          // Title
          Text(
            'React to message',
            style: TextStyle(
              fontSize: titleSize,
              fontWeight: FontWeight.w600,
              color: Colors.grey[800],
            ),
          ),
          SizedBox(height: spacing),
          // Emoji grid
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: availableEmojis.map((emoji) {
              return GestureDetector(
                onTap: () {
                  onReactionSelected(emoji);
                  Navigator.pop(context);
                },
                child: Container(
                  width: emojiSize,
                  height: emojiSize,
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(emojiSize / 2),
                    border: Border.all(
                      color: Colors.grey[300]!,
                      width: 1,
                    ),
                  ),
                  child: Center(
                    child: Text(
                      emoji,
                      style: TextStyle(fontSize: emojiFontSize),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  static void show(BuildContext context, int messageId, Function(String) onReactionSelected) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => ReactionPicker(
        messageId: messageId,
        onReactionSelected: onReactionSelected,
      ),
    );
  }
}
