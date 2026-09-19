import 'sharing_ui.dart';
import 'opaque_navigation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/chat_payloads.dart';

class ChatContactBubble extends StatelessWidget {
  final ContactPayload payload;
  final bool isMe;

  const ChatContactBubble({
    super.key,
    required this.payload,
    required this.isMe,
  });

  Future<void> _callNumber(BuildContext context, String number) async {
    try {
      final clean = number.replaceAll(RegExp(r'[\s().-]'), '');
      if (!RegExp(r'^\+?[0-9]{3,20}$').hasMatch(clean)) {
        throw const FormatException('Unsupported phone number');
      }
      if (!await launchUrl(Uri(scheme: 'tel', path: clean))) throw StateError('No dialer available');
    } catch (_) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not open this number in the phone app.')));
    }
  }
  Future<void> _saveContact(BuildContext context) async {
    try {
      final permission = await FlutterContacts.requestPermission();
      if (!permission) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Contacts permission denied')),
          );
        }
        return;
      }

      final newContact = Contact()
        ..name.first = payload.name
        ..phones = payload.phones.map((p) => Phone(p)).toList()
        ..emails = payload.emails.map((e) => Email(e)).toList();

      if (payload.organization != null && payload.organization!.isNotEmpty) {
        newContact.organizations = [Organization(company: payload.organization!)];
      }

      await FlutterContacts.openExternalInsert(newContact);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save contact: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = SharingColors(context);
    final phone = payload.phones.isEmpty ? null : payload.phones.first;
    final name = payload.name.trim();
    final initials = name.isEmpty ? '?' : name.split(RegExp(r'\s+')).take(2).map((s) => s.characters.first).join().toUpperCase();
    Widget button(String label, String icon, VoidCallback? onTap) => Expanded(child: SizedBox(height: 30, child: OutlinedButton.icon(
      onPressed: onTap, icon: OpaqueIcon(icon, size: 14, color: c.blue), label: Text(label, style: c.text(11).copyWith(color: c.blue)),
      style: OutlinedButton.styleFrom(backgroundColor: c.dark ? const Color(0xFF2D405B) : const Color(0xFFE7EEF8), foregroundColor: c.blue,
        side: BorderSide(color: c.dark ? const Color(0xFF3A506D) : const Color(0xFFD7E2F1)), padding: const EdgeInsets.symmetric(horizontal: 8),
        minimumSize: Size.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
    )));
    return SizedBox(width: 214, child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [CircleAvatar(radius: 16, backgroundColor: c.dark ? const Color(0xFF2C4851) : const Color(0xFFDEECEF), child: Text(initials, style: c.text(11))),
        const SizedBox(width: 9), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(payload.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: c.text(12, bold: true)), const SizedBox(height: 1),
          Text(phone ?? (payload.emails.isEmpty ? 'Contact' : payload.emails.first), maxLines: 1, overflow: TextOverflow.ellipsis, style: c.text(10, secondary: true)),
        ])),
      ]), const SizedBox(height: 8),
      Row(children: [button('Call', 'calls', phone == null ? null : () => _callNumber(context, phone)), const SizedBox(width: 7), button('Save', 'add', () => _saveContact(context))]),
    ]));
  }
}
