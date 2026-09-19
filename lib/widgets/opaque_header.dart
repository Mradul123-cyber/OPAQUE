import 'package:flutter/material.dart';

class OpaqueHeader extends StatelessWidget implements PreferredSizeWidget {
  const OpaqueHeader({
    super.key,
    required this.isDark,
    required this.profile,
    required this.onProfile,
    required this.menuItems,
    required this.onMenuSelected,
  });
  final bool isDark;
  final Widget profile;
  final VoidCallback onProfile;
  final List<PopupMenuEntry<String>> menuItems;
  final ValueChanged<String> onMenuSelected;

  @override
  Size get preferredSize => const Size.fromHeight(60);

  @override
  Widget build(BuildContext context) {
    final ink = isDark ? const Color(0xFFE0E6EF) : const Color(0xFF202127);
    final surface = isDark ? const Color(0xFF19202A) : Colors.white;
    return Material(
      color: surface,
      child: SafeArea(
        bottom: false,
        child: Container(
          height: 60,
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: isDark
                    ? const Color(0xFF303947)
                    : const Color(0xFFEDEDF0),
              ),
            ),
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Semantics(
                label: 'OPAQUE',
                header: true,
                child: ExcludeSemantics(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 23,
                        height: 25,
                        child: CustomPaint(painter: _OpaqueMark(ink, surface)),
                      ),
                      const SizedBox(width: 3),
                      Text(
                        'PAQUE',
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 19,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 2.5,
                          color: ink,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Positioned(
                left: 12,
                child: IconButton(
                  tooltip: 'Your profile',
                  onPressed: onProfile,
                  icon: SizedBox(
                    width: 36,
                    height: 36,
                    child: Container(
                      foregroundDecoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.black, width: 1.5),
                      ),
                      child: ClipOval(child: profile),
                    ),
                  ),
                ),
              ),
              Positioned(
                right: 12,
                child: PopupMenuButton<String>(
                  tooltip: 'More options',
                  icon: Icon(Icons.more_vert_rounded, size: 22, color: ink),
                  color: surface,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  itemBuilder: (_) => menuItems,
                  onSelected: onMenuSelected,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OpaqueMark extends CustomPainter {
  const _OpaqueMark(this.ink, this.surface);
  final Color ink;
  final Color surface;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawOval(
      Rect.fromLTWH(2.5, 2.5, size.width - 5, size.height - 5),
      Paint()
        ..color = ink
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5,
    );
    canvas.drawLine(
      Offset(size.width * .25, size.height),
      Offset(size.width * .75, 0),
      Paint()
        ..color = surface
        ..strokeWidth = 2.5,
    );
  }

  @override
  bool shouldRepaint(_OpaqueMark old) =>
      old.ink != ink || old.surface != surface;
}
