// lib/services/webrtc_service.dart
import 'dart:async';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'turn_service.dart';

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

  // 🔧 FIX: Disconnection timeout to avoid premature call ending
  Timer? _disconnectionTimer;
  bool _hasBeenConnected = false;

  // 🔧 FIX: Track whether remote description has been set
  // We can't rely on getRemoteDescription() != null because it's unreliable
  bool _remoteDescriptionSet = false;

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

  // 🔒 PRODUCTION: TURN credentials now fetched from backend
  // This ensures the secret is never exposed in client code
  Map<String, dynamic>? _cachedConfiguration;

  // Get TURN configuration from backend (cached for performance)
  Future<Map<String, dynamic>> _getConfiguration() async {
    // Use cached configuration if available
    if (_cachedConfiguration != null) {
      return _cachedConfiguration!;
    }

    // Fetch credentials from backend
    final credentials = await TurnService.getTurnCredentials();

    if (credentials != null && credentials['ice_servers'] != null) {
      // Use backend-provided configuration
      _cachedConfiguration = {
        'iceServers': credentials['ice_servers'],
        'sdpSemantics': 'unified-plan',
        'bundlePolicy': 'max-bundle',
        'rtcpMuxPolicy': 'require',
        // Add security constraints
        'mandatory': {
          'DtlsSrtpKeyAgreement': true,
          'encryption': 'mandatory',
        },
        'iceCandidatePoolSize': 2,
      };

      print('[WebRTC] ✅ Using backend TURN configuration');
    } else {
      // Fallback configuration (for development only)
      print('[WebRTC] ⚠️ Using fallback configuration - backend unavailable');
      _cachedConfiguration = {
        'iceServers': [
          {'urls': 'stun:stun.l.google.com:19302'},
          {'urls': 'stun:stun1.l.google.com:19302'},
        ],
        'sdpSemantics': 'unified-plan',
        'bundlePolicy': 'max-bundle',
        'rtcpMuxPolicy': 'require',
        'mandatory': {
          'DtlsSrtpKeyAgreement': true,
          'encryption': 'mandatory',
        },
      };
    }

    return _cachedConfiguration!;
  }

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
    print('[WebRTC] 🔄 Call state changing: $_callState -> $newState');
    _callState = newState;
    if (!_callStateController.isClosed) {
      _callStateController.add(newState);
      print('[WebRTC] ✅ Call state updated and broadcast to: $newState');
    } else {
      print('[WebRTC] ❌ Call state controller is closed!');
    }
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

      // 🔧 FIX: Enable audio tracks to stay active in background
      _enableBackgroundAudio();

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

      // 🔍 DEBUG: Log SDP offer details
      print('[WebRTC] 📋 SDP OFFER created:');
      print('[WebRTC] 📋 Type: ${offer.type}');
      print('[WebRTC] 📋 SDP length: ${offer.sdp?.length ?? 0}');
      if (offer.sdp != null) {
        // Log first 500 chars of SDP for debugging
        final sdpPreview = offer.sdp!.length > 500 ? offer.sdp!.substring(0, 500) : offer.sdp!;
        print('[WebRTC] 📋 SDP preview: $sdpPreview');
      }

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

      // 🔧 FIX: Enable audio tracks to stay active in background
      _enableBackgroundAudio();

      _localStreamController.add(_localStream);

      // Create peer connection
      await _createPeerConnection();

      // Add local stream to peer connection
      _localStream!.getTracks().forEach((track) {
        _peerConnection!.addTrack(track, _localStream!);
      });

      print('[WebRTC] ✅ Call accepted, waiting for offer');
    } catch (e) {
      print('[WebRTC] ❌ ERROR accepting call: $e');
      print('[WebRTC] ❌ This usually means microphone permission was denied');
      await endCall();
      rethrow;
    }
  }

  /// Handle incoming offer from remote peer
  Future<void> handleOffer(String sdp) async {
    try {
      print('[WebRTC] 📥 Handling incoming offer (SDP length: ${sdp.length})');

      if (_peerConnection == null) {
        print('[WebRTC] ❌ Peer connection is null, cannot handle offer');
        return;
      }

      // 🔍 DEBUG: Log SDP offer preview
      final sdpPreview = sdp.length > 500 ? sdp.substring(0, 500) : sdp;
      print('[WebRTC] 📋 SDP OFFER preview: $sdpPreview');

      final description = RTCSessionDescription(sdp, 'offer');
      await _peerConnection!.setRemoteDescription(description);
      _remoteDescriptionSet = true;  // 🔧 FIX: Mark that remote description is now set
      print('[WebRTC] ✅ Remote description set');

      // Create and send answer
      final answer = await _peerConnection!.createAnswer();
      await _peerConnection!.setLocalDescription(answer);

      // 🔍 DEBUG: Log SDP answer details
      print('[WebRTC] 📋 SDP ANSWER created:');
      print('[WebRTC] 📋 Type: ${answer.type}');
      print('[WebRTC] 📋 SDP length: ${answer.sdp?.length ?? 0}');
      if (answer.sdp != null) {
        final answerPreview = answer.sdp!.length > 500 ? answer.sdp!.substring(0, 500) : answer.sdp!;
        print('[WebRTC] 📋 SDP preview: $answerPreview');
      }

      print('[WebRTC] ✅ Answer created and local description set');

      // TEST: No delay - testing immediate answer creation
      print('[WebRTC] ⚡ NO DELAY - Creating answer immediately');

      // Send answer via signaling
      onSendSignal?.call(<String, dynamic>{
        'type': 'call_answer',
        'sdp': answer.sdp,
      });
      print('[WebRTC] 📤 Answer sent via signaling (after ICE gathering)');

      // Add buffered ICE candidates
      print('[WebRTC] 📦 Adding ${_iceCandidates.length} buffered ICE candidates');
      for (var candidate in _iceCandidates) {
        await _peerConnection!.addCandidate(candidate);
      }
      _iceCandidates.clear();

      _updateCallState(CallState.connecting);
      print('[WebRTC] ✅ Offer handling complete');
    } catch (e) {
      print('[WebRTC] ❌ ERROR handling offer: $e');
      print('[WebRTC] ❌ Stack trace: ${StackTrace.current}');
      await endCall();
    }
  }

  /// Handle incoming answer from remote peer
  Future<void> handleAnswer(String sdp) async {
    try {
      print('[WebRTC] 📥 Handling incoming answer (SDP length: ${sdp.length})');

      if (_peerConnection == null) {
        print('[WebRTC] ❌ Peer connection is null, cannot handle answer');
        return;
      }

      // 🔍 DEBUG: Log SDP answer preview
      final sdpPreview = sdp.length > 500 ? sdp.substring(0, 500) : sdp;
      print('[WebRTC] 📋 SDP ANSWER preview: $sdpPreview');

      // ⏱️ OPTIMIZED: Reduced wait from 2s to 1s for faster call setup
      // The receiver sends host/srflx candidates immediately, relay candidates follow via trickle ICE
      // TEST: No delay - testing if trickle ICE alone is sufficient
      print('[WebRTC] ⚡ NO DELAY - Testing without wait (${_iceCandidates.length} candidates already buffered)');

      // 🔧 CRITICAL: Set remote description first to enable candidate adding
      final description = RTCSessionDescription(sdp, 'answer');
      await _peerConnection!.setRemoteDescription(description);
      _remoteDescriptionSet = true;  // 🔧 Mark immediately so new arrivals go directly
      print('[WebRTC] ✅ Remote description (answer) set');

      // 🔧 CRITICAL: Add buffered candidates IMMEDIATELY (must happen before ICE checking stats)
      print('[WebRTC] 📦 Adding ${_iceCandidates.length} buffered ICE candidates');
      for (var candidate in _iceCandidates) {
        await _peerConnection!.addCandidate(candidate);
      }
      _iceCandidates.clear();

      // TEST: No delay - candidates should be processed immediately
      print('[WebRTC] ⚡ NO DELAY - All buffered candidates added');

      _updateCallState(CallState.connecting);
      print('[WebRTC] ✅ Answer handling complete');
    } catch (e) {
      print('[WebRTC] ❌ Error handling answer: $e');
      await endCall();
    }
  }

  /// Handle incoming ICE candidate from remote peer
  Future<void> handleIceCandidate(Map<String, dynamic> candidateData) async {
    try {
      final candStr = candidateData['candidate'] as String?;

      // Null candidate means end of candidates (ICE gathering complete on remote)
      if (candStr == null) {
        print('[WebRTC] ✅ Received end-of-candidates signal from remote peer');
        return;
      }

      // Extract candidate type for debugging
      String candType = 'unknown';
      if (candStr.contains('typ host')) candType = 'host';
      else if (candStr.contains('typ srflx')) candType = 'srflx';
      else if (candStr.contains('typ relay')) candType = 'relay';

      print('[WebRTC] 📥 Received remote ICE candidate [type: $candType]: $candStr');
      final candidate = RTCIceCandidate(
        candStr,
        candidateData['sdpMid'],
        candidateData['sdpMLineIndex'],
      );

      // 🔧 FIX: Only add candidate if remote description has been explicitly set
      // WebRTC silently drops candidates added before remote description!
      if (_peerConnection != null && _remoteDescriptionSet) {
        await _peerConnection!.addCandidate(candidate);
        print('[WebRTC] ✅ ICE candidate [type: $candType] added to peer connection');
      } else {
        _iceCandidates.add(candidate);
        print('[WebRTC] 📦 ICE candidate [type: $candType] buffered (remote desc not ready yet, count: ${_iceCandidates.length})');
      }
    } catch (e) {
      print('[WebRTC] ❌ Error handling ICE candidate: $e');
    }
  }

  /// Create peer connection with all event handlers
  Future<void> _createPeerConnection() async {
    // TEST: No delay - create peer connection immediately

    print('[WebRTC] 🔧 Creating new peer connection...');
    final configuration = await _getConfiguration();
    _peerConnection = await createPeerConnection(configuration);
    print('[WebRTC] ✅ Peer connection created successfully');

    // Handle ICE candidates
    _peerConnection!.onIceCandidate = (candidate) {
      if (candidate.candidate != null) {
        // Extract candidate type for debugging (host/srflx/relay)
        final candStr = candidate.candidate!;
        String candType = 'unknown';
        if (candStr.contains('typ host')) candType = 'host';
        else if (candStr.contains('typ srflx')) candType = 'srflx';
        else if (candStr.contains('typ relay')) candType = 'relay';

        print('[WebRTC] 📤 Sending local ICE candidate [type: $candType]: ${candidate.candidate}');
        onSendSignal?.call(<String, dynamic>{
          'type': 'ice_candidate',
          'candidate': candidate.candidate,
          'sdpMid': candidate.sdpMid,
          'sdpMLineIndex': candidate.sdpMLineIndex,
        });
        print('[WebRTC] ✅ Local ICE candidate sent via onSendSignal callback');
      } else {
        print('[WebRTC] ⚠️ ICE candidate is null - ICE gathering may be complete');
      }
    };

    // 🔍 Handle ICE gathering state (to debug candidate collection)
    _peerConnection!.onIceGatheringState = (state) {
      print('[WebRTC] 🧊 ICE Gathering State: $state');

      // When gathering is complete, send a null candidate to signal end
      if (state == RTCIceGatheringState.RTCIceGatheringStateComplete) {
        print('[WebRTC] ✅ ICE gathering complete - signaling end of candidates');
        onSendSignal?.call(<String, dynamic>{
          'type': 'ice_candidate',
          'candidate': null, // Signal end of candidates
          'sdpMid': null,
          'sdpMLineIndex': null,
        });
      }
    };

    // 🔍 Handle ICE connection state (detailed connection progress)
    _peerConnection!.onIceConnectionState = (state) async {
      print('[WebRTC] 🧊 ICE Connection State: $state');

      // Log detailed candidate pair information when checking starts
      if (state == RTCIceConnectionState.RTCIceConnectionStateChecking) {
        print('[WebRTC] 🔍 ICE connectivity checks started - analyzing candidate pairs...');

        // TEST: No delay - query stats immediately
        print('[WebRTC] ⚡ NO DELAY - Querying stats immediately');

        try {
          final stats = await _peerConnection!.getStats();

          // Count candidates
          int localHost = 0, localSrflx = 0, localRelay = 0;
          int remoteHost = 0, remoteSrflx = 0, remoteRelay = 0;

          stats.forEach((report) {
            if (report.type == 'local-candidate') {
              final candType = report.values['candidateType'];
              if (candType == 'relay') localRelay++;
              else if (candType == 'srflx') localSrflx++;
              else if (candType == 'host') localHost++;
            } else if (report.type == 'remote-candidate') {
              final candType = report.values['candidateType'];
              if (candType == 'relay') remoteRelay++;
              else if (candType == 'srflx') remoteSrflx++;
              else if (candType == 'host') remoteHost++;
            }
          });

          print('[WebRTC] 📊 Local candidates: host=$localHost, srflx=$localSrflx, relay=$localRelay');
          print('[WebRTC] 📊 Remote candidates: host=$remoteHost, srflx=$remoteSrflx, relay=$remoteRelay');

          // Log all candidate pairs and their states
          int pairCount = 0;
          stats.forEach((report) {
            if (report.type == 'candidate-pair') {
              pairCount++;
              final state = report.values['state'];
              final localId = report.values['localCandidateId'];
              final remoteId = report.values['remoteCandidateId'];
              print('[WebRTC] 🔗 Pair #$pairCount: state=$state, local=$localId, remote=$remoteId');
            }
          });

          if (pairCount == 0) {
            print('[WebRTC] ⚠️ WARNING: No candidate pairs formed yet!');
          }
        } catch (e) {
          print('[WebRTC] ⚠️ Could not get ICE checking stats: $e');
        }
      }

      // Log when ICE fails (this is different from connection state failed)
      if (state == RTCIceConnectionState.RTCIceConnectionStateFailed) {
        print('[WebRTC] ❌ ICE checks FAILED - no candidate pair worked');

        // Get detailed stats to see what went wrong
        try {
          final stats = await _peerConnection!.getStats();
          int relayCount = 0;
          int srflxCount = 0;
          int hostCount = 0;

          stats.forEach((report) {
            if (report.type == 'local-candidate') {
              final candType = report.values['candidateType'];
              if (candType == 'relay') relayCount++;
              else if (candType == 'srflx') srflxCount++;
              else if (candType == 'host') hostCount++;
            }
          });

          print('[WebRTC] 📊 Local candidates tried: host=$hostCount, srflx=$srflxCount, relay=$relayCount');

          // Log actual relay server addresses
          if (relayCount > 0) {
            print('[WebRTC] 🌐 Relay servers allocated:');
            stats.forEach((report) {
              if (report.type == 'local-candidate' && report.values['candidateType'] == 'relay') {
                final address = report.values['address'] ?? report.values['ip'];
                final port = report.values['port'];
                final relatedAddress = report.values['relatedAddress'];
                final relatedPort = report.values['relatedPort'];
                print('[WebRTC]   - $address:$port (from $relatedAddress:$relatedPort)');
              }
            });
          } else {
            print('[WebRTC] ⚠️ WARNING: NO RELAY CANDIDATES - TURN server might be failing!');
          }

          // Log all candidate pairs and their final states
          print('[WebRTC] 🔗 Candidate pair states at failure:');
          int failedPairs = 0, waitingPairs = 0, inProgressPairs = 0, succeededPairs = 0;

          stats.forEach((report) {
            if (report.type == 'candidate-pair') {
              final state = report.values['state'];
              final nominated = report.values['nominated'];
              final localId = report.values['localCandidateId'];
              final remoteId = report.values['remoteCandidateId'];

              // Count states
              if (state == 'failed') failedPairs++;
              else if (state == 'waiting') waitingPairs++;
              else if (state == 'in-progress') inProgressPairs++;
              else if (state == 'succeeded') succeededPairs++;

              // Find candidate details
              String localType = 'unknown', localAddr = 'unknown';
              String remoteType = 'unknown', remoteAddr = 'unknown';

              stats.forEach((candReport) {
                if (candReport.id == localId) {
                  localType = candReport.values['candidateType'] ?? 'unknown';
                  localAddr = candReport.values['address'] ?? candReport.values['ip'] ?? 'unknown';
                }
                if (candReport.id == remoteId) {
                  remoteType = candReport.values['candidateType'] ?? 'unknown';
                  remoteAddr = candReport.values['address'] ?? candReport.values['ip'] ?? 'unknown';
                }
              });

              print('[WebRTC]   [$state] $localType($localAddr) <-> $remoteType($remoteAddr) ${nominated == true ? "NOMINATED" : ""}');
            }
          });

          print('[WebRTC] 📊 Pair summary: succeeded=$succeededPairs, failed=$failedPairs, in-progress=$inProgressPairs, waiting=$waitingPairs');

          // If we have succeeded pairs but still failed, something is wrong with nomination
          if (succeededPairs > 0) {
            print('[WebRTC] ⚠️ WARNING: We have succeeded pairs but ICE still failed! Nomination issue?');
          }
        } catch (e) {
          print('[WebRTC] ⚠️ Could not get ICE stats: $e');
        }
      }
      else if (state == RTCIceConnectionState.RTCIceConnectionStateClosed) {
        print('[WebRTC] 🔴 ICE connection CLOSED (connection was terminated)');
      }
      else if (state == RTCIceConnectionState.RTCIceConnectionStateConnected) {
        print('[WebRTC] ✅ ICE connection CONNECTED - at least one candidate pair working!');
        try {
          final stats = await _peerConnection!.getStats();
          stats.forEach((report) {
            if (report.type == 'candidate-pair' && (report.values['state'] == 'succeeded' || report.values['nominated'] == true)) {
              final localId = report.values['localCandidateId'];
              final remoteId = report.values['remoteCandidateId'];

              String localType = 'unknown', localAddr = 'unknown';
              String remoteType = 'unknown', remoteAddr = 'unknown';

              stats.forEach((candReport) {
                if (candReport.id == localId) {
                  localType = candReport.values['candidateType'] ?? 'unknown';
                  localAddr = candReport.values['address'] ?? candReport.values['ip'] ?? 'unknown';
                }
                if (candReport.id == remoteId) {
                  remoteType = candReport.values['candidateType'] ?? 'unknown';
                  remoteAddr = candReport.values['address'] ?? candReport.values['ip'] ?? 'unknown';
                }
              });

              print('[WebRTC] 🎯 WORKING pair: $localType($localAddr) <-> $remoteType($remoteAddr)');
            }
          });
        } catch (e) {
          print('[WebRTC] ⚠️ Could not get connection stats: $e');
        }
      }
    };

    // 🔍 Handle signaling state changes (to debug offer/answer issues)
    _peerConnection!.onSignalingState = (state) {
      print('[WebRTC] 📡 Signaling State: $state');
    };

    // Handle connection state changes
    _peerConnection!.onConnectionState = (state) async {
      print('[WebRTC] Connection state: $state');

      if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        print('[WebRTC] ✅ Setting state to CONNECTED');

        // 🔍 LOG: Which candidate pair was selected?
        try {
          final stats = await _peerConnection!.getStats();
          stats.forEach((report) {
            if (report.type == 'candidate-pair' && report.values['state'] == 'succeeded') {
              final localCandidateId = report.values['localCandidateId'];
              final remoteCandidateId = report.values['remoteCandidateId'];
              print('[WebRTC] 🎯 SELECTED candidate pair: local=$localCandidateId, remote=$remoteCandidateId');

              // Find the actual candidate details
              stats.forEach((candidateReport) {
                if (candidateReport.id == localCandidateId) {
                  final candType = candidateReport.values['candidateType'];
                  final address = candidateReport.values['address'] ?? candidateReport.values['ip'];
                  print('[WebRTC] 🎯 Local: $candType ($address)');
                }
                if (candidateReport.id == remoteCandidateId) {
                  final candType = candidateReport.values['candidateType'];
                  final address = candidateReport.values['address'] ?? candidateReport.values['ip'];
                  print('[WebRTC] 🎯 Remote: $candType ($address)');
                }
              });
            }
          });
        } catch (e) {
          print('[WebRTC] ⚠️ Could not get connection stats: $e');
        }

        _hasBeenConnected = true;
        _disconnectionTimer?.cancel();
        _disconnectionTimer = null;
        _updateCallState(CallState.connected);
      }
      else if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
        // FAILED state is permanent - end call immediately
        print('[WebRTC] ❌ Connection FAILED (permanent failure)');
        _disconnectionTimer?.cancel();
        endCall();
      }
      else if (state == RTCPeerConnectionState.RTCPeerConnectionStateClosed) {
        // CLOSED state means connection was terminated - end call immediately
        print('[WebRTC] ❌ Connection CLOSED');
        _disconnectionTimer?.cancel();
        endCall();
      }
      else if (state == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected) {
        // 🔧 FIX: DISCONNECTED can be temporary during initial connection
        // Only end call if it stays disconnected for too long
        if (_hasBeenConnected) {
          // If we were connected before, disconnection might be network issue
          print('[WebRTC] ⚠️ Connection DISCONNECTED (was previously connected) - starting 10s timeout');
          _disconnectionTimer?.cancel();
          _disconnectionTimer = Timer(const Duration(seconds: 10), () {
            print('[WebRTC] ❌ Connection stayed disconnected for 10s - ending call');
            endCall();
          });
        } else {
          // Never been connected - give it 30 seconds (for slow mobile data)
          print('[WebRTC] ⚠️ Connection DISCONNECTED (never connected) - starting 30s timeout');
          _disconnectionTimer?.cancel();
          _disconnectionTimer = Timer(const Duration(seconds: 30), () {
            print('[WebRTC] ❌ Failed to connect within 30s - ending call');
            endCall();
          });
        }
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

  /// Enable background audio mode to keep microphone active when app is minimized
  void _enableBackgroundAudio() {
    if (_localStream == null) return;

    try {
      // Enable audio track to stay active in background
      final audioTracks = _localStream!.getAudioTracks();
      for (var track in audioTracks) {
        // Keep track enabled
        track.enabled = true;
        print('[WebRTC] 🎤 Audio track configured for background mode: ${track.id}');
      }

      // Enable background mode for Android specifically
      // inCommunication mode keeps audio active during calls even when app is minimized
      Helper.setAndroidAudioConfiguration(
        AndroidAudioConfiguration(
          androidAudioMode: AndroidAudioMode.inCommunication,
          androidAudioFocusMode: AndroidAudioFocusMode.gain,
        ),
      );
      print('[WebRTC] 🎤 Android audio configuration set: inCommunication mode with focus gain');
    } catch (e) {
      print('[WebRTC] ⚠️ Error enabling background audio: $e');
    }
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

  /// Toggle speaker on/off
  bool _isSpeakerOn = false;
  bool get isSpeakerOn => _isSpeakerOn;

  Future<void> toggleSpeaker() async {
    _isSpeakerOn = !_isSpeakerOn;
    await Helper.setSpeakerphoneOn(_isSpeakerOn);
    print('[WebRTC] 🔊 Speaker ${_isSpeakerOn ? "enabled" : "disabled"}');
  }

  /// Enable speaker (useful for auto-enabling on call start)
  Future<void> enableSpeaker(bool enable) async {
    _isSpeakerOn = enable;
    await Helper.setSpeakerphoneOn(enable);
    print('[WebRTC] 🔊 Speaker ${enable ? "enabled" : "disabled"}');
  }

  /// End the call and cleanup resources
  Future<void> endCall() async {
    print('[WebRTC] 🛑 endCall() called - Stack trace:');
    print(StackTrace.current);

    // 🔧 FIX: Cancel disconnection timer and reset connection flag
    _disconnectionTimer?.cancel();
    _disconnectionTimer = null;
    _hasBeenConnected = false;
    _remoteDescriptionSet = false;  // 🔧 FIX: Reset for next call
    _iceCandidates.clear();  // 🔧 FIX: Clear any buffered candidates

    // Close and dispose peer connection properly
    if (_peerConnection != null) {
      // Remove all event handlers first
      _peerConnection!.onIceCandidate = null;
      _peerConnection!.onIceGatheringState = null;
      _peerConnection!.onIceConnectionState = null;
      _peerConnection!.onSignalingState = null;
      _peerConnection!.onConnectionState = null;
      _peerConnection!.onTrack = null;

      // Close the connection
      await _peerConnection!.close();

      // Dispose it
      await _peerConnection!.dispose();
      _peerConnection = null;

      print('[WebRTC] ✅ Peer connection fully disposed');
    }

    // Stop and dispose local stream
    _localStream?.getTracks().forEach((track) {
      track.stop();
    });
    await _localStream?.dispose();
    _localStream = null;
    if (!_localStreamController.isClosed) {
      _localStreamController.add(null);
    }

    // Dispose remote stream
    await _remoteStream?.dispose();
    _remoteStream = null;
    if (!_remoteStreamController.isClosed) {
      _remoteStreamController.add(null);
    }

    // Clear buffered candidates
    _iceCandidates.clear();

    _updateCallState(CallState.ended);

    print('[WebRTC] ✅ All resources cleaned up');

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

  /// Clear cached TURN configuration (call on logout)
  void clearTurnCache() {
    _cachedConfiguration = null;
    TurnService.clearCache();
    print('[WebRTC] TURN cache cleared');
  }

  void dispose() {
    _callStateController.close();
    _remoteStreamController.close();
    _localStreamController.close();
    clearTurnCache();
    endCall();
  }
}
