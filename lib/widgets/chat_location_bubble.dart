import 'location_map.dart';
import 'sharing_ui.dart';
import 'package:flutter/material.dart';
import '../models/chat_payloads.dart';

class ChatLocationBubble extends StatelessWidget {
  final LocationPayload payload;
  final bool isMe;

  const ChatLocationBubble({
    super.key,
    required this.payload,
    required this.isMe,
  });

  @override
  Widget build(BuildContext context) {
    final c = SharingColors(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SizedBox(
      width: 245,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LocationMap(
            latitude: payload.latitude,
            longitude: payload.longitude,
            height: 130,
          ),
          const SizedBox(height: 9),
          Text(
            payload.name?.isNotEmpty == true ? payload.name! : 'Shared Location',
            style: c.text(13, bold: true),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (payload.address?.isNotEmpty == true) ...[
            const SizedBox(height: 2),
            Text(
              payload.address!,
              style: c.text(11, secondary: true),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          const SizedBox(height: 6),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.directions_outlined,
                size: 13,
                color: isDark ? const Color(0xFF8BA5DF) : const Color(0xFF4267B2),
              ),
              const SizedBox(width: 4),
              Text(
                'Open in Google Maps',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: isDark ? const Color(0xFF8BA5DF) : const Color(0xFF4267B2),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
