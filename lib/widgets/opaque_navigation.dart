import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Outline icons used by the approved OPAQUE reference.
class OpaqueIcon extends StatelessWidget {
  const OpaqueIcon(
    this.name, {
    super.key,
    this.size = 22,
    this.color = const Color(0xFF7B7E89),
    this.strokeWidth = 1.7,
  });
  final String name;
  final double size;
  final Color color;
  final double strokeWidth;
  static const paths = {
    'back': '<path d="m12 19-7-7 7-7M5 12h14"/>',
    'more': '<circle cx="12" cy="5" r="1"/><circle cx="12" cy="12" r="1"/><circle cx="12" cy="19" r="1"/>',
    'attach': '<path d="m21.44 11.05-9.19 9.19a6 6 0 0 1-8.49-8.49l10.6-10.6a4 4 0 0 1 5.66 5.66L9.41 17.41a2 2 0 0 1-2.83-2.83l9.19-9.19"/>',
    'sparkles': '<path d="m12 3 2.7 6.3L21 12l-6.3 2.7L12 21l-2.7-6.3L3 12l6.3-2.7ZM5 3v4M3 5h4M19 17v4M17 19h4"/>',
    'arrow-up': '<path d="M12 19V5m-7 7 7-7 7 7"/>',
    'mic': '<rect x="9" y="2" width="6" height="12" rx="3"/><path d="M5 10v2a7 7 0 0 0 14 0v-2M12 19v3M8 22h8"/>',
    'gallery': '<rect x="3" y="3" width="18" height="18" rx="2"/><circle cx="8.5" cy="8.5" r="1.5"/><path d="m21 15-5-5L5 21"/>',
    'camera': '<path d="M14.5 4h-5L7 7H4a2 2 0 0 0-2 2v11h20V9a2 2 0 0 0-2-2h-3z"/><circle cx="12" cy="13" r="3"/>',
    'document': '<path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8zM14 2v6h6M8 13h8M8 17h6"/>',
    'contact': '<circle cx="12" cy="8" r="4"/><path d="M20 21v-2a6 6 0 0 0-6-6h-4a6 6 0 0 0-6 6v2"/>',
    'location': '<path d="M20 10c0 6-8 12-8 12S4 16 4 10a8 8 0 0 1 16 0Z"/><circle cx="12" cy="10" r="3"/>',
    'poll': '<path d="M3 3v18h18M7 14v3M12 9v8M17 5v12"/>',
    'chats':
        '<path d="M16 10a2 2 0 0 1-2 2H6l-4 4V4a2 2 0 0 1 2-2h10a2 2 0 0 1 2 2z"/><path d="M20 8a2 2 0 0 1 2 2v12l-4-4h-8a2 2 0 0 1-2-2"/>',
    'calls':
        '<path d="M22 16.92v3a2 2 0 0 1-2.18 2 19.79 19.79 0 0 1-8.63-3.07 19.5 19.5 0 0 1-6-6 19.79 19.79 0 0 1-3.07-8.67A2 2 0 0 1 4.11 2h3a2 2 0 0 1 2 1.72c.12.96.36 1.9.7 2.79a2 2 0 0 1-.45 2.11L8.09 9.89a16 16 0 0 0 6 6l1.27-1.27a2 2 0 0 1 2.11-.45c.9.34 1.83.58 2.79.7A2 2 0 0 1 22 16.92z"/>',
    'friends':
        '<path d="M16 2v2M8 2v2M17.915 21a6 6 0 10-12 0"/><circle cx="12" cy="11" r="4"/><rect x="3" y="3" width="18" height="18" rx="2"/>',
    'style':
        '<circle cx="13.5" cy="6.5" r=".5" fill="currentColor"/><circle cx="17.5" cy="10.5" r=".5" fill="currentColor"/><circle cx="8.5" cy="7.5" r=".5" fill="currentColor"/><circle cx="6.5" cy="12.5" r=".5" fill="currentColor"/><path d="M12 22a10 10 0 1 1 10-10 4 4 0 0 1-4 4h-1.8a1.8 1.8 0 0 0-1.3 3c.3.3.5.8.5 1.2A1.8 1.8 0 0 1 13.6 22z"/>',
    'notes':
        '<path d="M13.4 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2v-7.4M2 6h4M2 10h4M2 14h4M2 18h4"/><path d="M21.378 5.626a1 1 0 1 0-3.004-3.004l-5.01 5.012a2 2 0 0 0-.506.854l-.837 2.87a.5.5 0 0 0 .62.62l2.87-.837a2 2 0 0 0 .854-.506z"/>',
    'users':
        '<path d="M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2M22 21v-2a4 4 0 0 0-3-3.87M16 3.13a4 4 0 0 1 0 7.75"/><circle cx="9" cy="7" r="4"/>',
    'received': '<path d="M17 7 7 17M17 17H7V7"/>',
    'sent': '<path d="M7 17 17 7M7 7h10v10"/>',
    'search': '<circle cx="11" cy="11" r="8"/><path d="m21 21-4.3-4.3"/>',
    'add':
        '<path d="M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2M20 8v6M23 11h-6"/><circle cx="9" cy="7" r="4"/>',
    'check': '<path d="m20 6-11 11-5-5"/>',
    'close': '<path d="m18 6-12 12M6 6l12 12"/>',
    'video': '<path d="m16 8 6-4v16l-6-4"/><rect x="2" y="6" width="14" height="12" rx="2"/>',
    'missed': '<path d="m6 2 6 6 6-6M12 8V2M2 17a16 16 0 0 1 20 0v4h-5v-3a10 10 0 0 0-10 0v3H2z"/>',
    'pending': '<circle cx="12" cy="12" r="10"/><path d="M12 6v6h4"/>',
  };
  @override
  Widget build(BuildContext context) => SvgPicture.string(
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="$strokeWidth" stroke-linecap="round" stroke-linejoin="round">${paths[name] ?? paths['friends']}</svg>',
    width: size,
    height: size,
    colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
  );
}

class OpaqueBottomNavigation extends StatelessWidget {
  const OpaqueBottomNavigation({
    super.key,
    required this.index,
    required this.isDark,
    required this.onSelected,
  });
  final int index;
  final bool isDark;
  final ValueChanged<int> onSelected;
  static const destinations = [
    ('Chats', 'chats'),
    ('Calls', 'calls'),
    ('Friends', 'friends'),
    ('Style', 'style'),
    ('Notes', 'notes'),
  ];
  @override
  Widget build(BuildContext context) => Material(
    color: isDark ? const Color(0xFF19202A) : Colors.white,
    child: Container(
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: isDark ? const Color(0xFF303947) : const Color(0xFFEDEDF1),
          ),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            MediaQuery.sizeOf(context).width < 350 ? 9 : 14,
            10,
            MediaQuery.sizeOf(context).width < 350 ? 9 : 14,
            3,
          ),
          child: Row(
            children: [
              for (var i = 0; i < destinations.length; i++)
                Expanded(
                  child: Semantics(
                    selected: index == i,
                    button: true,
                    child: InkWell(
                      onTap: () => onSelected(i),
                      borderRadius: BorderRadius.circular(17),
                      splashFactory: NoSplash.splashFactory,
                      highlightColor: Colors.transparent,
                      hoverColor: Colors.transparent,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 57),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              width: 38,
                              height: 34,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: index == i
                                    ? const Color(0xFF252832)
                                    : null,
                                borderRadius: BorderRadius.circular(13),
                              ),
                              child: OpaqueIcon(
                                destinations[i].$2,
                                strokeWidth: index == i ? 1.9 : 1.7,
                                color: index == i
                                    ? Colors.white
                                    : const Color(0xFF7B7E89),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              destinations[i].$1,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                                letterSpacing: -.1,
                                color: index == i
                                    ? (isDark
                                          ? const Color(0xFFDCE3EF)
                                          : const Color(0xFF232630))
                                    : const Color(0xFF7B7E89),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}

class OpaqueFriendTabs extends StatelessWidget {
  const OpaqueFriendTabs({
    super.key,
    required this.controller,
    required this.isDark,
  });
  final TabController controller;
  final bool isDark;
  static const tabs = [
    ('My Friends', 'users', Color(0xFF5884C8), Color(0xFFEFF4FC)),
    ('Received', 'received', Color(0xFF479F7B), Color(0xFFEEF8F3)),
    ('Sent', 'sent', Color(0xFFD19450), Color(0xFFFCF5EC)),
    ('Find Friends', 'search', Color(0xFF6087BD), Color(0xFFF0F5FC)),
  ];
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) => Container(
      margin: const EdgeInsets.only(top: 10, bottom: 18),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: isDark ? const Color(0xFF303947) : const Color(0xFFE9EDF3),
          ),
        ),
      ),
      child: Row(
        children: [
          for (var i = 0; i < tabs.length; i++)
            Expanded(
              child: Semantics(
                selected: controller.index == i,
                button: true,
                child: InkWell(
                  onTap: () => controller.animateTo(i),
                  child: Container(
                    constraints: const BoxConstraints(minHeight: 65),
                    decoration: BoxDecoration(
                      gradient: controller.index == i
                          ? LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: isDark
                                  ? [
                                      const Color(0xFF19202A),
                                      tabs[i].$3.withValues(alpha: .15),
                                    ]
                                  : [Colors.white, tabs[i].$4],
                            )
                          : null,
                    ),
                    child: Stack(
                      alignment: Alignment.bottomCenter,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(2, 10, 2, 12),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              OpaqueIcon(
                                tabs[i].$2,
                                size: 19,
                                color: tabs[i].$3,
                              ),
                              const SizedBox(height: 6),
                              Text(
                                tabs[i].$1,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w500,
                                  color: controller.index == i
                                      ? tabs[i].$3
                                      : const Color(0xFF8591A3),
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (controller.index == i)
                          Positioned(
                            left: 18,
                            right: 18,
                            bottom: 0,
                            child: Container(height: 2, color: tabs[i].$3),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    ),
  );
}
