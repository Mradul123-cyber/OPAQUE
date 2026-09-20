import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/user_settings_provider.dart';
import '../widgets/call_aware_screen.dart';
import '../widgets/global_call_overlay.dart';
import '../widgets/opaque_style_panel.dart';
import '../widgets/backup_design.dart';
import '../widgets/opaque_toast.dart';

class StyleScreen extends StatefulWidget {
  const StyleScreen({super.key, this.embedded = false});
  final bool embedded;

  @override
  State<StyleScreen> createState() => _StyleScreenState();
}

class _StyleScreenState extends State<StyleScreen> {
  bool _isCircularOverlay = true;

  @override
  void initState() {
    super.initState();
    _loadCallOverlayStyle();
  }

  Future<void> _loadCallOverlayStyle() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _isCircularOverlay = prefs.getBool('call_overlay_circular') ?? true;
    });
  }

  Future<void> _saveCallOverlayStyle(bool isCircular) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('call_overlay_circular', isCircular);
    if (!mounted) return;
    setState(() {
      _isCircularOverlay = isCircular;
    });

    // Reload the GlobalCallOverlay style
    GlobalCallOverlay.globalKey.currentState?.reloadStyle();

    if (mounted) {
      OpaqueToast.success(context, 'Call overlay style updated');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<UserSettingsProvider>(
      builder: (context, settings, _) {
        return CallAwareScreen(
          screenName: 'StyleScreen',
          child: Scaffold(
            backgroundColor: settings.isDarkMode
                ? const Color(0xFF19202A)
                : Colors.white,
            appBar: widget.embedded
                ? null
                : const BackupHeader(),
            body: OpaqueStylePanel(
              settings: settings,
              circularOverlay: _isCircularOverlay,
              onOverlayChanged: _saveCallOverlayStyle,
            ),
          ),
        );
      },
    );
  }
}
