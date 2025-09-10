import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:zarq_messenger/app_theme.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

import 'firebase_options.dart';
import 'home_screen.dart';
import 'login_screen.dart';
import 'providers/chat_provider.dart';
import 'providers/home_provider.dart';
import 'register_screen.dart';
import 'services/conversation_service.dart';
import 'services/database_service.dart';
import 'services/websocket_service.dart';
import 'theme_notifier.dart';
import 'services/device_service.dart';


void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform, // from firebase_options.dart
  );

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

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Zarq Messenger',
      theme: zarqDarkTheme,
      home: const AuthGate(),
    );
  }
}

/// The AuthGate remains the single source of truth for authentication state.
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
          // User is logged in, show the AuthWrapper which handles initialization.
          return AuthWrapper(
            key: ValueKey(snapshot.data!.uid),
            user: snapshot.data!,
          );
        }

        // User is logged out.
        return const LoginScreen();
      },
    );
  }
}

/// This widget now contains the FINAL CORRECTED initialization logic.
class AuthWrapper extends StatefulWidget {
  final User user;
  const AuthWrapper({super.key, required this.user});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  late Future<bool> _initializationFuture;

  @override
  void initState() {
    super.initState();
    print("[AuthWrapper] initState: Starting user initialization.");
    _initializationFuture = _initializeUserServices();
  }

  // --- THIS IS THE CORRECTED INITIALIZATION FUNCTION ---
Future<bool> _initializeUserServices() async {
    // If running on Web, skip sqflite/sqlcipher native init (plugin not available on web)
  final bool runningOnWeb = kIsWeb;
  if (runningOnWeb) {
    print('⚠️ Running on Web: will skip native sqflite/sqlcipher initialization and continue.');
  }

  try {
    final dbService = Provider.of<DatabaseService>(context, listen: false);
    final websocketService = Provider.of<WebSocketService>(context, listen: false);

    // Step 1: Initialize the database service
    print("=== [AuthWrapper] STEP 1: Initializing database service ===");
    if (!runningOnWeb) {
      try {
        await dbService.init();
        print("✅ Database initialized successfully.");
      } catch (dbErr, st) {
        print("❌ Database init failed: $dbErr\n$st");
        rethrow;
      }
    } else {
      print("⚠️ Skipping DB init on web (no sqflite).");
    }

    // Step 2: Check if the user has a profile on the server
    print("=== [AuthWrapper] STEP 2: Checking server profile ===");
    bool profileExists = false;
    try {
      profileExists = await _checkIfProfileExists();
      print("✅ Server profile check complete. Exists=$profileExists");
    } catch (srvErr, st) {
      print("❌ Server profile check failed: $srvErr\n$st");
      rethrow;
    }
    if (!profileExists) {
      print("⚠️ No server profile found, redirecting to RegisterScreen.");
      return false;
    }

    // Step 3: Register this device with backend (upload keys)
    // NOTE: replace placeholder base64 keys with real client-generated keys.
    try {
      print("=== [AuthWrapper] STEP 3: Registering device with backend ===");
      // Example values for testing. Replace with real keygen output in production.
      final deviceResp = await DeviceService.registerDevice(
        deviceId: 1,
        deviceName: 'Flutter Device',
        platform: 'flutter',
        pushToken: 'placeholder_push_token',
        identityKeyB64: 'AAECAwQFBgcICQ==',
        registrationId: 123456,
        signedPreKeyId: 1,
        signedPreKeyB64: 'AQIDBAUGBwgJCgs=',
        signedPreKeySignatureB64: 'MTIzNDU2Nzg5MDEyMzQ1Ng==',
        oneTimePreKeys: [
          {'key_id': 1, 'public_key_b64': 'BQYHCAkKCwwNDg=='},
          {'key_id': 2, 'public_key_b64': 'Dg8QERITFBU='},
        ],
      );
      print("✅ Device registration successful: $deviceResp");
    } catch (regErr) {
      // Non-fatal: log and continue (but consider failing if you must have keys uploaded)
      print("⚠️ Device registration failed (continuing): $regErr");
    }

    // Step 4: Connect to the WebSocket
    print("=== [AuthWrapper] STEP 4: Connecting to WebSocket ===");
    try {
      final token = await widget.user.getIdToken(true);
      print("Obtained Firebase ID token (length=${token?.length}).");
      await websocketService.connect(token);
      print("✅ WebSocket connected successfully.");
    } catch (wsErr, st) {
      print("❌ WebSocket connect failed: $wsErr\n$st");
      rethrow;
    }

    print("🎉 [AuthWrapper] All initialization steps completed successfully.");
    return true; // Proceed to HomeScreen
  } catch (e, st) {
    print("🚨 [AuthWrapper] Initialization FAILED: $e\n$st");
    rethrow;
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
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }

        if (snapshot.hasError) {
          return Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text("Initialization Failed:\n${snapshot.error}", textAlign: TextAlign.center),
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