import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class WebSocketService with ChangeNotifier {
  WebSocketChannel? _channel;
  bool _isConnected = false;
  String? _lastToken;
  StreamSubscription? _streamSubscription; // To keep track of the listener

  final StreamController<dynamic> _streamController = StreamController<dynamic>.broadcast();

  Stream<dynamic> get stream => _streamController.stream;
  WebSocketChannel? get channel => _channel;
  bool get isConnected => _isConnected;

  /// Connects to the WebSocket server. Returns a Future that completes
  /// when the connection is established or fails definitively.
  Future<void> connect(String? token) async {
    // If we are already connected with the same token, do nothing.
    if (_isConnected && _channel != null && token == _lastToken) {
      print("[WebSocketService] Already connected. No action needed.");
      return;
    }

    // If we are trying to connect with a new user (different token),
    // we must first perform a full disconnect.
    if (_isConnected || _channel != null) {
      print("[WebSocketService] A new connection was requested. Disconnecting the old one first...");
      await disconnect(); // Ensure a clean state before reconnecting
    }
    
    if (token == null) {
      print("[WebSocketService] Connection attempted with no token.");
      return;
    }

    _lastToken = token;
    print("[WebSocketService] Attempting to connect...");

    final completer = Completer<void>();

    try {
      final String host = kIsWeb ? 'ws://192.168.29.81:8080/ws' : 'ws://192.168.29.81:8080/ws';
      final uri = Uri.parse('$host?token=$token');
      _channel = WebSocketChannel.connect(uri);

      // We use a local variable for the subscription to avoid race conditions.
      final subscription = _channel!.stream.listen(
        (message) {
          // The first message received confirms the connection is successful.
          if (!_isConnected) {
            _isConnected = true;
            print("[WebSocketService] Connection established.");
            notifyListeners();
            if (!completer.isCompleted) {
              completer.complete();
            }
          }
          _streamController.add(message);
        },
        onDone: () {
          print("[WebSocketService] Connection closed by server (onDone).");
          if (!completer.isCompleted) {
            completer.completeError(Exception("Connection closed before it could be established."));
          }
          _handleDisconnection();
        },
        onError: (error) {
          print("[WebSocketService] WebSocket error: $error");
          if (!completer.isCompleted) {
            completer.completeError(error);
          }
          _handleDisconnection();
        },
        cancelOnError: true, // Important: automatically cancel subscription on error.
      );

      // Store the subscription so we can cancel it later.
      _streamSubscription = subscription;

    } catch (e) {
      print("[WebSocketService] Failed to connect: $e");
      if (!completer.isCompleted) {
        completer.completeError(e);
      }
      _handleDisconnection();
    }

    return completer.future;
  }

  void _handleDisconnection() {
    if (!_isConnected) return; // Prevent multiple disconnection calls
    
    print("[WebSocketService] Handling disconnection...");
    _isConnected = false;
    // We don't need to close the sink here, as the onDone/onError already implies it's closed.
    notifyListeners();
  }

  /// Performs a full and clean disconnection and reset of the service.
  Future<void> disconnect() async {
    print("[WebSocketService] Disconnecting and resetting state...");
    _lastToken = null;
    
    // --- THE FIX IS HERE: We cancel the old stream subscription ---
    await _streamSubscription?.cancel();
    _streamSubscription = null;
    // -----------------------------------------------------------

    await _channel?.sink.close();
    _channel = null;

    if (_isConnected) {
      _isConnected = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    disconnect();
    _streamController.close();
    super.dispose();
  }
}
