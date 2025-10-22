// lib/screens/markdown_viewer_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'dart:ui';
import '../profile_background.dart';
import '../widgets/call_aware_screen.dart';

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

  @override
  void initState() {
    super.initState();
    _loadMarkdown();
  }

  Future<void> _loadMarkdown() async {
    try {
      final content = await rootBundle.loadString(widget.assetPath);
      setState(() {
        _markdownContent = content;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _markdownContent = 'Failed to load content: $e';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    final outerPadding = (screenWidth * 0.05).clamp(16.0, 24.0);
    final containerPadding = (screenWidth * 0.06).clamp(20.0, 28.0);
    final borderRadius1 = (screenWidth * 0.05).clamp(16.0, 24.0);
    final titleSize = (screenWidth * 0.05).clamp(18.0, 22.0);

    return CallAwareScreen(
      screenName: 'MarkdownViewerScreen',
      child: ProfileBackground(
        child: Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            title: Text(widget.title, style: TextStyle(fontSize: titleSize)),
            centerTitle: true,
          ),
          body: Center(
            child: Padding(
              padding: EdgeInsets.only(
                left: outerPadding,
                right: outerPadding,
                top: outerPadding,
                bottom: MediaQuery.of(context).padding.bottom + outerPadding,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(borderRadius1),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 12.0, sigmaY: 12.0),
                  child: Container(
                    padding: EdgeInsets.all(containerPadding),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.25),
                      borderRadius: BorderRadius.circular(borderRadius1),
                      border: Border.all(color: Colors.white.withOpacity(0.2)),
                    ),
                    child: _isLoading
                        ? const Center(
                            child: CircularProgressIndicator(
                              color: Colors.cyanAccent,
                            ),
                          )
                        : Markdown(
                            data: _markdownContent,
                            styleSheet: MarkdownStyleSheet(
                              // Headings
                              h1: TextStyle(
                                fontSize: (screenWidth * 0.06).clamp(22.0, 28.0),
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                              h2: TextStyle(
                                fontSize: (screenWidth * 0.055).clamp(20.0, 26.0),
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                              h3: TextStyle(
                                fontSize: (screenWidth * 0.05).clamp(18.0, 24.0),
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                              h4: TextStyle(
                                fontSize: (screenWidth * 0.045).clamp(16.0, 20.0),
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                              // Body text
                              p: TextStyle(
                                fontSize: (screenWidth * 0.035).clamp(13.0, 16.0),
                                color: Colors.white70,
                                height: 1.6,
                              ),
                              // Lists
                              listBullet: TextStyle(
                                fontSize: (screenWidth * 0.035).clamp(13.0, 16.0),
                                color: Colors.cyanAccent,
                              ),
                              // Links
                              a: const TextStyle(
                                color: Colors.cyanAccent,
                                decoration: TextDecoration.underline,
                              ),
                              // Code
                              code: TextStyle(
                                backgroundColor: Colors.black.withOpacity(0.3),
                                color: Colors.cyanAccent,
                                fontSize: (screenWidth * 0.032).clamp(12.0, 15.0),
                              ),
                              // Blockquote
                              blockquote: TextStyle(
                                fontSize: (screenWidth * 0.035).clamp(13.0, 16.0),
                                color: Colors.white60,
                                fontStyle: FontStyle.italic,
                              ),
                              blockquoteDecoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.05),
                                borderRadius: BorderRadius.circular(8),
                                border: Border(
                                  left: BorderSide(
                                    color: Colors.cyanAccent.withOpacity(0.5),
                                    width: 3,
                                  ),
                                ),
                              ),
                              // Horizontal rule
                              horizontalRuleDecoration: BoxDecoration(
                                border: Border(
                                  top: BorderSide(
                                    color: Colors.white.withOpacity(0.3),
                                    width: 1,
                                  ),
                                ),
                              ),
                              // Table
                              tableBody: TextStyle(
                                fontSize: (screenWidth * 0.032).clamp(12.0, 15.0),
                                color: Colors.white70,
                              ),
                              tableHead: TextStyle(
                                fontSize: (screenWidth * 0.035).clamp(13.0, 16.0),
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
