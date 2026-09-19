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
    return SizedBox(width: 241, child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
      LocationMap(latitude: payload.latitude, longitude: payload.longitude, height: 125), const SizedBox(height: 9),
      Text(payload.name?.isNotEmpty == true ? payload.name! : 'Shared location', style: c.text(13, bold: true)),
      if (payload.address?.isNotEmpty == true) Text(payload.address!, style: c.text(11, secondary: true)),
    ]));
  }
}
