import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import '../models/chat_payloads.dart';
import 'sharing_ui.dart';

class ShareContactPage extends StatefulWidget {
  const ShareContactPage({super.key, this.initialContact});
  final Contact? initialContact;
  @override
  State<ShareContactPage> createState() => _ShareContactPageState();
}
class _ShareContactPageState extends State<ShareContactPage> {
  final _search = TextEditingController();
  List<Contact> _contacts = [];
  Contact? _selected;
  int _phone = 0;
  bool _loading = true;
  String? _error;
  @override
  void initState() { super.initState(); if (widget.initialContact != null) { _selected = widget.initialContact; _loading = false; } else { _load(); } }
  @override
  void dispose() { _search.dispose(); super.dispose(); }
  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final contacts = await FlutterContacts.getContacts(withProperties: true);
      contacts.sort((a, b) => a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()));
      if (mounted) setState(() => _contacts = contacts);
    } catch (_) { if (mounted) setState(() => _error = 'Could not load contacts. Please try again.'); }
    finally { if (mounted) setState(() => _loading = false); }
  }
  @override
  Widget build(BuildContext context) {
    final c = SharingColors(context);
    final selected = _selected;
    final query = _search.text.trim().toLowerCase();
    final rows = _contacts.where((v) => v.displayName.toLowerCase().contains(query) || v.phones.any((p) => p.number.contains(query))).toList();
    Widget avatar(String name, double radius) => CircleAvatar(radius: radius, backgroundColor: c.soft, child: Text(name.isEmpty ? '?' : name.characters.first.toUpperCase(), style: c.text(13)));
    return SharingPage(title: selected == null ? 'Share a contact' : 'Share contact', subtitle: selected == null ? 'Your phone contacts' : 'From your phone contacts',
      onBack: selected == null || widget.initialContact != null ? null : () => setState(() => _selected = null),
      action: selected == null ? null : 'Share contact',
      onAction: selected == null || selected.phones.isEmpty ? null : () => Navigator.pop(context, ContactPayload(name: selected.displayName.isEmpty ? 'Contact' : selected.displayName, phones: [selected.phones[_phone].number])),
      child: selected != null ? ListView(padding: const EdgeInsets.all(22), children: [
        Row(children: [avatar(selected.displayName, 24), const SizedBox(width: 12), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(selected.displayName, style: c.text(16, bold: true)), Text('Contact details', style: c.text(11, secondary: true))]))]),
        const SizedBox(height: 24), Text('PHONE NUMBER', style: c.text(10, secondary: true)),
        for (var i = 0; i < selected.phones.length; i++) InkWell(onTap: () => setState(() => _phone = i), child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14), decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.line))),
          child: Row(children: [Icon(Icons.phone_outlined, size: 18, color: c.muted), const SizedBox(width: 12), Expanded(child: Text(selected.phones[i].number, style: c.text(12))), Icon(_phone == i ? Icons.radio_button_checked : Icons.radio_button_off, size: 18, color: c.blue)]))),
        const SizedBox(height: 16), Text(selected.phones.isEmpty ? 'This contact has no phone number. Choose another contact.' : 'Only the name and selected phone number will be shared.', style: c.text(11, secondary: true)),
      ]) : Column(children: [Padding(padding: const EdgeInsets.fromLTRB(22, 20, 22, 10), child: TextField(controller: _search, onChanged: (_) => setState(() {}), style: c.text(12), decoration: c.field('Search name or number').copyWith(prefixIcon: Icon(Icons.search, size: 18, color: c.muted)))),
        Expanded(child: _loading ? Center(child: CircularProgressIndicator(color: c.blue, strokeWidth: 2)) : _error != null ? Center(child: TextButton(onPressed: _load, child: Text(_error!))) : rows.isEmpty ? Center(child: Text('No matching contacts.', style: c.text(12, secondary: true))) : ListView.builder(padding: const EdgeInsets.symmetric(horizontal: 22), itemCount: rows.length, itemBuilder: (_, i) {
          final contact = rows[i];
          return InkWell(onTap: () => setState(() { _selected = contact; _phone = 0; }), child: Container(padding: const EdgeInsets.symmetric(vertical: 13), decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.line))), child: Row(children: [avatar(contact.displayName, 20), const SizedBox(width: 11), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(contact.displayName, style: c.text(13)), Text(contact.phones.isEmpty ? 'No phone number' : contact.phones.first.number, style: c.text(11, secondary: true))])), Icon(Icons.chevron_right, color: c.muted, size: 18)])));
        })),
      ]));
  }
}
