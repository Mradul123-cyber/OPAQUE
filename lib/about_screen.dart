import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'screens/markdown_viewer_screen.dart';
import 'services/user_settings_provider.dart';
import 'widgets/call_aware_screen.dart';
import 'widgets/opaque_info_design.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final c = OpaqueInfoColors(
      context.watch<UserSettingsProvider>().isDarkMode,
    );
    Widget paragraph(String text) =>
        Text(text, style: c.text(12, muted: true).copyWith(height: 1.75));
    Widget section(String title, Widget child) => Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 20),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: c.line)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: c.text(13, bold: true)),
          const SizedBox(height: 9),
          child,
        ],
      ),
    );
    Widget document(String label, String title, String asset, IconData icon) =>
        Material(
          color: Colors.transparent,
          child: InkWell(
            hoverColor: c.soft,
            focusColor: c.soft,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) =>
                    MarkdownViewerScreen(title: title, assetPath: asset),
              ),
            ),
            child: Container(
              constraints: const BoxConstraints(minHeight: 48),
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: c.line)),
              ),
              child: Row(
                children: [
                  Icon(icon, size: 19, color: c.muted),
                  const SizedBox(width: 11),
                  Expanded(child: Text(label, style: c.text(12))),
                  Icon(Icons.chevron_right, size: 19, color: c.muted),
                ],
              ),
            ),
          ),
        );
    const features = <(IconData, String)>[
      (Icons.chat_bubble_outline, 'Private messages'),
      (Icons.people_outline, 'Group chats'),
      (Icons.call_outlined, 'Voice & video calls'),
      (Icons.image_outlined, 'Media sharing'),
      (Icons.restore, 'Backup & restore'),
      (Icons.palette_outlined, 'Your own style'),
    ];
    return CallAwareScreen(
      screenName: 'AboutScreen',
      child: Scaffold(
        backgroundColor: c.surface,
        appBar: OpaqueInfoHeader(title: 'About', colors: c),
        body: SafeArea(
          top: false,
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(23, 0, 23, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(0, 30, 0, 25),
                        child: Column(
                          children: [
                            // Keep the existing asset until a final logo is chosen.
                            ClipOval(
                              child: Image.asset(
                                'assets/zarq_logo_circle.png',
                                width: 74,
                                height: 74,
                                fit: BoxFit.cover,
                                excludeFromSemantics: true,
                              ),
                            ),
                            const SizedBox(height: 17),
                            Text(
                              'OPAQUE',
                              style: c
                                  .text(26, bold: true)
                                  .copyWith(
                                    letterSpacing: 4,
                                    color: c.dark ? Colors.white : c.ink,
                                  ),
                            ),
                            const SizedBox(height: 9),
                            Text(
                              'A little more private. A lot more you.',
                              textAlign: TextAlign.center,
                              style: c.text(13, muted: true),
                            ),
                            const SizedBox(height: 12),
                            DecoratedBox(
                              decoration: BoxDecoration(
                                color: c.soft,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 5,
                                ),
                                child: Text(
                                  'Version 1.0.0',
                                  style: c.text(10, muted: true),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    section(
                      'Your conversations. Your space.',
                      paragraph(
                        'Stay close to your people with private messages, group conversations, and voice and video calls.',
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.all(15),
                      margin: const EdgeInsets.only(bottom: 22),
                      decoration: BoxDecoration(
                        color: c.soft,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.shield_outlined,
                            size: 19,
                            color: c.accent,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'End-to-end encrypted messaging',
                                  style: c.text(12, bold: true),
                                ),
                                const SizedBox(height: 5),
                                Text(
                                  'Built on the Signal Protocol to help keep your personal conversations private.',
                                  style: c
                                      .text(11, muted: true)
                                      .copyWith(height: 1.65),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    section(
                      'Made for the everyday',
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final singleColumn =
                              MediaQuery.textScalerOf(context).scale(11) > 16;
                          final width = singleColumn
                              ? constraints.maxWidth
                              : (constraints.maxWidth - 10) / 2;
                          return Wrap(
                            spacing: 10,
                            runSpacing: 13,
                            children: [
                              for (final feature in features)
                                SizedBox(
                                  width: width,
                                  child: Row(
                                    children: [
                                      Icon(
                                        feature.$1,
                                        size: 16,
                                        color: c.muted,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          feature.$2,
                                          style: c.text(11, muted: true),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          );
                        },
                      ),
                    ),
                    section(
                      'Built with care',
                      paragraph(
                        'Independently developed with a focus on privacy, thoughtful design, and everyday connection.',
                      ),
                    ),
                    section(
                      'Legal & support',
                      Column(
                        children: [
                          document(
                            'Privacy Policy',
                            'Privacy Policy',
                            'assets/privacy_policy.md',
                            Icons.privacy_tip_outlined,
                          ),
                          document(
                            'Terms of Service',
                            'Terms of Service',
                            'assets/terms_of_service.md',
                            Icons.description_outlined,
                          ),
                          document(
                            'Contact Support',
                            'Contact & Support',
                            'assets/contact_support.md',
                            Icons.support_agent,
                          ),
                        ],
                      ),
                    ),
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Text(
                          'OPAQUE\nA space for your conversations.',
                          textAlign: TextAlign.center,
                          style: c.text(10, muted: true).copyWith(height: 1.8),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
