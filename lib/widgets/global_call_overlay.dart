// lib/widgets/global_call_overlay.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../services/global_call_manager.dart';
import '../services/webrtc_service.dart';
import '../services/navigation_handler.dart';
import '../main.dart';
import 'dart:math' as math;

// Helper widget for cached avatar
Widget _buildCachedAvatar({
  required String? avatarUrl,
  required String callerName,
  required double radius,
}) {
  final initial = callerName.isNotEmpty ? callerName[0].toUpperCase() : '?';
  final color = Color(callerName.hashCode | 0xFF000000);

  if (avatarUrl != null && avatarUrl.isNotEmpty) {
    return CachedNetworkImage(
      imageUrl: avatarUrl,
      imageBuilder: (context, imageProvider) => CircleAvatar(
        radius: radius,
        backgroundImage: imageProvider,
        backgroundColor: Colors.transparent,
      ),
      placeholder: (context, url) => CircleAvatar(
        radius: radius,
        backgroundColor: color,
        child: SizedBox(
          width: radius * 0.6,
          height: radius * 0.6,
          child: const CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
          ),
        ),
      ),
      errorWidget: (context, url, error) => Container(
        width: radius * 2,
        height: radius * 2,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            colors: [color.withOpacity(0.8), color],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Center(
          child: Text(
            initial,
            style: TextStyle(
              color: Colors.white,
              fontSize: radius * 0.8,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }

  return Container(
    width: radius * 2,
    height: radius * 2,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      gradient: LinearGradient(
        colors: [color.withOpacity(0.8), color],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
    ),
    child: Center(
      child: Text(
        initial,
        style: TextStyle(
          color: Colors.white,
          fontSize: radius * 0.8,
          fontWeight: FontWeight.bold,
        ),
      ),
    ),
  );
}

class GlobalCallOverlay extends StatefulWidget {
  // GlobalKey to access the state from outside
  static final GlobalKey<_GlobalCallOverlayState> globalKey = GlobalKey<_GlobalCallOverlayState>();

  const GlobalCallOverlay({super.key});

  // Static method to minimize the call overlay
  static void minimize() {
    // print('[GlobalCallOverlay] 📞 Static minimize() called');
    globalKey.currentState?._minimize();
  }

  // Static getter to check if minimized
  static bool get isMinimized => globalKey.currentState?._isMinimized ?? false;

  @override
  State<GlobalCallOverlay> createState() => _GlobalCallOverlayState();
}

class _GlobalCallOverlayState extends State<GlobalCallOverlay> with WidgetsBindingObserver {
  String? _lastShownCallerId; // Track which call we've shown
  bool _isMinimized = false; // Track if call UI is minimized
  Offset _position = const Offset(20, 100); // Draggable position
  bool _isCircularStyle = true; // false = horizontal, true = circular
  bool _isCircularExpanded = false; // For circular style: show/hide buttons

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadOverlayStyle();
  }

  Future<void> _loadOverlayStyle() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _isCircularStyle = prefs.getBool('call_overlay_circular') ?? true;
    });
  }

  Future<void> _saveOverlayStyle(bool isCircular) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('call_overlay_circular', isCircular);
    setState(() {
      _isCircularStyle = isCircular;
      _isCircularExpanded = false; // Reset expansion when switching styles
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // print('[GlobalCallOverlay] App lifecycle changed: $state');
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      // App going to background - minimize if in call
      final callManager = Provider.of<GlobalCallManager>(context, listen: false);
      if (callManager.isInCall && !_isMinimized) {
        // print('[GlobalCallOverlay] App going to background - auto-minimizing call');
        setState(() {
          _isMinimized = true;
        });
      }
    }
  }

  // Method to minimize the call
  void _minimize() {
    // print('[GlobalCallOverlay] ⬇️ Minimize called externally');
    setState(() {
      _isMinimized = true;
    });
  }

  // Method to reload overlay style from SharedPreferences
  void reloadStyle() {
    _loadOverlayStyle();
  }

  // Helper methods for responsive sizing
  double _getResponsiveSize(BuildContext context, double baseSize) {
    final screenWidth = MediaQuery.of(context).size.width;
    final scale = (screenWidth / 400).clamp(0.7, 1.3);
    return baseSize * scale;
  }

  double _getResponsiveFontSize(BuildContext context, double baseSize) {
    final screenWidth = MediaQuery.of(context).size.width;
    final scale = (screenWidth / 400).clamp(0.8, 1.2);
    return baseSize * scale;
  }

  double _getButtonSize(BuildContext context, double baseSize) {
    final screenWidth = MediaQuery.of(context).size.width;
    if (screenWidth < 360) return baseSize * 0.75;
    if (screenWidth < 400) return baseSize * 0.85;
    if (screenWidth > 500) return baseSize * 1.1;
    return baseSize;
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<GlobalCallManager>(
      builder: (context, callManager, child) {
        final currentCallerId = callManager.incomingCall?.callerUid;
        // print('[GlobalCallOverlay] 🔍 build - hasIncomingCall: ${callManager.hasIncomingCall}, isInCall: ${callManager.isInCall}, currentCallerId: $currentCallerId, lastShown: $_lastShownCallerId');

        // Show incoming call dialog for NEW calls (different caller or first call)
        // BUT skip if this call is already accepted (auto-answer scenario)
        if (callManager.hasIncomingCall && !callManager.isInCall && currentCallerId != _lastShownCallerId) {
          // print('[GlobalCallOverlay] 📞 Preparing to show incoming call dialog for caller: $currentCallerId');
          _lastShownCallerId = currentCallerId;

          // Delay to allow auto-answer to kick in first
          WidgetsBinding.instance.addPostFrameCallback((_) {
            // Wait a bit to see if auto-answer will accept the call
            Future.delayed(const Duration(milliseconds: 400), () {
              // Only show dialog if call is still incoming (not auto-answered)
              if (mounted && callManager.hasIncomingCall && !callManager.isInCall && callManager.incomingCall?.callerUid == currentCallerId) {
                // print('[GlobalCallOverlay] 📞 Showing incoming call dialog now (call was not auto-answered)');
                _showIncomingCallDialog(context, callManager);
              } else {
                // print('[GlobalCallOverlay] ⚠️ Skipping dialog - call was auto-answered or already in call');
                // print('[GlobalCallOverlay]   - mounted: $mounted, hasIncoming: ${callManager.hasIncomingCall}, isInCall: ${callManager.isInCall}');
              }
            });
          });
        }

        // Reset tracking when no incoming call
        if (!callManager.hasIncomingCall) {
          _lastShownCallerId = null;
        }

        // Reset minimized state when call ends
        if (!callManager.isInCall && _isMinimized) {
          _isMinimized = false;
        }

        // Show active call overlay (full or minimized)
        if (callManager.isInCall) {
          // print('[GlobalCallOverlay] 📱 Showing active call overlay - minimized: $_isMinimized');
          if (_isMinimized) {
            // print('[GlobalCallOverlay] 🔽 Building minimized call indicator');
            return _buildMinimizedCallIndicator(context, callManager);
          } else {
            // print('[GlobalCallOverlay] 🔼 Building full active call overlay');
            return _buildActiveCallOverlay(context, callManager);
          }
        }

        // print('[GlobalCallOverlay] ⬜ No call active, returning empty widget');
        return const SizedBox.shrink();
      },
    );
  }

  void _showIncomingCallDialog(BuildContext context, GlobalCallManager callManager) {
    final call = callManager.incomingCall!;

    // print('[GlobalCallOverlay] 🔍 _showIncomingCallDialog called');
    // print('[GlobalCallOverlay] 🔍 Call info - name: ${call.callerName}, uid: ${call.callerUid}');

    // Get navigator context using the global key
    final navigatorContext = MyApp.navigatorKey.currentContext;
    if (navigatorContext == null) {
      // print('[GlobalCallOverlay] ❌ Navigator context is null!');
      return;
    }

    // print('[GlobalCallOverlay] ✅ Got navigator context');

    // Responsive sizing
    final screenWidth = MediaQuery.of(navigatorContext).size.width;
    final dialogPadding = (screenWidth * 0.06).clamp(20.0, 28.0);
    final borderRadius = (screenWidth * 0.06).clamp(20.0, 28.0);
    final avatarSize = (screenWidth * 0.2).clamp(70.0, 90.0);
    final avatarRadius = avatarSize / 2;
    final avatarTextSize = (screenWidth * 0.09).clamp(30.0, 40.0);
    final nameTextSize = (screenWidth * 0.055).clamp(20.0, 26.0);
    final callTypeTextSize = (screenWidth * 0.035).clamp(13.0, 16.0);
    final iconSize = (screenWidth * 0.04).clamp(14.0, 18.0);
    final spacing1 = (screenWidth * 0.05).clamp(18.0, 24.0);
    final spacing2 = (screenWidth * 0.02).clamp(6.0, 10.0);
    final spacing3 = (screenWidth * 0.08).clamp(28.0, 36.0);
    final badgePaddingH = (screenWidth * 0.04).clamp(14.0, 18.0);
    final badgePaddingV = (screenWidth * 0.015).clamp(5.0, 8.0);
    final badgeRadius = (screenWidth * 0.04).clamp(14.0, 18.0);

    try {
      showDialog(
        context: navigatorContext, // Use navigator context instead
        barrierDismissible: false,
        builder: (dialogContext) {
          // print('[GlobalCallOverlay] 🔍 Dialog builder called');
          return Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          padding: EdgeInsets.all(dialogPadding),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFF1a1a2e),
                Color(0xFF16213e),
              ],
            ),
            borderRadius: BorderRadius.circular(borderRadius),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.5),
                blurRadius: 30,
                spreadRadius: 5,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Avatar
              Container(
                width: avatarSize,
                height: avatarSize,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: call.avatarUrl != null
                        ? Colors.black.withOpacity(0.3)
                        : Color(call.callerName.hashCode | 0xFF000000).withOpacity(0.5),
                      blurRadius: 20,
                      spreadRadius: 3,
                    ),
                  ],
                ),
                child: call.avatarUrl != null && call.avatarUrl!.isNotEmpty
                  ? CircleAvatar(
                      radius: avatarRadius,
                      backgroundImage: NetworkImage(call.avatarUrl!),
                      backgroundColor: Colors.transparent,
                      onBackgroundImageError: (_, __) {},
                      child: Container(),
                    )
                  : Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          colors: [
                            Color(call.callerName.hashCode | 0xFF000000),
                            Color((call.callerName.hashCode * 2) | 0xFF000000),
                          ],
                        ),
                      ),
                      child: Center(
                        child: Text(
                          call.callerName.isNotEmpty ? call.callerName[0].toUpperCase() : '?',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: avatarTextSize,
                            fontWeight: FontWeight.bold,
                            decoration: TextDecoration.none,
                          ),
                        ),
                      ),
                    ),
              ),
              SizedBox(height: spacing1),
              // Name
              Text(
                call.callerName,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: nameTextSize,
                  fontWeight: FontWeight.w600,
                  decoration: TextDecoration.none,
                ),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: spacing2),
              // Call type
              Container(
                padding: EdgeInsets.symmetric(horizontal: badgePaddingH, vertical: badgePaddingV),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(badgeRadius),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      call.callType == CallType.video ? Icons.videocam : Icons.call,
                      color: Colors.white70,
                      size: iconSize,
                    ),
                    SizedBox(width: spacing2),
                    Text(
                      'Incoming ${call.callType.name} call',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: callTypeTextSize,
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: spacing3),
              // Action buttons
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  // Reject button
                  _buildDialogButton(
                    context: navigatorContext,
                    icon: Icons.call_end_rounded,
                    label: 'Decline',
                    gradient: const LinearGradient(
                      colors: [Color(0xFFFF416C), Color(0xFFFF4B2B)],
                    ),
                    onTap: () async {
                      Navigator.of(navigatorContext).pop();
                      await callManager.rejectIncomingCall();
                    },
                  ),
                  // Accept button
                  _buildDialogButton(
                    context: navigatorContext,
                    icon: Icons.call_rounded,
                    label: 'Accept',
                    gradient: const LinearGradient(
                      colors: [Color(0xFF56ab2f), Color(0xFF4cb848)],
                    ),
                    onTap: () async {
                      Navigator.of(navigatorContext).pop();
                      await _acceptCall(navigatorContext, callManager, call.callType);
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      );
        },
      ).then((value) {
        // print('[GlobalCallOverlay] ✅ Dialog closed with result: $value');
      }).catchError((error) {
        // print('[GlobalCallOverlay] ❌ Dialog error: $error');
      });
      // print('[GlobalCallOverlay] ✅ showDialog called successfully');
    } catch (e, stackTrace) {
      // print('[GlobalCallOverlay] ❌ ERROR showing dialog: $e');
      // print('[GlobalCallOverlay] ❌ Stack trace: $stackTrace');
    }
  }

  Widget _buildDialogButton({
    required BuildContext context,
    required IconData icon,
    required String label,
    required Gradient gradient,
    required VoidCallback onTap,
  }) {
    final screenWidth = MediaQuery.of(context).size.width;
    final buttonSize = (screenWidth * 0.16).clamp(56.0, 70.0);
    final iconSize = (screenWidth * 0.075).clamp(26.0, 34.0);
    final labelSize = (screenWidth * 0.0325).clamp(12.0, 15.0);
    final spacing = (screenWidth * 0.02).clamp(6.0, 10.0);

    return Column(
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            customBorder: const CircleBorder(),
            child: Container(
              width: buttonSize,
              height: buttonSize,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: gradient,
                boxShadow: [
                  BoxShadow(
                    color: (gradient.colors.first).withOpacity(0.4),
                    blurRadius: 15,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: Icon(icon, color: Colors.white, size: iconSize),
            ),
          ),
        ),
        SizedBox(height: spacing),
        Text(
          label,
          style: TextStyle(
            color: Colors.white70,
            fontSize: labelSize,
            decoration: TextDecoration.none,
          ),
        ),
      ],
    );
  }

  Future<void> _acceptCall(BuildContext context, GlobalCallManager callManager, CallType callType) async {
    // Request permissions
    if (callType == CallType.video) {
      final permissions = await [Permission.camera, Permission.microphone].request();
      if (!permissions[Permission.camera]!.isGranted || !permissions[Permission.microphone]!.isGranted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Camera and microphone permissions required')),
        );
        await callManager.rejectIncomingCall();
        return;
      }
    } else {
      final micStatus = await Permission.microphone.request();
      if (!micStatus.isGranted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Microphone permission required')),
        );
        await callManager.rejectIncomingCall();
        return;
      }
    }

    await callManager.acceptIncomingCall();
  }

  Widget _buildActiveCallOverlay(BuildContext context, GlobalCallManager callManager) {
    final call = callManager.activeCall!;
    final webrtc = callManager.webrtcService;

    return Material(
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF1a1a2e),
              Color(0xFF16213e),
              Color(0xFF0f3460),
            ],
          ),
        ),
        child: SafeArea(
          child: Stack(
            children: [
              // Background particles effect for voice calls
              if (call.callType == CallType.voice) _buildParticlesBackground(),

              Column(
                children: [
                  // Modern header
                  _buildModernHeader(call, webrtc?.callState ?? CallState.idle),
                  // Video or voice content
                  Expanded(
                    child: call.callType == CallType.video
                        ? _buildVideoContent(callManager, webrtc?.callState ?? CallState.idle)
                        : _buildVoiceContent(callManager, call, webrtc?.callState ?? CallState.idle),
                  ),
                  // Modern call controls
                  _buildModernControls(callManager, call.callType),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildParticlesBackground() {
    return Positioned.fill(
      child: CustomPaint(
        painter: _ParticlesPainter(),
      ),
    );
  }

  Widget _buildModernHeader(CallInfo call, CallState callState) {
    final callManager = Provider.of<GlobalCallManager>(context, listen: true);
    final duration = callManager.callDuration;
    final screenWidth = MediaQuery.of(context).size.width;

    final paddingH = (screenWidth * 0.05).clamp(16.0, 24.0);
    final paddingV = (screenWidth * 0.04).clamp(14.0, 20.0);
    final avatarRadius = (screenWidth * 0.05).clamp(18.0, 24.0);
    final avatarSize = avatarRadius * 2;
    final avatarTextSize = (screenWidth * 0.045).clamp(16.0, 20.0);
    final nameTextSize = (screenWidth * 0.045).clamp(16.0, 20.0);
    final statusTextSize = (screenWidth * 0.035).clamp(13.0, 16.0);
    final iconSize = (screenWidth * 0.05).clamp(18.0, 24.0);
    final indicatorSize = (screenWidth * 0.02).clamp(7.0, 10.0);
    final spacing1 = (screenWidth * 0.03).clamp(10.0, 14.0);
    final spacing2 = (screenWidth * 0.02).clamp(6.0, 10.0);
    final spacing3 = (screenWidth * 0.005).clamp(1.5, 3.0);
    final badgePadding = (screenWidth * 0.02).clamp(7.0, 10.0);
    final badgeRadius = (screenWidth * 0.02).clamp(7.0, 10.0);

    return Container(
      padding: EdgeInsets.symmetric(horizontal: paddingH, vertical: paddingV),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.black.withOpacity(0.3),
            Colors.transparent,
          ],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: Row(
        children: [
          // Avatar (small)
          call.avatarUrl != null && call.avatarUrl!.isNotEmpty
            ? CircleAvatar(
                radius: avatarRadius,
                backgroundImage: NetworkImage(call.avatarUrl!),
                backgroundColor: Colors.transparent,
                onBackgroundImageError: (_, __) {},
              )
            : Container(
                width: avatarSize,
                height: avatarSize,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [
                      Color(call.callerName.hashCode | 0xFF000000),
                      Color((call.callerName.hashCode * 2) | 0xFF000000),
                    ],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Center(
                  child: Text(
                    call.callerName.isNotEmpty ? call.callerName[0].toUpperCase() : '?',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: avatarTextSize,
                      fontWeight: FontWeight.bold,
                      decoration: TextDecoration.none,
                    ),
                  ),
                ),
              ),
          SizedBox(width: spacing1),
          // Name and status
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  call.callerName,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: nameTextSize,
                    fontWeight: FontWeight.w600,
                    decoration: TextDecoration.none,
                    shadows: const [
                      Shadow(
                        color: Colors.black45,
                        blurRadius: 4,
                      ),
                    ],
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                SizedBox(height: spacing3),
                Row(
                  children: [
                    Container(
                      width: indicatorSize,
                      height: indicatorSize,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: callState == CallState.connected
                            ? Colors.greenAccent
                            : Colors.orangeAccent,
                        boxShadow: [
                          BoxShadow(
                            color: (callState == CallState.connected
                                    ? Colors.greenAccent
                                    : Colors.orangeAccent)
                                .withOpacity(0.5),
                            blurRadius: 8,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                    ),
                    SizedBox(width: spacing2),
                    Text(
                      callState == CallState.connected && duration.inSeconds > 0
                          ? _formatCallDuration(duration)
                          : _callStateText(callState),
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: statusTextSize,
                        decoration: TextDecoration.none,
                        shadows: const [
                          Shadow(
                            color: Colors.black45,
                            blurRadius: 4,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Call type icon
          Container(
            padding: EdgeInsets.all(badgePadding),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.1),
              borderRadius: BorderRadius.circular(badgeRadius),
            ),
            child: Icon(
              call.callType == CallType.video ? Icons.videocam : Icons.call,
              color: Colors.white,
              size: iconSize,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVideoContent(GlobalCallManager callManager, CallState callState) {
    return Builder(
      builder: (context) {
        final pipWidth = _getResponsiveSize(context, 100);
        final pipHeight = _getResponsiveSize(context, 140);
        final pipBorderRadius = _getResponsiveSize(context, 16);

        return Stack(
          children: [
            // Remote video (full screen)
            if (callManager.remoteRenderer.srcObject != null)
              Positioned.fill(
                child: RTCVideoView(callManager.remoteRenderer, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover),
              )
            else
              _buildWaitingForVideo(callManager.activeCall!, callState),
            // Local video (floating PIP)
            if (callManager.localRenderer.srcObject != null)
              Positioned(
                top: 20,
                right: 20,
                child: GestureDetector(
                  onTap: () => callManager.switchCamera(),
                  child: Container(
                    width: pipWidth,
                    height: pipHeight,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(pipBorderRadius),
                      border: Border.all(color: Colors.white.withOpacity(0.3), width: 2),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.5),
                          blurRadius: 20,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(pipBorderRadius - 2),
                      child: RTCVideoView(callManager.localRenderer, mirror: true, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildWaitingForVideo(CallInfo call, CallState callState) {
    return Builder(
      builder: (context) {
        final avatarSize = _getResponsiveSize(context, 120);
        final avatarRadius = avatarSize / 2;

        return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(call.callerName.hashCode | 0xFF000000).withOpacity(0.3),
            Color((call.callerName.hashCode * 2) | 0xFF000000).withOpacity(0.3),
          ],
        ),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            call.avatarUrl != null && call.avatarUrl!.isNotEmpty
              ? CircleAvatar(
                  radius: avatarRadius,
                  backgroundImage: NetworkImage(call.avatarUrl!),
                  backgroundColor: Colors.transparent,
                  onBackgroundImageError: (_, __) {},
                )
              : Container(
                  width: avatarSize,
                  height: avatarSize,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [
                        Color(call.callerName.hashCode | 0xFF000000),
                        Color((call.callerName.hashCode * 2) | 0xFF000000),
                      ],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.4),
                        blurRadius: 30,
                        spreadRadius: 5,
                      ),
                    ],
                  ),
                  child: Center(
                    child: Text(
                      call.callerName.isNotEmpty ? call.callerName[0].toUpperCase() : '?',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: _getResponsiveFontSize(context, 50),
                        fontWeight: FontWeight.bold,
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ),
                ),
            SizedBox(height: _getResponsiveSize(context, 24)),
            if (callState != CallState.connected)
              const CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white54),
                strokeWidth: 2,
              ),
            if (callState != CallState.connected)
              SizedBox(height: _getResponsiveSize(context, 16)),
            Text(
              _callStateText(callState),
              style: TextStyle(
                color: callState == CallState.connected ? Colors.greenAccent : Colors.white70,
                fontSize: _getResponsiveFontSize(context, 16),
                fontWeight: FontWeight.w500,
                decoration: TextDecoration.none,
              ),
            ),
          ],
        ),
      ),
    );
      },
    );
  }

  Widget _buildVoiceContent(GlobalCallManager callManager, CallInfo call, CallState callState) {
    // Check if remote stream has video (screen sharing during voice call)
    final hasRemoteStream = callManager.remoteRenderer.srcObject != null;
    final hasRemoteVideo = hasRemoteStream &&
        callManager.remoteRenderer.srcObject!.getVideoTracks().isNotEmpty;

    // print('[GlobalCallOverlay] Voice call - hasRemoteStream: $hasRemoteStream, hasRemoteVideo: $hasRemoteVideo');
    if (hasRemoteStream) {
      // print('[GlobalCallOverlay] Remote video tracks: ${callManager.remoteRenderer.srcObject!.getVideoTracks().length}');
    }

    // If remote is sharing screen, show it
    if (hasRemoteVideo) {
      // print('[GlobalCallOverlay] 📺 Showing remote screen share in voice call');
      return Builder(
        builder: (context) {
          final screenWidth = MediaQuery.of(context).size.width;
          final badgePaddingH = (screenWidth * 0.03).clamp(10.0, 14.0);
          final badgePaddingV = (screenWidth * 0.02).clamp(7.0, 10.0);
          final badgeRadius = (screenWidth * 0.05).clamp(18.0, 24.0);
          final iconSize = (screenWidth * 0.04).clamp(14.0, 18.0);
          final textSize = (screenWidth * 0.03).clamp(11.0, 14.0);
          final spacing = (screenWidth * 0.015).clamp(5.0, 8.0);
          final position = (screenWidth * 0.05).clamp(18.0, 24.0);

          return Stack(
            children: [
              // Remote screen share (full screen)
              Positioned.fill(
                child: RTCVideoView(
                  callManager.remoteRenderer,
                  objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitContain,
                ),
              ),
              // Small avatar indicator in corner
              Positioned(
                top: position,
                left: position,
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: badgePaddingH, vertical: badgePaddingV),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.7),
                    borderRadius: BorderRadius.circular(badgeRadius),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.screen_share, color: Colors.greenAccent, size: iconSize),
                      SizedBox(width: spacing),
                      Text(
                        'Screen sharing',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: textSize,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      );
    }

    // Normal voice call - show avatar
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Animated avatar with pulse effect
          TweenAnimationBuilder(
            tween: Tween<double>(begin: 0, end: 1),
            duration: const Duration(seconds: 2),
            builder: (context, double value, child) {
              return call.avatarUrl != null && call.avatarUrl!.isNotEmpty
                ? Container(
                    width: 180 + (math.sin(value * math.pi * 2) * 10),
                    height: 180 + (math.sin(value * math.pi * 2) * 10),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Color(call.callerName.hashCode | 0xFF000000).withOpacity(0.4),
                          blurRadius: 40,
                          spreadRadius: 10,
                        ),
                      ],
                    ),
                    child: CircleAvatar(
                      radius: 90,
                      backgroundImage: NetworkImage(call.avatarUrl!),
                      backgroundColor: Colors.transparent,
                      onBackgroundImageError: (_, __) {},
                    ),
                  )
                : Container(
                    width: 180 + (math.sin(value * math.pi * 2) * 10),
                    height: 180 + (math.sin(value * math.pi * 2) * 10),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Color(call.callerName.hashCode | 0xFF000000),
                          Color((call.callerName.hashCode * 2) | 0xFF000000),
                        ],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Color(call.callerName.hashCode | 0xFF000000).withOpacity(0.4),
                          blurRadius: 40,
                          spreadRadius: 10,
                        ),
                      ],
                    ),
                    child: Center(
                      child: Text(
                        call.callerName.isNotEmpty ? call.callerName[0].toUpperCase() : '?',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: _getResponsiveFontSize(context, 70),
                          fontWeight: FontWeight.bold,
                          decoration: TextDecoration.none,
                        ),
                      ),
                    ),
                  );
            },
            onEnd: () {
              // This triggers rebuild to restart animation
              if (mounted) {
                // Force rebuild by using setState in parent
              }
            },
          ),
          SizedBox(height: _getResponsiveSize(context, 40)),
          Text(
            call.callerName,
            style: TextStyle(
              color: Colors.white,
              fontSize: _getResponsiveFontSize(context, 28),
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
              decoration: TextDecoration.none,
            ),
          ),
          SizedBox(height: _getResponsiveSize(context, 12)),
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: _getResponsiveSize(context, 16),
              vertical: _getResponsiveSize(context, 8),
            ),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.1),
              borderRadius: BorderRadius.circular(_getResponsiveSize(context, 20)),
            ),
            child: Text(
              _callStateText(callState),
              style: TextStyle(
                color: Colors.white70,
                fontSize: _getResponsiveFontSize(context, 16),
                fontWeight: FontWeight.w500,
                decoration: TextDecoration.none,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModernControls(GlobalCallManager callManager, CallType callType) {
    return Builder(
      builder: (context) {
        final horizontalPadding = _getResponsiveSize(context, 24);
        final verticalPadding = _getResponsiveSize(context, 32);
        final screenWidth = MediaQuery.of(context).size.width;
        final buttonSpacing = screenWidth < 360 ? 8.0 : _getResponsiveSize(context, 12);

        return Container(
          padding: EdgeInsets.symmetric(
            horizontal: horizontalPadding,
            vertical: verticalPadding,
          ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.transparent,
            Colors.black.withOpacity(0.4),
          ],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
        mainAxisAlignment: callType == CallType.video
            ? MainAxisAlignment.center
            : MainAxisAlignment.center,
        children: [
          // Mute button
          _buildModernControlButton(
            icon: callManager.isMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
            label: callManager.isMuted ? 'Unmute' : 'Mute',
            onPressed: () async {
              // print('[GlobalCallOverlay] 🎤 Mute button tapped');
              await callManager.toggleMicrophone();
            },
            isActive: callManager.isMuted,
            activeColor: Colors.white,
            inactiveColor: Colors.white.withOpacity(0.2),
          ),

          SizedBox(width: buttonSpacing),
          // Speaker button
          _buildModernControlButton(
            icon: callManager.isSpeakerOn ? Icons.volume_up_rounded : Icons.volume_down_rounded,
            label: 'Speaker',
            onPressed: () async {
              await callManager.toggleSpeaker();
            },
            isActive: callManager.isSpeakerOn,
            activeColor: Colors.white,
            inactiveColor: Colors.white.withOpacity(0.2),
          ),

          if (callType == CallType.video) ...[
            SizedBox(width: buttonSpacing),
            // Camera toggle
            _buildModernControlButton(
              icon: callManager.isCameraOff ? Icons.videocam_off_rounded : Icons.videocam_rounded,
              label: 'Camera',
              onPressed: () async {
                // print('[GlobalCallOverlay] 📹 Camera button tapped');
                await callManager.toggleCamera();
              },
              isActive: callManager.isCameraOff,
              activeColor: Colors.white,
              inactiveColor: Colors.white.withOpacity(0.2),
            ),
          ],

          SizedBox(width: buttonSpacing),
          // End call button (larger)
          _buildModernEndCallButton(callManager),

          if (callType == CallType.video) ...[
            SizedBox(width: buttonSpacing),
            // Switch camera (only in video calls)
            _buildModernControlButton(
              icon: Icons.flip_camera_android_rounded,
              label: 'Flip',
              onPressed: () async {
                // print('[GlobalCallOverlay] 🔄 Switch camera button tapped');
                await callManager.switchCamera();
              },
              isActive: false,
              activeColor: Colors.white,
              inactiveColor: Colors.white.withOpacity(0.2),
            ),
          ],
        ],
      ),
        ),
    );
      },
    );
  }

  Widget _buildModernControlButton({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
    required bool isActive,
    required Color activeColor,
    required Color inactiveColor,
    bool isDisabled = false,
  }) {
    return Builder(
      builder: (context) {
        final buttonSize = _getButtonSize(context, 60);
        final iconSize = _getButtonSize(context, 28);
        final fontSize = _getResponsiveFontSize(context, 12);

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: isDisabled ? null : onPressed,
                customBorder: const CircleBorder(),
                child: Container(
                  width: buttonSize,
                  height: buttonSize,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isDisabled
                    ? Colors.white.withOpacity(0.1)
                    : (isActive ? activeColor : inactiveColor),
                boxShadow: isActive && !isDisabled
                    ? [
                        BoxShadow(
                          color: activeColor.withOpacity(0.3),
                          blurRadius: 20,
                          spreadRadius: 2,
                        ),
                      ]
                    : [],
              ),
              child: Icon(
                icon,
                color: isDisabled
                    ? Colors.white.withOpacity(0.3)
                    : (isActive ? const Color(0xFF1a1a2e) : Colors.white),
                size: iconSize,
              ),
            ),
          ),
        ),
        SizedBox(height: _getResponsiveSize(context, 8)),
        Text(
          label,
          style: TextStyle(
            color: isDisabled
                ? Colors.white.withOpacity(0.3)
                : Colors.white.withOpacity(0.8),
            fontSize: fontSize,
            fontWeight: FontWeight.w500,
            decoration: TextDecoration.none,
          ),
        ),
      ],
    );
      },
    );
  }

  Widget _buildModernEndCallButton(GlobalCallManager callManager) {
    return Builder(
      builder: (context) {
        final buttonSize = _getButtonSize(context, 70);
        final iconSize = _getButtonSize(context, 32);
        final fontSize = _getResponsiveFontSize(context, 12);

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () async {
                  // print('[GlobalCallOverlay] ☎️ End call button tapped');
                  // print('[GlobalCallOverlay] Before endCall - isInCall: ${callManager.isInCall}');
                  await callManager.endCall();
                  // print('[GlobalCallOverlay] After endCall - isInCall: ${callManager.isInCall}');
                },
                customBorder: const CircleBorder(),
                child: Container(
                  width: buttonSize,
                  height: buttonSize,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  colors: [Color(0xFFFF416C), Color(0xFFFF4B2B)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFFF416C).withOpacity(0.5),
                    blurRadius: 20,
                    spreadRadius: 2,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Icon(
                Icons.call_end_rounded,
                color: Colors.white,
                size: iconSize,
              ),
            ),
          ),
        ),
        SizedBox(height: _getResponsiveSize(context, 8)),
        Text(
          'End',
          style: TextStyle(
            color: Colors.white.withOpacity(0.8),
            fontSize: fontSize,
            fontWeight: FontWeight.w500,
            decoration: TextDecoration.none,
          ),
        ),
      ],
    );
      },
    );
  }

  Widget _buildMinimizedCallIndicator(BuildContext context, GlobalCallManager callManager) {
    final call = callManager.activeCall;
    if (call == null) return const SizedBox.shrink();

    final webrtc = callManager.webrtcService;
    final callState = webrtc?.callState ?? CallState.idle;
    final duration = callManager.callDuration;
    final screenSize = MediaQuery.of(context).size;

    // print('[GlobalCallOverlay] Building minimized - isCircularStyle: $_isCircularStyle');

    // Switch between styles
    return _isCircularStyle
        ? _buildCircularOverlay(context, callManager, call, callState, duration, screenSize)
        : _buildHorizontalOverlay(context, callManager, call, callState, duration, screenSize);
  }

  Widget _buildHorizontalOverlay(
    BuildContext context,
    GlobalCallManager callManager,
    CallInfo call,
    CallState callState,
    Duration duration,
    Size screenSize,
  ) {
    final screenWidth = MediaQuery.of(context).size.width;
    final containerWidth = (screenWidth * 0.7).clamp(250.0, 300.0);
    final containerHeight = (screenWidth * 0.175).clamp(62.0, 76.0);
    final paddingH = (screenWidth * 0.03).clamp(10.0, 14.0);
    final paddingV = (screenWidth * 0.025).clamp(8.0, 12.0);
    final borderRadius = (screenWidth * 0.04).clamp(14.0, 18.0);
    final avatarRadius = (screenWidth * 0.05).clamp(18.0, 24.0);
    final avatarTextSize = (screenWidth * 0.035).clamp(13.0, 16.0);
    final nameTextSize = (screenWidth * 0.0325).clamp(12.0, 15.0);
    final statusTextSize = (screenWidth * 0.0275).clamp(10.0, 13.0);
    final spacing1 = (screenWidth * 0.03).clamp(10.0, 14.0);
    final spacing2 = (screenWidth * 0.02).clamp(6.0, 10.0);
    final spacing3 = (screenWidth * 0.005).clamp(1.5, 3.0);

    return Positioned(
      left: _position.dx,
      top: _position.dy,
      child: GestureDetector(
        onPanUpdate: (details) {
          setState(() {
            _position = Offset(
              (_position.dx + details.delta.dx).clamp(0.0, screenSize.width - containerWidth),
              (_position.dy + details.delta.dy).clamp(0.0, screenSize.height - containerHeight),
            );
          });
        },
        onTap: () {
          // Expand when tapping anywhere on the overlay
          setState(() {
            _isMinimized = false;
          });
        },
        child: Material(
          color: Colors.transparent,
          child: Container(
            width: containerWidth,
            padding: EdgeInsets.symmetric(horizontal: paddingH, vertical: paddingV),
            decoration: BoxDecoration(
              color: const Color(0xFF1a1a2e),
              borderRadius: BorderRadius.circular(borderRadius),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.4),
                  blurRadius: 12,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Row(
              children: [
                // Avatar
                CircleAvatar(
                  radius: avatarRadius,
                  backgroundImage: call.avatarUrl != null && call.avatarUrl!.isNotEmpty
                    ? NetworkImage(call.avatarUrl!)
                    : null,
                  backgroundColor: call.avatarUrl == null
                    ? Color(call.callerName.hashCode | 0xFF000000)
                    : Colors.transparent,
                  child: call.avatarUrl == null
                    ? Text(
                        call.callerName.isNotEmpty ? call.callerName[0].toUpperCase() : '?',
                        style: TextStyle(color: Colors.white, fontSize: avatarTextSize, fontWeight: FontWeight.bold, decoration: TextDecoration.none),
                      )
                    : null,
                ),
                SizedBox(width: spacing1),
                // Name and duration - Tappable to expand
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        call.callerName,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: nameTextSize,
                          fontWeight: FontWeight.w600,
                          decoration: TextDecoration.none,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      SizedBox(height: spacing3),
                      Text(
                        callState == CallState.connected
                          ? _formatCallDuration(duration)
                          : 'Connecting...',
                        style: TextStyle(
                          color: Colors.white60,
                          fontSize: statusTextSize,
                          decoration: TextDecoration.none,
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(width: spacing2),
                // Control buttons - prevent tap propagation
                GestureDetector(
                  onTap: () {}, // Absorb taps on buttons area
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Mute button
                      _buildMiniButton(
                        context: context,
                        icon: callManager.isMuted ? Icons.mic_off : Icons.mic,
                        color: callManager.isMuted ? Colors.red : Colors.white,
                        onTap: () => callManager.toggleMicrophone(),
                      ),
                      SizedBox(width: spacing2),
                      // Speaker button
                      _buildMiniButton(
                        context: context,
                        icon: callManager.isSpeakerOn ? Icons.volume_up : Icons.volume_down,
                        color: callManager.isSpeakerOn ? Colors.greenAccent : Colors.white,
                        onTap: () => callManager.toggleSpeaker(),
                      ),
                      SizedBox(width: spacing2),
                      // End call button
                      _buildMiniButton(
                        context: context,
                        icon: Icons.call_end,
                        color: Colors.red,
                        onTap: () => callManager.endCall(),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCircularOverlay(
    BuildContext context,
    GlobalCallManager callManager,
    CallInfo call,
    CallState callState,
    Duration duration,
    Size screenSize,
  ) {
    final screenWidth = MediaQuery.of(context).size.width;
    final collapsedSize = (screenWidth * 0.175).clamp(62.0, 76.0);
    final expandedSize = (screenWidth * 0.5).clamp(180.0, 220.0);
    final size = _isCircularExpanded ? expandedSize : collapsedSize;

    return Positioned(
      left: _position.dx,
      top: _position.dy,
      child: GestureDetector(
        onPanUpdate: (details) {
          setState(() {
            _position = Offset(
              (_position.dx + details.delta.dx).clamp(0.0, screenSize.width - size),
              (_position.dy + details.delta.dy).clamp(0.0, screenSize.height - size),
            );
          });
        },
        onTap: () {
          if (!_isCircularExpanded) {
            // Expand to show buttons
            setState(() {
              _isCircularExpanded = true;
            });
          } else {
            // Check if tap is on center (collapse) or outside (expand full call)
            setState(() {
              _isCircularExpanded = false;
            });
          }
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: size,
          height: size,
          child: Material(
            color: Colors.transparent,
            child: _isCircularExpanded
                ? _buildExpandedCircular(context, callManager, call, callState, duration)
                : _buildCollapsedCircular(context, call),
          ),
        ),
      ),
    );
  }

  Widget _buildCollapsedCircular(BuildContext context, CallInfo call) {
    final screenWidth = MediaQuery.of(context).size.width;
    final size = (screenWidth * 0.175).clamp(62.0, 76.0);
    final borderWidth = (screenWidth * 0.0075).clamp(2.5, 3.5);
    final avatarRadius = (size / 2) - borderWidth - 2;
    final avatarTextSize = (screenWidth * 0.06).clamp(21.0, 27.0);

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: const Color(0xFF1a1a2e),
        border: Border.all(color: Colors.greenAccent, width: borderWidth),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.4),
            blurRadius: 12,
            spreadRadius: 2,
          ),
        ],
      ),
      child: CircleAvatar(
        radius: avatarRadius,
        backgroundImage: call.avatarUrl != null && call.avatarUrl!.isNotEmpty
          ? NetworkImage(call.avatarUrl!)
          : null,
        backgroundColor: call.avatarUrl == null
          ? Color(call.callerName.hashCode | 0xFF000000)
          : Colors.transparent,
        child: call.avatarUrl == null
          ? Text(
              call.callerName.isNotEmpty ? call.callerName[0].toUpperCase() : '?',
              style: TextStyle(
                color: Colors.white,
                fontSize: avatarTextSize,
                fontWeight: FontWeight.bold,
                decoration: TextDecoration.none,
              ),
            )
          : null,
      ),
    );
  }

  Widget _buildExpandedCircular(
    BuildContext context,
    GlobalCallManager callManager,
    CallInfo call,
    CallState callState,
    Duration duration,
  ) {
    final screenWidth = MediaQuery.of(context).size.width;
    final centerSize = (screenWidth * 0.175).clamp(62.0, 76.0);
    final borderWidth = (screenWidth * 0.0075).clamp(2.5, 3.5);
    final avatarRadius = (centerSize / 2) - borderWidth - 2;
    final avatarTextSize = (screenWidth * 0.06).clamp(21.0, 27.0);

    return Stack(
      alignment: Alignment.center,
      children: [
        // Center avatar - tap to collapse
        GestureDetector(
          onTap: () {
            setState(() {
              _isCircularExpanded = false;
            });
          },
          child: Container(
            width: centerSize,
            height: centerSize,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF1a1a2e),
              border: Border.all(color: Colors.greenAccent, width: borderWidth),
            ),
            child: CircleAvatar(
              radius: avatarRadius,
              backgroundImage: call.avatarUrl != null && call.avatarUrl!.isNotEmpty
                ? NetworkImage(call.avatarUrl!)
                : null,
              backgroundColor: call.avatarUrl == null
                ? Color(call.callerName.hashCode | 0xFF000000)
                : Colors.transparent,
              child: call.avatarUrl == null
                ? Text(
                    call.callerName.isNotEmpty ? call.callerName[0].toUpperCase() : '?',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: avatarTextSize,
                      fontWeight: FontWeight.bold,
                      decoration: TextDecoration.none,
                    ),
                  )
                : null,
            ),
          ),
        ),
        // Mute button - top
        Positioned(
          top: 0,
          child: GestureDetector(
            onTap: () => callManager.toggleMicrophone(),
            child: _buildCircularButton(
              context: context,
              icon: callManager.isMuted ? Icons.mic_off : Icons.mic,
              color: callManager.isMuted ? Colors.red : Colors.white,
            ),
          ),
        ),
        // End call button - bottom
        Positioned(
          bottom: 0,
          child: GestureDetector(
            onTap: () => callManager.endCall(),
            child: _buildCircularButton(
              context: context,
              icon: Icons.call_end,
              color: Colors.red,
            ),
          ),
        ),
        // Expand button - right
        Positioned(
          right: 0,
          child: GestureDetector(
            onTap: () {
              setState(() {
                _isMinimized = false;
              });
            },
            child: _buildCircularButton(
              context: context,
              icon: Icons.open_in_full,
              color: Colors.white,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCircularButton({required BuildContext context, required IconData icon, required Color color}) {
    final screenWidth = MediaQuery.of(context).size.width;
    final buttonSize = (screenWidth * 0.125).clamp(45.0, 55.0);
    final iconSize = (screenWidth * 0.06).clamp(21.0, 27.0);
    final borderWidth = (screenWidth * 0.005).clamp(1.8, 2.5);

    return Container(
      width: buttonSize,
      height: buttonSize,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: const Color(0xFF1a1a2e),
        border: Border.all(color: color, width: borderWidth),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 8,
          ),
        ],
      ),
      child: Icon(icon, color: color, size: iconSize),
    );
  }

  Widget _buildMiniButton({required BuildContext context, required IconData icon, required Color color, required VoidCallback onTap}) {
    final screenWidth = MediaQuery.of(context).size.width;
    final padding = (screenWidth * 0.025).clamp(8.0, 12.0);
    final borderRadius = (screenWidth * 0.02).clamp(7.0, 10.0);
    final iconSize = (screenWidth * 0.05).clamp(18.0, 24.0);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(borderRadius),
      child: Container(
        padding: EdgeInsets.all(padding),
        decoration: BoxDecoration(
          color: color.withOpacity(0.2),
          borderRadius: BorderRadius.circular(borderRadius),
        ),
        child: Icon(icon, color: color, size: iconSize),
      ),
    );
  }

  String _formatCallDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);

    if (hours > 0) {
      return '${twoDigits(hours)}:${twoDigits(minutes)}:${twoDigits(seconds)}';
    } else {
      return '${twoDigits(minutes)}:${twoDigits(seconds)}';
    }
  }

  String _callStateText(CallState callState) {
    switch (callState) {
      case CallState.outgoing:
        return 'Calling...';
      case CallState.incoming:
        return 'Incoming call...';
      case CallState.connecting:
        return 'Connecting...';
      case CallState.connected:
        return 'Connected';
      default:
        return '';
    }
  }
}

// Particles background painter for voice calls
class _ParticlesPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.white.withOpacity(0.1);
    final random = math.Random(42); // Fixed seed for consistent pattern

    for (int i = 0; i < 50; i++) {
      final x = random.nextDouble() * size.width;
      final y = random.nextDouble() * size.height;
      final radius = random.nextDouble() * 2 + 1;
      canvas.drawCircle(Offset(x, y), radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
