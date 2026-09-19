import 'message_bubble_style.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../services/user_settings_provider.dart';

/// Presentation only; the existing settings provider owns persistence.
class OpaqueStylePanel extends StatelessWidget {
  const OpaqueStylePanel({
    super.key,
    required this.settings,
    required this.circularOverlay,
    required this.onOverlayChanged,
  });

  final UserSettingsProvider settings;
  final bool circularOverlay;
  final ValueChanged<bool> onOverlayChanged;

  static const starts = [
    ('Blue', '719CDD'),
    ('Lilac', 'A58BD4'),
    ('Mint', '70B9A4'),
    ('Rose', 'D88FA4'),
    ('Amber', 'D9AD76'),
  ];
  static const ends = [
    ('Blue', '507FC3'),
    ('Violet', '8066B8'),
    ('Teal', '438E83'),
    ('Berry', 'B56588'),
    ('Copper', 'B88853'),
  ];

  Color _hex(String value) => Color(
    int.tryParse('FF${value.replaceAll('#', '')}', radix: 16) ?? 0xFF507FC3,
  );

  @override
  Widget build(BuildContext context) {
    final dark = settings.isDarkMode;
    final ink = dark ? const Color(0xFFE0E6EF) : const Color(0xFF424D60);
    final muted = dark ? const Color(0xFF9CA8BB) : const Color(0xFF929BAD);
    final surface = dark ? const Color(0xFF19202A) : Colors.white;
    final tint = dark ? const Color(0xFF252E3B) : const Color(0xFFF3F5F9);
    final line = dark ? const Color(0xFF303947) : const Color(0xFFEDF0F5);
    final selectedTint = dark
        ? const Color(0xFF2B3B52)
        : const Color(0xFFEDF3FC);
    final blue = dark ? const Color(0xFFABC9F2) : const Color(0xFF6085BA);

    Widget heading(String text) => Padding(
      padding: const EdgeInsets.only(top: 18, bottom: 12),
      child: Text(
        text,
        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: ink),
      ),
    );

    Widget choice(
      String label,
      bool selected,
      VoidCallback onTap, {
      IconData? icon,
    }) => Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        child: Semantics(
          selected: selected,
          child: OutlinedButton(
            onPressed: onTap,
            style: OutlinedButton.styleFrom(
              backgroundColor: selected ? selectedTint : surface,
              foregroundColor: selected ? blue : muted,
              minimumSize: const Size(0, 40),
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 10),
              side: BorderSide(
                color: selected ? blue.withValues(alpha: .3) : line,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 17),
                  const SizedBox(width: 7),
                ],
                Flexible(
                  child: Text(label, style: const TextStyle(fontSize: 11)),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    Widget palette(
      String label,
      List<(String, String)> colors,
      String current,
      bool start,
    ) {
      final matches = colors.where(
        (c) => c.$2.toUpperCase() == current.replaceAll('#', '').toUpperCase(),
      );
      return Column(
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 5),
            child: Row(
              children: [
                Text(label, style: TextStyle(fontSize: 11, color: muted)),
                const Spacer(),
                Text(
                  matches.isEmpty ? 'Custom' : matches.first.$1,
                  style: TextStyle(fontSize: 10, color: muted),
                ),
              ],
            ),
          ),
          Row(
            children: colors.map((entry) {
              final selected =
                  entry.$2.toUpperCase() ==
                  current.replaceAll('#', '').toUpperCase();
              return Expanded(
                child: Semantics(
                  selected: selected,
                  child: IconButton(
                    tooltip: '$label: ${entry.$1}',
                    onPressed: () => settings.saveSettings(
                      colorStart: start ? entry.$2 : null,
                      colorEnd: start ? null : entry.$2,
                    ),
                    icon: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _hex(entry.$2),
                        boxShadow: selected
                            ? [
                                BoxShadow(
                                  color: _hex(entry.$2),
                                  spreadRadius: 5,
                                ),
                                BoxShadow(color: surface, spreadRadius: 4),
                              ]
                            : null,
                      ),
                      child: selected
                          ? const Icon(
                              Icons.check_rounded,
                              size: 16,
                              color: Colors.white,
                            )
                          : null,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      );
    }

    Widget sample(String text, bool mine) => Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(top: 10),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: settings.bubbleStyleKey == 'modern_card'
            ? messageCardDecoration(
                mine,
                false,
                settings.cardBubbleColor,
                MediaQuery.sizeOf(context).width,
              )
            : BoxDecoration(
                color: mine
                    ? null
                    : dark
                    ? const Color(0xFF303B4B)
                    : const Color(0xFFE9EDF4),
                gradient: mine
                    ? LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          _hex(settings.colorStartHex),
                          _hex(settings.colorEndHex),
                        ],
                      )
                    : null,
                borderRadius: messageBubbleRadius(
                  mine,
                  settings.bubbleStyleKey,
                  MediaQuery.sizeOf(context).width,
                  preview: true,
                ),
              ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              text,
              style: TextStyle(
                fontSize: 12,
                color: settings.bubbleStyleKey == 'modern_card'
                    ? Colors.black87
                    : mine
                    ? Colors.white
                    : ink,
              ),
            ),
            if (mine)
              Padding(
                padding: const EdgeInsets.only(top: 5),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '10:42',
                      style: TextStyle(
                        fontSize: 9,
                        color: settings.bubbleStyleKey == 'modern_card'
                            ? Colors.black54
                            : Colors.white70,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      Icons.done_all,
                      size: 12,
                      color: settings.bubbleStyleKey == 'modern_card'
                          ? Colors.black54
                          : Colors.white70,
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );

    Widget overlay(bool circular) => Expanded(
      child: Padding(
        padding: EdgeInsets.only(
          left: circular ? 0 : 5,
          right: circular ? 5 : 0,
        ),
        child: Semantics(
          selected: circularOverlay == circular,
          child: OutlinedButton(
            onPressed: () => onOverlayChanged(circular),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.fromLTRB(7, 7, 7, 10),
              backgroundColor: dark ? const Color(0xFF202731) : Colors.white,
              side: BorderSide(
                color: circularOverlay == circular
                    ? const Color(0xFFB9CEE9)
                    : line,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(15),
              ),
            ),
            child: Column(
              children: [
                Container(
                  height: 59,
                  decoration: BoxDecoration(
                    color: tint,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Center(
                    child: circular
                        ? Container(
                            width: 33,
                            height: 33,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: LinearGradient(
                                colors: [Color(0xFF86BDA9), Color(0xFF5DA38C)],
                              ),
                            ),
                            child: const Icon(
                              Icons.phone_outlined,
                              color: Colors.white,
                              size: 16,
                            ),
                          )
                        : Container(
                            key: const ValueKey('horizontal-overlay-preview'),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFDFEDE7),
                              borderRadius: BorderRadius.circular(9),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                SvgPicture.string(
                                  '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="#65927f" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"><path d="M22 16.92v3a2 2 0 0 1-2.18 2 19.79 19.79 0 0 1-8.63-3.07 19.5 19.5 0 0 1-6-6 19.79 19.79 0 0 1-3.07-8.67A2 2 0 0 1 4.11 2h3a2 2 0 0 1 2 1.72c.12.96.36 1.9.7 2.79a2 2 0 0 1-.45 2.11L8.09 9.89a16 16 0 0 0 6 6l1.27-1.27a2 2 0 0 1 2.11-.45c.9.34 1.83.58 2.79.7A2 2 0 0 1 22 16.92z"/></svg>',
                                  width: 14,
                                  height: 14,
                                ),
                                const SizedBox(width: 9),
                                const Text(
                                  '02:34',
                                  style: TextStyle(
                                    fontSize: 9,
                                    height: 1.45,
                                    fontWeight: FontWeight.w400,
                                    letterSpacing: 0,
                                    color: Color(0xFF65927F),
                                  ),
                                ),
                                const SizedBox(width: 9),
                                SvgPicture.string(
                                  '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="#65927f" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"><rect x="9" y="2" width="6" height="12" rx="3"/><path d="M5 10v2a7 7 0 0 0 14 0v-2M12 19v3"/></svg>',
                                  width: 14,
                                  height: 14,
                                ),
                              ],
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  circular ? 'Circular bubble' : 'Horizontal bar',
                  style: TextStyle(
                    fontSize: 10,
                    color: circularOverlay == circular ? blue : muted,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    return ColoredBox(
      color: surface,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        children: [
          Text(
            'Style',
            style: TextStyle(
              fontSize: 21,
              fontWeight: FontWeight.w500,
              letterSpacing: -.45,
              color: ink,
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: dark
                    ? const [Color(0xFF212B39), Color(0xFF1D2531)]
                    : const [Color(0xFFF3F6FC), Color(0xFFF7F8FB)],
              ),
              border: Border.all(color: line),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'CHAT PREVIEW',
                  style: TextStyle(
                    fontSize: 9,
                    letterSpacing: 1.2,
                    color: muted,
                  ),
                ),
                sample('Coffee after the rain?', false),
                sample('Absolutely. Same place?', true),
              ],
            ),
          ),
          heading('Theme'),
          Row(
            children: [
              choice(
                'Light',
                !dark,
                () => settings.saveSettings(isDarkMode: false),
                icon: Icons.light_mode_outlined,
              ),
              choice(
                'Dark',
                dark,
                () => settings.saveSettings(isDarkMode: true),
                icon: Icons.dark_mode_outlined,
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(top: 18),
            child: Divider(height: 1, color: line),
          ),
          heading('Message bubbles'),
          Row(
            children: [
              choice(
                'Soft',
                settings.bubbleStyleKey == 'default_rounded',
                () => settings.saveSettings(styleKey: 'default_rounded'),
              ),
              choice(
                'Rounded',
                settings.bubbleStyleKey == 'soft_edges',
                () => settings.saveSettings(styleKey: 'soft_edges'),
              ),
              choice(
                'Squared',
                settings.bubbleStyleKey == 'square_corners',
                () => settings.saveSettings(styleKey: 'square_corners'),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(top: 18),
            child: Divider(height: 1, color: line),
          ),
          heading('Bubble colours'),
          palette('Start colour', starts, settings.colorStartHex, true),
          palette('End colour', ends, settings.colorEndHex, false),
          Padding(
            padding: const EdgeInsets.only(top: 18),
            child: Divider(height: 1, color: line),
          ),
          heading('Call overlay'),
          Row(children: [overlay(true), overlay(false)]),
        ],
      ),
    );
  }
}
