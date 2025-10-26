// lib/services/global_call_manager.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:firebase_auth/firebase_auth.dart'; // 🔧 FIX: For getting current user UID
import 'webrtc_service.dart';
import 'SignalService.dart';
import 'system_overlay_service.dart';
import 'device_service.dart'; // 🔧 FIX: Import DeviceService for getting recipient device ID

class CallInfo {
  final String callerUid;
  final String callerName;
  final CallType callType;
  final String sdp;
  final int conversationId;
  final String? avatarUrl;

  CallInfo({
    required this.callerUid,
    required this.callerName,
    required this.callType,
    required this.sdp,
    required this.conversationId,
    this.avatarUrl,
  });
}

class GlobalCallManager with ChangeNotifier {
  static final GlobalCallManager _instance = GlobalCallManager._internal();
  factory GlobalCallManager() => _instance;
  GlobalCallManager._internal();

  static const _pipChannel = MethodChannel('com.zarq/pip');

  WebRTCService? _webrtcService;
  CallInfo? _incomingCall;
  CallInfo? _activeCall;
  bool _isInCall = false;
  bool _isEndingCall = false; // Guard to prevent multiple endCall executions

  // 🔧 FIX: Buffer ICE candidates that arrive before peer connection is created
  final List<Map<String, dynamic>> _bufferedIceCandidates = [];

  // System overlay state
  bool _isAppInBackground = false;
  bool _isSystemOverlayShown = false;

  // Notify Android about call state
  Future<void> _notifyCallState(bool isInCall) async {
    try {
      await _pipChannel.invokeMethod('setCallState', {'isInCall': isInCall});
      // print('[GlobalCallManager] 📱 Notified Android - isInCall: $isInCall');
    } catch (e) {
      // print('[GlobalCallManager] ⚠️ Failed to notify call state: $e');
    }
  }

  // Call control states
  bool _isMuted = false;
  bool _isCameraOff = false;
  bool _isSpeakerOn = false;

  // Call duration tracking
  DateTime? _callStartTime;
  Timer? _callDurationTimer;
  Duration _currentDuration = Duration.zero;

  final RTCVideoRenderer localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer remoteRenderer = RTCVideoRenderer();

  CallInfo? get incomingCall => _incomingCall;
  CallInfo? get activeCall => _activeCall;
  bool get isInCall => _isInCall;
  bool get hasIncomingCall => _incomingCall != null;
  WebRTCService? get webrtcService => _webrtcService;
  bool get isMuted => _isMuted;
  bool get isCameraOff => _isCameraOff;
  bool get isSpeakerOn => _isSpeakerOn;
  Duration get callDuration => _currentDuration;

  // Get count of buffered ICE candidates (for auto-answer timing)
  int getBufferedCandidatesCount() => _bufferedIceCandidates.length;

  // Callback for sending call signals
  Function(Map<String, dynamic>)? onSendSignal;

  Future<void> initialize() async {
    await localRenderer.initialize();
    await remoteRenderer.initialize();
    // print('[GlobalCallManager] Initialized');
  }

  /// Handle app lifecycle state changes
  Future<void> handleAppLifecycleState(AppLifecycleState state) async {
    // print('[GlobalCallManager] 🔄 App lifecycle: $state, wasInBackground: $_isAppInBackground');

    final wasInBackground = _isAppInBackground;

    // Only consider truly backgrounded states (ignore inactive - it's transitional)
    _isAppInBackground = (state == AppLifecycleState.paused ||
                         state == AppLifecycleState.detached);

    // App went to background during active call - show system overlay
    // Only trigger on paused (not inactive, which is just transitional)
    if (!wasInBackground && _isAppInBackground && _isInCall && _activeCall != null) {
      // print('[GlobalCallManager] 🪟 App backgrounded - showing system overlay');
      await _showSystemOverlay();
    }

    // App came back to foreground - hide system overlay
    // Only hide on resumed state
    if (wasInBackground && state == AppLifecycleState.resumed && _isSystemOverlayShown) {
      // print('[GlobalCallManager] 🪟 App foregrounded - hiding system overlay');
      await _hideSystemOverlay();
    }
  }

  /// Show system overlay (floating window over other apps)
  Future<void> _showSystemOverlay() async {
    if (_isSystemOverlayShown || _activeCall == null) return;

    try {
      // print('[GlobalCallManager] 🪟 Showing system overlay for ${_activeCall!.callerName}');

      final success = await SystemOverlayService.showOverlay(
        callerName: _activeCall!.callerName,
        isVideo: _activeCall!.callType == CallType.video,
        avatarUrl: _activeCall!.avatarUrl,
        isMuted: _isMuted,
      );

      if (success) {
        _isSystemOverlayShown = true;
        // print('[GlobalCallManager] ✅ System overlay shown');
      } else {
        // print('[GlobalCallManager] ⚠️ Failed to show system overlay - may need permission');
      }
    } catch (e) {
      // print('[GlobalCallManager] ❌ Error showing system overlay: $e');
    }
  }

  /// Hide system overlay
  Future<void> _hideSystemOverlay() async {
    if (!_isSystemOverlayShown) return;

    try {
      // print('[GlobalCallManager] 🪟 Hiding system overlay');
      await SystemOverlayService.hideOverlay();
      _isSystemOverlayShown = false;
      // print('[GlobalCallManager] ✅ System overlay hidden');
    } catch (e) {
      // print('[GlobalCallManager] ❌ Error hiding system overlay: $e');
    }
  }

  void _startCallDurationTimer() {
    _callStartTime = DateTime.now();
    _currentDuration = Duration.zero;
    _callDurationTimer?.cancel();

    _callDurationTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_callStartTime != null) {
        _currentDuration = DateTime.now().difference(_callStartTime!);
        notifyListeners();
      }
    });

    // print('[GlobalCallManager] ⏱️ Call duration timer started');
  }

  void _stopCallDurationTimer() {
    _callDurationTimer?.cancel();
    _callDurationTimer = null;
    _callStartTime = null;
    _currentDuration = Duration.zero;
    // print('[GlobalCallManager] ⏱️ Call duration timer stopped');
  }

  void setIncomingCall(CallInfo callInfo) {
    _incomingCall = callInfo;
    // print('[GlobalCallManager] ✅ setIncomingCall - callerName: ${callInfo.callerName}, avatarUrl: ${callInfo.avatarUrl}, conversationId: ${callInfo.conversationId}');
    notifyListeners();
    // print('[GlobalCallManager] ✅ notifyListeners called - hasIncomingCall: $hasIncomingCall');
  }

  void clearIncomingCall() {
    _incomingCall = null;
    notifyListeners();
  }

  Future<void> startOutgoingCall({
    required String recipientUid,
    required String recipientName,
    required int conversationId,
    required CallType callType,
    String? recipientAvatarUrl,
  }) async {
    try {
      // print('[GlobalCallManager] Starting outgoing ${callType.name} call to $recipientName');
      // print('[GlobalCallManager] Recipient avatar: $recipientAvatarUrl');

      _activeCall = CallInfo(
        callerUid: recipientUid,
        callerName: recipientName,
        callType: callType,
        sdp: '',
        conversationId: conversationId,
        avatarUrl: recipientAvatarUrl,
      );
      _isInCall = true;
      _notifyCallState(true);

      // Create WebRTC service
      _webrtcService = WebRTCService();
      await _webrtcService!.initialize();

      // Setup callbacks
      _webrtcService!.onSendSignal = (signalData) async {
        // 🔧 FIX: Add sender's device ID so receiver can decrypt
        final myDeviceId = await SignalService.getDeviceId();
        final myUid = await _getCurrentUserUid();

        signalData['recipient_uid'] = recipientUid;
        signalData['conversation_id'] = conversationId;
        signalData['sender_uid'] = myUid; // 🔧 FIX: Add sender UID
        signalData['sender_device_id'] = myDeviceId; // 🔧 FIX: Add sender device ID

        // Encrypt SDP and ICE candidates using Signal Protocol
        await _encryptCallSignal(signalData, recipientUid);

        onSendSignal?.call(signalData);
      };

      _webrtcService!.onCallEnded = () {
        endCall();
      };

      // Listen to streams
      _webrtcService!.localStreamStream.listen((stream) {
        if (stream != null) {
          localRenderer.srcObject = stream;
          notifyListeners();
        }
      });

      _webrtcService!.remoteStreamStream.listen((stream) {
        if (stream != null) {
          remoteRenderer.srcObject = stream;
          notifyListeners();
        }
      });

      // Start call with recipient's avatar
      await _webrtcService!.startCall(callType: callType, avatarUrl: recipientAvatarUrl);

      notifyListeners();
    } catch (e) {
      // print('[GlobalCallManager] Error starting call: $e');
      endCall();
      rethrow;
    }
  }

  Future<void> acceptIncomingCall() async {
    if (_incomingCall == null) return;

    try {
      // print('[GlobalCallManager] Accepting call from ${_incomingCall!.callerName}');

      _activeCall = _incomingCall;
      _incomingCall = null;
      _isInCall = true;
      _notifyCallState(true);

      // Create WebRTC service
      _webrtcService = WebRTCService();
      await _webrtcService!.initialize();

      // Setup callbacks
      _webrtcService!.onSendSignal = (signalData) async {
        // 🔧 FIX: Add sender's device ID so receiver can decrypt
        final myDeviceId = await SignalService.getDeviceId();
        final myUid = await _getCurrentUserUid();

        signalData['recipient_uid'] = _activeCall!.callerUid;
        signalData['conversation_id'] = _activeCall!.conversationId;
        signalData['sender_uid'] = myUid; // 🔧 FIX: Add sender UID
        signalData['sender_device_id'] = myDeviceId; // 🔧 FIX: Add sender device ID

        // Encrypt SDP and ICE candidates using Signal Protocol
        await _encryptCallSignal(signalData, _activeCall!.callerUid);

        onSendSignal?.call(signalData);
      };

      _webrtcService!.onCallEnded = () {
        endCall();
      };

      // Listen to streams
      _webrtcService!.localStreamStream.listen((stream) {
        if (stream != null) {
          localRenderer.srcObject = stream;
          notifyListeners();
        }
      });

      _webrtcService!.remoteStreamStream.listen((stream) {
        if (stream != null) {
          remoteRenderer.srcObject = stream;
          notifyListeners();
        }
      });

      // 🔧 FIX: Pass buffered ICE candidates to WebRTC service
      if (_bufferedIceCandidates.isNotEmpty) {
        print('[GlobalCallManager] 📦 Passing ${_bufferedIceCandidates.length} buffered ICE candidates to WebRTC service');
        for (var candidateData in _bufferedIceCandidates) {
          await _webrtcService!.handleIceCandidate(candidateData);
        }
        _bufferedIceCandidates.clear();
        print('[GlobalCallManager] ✅ All buffered candidates passed to WebRTC service');
      } else {
        print('[GlobalCallManager] ⚠️ No buffered candidates - caller might not have sent any yet');
      }

      // Accept call
      await _webrtcService!.acceptCall(callType: _activeCall!.callType);
      await _webrtcService!.handleOffer(_activeCall!.sdp);

      // Start call duration timer
      _startCallDurationTimer();

      notifyListeners();
    } catch (e) {
      // print('[GlobalCallManager] Error accepting call: $e');
      endCall();
      rethrow;
    }
  }

  Future<void> rejectIncomingCall() async {
    if (_incomingCall == null) {
      // print('[GlobalCallManager] ⚠️ rejectIncomingCall called but no incoming call');
      return;
    }

    // print('[GlobalCallManager] ❌ Rejecting call from ${_incomingCall!.callerName}');

    // Send rejection signal
    onSendSignal?.call({
      'type': 'call_rejected',
      'recipient_uid': _incomingCall!.callerUid,
    });

    _incomingCall = null;
    // print('[GlobalCallManager] ✅ Incoming call cleared, calling notifyListeners');
    notifyListeners();
    // print('[GlobalCallManager] ✅ hasIncomingCall: $hasIncomingCall');
  }

  /// Handle renegotiation offer (e.g., when remote adds video track during voice call)
  Future<void> handleRenegotiationOffer(String sdp) async {
    if (!_isInCall || _webrtcService == null) {
      // print('[GlobalCallManager] ⚠️ Cannot handle renegotiation - not in active call');
      return;
    }

    try {
      // print('[GlobalCallManager] 🔄 Handling renegotiation offer');
      await _webrtcService!.handleOffer(sdp);
      notifyListeners();
      // print('[GlobalCallManager] ✅ Renegotiation completed');
    } catch (e) {
      // print('[GlobalCallManager] ❌ Error handling renegotiation: $e');
    }
  }

  Future<void> handleCallAnswer(String sdp, {String? avatarUrl, bool? encrypted, String? senderUid, int? senderDeviceId}) async {
    if (_webrtcService != null) {
      String decryptedSdp = sdp;

      // Decrypt SDP if encrypted
      if (encrypted == true && senderUid != null) {
        print('[GlobalCallManager] 🔓 Decrypting call_answer SDP...');
        final decrypted = await _decryptCallSignal(sdp, senderUid, senderDeviceId);
        if (decrypted != null) {
          decryptedSdp = decrypted;
          print('[GlobalCallManager] ✅ Successfully decrypted call_answer SDP');
        } else {
          print('[GlobalCallManager] ⚠️ Failed to decrypt SDP, using original');
        }
      }

      await _webrtcService!.handleAnswer(decryptedSdp);

      // Start call duration timer (call is now connected)
      _startCallDurationTimer();

      // Update activeCall with receiver's avatar
      if (avatarUrl != null && _activeCall != null) {
        _activeCall = CallInfo(
          callerUid: _activeCall!.callerUid,
          callerName: _activeCall!.callerName,
          callType: _activeCall!.callType,
          sdp: _activeCall!.sdp,
          conversationId: _activeCall!.conversationId,
          avatarUrl: avatarUrl,
        );
        // print('[GlobalCallManager] Updated activeCall with receiver avatar: $avatarUrl');
        notifyListeners();
      }
    }
  }

  Future<void> handleIceCandidate(Map<String, dynamic> candidateData) async {
    // Decrypt ICE candidate if encrypted
    if (candidateData['encrypted'] == true) {
      final encryptedCandidate = candidateData['candidate'] as String?;
      final senderUid = candidateData['sender_uid'] as String?;
      final senderDeviceId = candidateData['sender_device_id'] as int?;

      if (encryptedCandidate != null && senderUid != null) {
        print('[GlobalCallManager] 🔓 Decrypting ICE candidate...');
        final decrypted = await _decryptCallSignal(encryptedCandidate, senderUid, senderDeviceId);
        if (decrypted != null) {
          candidateData['candidate'] = decrypted;
          print('[GlobalCallManager] ✅ Successfully decrypted ICE candidate');
        } else {
          print('[GlobalCallManager] ❌ FAILED to decrypt ICE candidate - will be dropped!');
          return; // Don't pass failed decrypt to WebRTC
        }
      }
    }

    // 🔧 FIX: Buffer candidates if WebRTC service doesn't exist yet
    if (_webrtcService != null) {
      await _webrtcService!.handleIceCandidate(candidateData);
    } else {
      _bufferedIceCandidates.add(candidateData);
      print('[GlobalCallManager] 📦 ICE candidate buffered (no WebRTC service yet, count: ${_bufferedIceCandidates.length})');
    }
  }

  void handleCallRejected() {
    // print('[GlobalCallManager] Call was rejected');
    endCall();
  }

  void handleCallEnded() {
    // print('[GlobalCallManager] Call ended by remote');
    endCall();
  }

  void handleCallFailed(String reason) {
    // print('[GlobalCallManager] Call failed: $reason');

    // Show appropriate message to user
    String message;
    switch (reason) {
      case 'user_offline':
        message = 'User is offline or unreachable';
        break;
      default:
        message = 'Call failed: $reason';
    }

    // Store the failure reason for UI to display
    _callFailureReason = message;

    endCall();
  }

  String? _callFailureReason;
  String? get callFailureReason => _callFailureReason;

  Future<void> endCall() async {
    // Prevent multiple simultaneous endCall executions
    if (_isEndingCall) {
      // print('[GlobalCallManager] ⚠️ endCall already in progress, skipping...');
      return;
    }

    _isEndingCall = true;
    // print('[GlobalCallManager] 🔴 Ending call - Current state: isInCall=$_isInCall, hasActiveCall=${_activeCall != null}');

    try {
      // Hide system overlay if shown
      if (_isSystemOverlayShown) {
        await _hideSystemOverlay();
      }

      // Send call ended signal if in active call
      if (_activeCall != null) {
        // print('[GlobalCallManager] 📤 Sending call_ended signal to ${_activeCall!.callerUid}');
        onSendSignal?.call({
          'type': 'call_ended',
          'recipient_uid': _activeCall!.callerUid,
        });
      }

      // Cleanup WebRTC
      // print('[GlobalCallManager] 🧹 Cleaning up WebRTC service...');
      if (_webrtcService != null) {
        await _webrtcService?.endCall();
        _webrtcService?.dispose();
        _webrtcService = null;
      }

      // 🔧 FIX: Clear buffered ICE candidates
      if (_bufferedIceCandidates.isNotEmpty) {
        print('[GlobalCallManager] 🧹 Clearing ${_bufferedIceCandidates.length} buffered ICE candidates');
        _bufferedIceCandidates.clear();
      }

      // Clear renderers safely
      // print('[GlobalCallManager] 🧹 Clearing video renderers...');
      try {
        localRenderer.srcObject = null;
        remoteRenderer.srcObject = null;
      } catch (e) {
        // print('[GlobalCallManager] ⚠️ Error clearing renderers: $e');
      }

      // print('[GlobalCallManager] 🧹 Clearing call state...');
      _stopCallDurationTimer();
      _activeCall = null;
      _isInCall = false;
      _notifyCallState(false);
      _isMuted = false;
      _isCameraOff = false;

      // print('[GlobalCallManager] 🔔 Calling notifyListeners - Final state: isInCall=$_isInCall, hasActiveCall=${_activeCall != null}');
      notifyListeners();
      // print('[GlobalCallManager] ✅ endCall completed');
    } catch (e) {
      // print('[GlobalCallManager] ❌ Error during endCall: $e');
    } finally {
      _isEndingCall = false;
    }
  }

  Future<void> toggleMicrophone() async {
    await _webrtcService?.toggleMicrophone();
    _isMuted = !_isMuted;
    // print('[GlobalCallManager] 🎤 Microphone ${_isMuted ? "muted" : "unmuted"}');

    // 🔧 FIX: Update overlay mute state when toggled from app
    if (_isSystemOverlayShown) {
      await SystemOverlayService.updateMuteState(_isMuted);
    }

    notifyListeners();
  }

  Future<void> toggleCamera() async {
    await _webrtcService?.toggleCamera();
    _isCameraOff = !_isCameraOff;
    // print('[GlobalCallManager] 📹 Camera ${_isCameraOff ? "off" : "on"}');
    notifyListeners();
  }

  Future<void> switchCamera() async {
    await _webrtcService?.switchCamera();
  }

  Future<void> toggleSpeaker() async {
    await _webrtcService?.toggleSpeaker();
    _isSpeakerOn = !_isSpeakerOn;
    print('[GlobalCallManager] 🔊 Speaker ${_isSpeakerOn ? "enabled" : "disabled"}');
    notifyListeners();
  }

  bool get isCallConnected => _webrtcService?.callState == CallState.connected;

  // ==================== Helper Methods ====================

  /// Get current user's UID from Firebase Auth
  Future<String?> _getCurrentUserUid() async {
    final user = FirebaseAuth.instance.currentUser;
    return user?.uid;
  }

  // ==================== Signal Protocol Encryption ====================

  /// Encrypt call signaling data (SDP/ICE) using Signal Protocol
  Future<void> _encryptCallSignal(Map<String, dynamic> signalData, String recipientUid) async {
    try {
      final type = signalData['type'] as String?;

      // 🔧 FIX: Get recipient's ACTUAL device ID (not fallback to sender's)
      final recipientDeviceId = await DeviceService.getActiveDeviceId(recipientUid);
      if (recipientDeviceId == null) {
        print('[GlobalCallManager] ⚠️ Could not get recipient device ID - skipping encryption');
        return;
      }

      if (type == 'call_offer' || type == 'call_answer') {
        // Encrypt SDP
        final sdp = signalData['sdp'] as String?;
        if (sdp != null) {
          final encryptedSdp = await SignalService.encryptMessage(
            recipientUid: recipientUid,
            plaintext: sdp,
            deviceId: recipientDeviceId, // 🔧 FIX: Pass recipient's device ID
          );
          if (encryptedSdp != null) {
            signalData['sdp'] = encryptedSdp;
            signalData['encrypted'] = true;
            print('[GlobalCallManager] 🔒 Encrypted SDP for $type with device ID: $recipientDeviceId');
          } else {
            print('[GlobalCallManager] ⚠️ Failed to encrypt SDP, sending unencrypted');
          }
        }
      } else if (type == 'ice_candidate') {
        // Encrypt ICE candidate
        final candidate = signalData['candidate'] as String?;
        if (candidate != null) {
          final encryptedCandidate = await SignalService.encryptMessage(
            recipientUid: recipientUid,
            plaintext: candidate,
            deviceId: recipientDeviceId, // 🔧 FIX: Pass recipient's device ID
          );
          if (encryptedCandidate != null) {
            signalData['candidate'] = encryptedCandidate;
            signalData['encrypted'] = true;
            print('[GlobalCallManager] 🔒 Encrypted ICE candidate with device ID: $recipientDeviceId');
          }
        }
      }
    } catch (e) {
      print('[GlobalCallManager] ❌ Encryption error: $e - sending unencrypted');
    }
  }

  /// Decrypt call signaling data (SDP/ICE) using Signal Protocol
  Future<String?> _decryptCallSignal(String encryptedData, String senderUid, int? senderDeviceId) async {
    try {
      final decrypted = await SignalService.decryptMessage(
        senderUid: senderUid,
        ciphertextB64: encryptedData,
        deviceId: senderDeviceId ?? 1,
      );

      if (decrypted != null) {
        // print('[GlobalCallManager] 🔓 Decrypted call signal from $senderUid');
        return decrypted;
      } else {
        // print('[GlobalCallManager] ⚠️ Failed to decrypt signal');
        return null;
      }
    } catch (e) {
      // print('[GlobalCallManager] ❌ Decryption error: $e');
      return null;
    }
  }

  void dispose() {
    _webrtcService?.dispose();
    localRenderer.dispose();
    remoteRenderer.dispose();
    super.dispose();
  }
}
