import 'dart:async';
import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zarq_messenger/app_theme.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

import 'firebase_options.dart';
import 'home_screen.dart';
import 'login_screen.dart';
import 'message_model.dart';
import 'providers/chat_provider.dart';
import 'providers/home_provider.dart';
import 'register_screen.dart';
import 'services/conversation_service.dart';
import 'services/database_service.dart';
import 'services/websocket_service.dart';
import 'theme_notifier.dart';
import 'services/device_service.dart';
import 'services/sent_message_service.dart';
import 'chat_screen.dart';

// Import the NavigationHandler
import 'services/navigation_handler.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  SentMessageService.initialize();

  final databaseService = DatabaseService.instance;

  runApp(
    MultiProvider(
      providers: [
        Provider<DatabaseService>.value(value: databaseService),
        Provider<ConversationService>(create: (_) => ConversationService()),
        ChangeNotifierProvider(create: (_) => WebSocketService()),
        ChangeNotifierProvider(create: (_) => ChatProvider()),
        ChangeNotifierProvider(create: (_) => ThemeNotifier()),
        ChangeNotifierProxyProvider2<ConversationService, WebSocketService, HomeProvider>(
          create: (context) => HomeProvider(
            conversationService: Provider.of<ConversationService>(context, listen: false),
            webSocketService: Provider.of<WebSocketService>(context, listen: false),
          ),
          update: (_, conversationService, webSocketService, homeProvider) =>
          homeProvider!..updateServices(conversationService, webSocketService),
        ),
      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  static final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  @override
  Widget build(BuildContext context) {
    // Initialize navigation handler for Kotlin communication
    NavigationHandler.initialize(navigatorKey);

    return MaterialApp(
      title: 'Zarq Messenger',
      theme: zarqDarkTheme,
      navigatorKey: navigatorKey,
      home: const AuthGate(),
      // Add routes for navigation from notifications
      routes: {
        '/chat': (context) {
          // For notification navigation, we need to redirect to HomeScreen
          // and let it handle the conversation opening
          final args = ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;

          if (args != null) {
            final conversationId = args['conversation_id'] as int?;
            print('[Route] Notification navigation to conversation: $conversationId');

            // Store the target conversation ID for HomeScreen to handle
            if (conversationId != null) {
              // You can use a global variable, SharedPreferences, or Provider to communicate this
              // For now, let's redirect to HomeScreen and handle navigation there
              WidgetsBinding.instance.addPostFrameCallback((_) {
                // Trigger navigation in HomeScreen after it loads
                Navigator.of(context).pushReplacementNamed('/home_with_conversation',
                    arguments: {'target_conversation_id': conversationId});
              });
            }
          }

          return const HomeScreen();
        },
        '/home_with_conversation': (context) {
          // This route tells HomeScreen to open a specific conversation
          return const HomeScreen();
        },
      },
      // Handle unknown routes
      onUnknownRoute: (settings) {
        print('[Navigation] Unknown route: ${settings.name}');
        return MaterialPageRoute(
          builder: (context) => const HomeScreen(),
        );
      },
    );
  }
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }

        if (snapshot.hasData) {
          return AuthWrapper(
            key: ValueKey(snapshot.data!.uid),
            user: snapshot.data!,
          );
        }

        return const LoginScreen();
      },
    );
  }
}

class AuthWrapper extends StatefulWidget {
  final User user;
  const AuthWrapper({super.key, required this.user});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  late Future<bool> _initializationFuture;
  static const platform = MethodChannel('com.zarq/signal');

  @override
  void initState() {
    super.initState();
    print("[AuthWrapper] initState: Starting user initialization.");
    _initializationFuture = _initializeUserServices();
  }

  /// Check if Signal Protocol keys already exist
  Future<bool> _checkExistingKeys() async {
    try {
      print("[AuthWrapper] Checking for existing Signal Protocol keys...");
      final result = await platform.invokeMethod('hasKeys');
      final hasKeys = result == true;
      print("[AuthWrapper] Existing keys check: $hasKeys");
      return hasKeys;
    } catch (e) {
      print("[AuthWrapper] Error checking existing keys: $e");
      return false;
    }
  }

  /// Generate Signal Protocol keys only if they don't exist
  Future<Map<String, dynamic>?> _generateSignalKeysIfNeeded() async {
    try {
      // First check if keys already exist
      final hasKeys = await _checkExistingKeys();
      if (hasKeys) {
        print("[AuthWrapper] Keys already exist, skipping generation");
        return null; // No new keys generated
      }

      print("[AuthWrapper] No existing keys found, generating new ones...");
      final result = await platform.invokeMethod('generateKeyBundle');
      print("[AuthWrapper] Successfully generated new keys: ${result.keys.join(', ')}");
      return Map<String, dynamic>.from(result);
    } catch (e) {
      print("[AuthWrapper] Key generation failed: $e");
      throw Exception('Signal key generation failed: $e');
    }
  }

  // Check if user is already fully initialized
  Future<bool> _isUserAlreadyInitialized() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final isInitialized = prefs.getBool('user_${widget.user.uid}_initialized') ?? false;

      // Also check if Signal keys exist
      final hasKeys = await _checkExistingKeys();

      return isInitialized && hasKeys;
    } catch (e) {
      print('[AuthWrapper] Error checking initialization status: $e');
      return false;
    }
  }

  // Mark user as initialized
  Future<void> _markUserAsInitialized() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('user_${widget.user.uid}_initialized', true);
    } catch (e) {
      print('[AuthWrapper] Error marking user as initialized: $e');
    }
  }

  // Mark undelivered messages as delivered on app login
  Future<void> _markUndeliveredMessagesAsDelivered(WebSocketService websocketService, DatabaseService dbService) async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) return;

      // Get all messages where user is recipient and status is still 'sent'
      final db = dbService.database;

      final undeliveredMessages = await dbService.getAllUndeliveredMessages(currentUser.uid);

      for (final message in undeliveredMessages) {
        await websocketService.sendStatusUpdate(
          messageId: message.id,
          status: 'delivered',
          conversationId: message.conversationId,
        );

        await dbService.updateMessageStatus(message.id, MessageStatus.delivered);
        print("Marked message ${message.id} as delivered on app login");
      }

      if (undeliveredMessages.isNotEmpty) {
        print("Marked ${undeliveredMessages.length} messages as delivered");
      }
    } catch (e) {
      print("Error marking undelivered messages: $e");
    }
  }

  Future<bool> _initializeUserServices() async {
    try {
      final dbService = Provider.of<DatabaseService>(context, listen: false);
      final websocketService = Provider.of<WebSocketService>(context, listen: false);

      // Quick check - if user is already initialized, skip most steps
      print("=== [AuthWrapper] QUICK CHECK: Is user already initialized? ===");
      final alreadyInitialized = await _isUserAlreadyInitialized();

      if (alreadyInitialized) {
        print("User already initialized - doing fast startup");

        // Only do essential steps for fast startup
        await dbService.init();

        // Check server profile quickly
        final profileExists = await _checkIfProfileExists();
        if (!profileExists) {
          return false;
        }

        // Connect WebSocket
        final token = await widget.user.getIdToken(true);
        await websocketService.connect(token);

        // Mark undelivered messages as delivered on login
        print("=== [AuthWrapper] Marking undelivered messages as delivered ===");
        await _markUndeliveredMessagesAsDelivered(websocketService, dbService);

        // Quick sync of recent messages only
        await _syncRecentMessages();

        print("[AuthWrapper] Fast initialization completed");
        return true;
      }

      // Full initialization for new users or after logout
      print("=== [AuthWrapper] FULL INITIALIZATION ===");

      // Step 1: Initialize the database service
      print("=== [AuthWrapper] STEP 1: Initializing database service ===");
      await dbService.init();

      // Step 2: Check if the user has a profile on the server FIRST
      print("=== [AuthWrapper] STEP 2: Checking server profile ===");
      final profileExists = await _checkIfProfileExists();
      if (!profileExists) {
        return false;
      }

      // Step 3: Initialize notifications AFTER profile exists
      print("=== [AuthWrapper] STEP 3: Initializing notifications ===");

      // Step 4: Check and conditionally generate Signal Protocol keys
      print("=== [AuthWrapper] STEP 4: Managing Signal Protocol keys ===");
      final newKeyBundle = await _generateSignalKeysIfNeeded();

      // Step 5: Register device with backend (only if new keys were generated)
      if (newKeyBundle != null) {
        print("=== [AuthWrapper] STEP 5: Registering device with new keys ===");
        final oneTimeKeys = newKeyBundle['one_time_prekeys'] as List<dynamic>? ?? [];

        await DeviceService.registerDevice(
          deviceId: 1,
          deviceName: 'Flutter Device',
          platform: 'flutter',
          pushToken: '', // Use actual FCM token
          identityKeyB64: newKeyBundle['identity_key_b64'] as String,
          registrationId: newKeyBundle['registration_id'] as int,
          signedPreKeyId: newKeyBundle['signed_prekey_id'] as int,
          signedPreKeyB64: newKeyBundle['signed_prekey_b64'] as String,
          signedPreKeySignatureB64: newKeyBundle['signed_prekey_signature_b64'] as String,
          oneTimePreKeys: oneTimeKeys.map((key) => Map<String, dynamic>.from(key)).toList(),
        );
      }

      // Step 6: Connect to the WebSocket
      print("=== [AuthWrapper] STEP 6: Connecting to WebSocket ===");
      final token = await widget.user.getIdToken(true);
      await websocketService.connect(token);

      await _uploadFCMTokenToServer();

      // Step 7: Full sync of missed messages
      print("=== [AuthWrapper] STEP 7: Syncing missed messages ===");
      await _syncMissedMessages();

      // Mark user as fully initialized
      await _markUserAsInitialized();

      print("[AuthWrapper] Full initialization completed successfully.");
      return true;
    } catch (e, st) {
      print("[AuthWrapper] Initialization FAILED: $e\n$st");
      rethrow;
    }
  }

  Future<void> _uploadFCMTokenToServer() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      // Get FCM token from Kotlin - use same channel as Signal methods
      const platform = MethodChannel('com.zarq/signal');
      final fcmToken = await platform.invokeMethod('getFCMToken');

      if (fcmToken != null && fcmToken.isNotEmpty) {
        print("[AuthWrapper] Uploading FCM token to server: ${fcmToken.substring(0, 20)}...");

        final token = await user.getIdToken();
        final url = Uri.parse('http://192.168.29.81:8080/v1/fcm/token');

        final response = await http.post(
          url,
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'fcm_token': fcmToken,
            'device_id': 1,
            'platform': 'android',
          }),
        );

        if (response.statusCode == 200) {
          print("[AuthWrapper] FCM token uploaded successfully");
        } else {
          print("[AuthWrapper] FCM token upload failed: ${response.statusCode} - ${response.body}");
        }
      } else {
        print("[AuthWrapper] No FCM token available yet");
      }
    } catch (e) {
      print("[AuthWrapper] Error uploading FCM token: $e");
    }
  }

  // Quick sync for fast startup (last 2 hours only)
  Future<void> _syncRecentMessages() async {
    try {
      // Only sync messages from last 2 hours for fast startup
      final since = DateTime.now().subtract(Duration(hours: 2));
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final token = await user.getIdToken();
      final url = Uri.parse('http://192.168.29.81:8080/v1/messages/missed?since=${since.toUtc().toIso8601String()}');

      final response = await http.get(url, headers: {'Authorization': 'Bearer $token'});

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final messages = data['messages'] as List;

        for (var msgData in messages) {
          await _processMissedMessage(msgData);
        }
      }
    } catch (e) {
      print('Quick sync failed: $e');
    }
  }

  Future<void> _syncMissedMessages() async {
    try {
      print("[SYNC] Starting missed message sync...");

      final lastSync = await _getLastSyncTimestamp();
      print("[SYNC] Last sync timestamp: $lastSync");

      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        print("[SYNC] No authenticated user, skipping sync");
        return;
      }

      final token = await user.getIdToken();
      if (token == null) {
        print("[SYNC] Failed to get ID token, skipping sync");
        return;
      }

      final url = Uri.parse('http://192.168.29.81:8080/v1/messages/missed?since=${lastSync.toUtc().toIso8601String()}');

      print("[SYNC] Making request to: $url");
      print("[SYNC] Request headers: Authorization: Bearer ${token.substring(0, token.length > 50 ? 50 : token.length)}...");

      final response = await http.get(url, headers: {'Authorization': 'Bearer $token'});

      print("[SYNC] Server response status: ${response.statusCode}");
      print("[SYNC] Server response body: ${response.body}");

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        print("[SYNC] Parsed response data: $data");

        final messages = data['messages'] as List?;
        print("[SYNC] Number of missed messages found: ${messages?.length ?? 0}");

        if (messages != null && messages.isNotEmpty) {
          print("[SYNC] Processing ${messages.length} missed messages...");

          for (int i = 0; i < messages.length; i++) {
          for (int i = 0; i < messages.length; i++) {
            final msgData = messages[i];
            print("[SYNC] Processing message ${i + 1}/${messages.length}: $msgData");
            await _processMissedMessage(msgData);
          }

          print("[SYNC] All missed messages processed successfully");
          await _updateLastSyncTimestamp(DateTime.now());
          print("[SYNC] Sync timestamp updated");
        }
        } else {
          print("[SYNC] No missed messages found");
        }
      } else {
        print("[SYNC] Server error: ${response.statusCode} - ${response.body}");
      }
    } catch (e, stackTrace) {
      print("[SYNC] Sync failed with error: $e");
      print("[SYNC] Stack trace: $stackTrace");
    }
  }

  Future<DateTime> _getLastSyncTimestamp() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final timestampString = prefs.getString('last_sync_timestamp');
      if (timestampString != null) {
        return DateTime.parse(timestampString);
      }
    } catch (e) {
      print('Error getting last sync timestamp: $e');
    }
    // Default to 30 days ago instead of 24 hours
    return DateTime.now().subtract(Duration(days: 30));
  }

  Future<void> _updateLastSyncTimestamp(DateTime timestamp) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('last_sync_timestamp', timestamp.toIso8601String());
    } catch (e) {
      print('Error updating last sync timestamp: $e');
    }
  }

  Future<void> _processMissedMessage(Map<String, dynamic> msgData) async {
    try {
      final messageId = msgData['message_id'] as int;
      final conversationId = msgData['conversation_id'] as int;
      final senderUid = msgData['sender_uid'] as String;
      final senderUsername = msgData['sender_username'] as String;
      final contentB64 = msgData['content_b64'] as String;
      final createdAt = msgData['created_at'] as String;
      final senderDeviceId = msgData['sender_device_id'] as int? ?? 1;

      // Decrypt the message content
      String decryptedContent;
      try {
        final result = await platform.invokeMethod('decryptMessage', {
          'myUid': widget.user.uid,
          'senderUid': senderUid,
          'ciphertextB64': contentB64,
          'senderDeviceId': senderDeviceId,
        });
        decryptedContent = result as String;
      } catch (e) {
        print('Decryption failed for missed message, using base64 decode: $e');
        decryptedContent = utf8.decode(base64Decode(contentB64));
      }

      // Save to local database
      final dbService = Provider.of<DatabaseService>(context, listen: false);
      final message = Message(
        id: messageId,
        conversationId: conversationId,
        username: senderUsername,
        content: decryptedContent,
        timestamp: DateTime.parse(createdAt),
        senderUid: senderUid,
        status: MessageStatus.sent,
      );

      await dbService.insertMessage(message);
      print('Missed message processed and saved: $decryptedContent');

    } catch (e) {
      print('Error processing missed message: $e');
    }
  }

  Future<bool> _checkIfProfileExists() async {
    final token = await widget.user.getIdToken(true);
    final url = Uri.parse('http://192.168.29.81:8080/profiles/me');
    final response = await http.get(url, headers: {'Authorization': 'Bearer $token'});
    return response.statusCode == 200;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _initializationFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text("Initializing secure messaging..."),
                ],
              ),
            ),
          );
        }

        if (snapshot.hasError) {
          return Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.error, size: 64, color: Colors.red),
                    SizedBox(height: 16),
                    Text("Initialization Failed:\n${snapshot.error}",
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.red)),
                    const SizedBox(height: 20),
                    ElevatedButton(
                      onPressed: () => FirebaseAuth.instance.signOut(),
                      child: const Text("Log Out"),
                    )
                  ],
                ),
              ),
            ),
          );
        }

        final bool isReady = snapshot.data ?? false;
        if (isReady) {
          return const HomeScreen();
        } else {
          return RegisterScreen(
            user: widget.user,
            onRegistrationComplete: () {
              setState(() {
                print("[AuthWrapper] onRegistrationComplete triggered. Re-initializing...");
                _initializationFuture = _initializeUserServices();
              });
            },
          );
        }
      },
    );
  }
}