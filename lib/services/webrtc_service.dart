// lib/services/webrtc_service.dart
import 'dart:async';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'dart:convert';

enum CallState {
  idle,
  outgoing,
  incoming,
  connecting,
  connected,
  ended,
}

enum CallType {
  voice,
  video,
}

class WebRTCService {
  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  MediaStream? _remoteStream;

  final List<RTCIceCandidate> _iceCandidates = [];

  CallState _callState = CallState.idle;
  CallType _callType = CallType.voice;

  // Stream controllers for reactive updates
  final _callStateController = StreamController<CallState>.broadcast();
  final _remoteStreamController = StreamController<MediaStream?>.broadcast();
  final _localStreamController = StreamController<MediaStream?>.broadcast();

  Stream<CallState> get callStateStream => _callStateController.stream;
  Stream<MediaStream?> get remoteStreamStream => _remoteStreamController.stream;
  Stream<MediaStream?> get localStreamStream => _localStreamController.stream;

  CallState get callState => _callState;
  CallType get callType => _callType;
  MediaStream? get localStream => _localStream;
  MediaStream? get remoteStream => _remoteStream;

  // Callbacks for signaling
  Function(Map<String, dynamic>)? onSendSignal;
  Function()? onCallEnded;

  // STUN servers configuration
  final Map<String, dynamic> _configuration = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
    ],
    'sdpSemantics': 'unified-plan',
  };

  // Media constraints
  final Map<String, dynamic> _voiceConstraints = {
    'audio': true,
    'video': false,
  };

  final Map<String, dynamic> _videoConstraints = {
    'audio': true,
    'video': {
      'facingMode': 'user',
      'width': {'ideal': 640},
      'height': {'ideal': 480},
    },
  };

  Future<void> initialize() async {
    // print('[WebRTC] Initializing WebRTC service');
  }

  void _updateCallState(CallState newState) {
    _callState = newState;
    _callStateController.add(newState);
    // print('[WebRTC] Call state changed to: $newState');
  }

  /// Start an outgoing call (voice or video)
  Future<void> startCall({required CallType callType, String? avatarUrl}) async {
    try {
      // print('[WebRTC] Starting ${callType.name} call');
      _callType = callType;
      _updateCallState(CallState.outgoing);

      // Get local media stream
      final constraints = callType == CallType.video ? _videoConstraints : _voiceConstraints;
      _localStream = await navigator.mediaDevices.getUserMedia(constraints);
      _localStreamController.add(_localStream);

      // Create peer connection
      await _createPeerConnection();

      // Add local stream to peer connection
      _localStream!.getTracks().forEach((track) {
        _peerConnection!.addTrack(track, _localStream!);
      });

      // Create and send offer
      final offer = await _peerConnection!.createOffer();
      await _peerConnection!.setLocalDescription(offer);

      // Send offer via signaling (include avatar_url if available)
      final Map<String, dynamic> signalData = {
        'type': 'call_offer',
        'callType': callType.name,
        'sdp': offer.sdp,
      };

      if (avatarUrl != null && avatarUrl.isNotEmpty) {
        signalData['avatar_url'] = avatarUrl;
      }

      onSendSignal?.call(signalData);

      // print('[WebRTC] Offer created and sent');
    } catch (e) {
      // print('[WebRTC] Error starting call: $e');
      await endCall();
      rethrow;
    }
  }

  /// Accept an incoming call
  Future<void> acceptCall({required CallType callType}) async {
    try {
      // print('[WebRTC] Accepting ${callType.name} call');
      _callType = callType;
      _updateCallState(CallState.connecting);

      // Get local media stream
      final constraints = callType == CallType.video ? _videoConstraints : _voiceConstraints;
      _localStream = await navigator.mediaDevices.getUserMedia(constraints);
      _localStreamController.add(_localStream);

      // Create peer connection
      await _createPeerConnection();

      // Add local stream to peer connection
      _localStream!.getTracks().forEach((track) {
        _peerConnection!.addTrack(track, _localStream!);
      });

      // print('[WebRTC] Call accepted, waiting for offer');
    } catch (e) {
      // print('[WebRTC] Error accepting call: $e');
      await endCall();
      rethrow;
    }
  }

  /// Handle incoming offer from remote peer
  Future<void> handleOffer(String sdp) async {
    try {
      // print('[WebRTC] Handling offer');

      final description = RTCSessionDescription(sdp, 'offer');
      await _peerConnection!.setRemoteDescription(description);

      // Create and send answer
      final answer = await _peerConnection!.createAnswer();
      await _peerConnection!.setLocalDescription(answer);

      // Send answer via signaling
      onSendSignal?.call(<String, dynamic>{
        'type': 'call_answer',
        'sdp': answer.sdp,
      });

      // Add buffered ICE candidates
      for (var candidate in _iceCandidates) {
        await _peerConnection!.addCandidate(candidate);
      }
      _iceCandidates.clear();

      _updateCallState(CallState.connecting);
      // print('[WebRTC] Answer created and sent');
    } catch (e) {
      // print('[WebRTC] Error handling offer: $e');
      await endCall();
    }
  }

  /// Handle incoming answer from remote peer
  Future<void> handleAnswer(String sdp) async {
    try {
      // print('[WebRTC] Handling answer');

      final description = RTCSessionDescription(sdp, 'answer');
      await _peerConnection!.setRemoteDescription(description);

      // Add buffered ICE candidates
      for (var candidate in _iceCandidates) {
        await _peerConnection!.addCandidate(candidate);
      }
      _iceCandidates.clear();

      _updateCallState(CallState.connecting);
      // print('[WebRTC] Answer set successfully');
    } catch (e) {
      // print('[WebRTC] Error handling answer: $e');
      await endCall();
    }
  }

  /// Handle incoming ICE candidate from remote peer
  Future<void> handleIceCandidate(Map<String, dynamic> candidateData) async {
    try {
      final candidate = RTCIceCandidate(
        candidateData['candidate'],
        candidateData['sdpMid'],
        candidateData['sdpMLineIndex'],
      );

      if (_peerConnection != null && _peerConnection!.getRemoteDescription() != null) {
        await _peerConnection!.addCandidate(candidate);
        // print('[WebRTC] ICE candidate added');
      } else {
        _iceCandidates.add(candidate);
        // print('[WebRTC] ICE candidate buffered');
      }
    } catch (e) {
      // print('[WebRTC] Error handling ICE candidate: $e');
    }
  }

  /// Create peer connection with all event handlers
  Future<void> _createPeerConnection() async {
    _peerConnection = await createPeerConnection(_configuration);

    // Handle ICE candidates
    _peerConnection!.onIceCandidate = (candidate) {
      if (candidate.candidate != null) {
        onSendSignal?.call(<String, dynamic>{
          'type': 'ice_candidate',
          'candidate': candidate.candidate,
          'sdpMid': candidate.sdpMid,
          'sdpMLineIndex': candidate.sdpMLineIndex,
        });
        // print('[WebRTC] Local ICE candidate sent');
      }
    };

    // Handle connection state changes
    _peerConnection!.onConnectionState = (state) {
      // print('[WebRTC] Connection state: $state');
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        _updateCallState(CallState.connected);
      } else if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
                 state == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected ||
                 state == RTCPeerConnectionState.RTCPeerConnectionStateClosed) {
        endCall();
      }
    };

    // Handle incoming remote stream
    _peerConnection!.onTrack = (event) {
      // print('[WebRTC] Remote track received');
      if (event.streams.isNotEmpty) {
        _remoteStream = event.streams[0];
        _remoteStreamController.add(_remoteStream);
      }
    };

    // print('[WebRTC] Peer connection created');
  }

  /// Toggle microphone mute/unmute
  Future<void> toggleMicrophone() async {
    if (_localStream != null) {
      final audioTrack = _localStream!.getAudioTracks().first;
      final enabled = audioTrack.enabled;
      audioTrack.enabled = !enabled;
      // print('[WebRTC] Microphone ${!enabled ? "enabled" : "muted"}');
    }
  }

  /// Toggle camera on/off (video calls only)
  Future<void> toggleCamera() async {
    if (_localStream != null && _callType == CallType.video) {
      final videoTrack = _localStream!.getVideoTracks().first;
      final enabled = videoTrack.enabled;
      videoTrack.enabled = !enabled;
      // print('[WebRTC] Camera ${!enabled ? "enabled" : "disabled"}');
    }
  }

  /// Switch camera (front/back) for video calls
  Future<void> switchCamera() async {
    if (_localStream != null && _callType == CallType.video) {
      final videoTrack = _localStream!.getVideoTracks().first;
      await Helper.switchCamera(videoTrack);
      // print('[WebRTC] Camera switched');
    }
  }


  /// End the call and cleanup resources
  Future<void> endCall() async {
    // print('[WebRTC] Ending call');

    // Close peer connection
    await _peerConnection?.close();
    _peerConnection = null;

    // Stop and dispose local stream
    _localStream?.getTracks().forEach((track) {
      track.stop();
    });
    await _localStream?.dispose();
    _localStream = null;
    _localStreamController.add(null);

    // Dispose remote stream
    await _remoteStream?.dispose();
    _remoteStream = null;
    _remoteStreamController.add(null);

    // Clear buffered candidates
    _iceCandidates.clear();

    _updateCallState(CallState.ended);

    // Notify call ended
    onCallEnded?.call();

    // Reset to idle after a short delay
    await Future.delayed(const Duration(milliseconds: 500));
    _updateCallState(CallState.idle);
  }

  /// Reject an incoming call
  Future<void> rejectCall() async {
    // print('[WebRTC] Rejecting call');
    onSendSignal?.call({'type': 'call_rejected'});
    await endCall();
  }

  void dispose() {
    _callStateController.close();
    _remoteStreamController.close();
    _localStreamController.close();
    endCall();
  }
}
