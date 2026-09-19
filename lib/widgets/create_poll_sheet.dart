import 'package:uuid/uuid.dart';
import 'sharing_ui.dart';
import 'opaque_navigation.dart';
import 'package:flutter/material.dart';
import '../models/chat_payloads.dart';

class CreatePollSheet extends StatefulWidget {
  final String? currentUid;

  const CreatePollSheet({super.key, this.currentUid});

  @override
  State<CreatePollSheet> createState() => _CreatePollSheetState();
}

class _CreatePollSheetState extends State<CreatePollSheet> {
  final TextEditingController _questionController = TextEditingController();
  final List<TextEditingController> _optionControllers = [
    TextEditingController(),
    TextEditingController(),
  ];
  bool _allowMultiple = false;
  bool _submitted = false;
  String? _validationError;

  @override
  void dispose() {
    _questionController.dispose();
    for (final c in _optionControllers) {
      c.dispose();
    }
    super.dispose();
  }

  void _addOption() {
    if (_optionControllers.length < 10) {
      setState(() {
        _optionControllers.add(TextEditingController());
      });
    }
  }

  void _removeOption(int index) {
    if (_optionControllers.length > 2) {
      setState(() {
        _optionControllers[index].dispose();
        _optionControllers.removeAt(index);
      });
    }
  }

  void _submit() {
    if (_submitted) return;
    final question = _questionController.text.trim();
    final values = _optionControllers.map((c) => c.text.trim()).toList();
    String? error;
    if (question.isEmpty) { error = 'Add a question first.'; }
    else if (values.any((v) => v.isEmpty)) { error = 'Fill in each option or remove empty ones.'; }
    else if (values.map((v) => v.toLowerCase()).toSet().length != values.length) { error = 'Give each option a different answer.'; }
    setState(() => _validationError = error);
    if (error != null) return;
    if (question.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a poll question')),
      );
      return;
    }

    final options = <PollOption>[];
    for (int i = 0; i < _optionControllers.length; i++) {
      final text = _optionControllers[i].text.trim();
      if (text.isNotEmpty) {
        options.add(PollOption(id: i + 1, text: text));
      }
    }

    if (options.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please provide at least 2 options')),
      );
      return;
    }

    final poll = PollPayload(
      pollId: 'poll_${const Uuid().v4()}',
      question: question,
      options: options,
      allowMultiple: _allowMultiple,
      creatorUid: widget.currentUid,
      createdAt: DateTime.now().toUtc().toIso8601String(),
    );

    _submitted = true; Navigator.of(context).pop(poll);
  }

  @override
  Widget build(BuildContext context) {
    final c = SharingColors(context);
    return SharingPage(title: 'Create poll', subtitle: 'Ask a question', action: 'Create poll', onAction: _submit,
      child: ListView(padding: const EdgeInsets.all(22), children: [
        Text('Question', style: c.text(11, secondary: true)), const SizedBox(height: 8),
        TextField(controller: _questionController, minLines: 2, maxLines: 4, maxLength: 240, style: c.text(14), decoration: c.field('Ask a question…')),
        const SizedBox(height: 12), Text('OPTIONS', style: c.text(10, secondary: true)), const SizedBox(height: 9),
        for (var i = 0; i < _optionControllers.length; i++) Padding(padding: const EdgeInsets.only(bottom: 9), child: Row(children: [
          SizedBox(width: 28, child: Text('${i + 1}'.padLeft(2, '0'), style: c.text(10, secondary: true))),
          Expanded(child: TextField(controller: _optionControllers[i], maxLength: 100, style: c.text(12), decoration: c.field('Option ${i + 1}').copyWith(counterText: ''))),
          SizedBox(width: 30, child: IconButton(tooltip: 'Remove option ${i + 1}', padding: EdgeInsets.zero, icon: Icon(Icons.close, size: 16, color: c.muted), onPressed: _optionControllers.length > 2 ? () => _removeOption(i) : null)),
        ])),
        Align(alignment: Alignment.centerLeft, child: TextButton.icon(onPressed: _optionControllers.length < 10 ? _addOption : null, icon: const Icon(Icons.add, size: 16), label: const Text('Add option'), style: TextButton.styleFrom(foregroundColor: c.blue, textStyle: c.text(12)))),
        const SizedBox(height: 14), Divider(color: c.line),
        Row(children: [Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Allow multiple answers', style: c.text(12)), Text('Choose more than one option', style: c.text(11, secondary: true))])),
          Switch(value: _allowMultiple, onChanged: (v) => setState(() => _allowMultiple = v), activeColor: c.blue),
        ]),
        if (_validationError != null) Padding(padding: const EdgeInsets.only(top: 12), child: Semantics(liveRegion: true, child: Text(_validationError!, style: c.text(11).copyWith(color: const Color(0xFFC66F77))))),
      ]));
  }
}
