import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class SharingColors {
  SharingColors(BuildContext context) : dark = Theme.of(context).brightness == Brightness.dark;
  final bool dark;
  Color get surface => dark ? const Color(0xFF19202A) : Colors.white;
  Color get ink => dark ? const Color(0xFFE0E6EF) : const Color(0xFF353943);
  Color get muted => dark ? const Color(0xFF9CA8BB) : const Color(0xFF8B929F);
  Color get soft => dark ? const Color(0xFF283241) : const Color(0xFFF3F4F7);
  Color get line => dark ? const Color(0xFF303947) : const Color(0xFFE9EDF2);
  Color get blue => dark ? const Color(0xFF8AAFE4) : const Color(0xFF507FC3);
  TextStyle text(double size, {bool bold = false, bool secondary = false}) => GoogleFonts.inter(fontSize: size, color: secondary ? muted : ink, fontWeight: bold ? FontWeight.w600 : FontWeight.w400);
  InputDecoration field(String hint) => InputDecoration(hintText: hint, hintStyle: text(12, secondary: true), filled: true, fillColor: soft,
    contentPadding: const EdgeInsets.all(12), isDense: true,
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: line)),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: line)),
    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: muted)));
}

class SharingPage extends StatelessWidget {
  const SharingPage({super.key, required this.title, required this.subtitle, required this.child, this.action, this.onAction, this.onBack});
  final String title, subtitle;
  final Widget child;
  final String? action;
  final VoidCallback? onAction, onBack;
  @override
  Widget build(BuildContext context) {
    final c = SharingColors(context);
    return Scaffold(backgroundColor: c.surface,
      appBar: AppBar(backgroundColor: c.surface, foregroundColor: c.ink, elevation: 0, scrolledUnderElevation: 0, surfaceTintColor: Colors.transparent,
        leading: IconButton(tooltip: 'Back', icon: const Icon(Icons.arrow_back, size: 20), onPressed: onBack ?? () => Navigator.pop(context)),
        titleSpacing: 0, title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: c.text(15, bold: true)), const SizedBox(height: 2), Text(subtitle, style: c.text(10, secondary: true))]),
        bottom: PreferredSize(preferredSize: const Size.fromHeight(1), child: Divider(height: 1, color: c.line))),
      body: SafeArea(child: Column(children: [Expanded(child: child), if (action != null) Container(
        padding: const EdgeInsets.fromLTRB(22, 12, 22, 16), decoration: BoxDecoration(border: Border(top: BorderSide(color: c.line))),
        child: SizedBox(width: double.infinity, child: FilledButton(onPressed: onAction,
          style: FilledButton.styleFrom(backgroundColor: c.blue, foregroundColor: c.dark ? c.surface : Colors.white, padding: const EdgeInsets.symmetric(vertical: 13), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13))),
          child: Text(action!, style: GoogleFonts.inter(fontSize: 12))))),
      ])),
    );
  }
}

class LocationCoordinatePanel extends StatelessWidget {
  const LocationCoordinatePanel({super.key, required this.latitude, required this.longitude, this.height = 125});
  final double latitude, longitude, height;
  @override
  Widget build(BuildContext context) {
    final c = SharingColors(context);
    return Container(height: height, width: double.infinity, decoration: BoxDecoration(color: c.soft, border: Border.all(color: c.line), borderRadius: BorderRadius.circular(14)),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Container(width: 34, height: 34, decoration: BoxDecoration(color: c.blue, shape: BoxShape.circle), child: Icon(Icons.location_on_outlined, color: c.surface, size: 20)),
        const SizedBox(height: 10), Text('${latitude.toStringAsFixed(5)}, ${longitude.toStringAsFixed(5)}', style: c.text(11)),
        const SizedBox(height: 3), Text('GPS coordinates', style: c.text(9, secondary: true)),
      ]));
  }
}
