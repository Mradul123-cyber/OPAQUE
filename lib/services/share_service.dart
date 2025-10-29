import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class SharedContent {
  final String type; // 'text', 'image', 'video', 'file', 'images', 'videos'
  final String? text;
  final String? subject;
  final String? uri;
  final List<String>? uris;
  final String? mimeType;

  SharedContent({
    required this.type,
    this.text,
    this.subject,
    this.uri,
    this.uris,
    this.mimeType,
  });

  factory SharedContent.fromMap(Map<dynamic, dynamic> map) {
    return SharedContent(
      type: map['type'] as String,
      text: map['text'] as String?,
      subject: map['subject'] as String?,
      uri: map['uri'] as String?,
      uris: map['uris'] != null
          ? List<String>.from(map['uris'] as List)
          : null,
      mimeType: map['mimeType'] as String?,
    );
  }

  bool get isSingleMedia => type == 'image' || type == 'video' || type == 'file';
  bool get isMultipleMedia => type == 'images' || type == 'videos';
  bool get isText => type == 'text';
}

class ShareService {
  static const MethodChannel _channel = MethodChannel('com.zarq/share');

  // Stream controller for shared content
  static final StreamController<SharedContent> _sharedContentController =
      StreamController<SharedContent>.broadcast();

  // Buffer for content received before listener is ready
  static SharedContent? _bufferedContent;
  static bool _hasListener = false;

  // Stream for listening to shared content
  static Stream<SharedContent> get sharedContentStream {
    // Mark that we have a listener
    _hasListener = true;

    // If there's buffered content, emit it immediately
    if (_bufferedContent != null) {
      final content = _bufferedContent!;
      _bufferedContent = null;
      debugPrint('ShareService: Emitting buffered content: ${content.type}');
      Future.microtask(() => _sharedContentController.add(content));
    }

    return _sharedContentController.stream;
  }

  // Initialize the share service
  static Future<void> initialize() async {
    debugPrint('ShareService: Initializing...');

    // Set up method call handler to receive shared content from Kotlin
    _channel.setMethodCallHandler(_handleMethodCall);

    // DON'T check for pending content here - will be checked after listener is set up

    debugPrint('ShareService: Initialized (pending content check deferred)');
  }

  // Handle method calls from Kotlin
  static Future<dynamic> _handleMethodCall(MethodCall call) async {
    debugPrint('ShareService: Received method call: ${call.method}');

    switch (call.method) {
      case 'handleSharedContent':
        final Map<dynamic, dynamic>? args = call.arguments as Map<dynamic, dynamic>?;
        if (args != null) {
          debugPrint('ShareService: Received shared content: $args');
          final sharedContent = SharedContent.fromMap(args);

          if (_hasListener) {
            debugPrint('ShareService: Listener exists, emitting immediately');
            _sharedContentController.add(sharedContent);
          } else {
            debugPrint('ShareService: No listener yet, buffering content');
            _bufferedContent = sharedContent;
          }

          return 'success';
        }
        return 'no_data';

      default:
        debugPrint('ShareService: Unknown method: ${call.method}');
        throw PlatformException(
          code: 'NOT_IMPLEMENTED',
          message: 'Method ${call.method} not implemented',
        );
    }
  }

  // Check for pending shared content on app start
  static Future<void> checkForPendingSharedContent() async {
    try {
      debugPrint('ShareService: Checking for pending shared content...');
      final result = await _channel.invokeMethod('getSharedContent');

      if (result != null && result is Map) {
        debugPrint('ShareService: Found pending shared content: $result');
        final sharedContent = SharedContent.fromMap(result as Map<dynamic, dynamic>);
        _sharedContentController.add(sharedContent);
      } else {
        debugPrint('ShareService: No pending shared content');
      }
    } catch (e) {
      debugPrint('ShareService: Error checking for pending shared content: $e');
    }
  }

  // Dispose the service
  static void dispose() {
    _sharedContentController.close();
  }
}
