import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AuthPalette {
  AuthPalette(BuildContext context)
    : dark = Theme.of(context).brightness == Brightness.dark;
  final bool dark;
  Color get background => dark ? const Color(0xFF19202A) : Colors.white;
  Color get ink => dark ? const Color(0xFFE1E7EF) : const Color(0xFF252832);
  Color get muted => dark ? const Color(0xFFA0ACBD) : const Color(0xFF7D8490);
  Color get soft => dark ? const Color(0xFF232D3B) : const Color(0xFFF5F6F8);
  Color get line => dark ? const Color(0xFF323D4C) : const Color(0xFFE7E9EE);
  Color get typingColor => dark ? Colors.white : Colors.black;
}

ThemeData opaqueAuthTheme(bool dark) {
  final ink = dark ? const Color(0xFFE1E7EF) : const Color(0xFF252832);
  final bg = dark ? const Color(0xFF19202A) : Colors.white;
  final soft = dark ? const Color(0xFF232D3B) : const Color(0xFFF5F6F8);
  final line = dark ? const Color(0xFF323D4C) : const Color(0xFFE7E9EE);
  final muted = dark ? const Color(0xFFA0ACBD) : const Color(0xFF7D8490);
  final typingColor = dark ? Colors.white : Colors.black;
  final scheme = ColorScheme.fromSeed(
    seedColor: ink,
    brightness: dark ? Brightness.dark : Brightness.light,
  ).copyWith(primary: ink, onPrimary: bg, surface: bg, onSurface: ink);
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: bg,
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: typingColor,
      selectionColor: typingColor.withOpacity(0.25),
      selectionHandleColor: typingColor,
    ),
    textTheme: GoogleFonts.interTextTheme(
      ThemeData(brightness: scheme.brightness).textTheme,
    ).apply(bodyColor: ink, displayColor: ink),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: soft,
      hintStyle: TextStyle(fontSize: 13, color: muted),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(11),
        borderSide: BorderSide(color: line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(11),
        borderSide: BorderSide(color: line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(11),
        borderSide: BorderSide(color: typingColor, width: 1.5),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(double.infinity, 46),
        backgroundColor: ink,
        foregroundColor: bg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(double.infinity, 46),
        foregroundColor: ink,
        side: BorderSide(color: line),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w500),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: ink,
        textStyle: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w500),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: bg,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(color: line),
      ),
    ),
  );
}

class AuthWordmark extends StatelessWidget {
  const AuthWordmark({super.key});
  @override
  Widget build(BuildContext context) {
    final c = AuthPalette(context);
    return Semantics(
      label: 'Opaque',
      child: ExcludeSemantics(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 22,
              height: 25,
              child: CustomPaint(painter: _Mark(c.ink, c.background)),
            ),
            const SizedBox(width: 4),
            Text(
              'PAQUE',
              style: GoogleFonts.inter(
                fontSize: 19,
                fontWeight: FontWeight.w700,
                letterSpacing: 2.5,
                color: c.ink,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Mark extends CustomPainter {
  _Mark(this.ink, this.bg);
  final Color ink, bg;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawOval(
      Rect.fromLTWH(2.5, 2.5, size.width - 5, size.height - 5),
      Paint()
        ..color = ink
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4.5,
    );
    canvas.drawLine(
      Offset(size.width * .25, size.height),
      Offset(size.width * .75, 0),
      Paint()
        ..color = bg
        ..strokeWidth = 2.5,
    );
  }

  @override
  bool shouldRepaint(_Mark old) => old.ink != ink || old.bg != bg;
}

/// Opaque handoff while existing key/device/session initialization runs.
class AuthStartupView extends StatefulWidget {
  const AuthStartupView({
    super.key,
    this.progress,
    this.error,
    this.onRetry,
    this.onSignOut,
  });
  final double? progress;
  final String? error;
  final VoidCallback? onRetry, onSignOut;
  @override
  State<AuthStartupView> createState() => _AuthStartupViewState();
}

class _AuthStartupViewState extends State<AuthStartupView> {
  String _theme = 'system';
  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((prefs) {
      if (mounted)
        setState(
          () => _theme = prefs.getString('opaque_auth_theme') ?? 'system',
        );
    });
  }

  @override
  Widget build(BuildContext context) {
    final dark =
        _theme == 'dark' ||
        _theme == 'system' &&
            MediaQuery.platformBrightnessOf(context) == Brightness.dark;
    return Theme(
      data: opaqueAuthTheme(dark),
      child: Builder(
        builder: (context) {
          final c = AuthPalette(context);
          return Scaffold(
            backgroundColor: c.background,
            body: SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(32),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 320),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const AuthWordmark(),
                        const SizedBox(height: 40),
                        Text(
                          widget.error == null
                              ? 'Preparing your conversations'
                              : 'Let’s try that again',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.inter(
                            fontSize: 21,
                            fontWeight: FontWeight.w600,
                            color: c.ink,
                          ),
                        ),
                        const SizedBox(height: 14),
                        Text(
                          widget.error ?? 'Setting up your secure connection.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 12,
                            height: 1.8,
                            color: c.muted,
                          ),
                        ),
                        const SizedBox(height: 24),
                        if (widget.error == null)
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: widget.progress,
                              minHeight: 3,
                              color: c.ink,
                              backgroundColor: c.line,
                            ),
                          )
                        else ...[
                          FilledButton(
                            onPressed: widget.onRetry,
                            child: const Text('Try again'),
                          ),
                          TextButton(
                            onPressed: widget.onSignOut,
                            child: const Text('Sign out'),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
