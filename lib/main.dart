import 'dart:async';
import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zarq_messenger/SignalTestPage.dart';
import 'package:zarq_messenger/app_theme.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:zarq_messenger/services/SignalService.dart';
import 'package:zarq_messenger/services/key_rotation_service.dart';

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
  await FirebaseAuth.instance.authStateChanges().first;

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
        '/signal_test': (context) => const SignalTestPage(), // Add Signal test route
        '/chat': (context) {
          final args = ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;

          if (args != null) {
            final conversationId = args['conversation_id'] as int?;
            print('[Route] Notification navigation to conversation: $conversationId');

            if (conversationId != null) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                Navigator.of(context).pushReplacementNamed('/home_with_conversation',
                    arguments: {'target_conversation_id': conversationId});
              });
            }
          }

          return const HomeScreen();
        },
        '/home_with_conversation': (context) {
          return const HomeScreen();
        },
      },
      // Handle unknown routes
      onUnknownRoute: (settings) {
        print('[Navigation] Unknown route: ${settings.name}');
        return MaterialPageRoute(
          builder: (context) => const SignalTestPage(),
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
    KeyRotationService.startBackgroundRotation();
    print("[AuthWrapper] initState: Starting user initialization.");
    _initializationFuture = _initializeUserServices();
  }

  /// Test Signal Protocol connection - Updated for current implementation
  Future<bool> _testSignalProtocol() async {
    try {
      print("[AuthWrapper] Testing Signal Protocol connection...");

      // Test basic method channel connection
      final pingResult = await platform.invokeMethod('ping');
      print("[AuthWrapper] Signal ping result: $pingResult");

      if (pingResult == 'Signal pong') {
        print("[AuthWrapper] Signal Protocol method channel is working!");
        return true;
      } else {
        print("[AuthWrapper] Signal Protocol method channel failed");
        return false;
      }
    } catch (e) {
      print("[AuthWrapper] Signal Protocol test failed: $e");
      return false;
    }
  }

  Future<bool> _checkExistingKeys() async {
    try {
      print("[AuthWrapper] Checking for existing Signal Protocol keys...");
      final hasKeys = await SignalService.hasKeys();
      print("[AuthWrapper] Existing keys check: $hasKeys");
      return hasKeys;
    } catch (e) {
      print("[AuthWrapper] Error checking existing keys: $e");
      return false;
    }
  }

  /// Placeholder for future Signal key generation
  Future<Map<String, dynamic>?> _generateSignalKeysIfNeeded() async {
    try {
      // First check if keys already exist
      final hasKeys = await _checkExistingKeys();
      if (hasKeys) {
        print("[AuthWrapper] Keys already exist, skipping generation");
        return null; // No new keys generated
      }

      print("[AuthWrapper] No existing keys found, generating new ones...");
      final keyBundle = await SignalService.generateKeyBundle();

      if (keyBundle != null) {
        print("[AuthWrapper] Successfully generated new keys:");
        print("  - Registration ID: ${keyBundle['registration_id']}");
        print("  - Signed PreKey ID: ${keyBundle['signed_prekey_id']}");
        print("  - Identity Key: ${keyBundle['identity_key_b64']?.toString().substring(0, 30)}...");
        print("  - One-Time PreKeys: ${(keyBundle['one_time_prekeys'] as List?)?.length ?? 0}");
        return keyBundle;
      } else {
        throw Exception('Key bundle generation returned null');
      }
    } catch (e) {
      print("[AuthWrapper] Key generation failed: $e");
      throw Exception('Signal key generation failed: $e');
    }
  }

// Check if user is already fully initialized - UPDATED
  Future<bool> _isUserAlreadyInitialized() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final isInitialized = prefs.getBool('user_${widget.user.uid}_initialized') ?? false;

      // UPDATED: Also check if Signal keys exist
      final hasKeys = await _checkExistingKeys();

      final fullyInitialized = isInitialized && hasKeys;
      print('[AuthWrapper] User initialization status: app_initialized=$isInitialized, signal_keys=$hasKeys, fully_initialized=$fullyInitialized');

      return fullyInitialized;
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

        await Future.delayed(Duration(milliseconds: 100));
        print("[AuthWrapper] Current user before DB init: ${widget.user.uid}");
        await dbService.init();

        // Check server profile quickly
        final profileExists = await _checkIfProfileExists();
        if (!profileExists) {
          return false;
        }

        // Test Signal Protocol connection
        await _testSignalProtocol();

        // Connect WebSocket
        final token = await widget.user.getIdToken(true);
        await websocketService.connect(token);

        // Mark undelivered messages as delivered on login
        print("=== [AuthWrapper] Marking undelivered messages as delivered ===");
        await _markUndeliveredMessagesAsDelivered(websocketService, dbService);

        // Quick sync of recent messages only
        await _fetchOfflineMessages();

        print("[AuthWrapper] Fast initialization completed");
        return true;
      }

      // Full initialization for new users or after logout
      print("=== [AuthWrapper] FULL INITIALIZATION ===");

      // Step 1: Initialize the database service
      print("=== [AuthWrapper] STEP 1: Initializing database service ===");
      await Future.delayed(Duration(milliseconds: 100));
      print("[AuthWrapper] Current user before DB init: ${widget.user.uid}");
      await dbService.init();

      // Step 2: Check if the user has a profile on the server FIRST
      print("=== [AuthWrapper] STEP 2: Checking server profile ===");
      final profileExists = await _checkIfProfileExists();
      if (!profileExists) {
        return false;
      }

      // Step 3: Initialize notifications AFTER profile exists
      print("=== [AuthWrapper] STEP 3: Initializing notifications ===");

      // Step 4: Generate Signal Protocol keys (UPDATED)
      print("=== [AuthWrapper] STEP 4: Managing Signal Protocol keys ===");
      final newKeyBundle = await _generateSignalKeysIfNeeded();

// Step 5: Register device with backend (UPDATED - now actually registers)
      if (newKeyBundle != null) {
        print("=== [AuthWrapper] STEP 5: Registering device with new keys ===");

        try {
          final oneTimeKeys = newKeyBundle['one_time_prekeys'] as List<dynamic>? ?? [];

          // Convert to the format expected by DeviceService
          final formattedOneTimeKeys = oneTimeKeys.map((key) => {
            'key_id': key['key_id'],
            'public_key_b64': key['public_key_b64'],
          }).toList();

          print("[AuthWrapper] Uploading ${formattedOneTimeKeys.length} one-time keys to server...");

          await DeviceService.registerDevice(
            deviceId: newKeyBundle['device_id'] as int,
            deviceName: 'Flutter Device',
            platform: 'android',
            pushToken: '', // FCM token will be uploaded separately
            identityKeyB64: newKeyBundle['identity_key_b64'] as String,
            registrationId: newKeyBundle['registration_id'] as int,
            signedPreKeyId: newKeyBundle['signed_prekey_id'] as int,
            signedPreKeyB64: newKeyBundle['signed_prekey_b64'] as String,
            signedPreKeySignatureB64: newKeyBundle['signed_prekey_signature_b64'] as String,
            oneTimePreKeys: formattedOneTimeKeys,
          );

          print("[AuthWrapper] Device registration successful!");

        } catch (e) {
          print("[AuthWrapper] Device registration failed: $e");
          // Don't throw - we can continue without backend registration for now
          print("[AuthWrapper] Continuing with local keys only...");
        }
      } else {
        print("=== [AuthWrapper] STEP 5: Using existing keys (no registration needed) ===");
        print("[AuthWrapper] Keys already exist on server, skipping registration");
      }

      // Step 6: Connect to the WebSocket
      print("=== [AuthWrapper] STEP 6: Connecting to WebSocket ===");
      final token = await widget.user.getIdToken(true);
      await websocketService.connect(token);

      await _uploadFCMTokenToServer();

// Step 7: Sync missed messages
      print("=== [AuthWrapper] STEP 7: Syncing missed messages ===");
// For now, skip encryption-dependent message sync
// TODO: Re-enable when session management is implemented
// await _fetchOfflineMessages();
      print("[AuthWrapper] Message sync temporarily skipped - encryption not ready");

// Mark user as fully initialized
      print("=== [AuthWrapper] FINAL: Marking user as fully initialized ===");
      await _markUserAsInitialized();

      final finalCheck = await _isUserAlreadyInitialized();
      print("[AuthWrapper] Final initialization verification: $finalCheck");

      if (finalCheck) {
        print("[AuthWrapper] ✅ Full initialization completed successfully!");
        print("[AuthWrapper] User has: Firebase Auth ✓ Signal Keys ✓ Backend Registration ✓");
      } else {
        print("[AuthWrapper] ⚠️ Initialization completed but verification failed");
      }

      print("[AuthWrapper] User ready for secure messaging.");
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

      // Get FCM token from Kotlin
      const utilityChannel = MethodChannel('com.zarq/utility');
      final fcmToken = await utilityChannel.invokeMethod('getFCMToken');

      if (fcmToken != null && fcmToken.isNotEmpty) {
        print("[AuthWrapper] Uploading FCM token to server: ${fcmToken.substring(0, 20)}...");

        // Get actual device ID
        final actualDeviceId = await SignalService.getDeviceId();
        print("[AuthWrapper] Using device ID: $actualDeviceId");

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
            'device_id': actualDeviceId,  // ← Fixed
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

  Future<void> _fetchOfflineMessages() async {
    try {
      print("[OFFLINE] Fetching offline messages (encryption skipped for now)...");

      // For now, just log that we would fetch messages
      // TODO: Implement when Signal Protocol encryption is ready
      print("[OFFLINE] Message fetching temporarily disabled - waiting for Signal Protocol implementation");

    } catch (e) {
      print("[OFFLINE] Fetch failed: $e");
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
                  SizedBox(height: 8),
                  Text("Testing Signal Protocol setup...",
                      style: TextStyle(fontSize: 12, color: Colors.grey)),
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
                      onPressed: () => Navigator.pushNamed(context, '/signal_test'),
                      child: const Text("Test Signal Protocol"),
                    ),
                    const SizedBox(height: 10),
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