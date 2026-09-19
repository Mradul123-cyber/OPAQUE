import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class HomeLogoutDialog extends StatelessWidget {
  const HomeLogoutDialog({super.key, required this.isDark});
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final surface = isDark ? const Color(0xFF19202A) : Colors.white;
    final ink = isDark ? const Color(0xFFE1E7EF) : const Color(0xFF252832);
    final muted = isDark ? const Color(0xFFA0ADBF) : const Color(0xFF7B808B);
    final soft = isDark ? const Color(0xFF242E3C) : const Color(0xFFF4F5F7);
    final line = isDark ? const Color(0xFF303B4B) : const Color(0xFFE8EAEE);
    return Dialog(
      backgroundColor: surface,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(23),
        side: BorderSide(color: line),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 340),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(23),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 45,
                height: 45,
                decoration: BoxDecoration(
                  color: soft,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(Icons.logout_rounded, size: 22, color: ink),
              ),
              const SizedBox(height: 20),
              Text(
                'Log out of Opaque?',
                style: GoogleFonts.inter(
                  fontSize: 23,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -.7,
                  color: ink,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                "You can sign back in whenever you're ready.",
                style: GoogleFonts.inter(
                  fontSize: 13,
                  height: 1.75,
                  color: muted,
                ),
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(13),
                decoration: BoxDecoration(
                  color: soft,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Icon(
                        Icons.phone_android_outlined,
                        size: 17,
                        color: muted,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Your messages stay here',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              height: 1.7,
                              color: ink,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Logging out keeps your messages on this phone.',
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              height: 1.7,
                              color: muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: ink,
                        minimumSize: const Size(0, 44),
                        side: BorderSide(color: line),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(11),
                        ),
                        textStyle: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => Navigator.of(context).pop(true),
                      style: FilledButton.styleFrom(
                        backgroundColor: ink,
                        foregroundColor: surface,
                        minimumSize: const Size(0, 44),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(11),
                        ),
                        textStyle: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      child: const Text('Log out'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
