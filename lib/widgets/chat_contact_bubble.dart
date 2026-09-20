import 'sharing_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/chat_payloads.dart';
import 'opaque_toast.dart';

class ChatContactBubble extends StatelessWidget {
  final ContactPayload payload;
  final bool isMe;
  final Widget? metadata;

  const ChatContactBubble({
    super.key,
    required this.payload,
    required this.isMe,
    this.metadata,
  });

  Future<void> _callNumber(BuildContext context, String number) async {
    try {
      final clean = number.replaceAll(RegExp(r'[\s().-]'), '');
      if (!RegExp(r'^\+?[0-9]{3,20}$').hasMatch(clean)) {
        throw const FormatException('Unsupported phone number');
      }
      if (!await launchUrl(Uri(scheme: 'tel', path: clean)))
        throw StateError('No dialer available');
    } catch (_) {
      if (context.mounted) {
        OpaqueToast.error(context, 'Could not open phone dialer');
      }
    }
  }

  Future<void> _saveContact(BuildContext context) async {
    try {
      final permission = await FlutterContacts.requestPermission();
      if (!permission) {
        if (context.mounted) {
          OpaqueToast.warning(context, 'Contacts permission denied');
        }
        return;
      }

      final newContact = Contact()
        ..name.first = payload.name
        ..phones = payload.phones.map((p) => Phone(p)).toList()
        ..emails = payload.emails.map((e) => Email(e)).toList();

      if (payload.organization != null && payload.organization!.isNotEmpty) {
        newContact.organizations = [
          Organization(company: payload.organization!),
        ];
      }

      await FlutterContacts.openExternalInsert(newContact);
    } catch (e) {
      if (context.mounted) {
        OpaqueToast.error(context, 'Could not save contact');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = SharingColors(context);
    final ink = c.dark ? const Color(0xFFE4E8EF) : const Color(0xFF202127);
    final muted = c.dark ? const Color(0xFF9DA7B6) : const Color(0xFF858A94);
    final edge = c.dark ? const Color(0xFF3C4655) : const Color(0xFFDFE3E8);
    final phone = payload.phones.isEmpty ? null : payload.phones.first;
    final name = payload.name.trim();
    final initials = name.isEmpty
        ? '?'
        : name
              .split(RegExp(r'\s+'))
              .take(2)
              .map((s) => s.characters.first)
              .join()
              .toUpperCase();
    Widget action(String label, IconData icon, VoidCallback? onTap) => Expanded(
      child: TextButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 16),
        label: Text(
          label,
          style: c
              .text(12)
              .copyWith(
                color: onTap == null ? muted : ink,
                fontWeight: FontWeight.w500,
              ),
        ),
        style: TextButton.styleFrom(
          foregroundColor: ink,
          disabledForegroundColor: muted,
          minimumSize: const Size(0, 43),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          shape: const RoundedRectangleBorder(),
        ),
      ),
    );
    return SizedBox(
      width: 268,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 15, 14, 11),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isMe
                        ? (c.dark ? const Color(0xFF19202A) : Colors.white)
                        : (c.dark
                              ? const Color(0xFF27313E)
                              : const Color(0xFFF3F4F6)),
                    border: Border.all(
                      color: c.dark
                          ? const Color(0xFF35404F)
                          : const Color(0xFFE9EBEE),
                    ),
                  ),
                  child: Text(
                    initials,
                    style: c
                        .text(13)
                        .copyWith(color: muted, fontWeight: FontWeight.w500),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name.isEmpty ? 'Contact' : name,
                        style: c
                            .text(14, bold: true)
                            .copyWith(
                              color: ink,
                              height: 1.45,
                              letterSpacing: -.15,
                            ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        phone ??
                            (payload.emails.isEmpty
                                ? 'Contact'
                                : payload.emails.first),
                        style: c.text(12).copyWith(color: muted, height: 1.5),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (metadata != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(13, 0, 13, 9),
              child: Align(alignment: Alignment.centerRight, child: metadata!),
            ),
          Divider(height: 1, thickness: 1, color: edge),
          Row(
            children: [
              action(
                'Call',
                Icons.call_outlined,
                phone == null ? null : () => _callNumber(context, phone),
              ),
              SizedBox(
                height: 19,
                child: VerticalDivider(width: 1, thickness: 1, color: edge),
              ),
              action(
                'Save contact',
                Icons.person_add_alt_outlined,
                () => _saveContact(context),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
