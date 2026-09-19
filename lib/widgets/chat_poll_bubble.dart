import 'sharing_ui.dart';
import 'opaque_navigation.dart';
import 'package:flutter/material.dart';
import '../models/chat_payloads.dart';

class ChatPollBubble extends StatelessWidget {
  final PollPayload payload;
  final Map<int, List<String>> votesByOption; // optionId -> list of voterUids
  final String? currentUid;
  final Function(int optionId) onVote;
  final bool isMe;

  const ChatPollBubble({
    super.key,
    required this.payload,
    required this.votesByOption,
    required this.currentUid,
    required this.onVote,
    required this.isMe,
  });

  @override
  Widget build(BuildContext context) {
    final c = SharingColors(context);
    final participants = votesByOption.values.expand((v) => v).toSet().length;
    return SizedBox(width: 241, child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(payload.question, style: c.text(13, bold: true)), const SizedBox(height: 3),
      Text(payload.allowMultiple ? 'Choose one or more' : 'Choose one answer', style: c.text(11, secondary: true)),
      for (final option in payload.options) Padding(padding: const EdgeInsets.only(top: 8), child: Builder(builder: (context) {
        final voters = votesByOption[option.id] ?? [];
        final chosen = currentUid != null && voters.contains(currentUid);
        return Semantics(selected: chosen, button: true, child: InkWell(onTap: () => onVote(option.id), borderRadius: BorderRadius.circular(8), child: Container(
          padding: const EdgeInsets.all(9), decoration: BoxDecoration(color: chosen ? c.soft : c.surface, border: Border.all(color: chosen ? c.blue : c.line), borderRadius: BorderRadius.circular(8)),
          child: Row(children: [Expanded(child: Text(option.text, style: c.text(12))), const SizedBox(width: 9), Text('${voters.length}', style: c.text(10, secondary: true))]),
        )));
      })), const SizedBox(height: 10),
      Text(participants == 0 ? 'No votes yet' : '$participants ${participants == 1 ? 'participant' : 'participants'}', style: c.text(11, secondary: true)),
    ]));
  }
}
