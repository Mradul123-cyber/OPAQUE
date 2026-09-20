import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:provider/provider.dart';
import '../services/user_settings_provider.dart';
import '../widgets/call_aware_screen.dart';
import '../widgets/opaque_info_design.dart';

class MarkdownViewerScreen extends StatefulWidget {
  final String title;
  final String assetPath;
  const MarkdownViewerScreen({
    super.key,
    required this.title,
    required this.assetPath,
  });
  @override
  State<MarkdownViewerScreen> createState() => _MarkdownViewerScreenState();
}

class _MarkdownViewerScreenState extends State<MarkdownViewerScreen> {
  String _markdownContent = '';
  bool _isLoading = true;
  bool _failed = false;
  @override
  void initState() {
    super.initState();
    _loadMarkdown();
  }

  Future<void> _loadMarkdown() async {
    setState(() {
      _isLoading = true;
      _failed = false;
    });
    try {
      final content = await rootBundle.loadString(widget.assetPath);
      if (!mounted) return;
      setState(() {
        _markdownContent = content;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _failed = true;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = OpaqueInfoColors(
      context.watch<UserSettingsProvider>().isDarkMode,
    );
    final body = c.text(13, muted: true).copyWith(height: 1.8);
    return CallAwareScreen(
      screenName: 'MarkdownViewerScreen',
      child: Scaffold(
        backgroundColor: c.surface,
        appBar: OpaqueInfoHeader(title: widget.title, colors: c),
        body: SafeArea(
          top: false,
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: _isLoading
                  ? Center(child: CircularProgressIndicator(color: c.accent))
                  : _failed
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(23),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Could not load this document.',
                              style: c.text(14),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 12),
                            TextButton(
                              onPressed: _loadMarkdown,
                              style: TextButton.styleFrom(
                                foregroundColor: c.accent,
                              ),
                              child: const Text('Try again'),
                            ),
                          ],
                        ),
                      ),
                    )
                  : Markdown(
                      data: _markdownContent,
                      selectable: true,
                      padding: const EdgeInsets.fromLTRB(23, 20, 23, 24),
                      styleSheet: MarkdownStyleSheet(
                        h1: c.text(22, bold: true).copyWith(height: 1.35),
                        h2: c.text(18, bold: true).copyWith(height: 1.4),
                        h3: c.text(15, bold: true).copyWith(height: 1.5),
                        h4: c.text(14, bold: true),
                        h5: c.text(13, bold: true),
                        h6: c.text(13, bold: true),
                        p: body,
                        strong: c.text(13, bold: true),
                        listBullet: body,
                        a: c
                            .text(13)
                            .copyWith(
                              color: c.accent,
                              decoration: TextDecoration.underline,
                            ),
                        code: c
                            .text(12)
                            .copyWith(
                              backgroundColor: c.soft,
                              fontFamily: 'monospace',
                            ),
                        codeblockDecoration: BoxDecoration(
                          color: c.soft,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        blockquote: body,
                        blockquoteDecoration: BoxDecoration(
                          color: c.soft,
                          border: Border(
                            left: BorderSide(color: c.accent, width: 3),
                          ),
                        ),
                        horizontalRuleDecoration: BoxDecoration(
                          border: Border(top: BorderSide(color: c.line)),
                        ),
                        tableBody: c
                            .text(12, muted: true)
                            .copyWith(height: 1.6),
                        tableHead: c.text(12, bold: true),
                        tableBorder: TableBorder.all(color: c.line),
                        tableCellsPadding: const EdgeInsets.all(8),
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
