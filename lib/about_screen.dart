// lib/about_screen.dart

import 'package:flutter/material.dart';
import 'dart:ui';
import 'profile_background.dart';
import 'widgets/call_aware_screen.dart';
import 'screens/markdown_viewer_screen.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    final outerPadding = (screenWidth * 0.05).clamp(16.0, 24.0);
    final containerPadding = (screenWidth * 0.06).clamp(20.0, 28.0);
    final borderRadius1 = (screenWidth * 0.05).clamp(16.0, 24.0);
    final titleSize = (screenWidth * 0.08).clamp(28.0, 36.0);
    final versionSize = (screenWidth * 0.04).clamp(14.0, 18.0);
    final sectionTitleSize = (screenWidth * 0.045).clamp(16.0, 20.0);
    final bodyTextSize = (screenWidth * 0.035).clamp(13.0, 16.0);
    final iconSize = (screenWidth * 0.06).clamp(20.0, 28.0);
    final spacing1 = (screenHeight * 0.025).clamp(16.0, 24.0);
    final spacing2 = (screenHeight * 0.02).clamp(12.0, 20.0);
    final spacing3 = (screenHeight * 0.0125).clamp(8.0, 12.0);

    return CallAwareScreen(
      screenName: 'AboutScreen',
      child: ProfileBackground(
        child: Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            title: Text('About', style: TextStyle(fontSize: sectionTitleSize)),
            centerTitle: true,
          ),
          body: Center(
            child: SingleChildScrollView(
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
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // App Logo/Icon
                          Container(
                            padding: EdgeInsets.all(spacing2),
                            decoration: BoxDecoration(
                              color: Colors.cyanAccent.withOpacity(0.15),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Colors.cyanAccent.withOpacity(0.5),
                                width: 2,
                              ),
                            ),
                            child: Icon(
                              Icons.messenger,
                              size: iconSize * 2.5,
                              color: Colors.cyanAccent,
                            ),
                          ),
                          SizedBox(height: spacing2),

                          // App Name
                          Text(
                            'Zarq Messenger',
                            style: TextStyle(
                              fontSize: titleSize,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                              letterSpacing: 1.2,
                            ),
                          ),
                          SizedBox(height: spacing3),

                          // Version
                          Text(
                            'Version 1.0.0',
                            style: TextStyle(
                              fontSize: versionSize,
                              color: Colors.white70,
                            ),
                          ),
                          SizedBox(height: spacing1),

                          const Divider(color: Colors.white30),
                          SizedBox(height: spacing1),

                          // Description
                          _buildSection(
                            icon: Icons.info_outline,
                            title: 'About Zarq',
                            content: 'Zarq Messenger is a secure messaging app that puts your privacy first. Chat with friends, create groups, and share moments with complete peace of mind.',
                            iconSize: iconSize,
                            sectionTitleSize: sectionTitleSize,
                            bodyTextSize: bodyTextSize,
                            spacing2: spacing2,
                            spacing3: spacing3,
                            borderRadius1: borderRadius1,
                          ),
                          SizedBox(height: spacing2),

                          // Security
                          _buildSection(
                            icon: Icons.security,
                            title: 'End-to-End Encryption',
                            content: 'All your messages are protected with the Signal Protocol - the gold standard in secure messaging. Only you and your recipient can read your messages.',
                            iconSize: iconSize,
                            sectionTitleSize: sectionTitleSize,
                            bodyTextSize: bodyTextSize,
                            spacing2: spacing2,
                            spacing3: spacing3,
                            borderRadius1: borderRadius1,
                          ),
                          SizedBox(height: spacing2),

                          // Features
                          _buildSection(
                            icon: Icons.star_outline,
                            title: 'Key Features',
                            content: '• Private messaging with E2EE\n• Group chats (up to 100 members)\n• Voice & video calls\n• Media sharing\n• Message backup & restore\n• Customizable appearance',
                            iconSize: iconSize,
                            sectionTitleSize: sectionTitleSize,
                            bodyTextSize: bodyTextSize,
                            spacing2: spacing2,
                            spacing3: spacing3,
                            borderRadius1: borderRadius1,
                          ),
                          SizedBox(height: spacing2),

                          // Developer
                          _buildSection(
                            icon: Icons.code,
                            title: 'Developer',
                            content: 'Developed with passion for privacy and security.',
                            iconSize: iconSize,
                            sectionTitleSize: sectionTitleSize,
                            bodyTextSize: bodyTextSize,
                            spacing2: spacing2,
                            spacing3: spacing3,
                            borderRadius1: borderRadius1,
                          ),
                          SizedBox(height: spacing1),

                          const Divider(color: Colors.white30),
                          SizedBox(height: spacing1),

                          // Links Section
                          Text(
                            'Legal & Support',
                            style: TextStyle(
                              fontSize: sectionTitleSize,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          SizedBox(height: spacing2),

                          _buildLinkButton(
                            icon: Icons.privacy_tip_outlined,
                            text: 'Privacy Policy',
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => const MarkdownViewerScreen(
                                  title: 'Privacy Policy',
                                  assetPath: 'assets/privacy_policy.md',
                                ),
                              ),
                            ),
                            iconSize: iconSize * 0.8,
                            bodyTextSize: bodyTextSize,
                            spacing3: spacing3,
                            borderRadius1: borderRadius1,
                          ),
                          SizedBox(height: spacing3),

                          _buildLinkButton(
                            icon: Icons.description_outlined,
                            text: 'Terms of Service',
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => const MarkdownViewerScreen(
                                  title: 'Terms of Service',
                                  assetPath: 'assets/terms_of_service.md',
                                ),
                              ),
                            ),
                            iconSize: iconSize * 0.8,
                            bodyTextSize: bodyTextSize,
                            spacing3: spacing3,
                            borderRadius1: borderRadius1,
                          ),
                          SizedBox(height: spacing3),

                          _buildLinkButton(
                            icon: Icons.support_agent,
                            text: 'Contact Support',
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => const MarkdownViewerScreen(
                                  title: 'Contact & Support',
                                  assetPath: 'assets/contact_support.md',
                                ),
                              ),
                            ),
                            iconSize: iconSize * 0.8,
                            bodyTextSize: bodyTextSize,
                            spacing3: spacing3,
                            borderRadius1: borderRadius1,
                          ),
                          SizedBox(height: spacing1),

                          const Divider(color: Colors.white30),
                          SizedBox(height: spacing1),

                          // Copyright
                          Text(
                            '© 2025 Zarq Messenger\nAll rights reserved',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: bodyTextSize * 0.9,
                              color: Colors.white60,
                              height: 1.5,
                            ),
                          ),
                        ],
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

  Widget _buildSection({
    required IconData icon,
    required String title,
    required String content,
    required double iconSize,
    required double sectionTitleSize,
    required double bodyTextSize,
    required double spacing2,
    required double spacing3,
    required double borderRadius1,
  }) {
    return Container(
      padding: EdgeInsets.all(spacing2),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(borderRadius1 * 0.6),
        border: Border.all(color: Colors.cyanAccent.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: Colors.cyanAccent, size: iconSize),
              SizedBox(width: spacing3),
              Text(
                title,
                style: TextStyle(
                  fontSize: sectionTitleSize,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          SizedBox(height: spacing3),
          Text(
            content,
            style: TextStyle(
              fontSize: bodyTextSize,
              color: Colors.white70,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLinkButton({
    required IconData icon,
    required String text,
    required VoidCallback onTap,
    required double iconSize,
    required double bodyTextSize,
    required double spacing3,
    required double borderRadius1,
  }) {
    return Material(
      color: Colors.white.withOpacity(0.08),
      borderRadius: BorderRadius.circular(borderRadius1 * 0.5),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(borderRadius1 * 0.5),
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: spacing3 * 1.5,
            vertical: spacing3,
          ),
          child: Row(
            children: [
              Icon(icon, color: Colors.cyanAccent, size: iconSize),
              SizedBox(width: spacing3),
              Expanded(
                child: Text(
                  text,
                  style: TextStyle(
                    fontSize: bodyTextSize,
                    color: Colors.white,
                  ),
                ),
              ),
              Icon(
                Icons.arrow_forward_ios,
                size: iconSize * 0.7,
                color: Colors.white60,
              ),
            ],
          ),
        ),
      ),
    );
  }

}
