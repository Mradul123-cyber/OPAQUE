import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:rxdart/rxdart.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zarq_messenger/app_theme.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:zarq_messenger/services/SignalService.dart';
import 'package:zarq_messenger/services/key_rotation_service.dart';
import 'package:zarq_messenger/services/user_settings_provider.dart';
import 'package:zarq_messenger/services/backup_service.dart';
import 'package:zarq_messenger/services/backup_settings_provider.dart';
import 'package:zarq_messenger/services/auto_backup_manager.dart';
import 'package:path/path.dart' as path;
import 'package:permission_handler/permission_handler.dart';
import 'package:restart_app/restart_app.dart';

import 'firebase_options.dart';
import 'home_screen.dart';
import 'login_screen.dart';
import 'message_model.dart';
import 'providers/chat_provider.dart';
import 'providers/home_provider.dart';
import 'register_screen.dart';
import 'profile_setup_screen.dart';
import 'services/conversation_service.dart';
import 'services/database_service.dart';
import 'services/websocket_service.dart';
import 'services/device_service.dart';
import 'services/sent_message_service.dart';
import 'services/global_call_manager.dart';
import 'services/system_overlay_service.dart';
import 'widgets/global_call_overlay.dart';
import 'chat_screen.dart';
import 'setting_screen.dart';

// Import the NavigationHandler
import 'services/navigation_handler.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Initialize auto-backup workmanager
  await AutoBackupManager.initialize();

  SentMessageService.initialize();

  final databaseService = DatabaseService.instance;

  // Initialize global call manager
  final globalCallManager = GlobalCallManager();
  await globalCallManager.initialize();

  // Initialize system overlay service and set up callbacks
  SystemOverlayService.initialize();
  SystemOverlayService.onEndCallFromOverlay = () {
    globalCallManager.endCall();
  };
  SystemOverlayService.onToggleMuteFromOverlay = (isMuted) {
    // The overlay already toggled the state, we just need to sync it
    globalCallManager.toggleMicrophone();
  };

  runApp(
    MultiProvider(
      providers: [
        Provider<DatabaseService>.value(value: databaseService),
        Provider<ConversationService>(create: (_) => ConversationService()),
        ChangeNotifierProvider(create: (_) => WebSocketService()),
        ChangeNotifierProvider(create: (_) => ChatProvider()),
        ChangeNotifierProvider(create: (_) => UserSettingsProvider()),
        ChangeNotifierProvider(create: (_) => BackupSettingsProvider()),
        ChangeNotifierProvider.value(value: globalCallManager),
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
      builder: (context, child) {
        return Consumer<GlobalCallManager>(
          builder: (context, callManager, _) {
            // print('[Main] Builder - isInCall: ${callManager.isInCall}');
            return WillPopScope(
              onWillPop: () async {
                // print('[Main] 🔙 WillPopScope triggered');
                // print('[Main]   - isInCall: ${callManager.isInCall}');
                // print('[Main]   - isMinimized: ${GlobalCallOverlay.isMinimized}');

                // Priority: If call is active AND not minimized, minimize it first
                if (callManager.isInCall && !GlobalCallOverlay.isMinimized) {
                  // print('[Main] 🔙 Call is maximized - minimizing overlay');
                  GlobalCallOverlay.minimize();
                  return false; // Don't pop - just minimize
                }

                // If call is minimized or no call - allow normal navigation
                // print('[Main] ✅ Allowing navigation');
                return true; // Allow pop
              },
              child: Stack(
                children: [
                  child!,
                  GlobalCallOverlay(key: GlobalCallOverlay.globalKey),
                ],
              ),
            );
          },
        );
      },
      // Add routes for navigation from notifications
      routes: {
        '/chat': (context) {
          final args = ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;

          if (args != null) {
            final conversationId = args['conversation_id'] as int?;
            // print('[Route] Notification navigation to conversation: $conversationId');

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

class _AuthWrapperState extends State<AuthWrapper> with WidgetsBindingObserver {
  late Future<bool> _initializationFuture;
  static const platform = MethodChannel('com.zarq/signal');

  // Progress tracking
  final ValueNotifier<double> _initProgress = ValueNotifier<double>(0.0);
  final ValueNotifier<String> _initStep = ValueNotifier<String>('Starting...');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    KeyRotationService.startBackgroundRotation();
    // print("[AuthWrapper] initState: Starting user initialization.");
    _initializationFuture = _initializeUserServices();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _initProgress.dispose();
    _initStep.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    // Forward lifecycle events to GlobalCallManager
    final callManager = Provider.of<GlobalCallManager>(context, listen: false);
    callManager.handleAppLifecycleState(state);

    // Handle WebSocket reconnection when app comes to foreground
    final websocketService = Provider.of<WebSocketService>(context, listen: false);

    if (state == AppLifecycleState.resumed) {
      // print('[AuthWrapper] App resumed - checking WebSocket connection');
      // Small delay to let the network stabilize after app resumes
      Future.delayed(const Duration(milliseconds: 500), () {
        if (!websocketService.isConnected) {
          // print('[AuthWrapper] WebSocket disconnected, reconnecting...');
          websocketService.reconnect();
        } else {
          // print('[AuthWrapper] WebSocket already connected');
        }
      });
    } else if (state == AppLifecycleState.paused) {
      // print('[AuthWrapper] App paused');
    } else if (state == AppLifecycleState.inactive) {
      // print('[AuthWrapper] App inactive');
    }
  }

  void _updateProgress(double progress, String step) {
    _initProgress.value = progress;
    _initStep.value = step;
    // print("[Progress] ${(progress * 100).toInt()}% - $step");
  }

  /// Test Signal Protocol connection - Updated for current implementation
  Future<bool> _testSignalProtocol() async {
    try {
      // print("[AuthWrapper] Testing Signal Protocol connection...");

      // Test basic method channel connection
      final pingResult = await platform.invokeMethod('ping');
      // print("[AuthWrapper] Signal ping result: $pingResult");

      if (pingResult == 'Signal pong') {
        // print("[AuthWrapper] Signal Protocol method channel is working!");
        return true;
      } else {
        // print("[AuthWrapper] Signal Protocol method channel failed");
        return false;
      }
    } catch (e) {
      // print("[AuthWrapper] Signal Protocol test failed: $e");
      return false;
    }
  }

  Future<bool> _checkExistingKeys() async {
    try {
      // print("[AuthWrapper] Checking for existing Signal Protocol keys...");
      final hasKeys = await SignalService.hasKeys();
      // print("[AuthWrapper] Existing keys check: $hasKeys");
      return hasKeys;
    } catch (e) {
      // print("[AuthWrapper] Error checking existing keys: $e");
      return false;
    }
  }

  /// Placeholder for future Signal key generation
  Future<Map<String, dynamic>?> _generateSignalKeysIfNeeded() async {
    try {
      // First check if keys already exist
      final hasKeys = await _checkExistingKeys();
      if (hasKeys) {
        // print("[AuthWrapper] Keys already exist, skipping generation");
        return null; // No new keys generated
      }

      // print("[AuthWrapper] No existing keys found, generating new ones...");
      final keyBundle = await SignalService.generateKeyBundle();

      if (keyBundle != null) {
        // print("[AuthWrapper] Successfully generated new keys:");
        // print("  - Registration ID: ${keyBundle['registration_id']}");
        // print("  - Signed PreKey ID: ${keyBundle['signed_prekey_id']}");
        // print("  - Identity Key: ${keyBundle['identity_key_b64']?.toString().substring(0, 30)}...");
        // print("  - One-Time PreKeys: ${(keyBundle['one_time_prekeys'] as List?)?.length ?? 0}");
        return keyBundle;
      } else {
        throw Exception('Key bundle generation returned null');
      }
    } catch (e) {
      // print("[AuthWrapper] Key generation failed: $e");
      throw Exception('Signal key generation failed: $e');
    }
  }

  /// Get existing key bundle (for restored keys or after backup restore)
  Future<Map<String, dynamic>?> _getExistingKeyBundle() async {
    try {
      // print("[AuthWrapper] Retrieving existing key bundle from Signal...");

      const platform = MethodChannel('com.zarq/signal');

      // IMPORTANT: Use existing device ID and registration ID (restored from backup)
      final deviceId = await platform.invokeMethod<int>('getDeviceId');
      final registrationId = await platform.invokeMethod<int>('getRegistrationId');

      // print("[AuthWrapper] Retrieved IDs - Device: $deviceId, Registration: $registrationId");

      if (deviceId == null || deviceId <= 0 || registrationId == null || registrationId <= 0) {
        // print("[AuthWrapper] ⚠️ Invalid device ID or registration ID");
        return null;
      }

      // Call a special method to get key bundle WITHOUT regenerating device ID
      // This will use existing identity keys and device ID (restored from backup)
      final keyBundle = await platform.invokeMethod<Map<dynamic, dynamic>>('getKeyBundleForRegistration');

      if (keyBundle == null) {
        // print("[AuthWrapper] ⚠️ Could not retrieve existing key bundle");
        return null;
      }

      final result = Map<String, dynamic>.from(keyBundle);
      // print("[AuthWrapper] ✅ Retrieved existing key bundle:");
      // print("  - Device ID: ${result['device_id']} (using EXISTING, not regenerated)");
      // print("  - Registration ID: ${result['registration_id']}");

      return result;
    } catch (e) {
      // print("[AuthWrapper] Error retrieving existing key bundle: $e");
      return null;
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
      // print('[AuthWrapper] User initialization status: app_initialized=$isInitialized, signal_keys=$hasKeys, fully_initialized=$fullyInitialized');

      return fullyInitialized;
    } catch (e) {
      // print('[AuthWrapper] Error checking initialization status: $e');
      return false;
    }
  }

  // Mark user as initialized
  Future<void> _markUserAsInitialized() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('user_${widget.user.uid}_initialized', true);
    } catch (e) {
      // print('[AuthWrapper] Error marking user as initialized: $e');
    }
  }

  // Mark undelivered messages as delivered on app login
  Future<void> _markUndeliveredMessagesAsDelivered(WebSocketService websocketService, DatabaseService dbService) async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) return;

      final prefs = await SharedPreferences.getInstance();
      final undeliveredMessages = await dbService.getAllUndeliveredMessages(currentUser.uid);

      for (final message in undeliveredMessages) {
        // Check if we already marked this message as delivered
        final deliveredKey = 'delivered_${message.id}';
        final lastDeliveredTimestamp = prefs.getInt(deliveredKey);

        if (lastDeliveredTimestamp != null) {
          final lastDelivered = DateTime.fromMillisecondsSinceEpoch(lastDeliveredTimestamp);
          if (DateTime.now().difference(lastDelivered) < Duration(hours: 1)) {
            // print("Skipping message ${message.id} - already marked delivered recently");
            continue;
          }
        }

        // Mark as delivered
        await prefs.setInt(deliveredKey, DateTime.now().millisecondsSinceEpoch);

        await websocketService.sendStatusUpdate(
          messageId: message.id,
          status: 'delivered',
          conversationId: message.conversationId,
        );

        await dbService.updateMessageStatus(message.id, MessageStatus.delivered);
        // print("Marked message ${message.id} as delivered on app login");
      }

      if (undeliveredMessages.isNotEmpty) {
        // print("Marked ${undeliveredMessages.length} messages as delivered");
      }
    } catch (e) {
      // print("Error marking undelivered messages: $e");
    }
  }

  Future<bool> _initializeUserServices() async {
    try {
      final dbService = Provider.of<DatabaseService>(context, listen: false);
      final websocketService = Provider.of<WebSocketService>(context, listen: false);
      final globalCallManager = Provider.of<GlobalCallManager>(context, listen: false);

      // Connect WebSocket to GlobalCallManager for call signaling
      websocketService.setGlobalCallManager(globalCallManager);

      // Quick check
      final alreadyInitialized = await _isUserAlreadyInitialized();

      if (alreadyInitialized) {
        // print("Fast startup for returning user");

        // Run these in PARALLEL
        _updateProgress(0.1, 'Starting up...');
        await Future.wait([
          dbService.init(),
          _checkIfProfileExists().then((exists) {
            if (!exists) throw Exception("Profile missing");
          }),
          _testSignalProtocol(),
          widget.user.getIdToken(true).then((token) =>
              websocketService.connect(token)
          ),
        ]);

        _updateProgress(0.3, 'Verifying session...');
        await Future.delayed(const Duration(milliseconds: 300));

        // Check if device needs re-registration (after restore)
        final prefs = await SharedPreferences.getInstance();
        final needsReregistration = prefs.getBool('needs_device_reregistration') ?? false;

        if (needsReregistration) {
          // print("[AuthWrapper] 🔄 Device needs re-registration after restore");

          _updateProgress(0.4, 'Restoring encryption keys...');
          await Future.delayed(const Duration(milliseconds: 400));

          // Get existing key bundle and register to backend
          _updateProgress(0.5, 'Preparing device registration...');
          final keyBundle = await _getExistingKeyBundle();

          if (keyBundle != null) {
            final oneTimeKeys = (keyBundle['one_time_prekeys'] as List<dynamic>? ?? [])
                .map((key) => {
              'key_id': key['key_id'],
              'public_key_b64': key['public_key_b64'],
            }).toList();

            // print("[AuthWrapper] Re-registering device ${keyBundle['device_id']} to backend...");
            // print("[AuthWrapper] This will REPLACE any existing device in backend");

            _updateProgress(0.6, 'Re-registering device...');
            await Future.delayed(const Duration(milliseconds: 300));

            await DeviceService.registerDevice(
              deviceId: keyBundle['device_id'] as int,
              deviceName: 'Flutter Device',
              platform: 'android',
              pushToken: '',
              identityKeyB64: keyBundle['identity_key_b64'] as String,
              registrationId: keyBundle['registration_id'] as int,
              signedPreKeyId: keyBundle['signed_prekey_id'] as int,
              signedPreKeyB64: keyBundle['signed_prekey_b64'] as String,
              signedPreKeySignatureB64: keyBundle['signed_prekey_signature_b64'] as String,
              oneTimePreKeys: oneTimeKeys,
            );

            // print("[AuthWrapper] ✅ Device re-registered successfully");

            _updateProgress(0.75, 'Synchronizing sessions...');
            await Future.delayed(const Duration(milliseconds: 400));

            // Clear the flag
            await prefs.setBool('needs_device_reregistration', false);
          } else {
            // print("[AuthWrapper] ⚠️ Could not get key bundle for re-registration");
          }
        } else {
          // Normal fast startup without re-registration
          _updateProgress(0.5, 'Loading encryption keys...');
          await Future.delayed(const Duration(milliseconds: 400));

          _updateProgress(0.7, 'Preparing secure connection...');
          await Future.delayed(const Duration(milliseconds: 400));
        }

        _updateProgress(0.85, 'Loading conversations...');
        await Future.delayed(const Duration(milliseconds: 300));

        // Only these need to be sequential (depend on WebSocket)
        await _markUndeliveredMessagesAsDelivered(websocketService, dbService);

        _updateProgress(0.95, 'Finalizing...');
        await Future.delayed(const Duration(milliseconds: 300));

        _updateProgress(1.0, 'Ready!');
        await Future.delayed(const Duration(milliseconds: 200));

        // print("Fast initialization done");
        return true;
      }

      // Full initialization - also parallelize where possible
      // print("Full initialization for new user");

      // Step 1 & 2: Check profile and test Signal in parallel
      _updateProgress(0.14, 'Checking profile and Signal Protocol...');
      final results = await Future.wait([
        _checkIfProfileExists(),
        _testSignalProtocol(),
      ]);

      if (!results[0]) return false; // Profile doesn't exist

      // Step 3: Generate Signal keys FIRST (required for database encryption)
      _updateProgress(0.28, 'Generating Signal Protocol keys...');
      final newKeyBundle = await _generateSignalKeysIfNeeded();

      // Step 4: Initialize database (uses identity key from Signal)
      _updateProgress(0.42, 'Initializing encrypted database...');
      await dbService.init();

      // Step 5: Register device (ALWAYS, even if keys already exist from restore)
      _updateProgress(0.57, 'Preparing device registration...');
      final keyBundleToRegister = newKeyBundle ?? await _getExistingKeyBundle();

      if (keyBundleToRegister != null) {
        final oneTimeKeys = (keyBundleToRegister['one_time_prekeys'] as List<dynamic>? ?? [])
            .map((key) => {
          'key_id': key['key_id'],
          'public_key_b64': key['public_key_b64'],
        })
            .toList();

        // print("[AuthWrapper] Registering device ${keyBundleToRegister['device_id']} to backend...");
        _updateProgress(0.71, 'Registering device to server...');

        await DeviceService.registerDevice(
          deviceId: keyBundleToRegister['device_id'] as int,
          deviceName: 'Flutter Device',
          platform: 'android',
          pushToken: '',
          identityKeyB64: keyBundleToRegister['identity_key_b64'] as String,
          registrationId: keyBundleToRegister['registration_id'] as int,
          signedPreKeyId: keyBundleToRegister['signed_prekey_id'] as int,
          signedPreKeyB64: keyBundleToRegister['signed_prekey_b64'] as String,
          signedPreKeySignatureB64: keyBundleToRegister['signed_prekey_signature_b64'] as String,
          oneTimePreKeys: oneTimeKeys,
        );

        // print("[AuthWrapper] ✅ Device registered to backend successfully");

        if (newKeyBundle != null) {
          KeyRotationService.startBackgroundRotation();
        }
      } else {
        throw Exception('Could not get key bundle for device registration');
      }

      // Step 6 & 7: Connect WebSocket and upload FCM token in parallel
      _updateProgress(0.85, 'Connecting to server...');
      final token = await widget.user.getIdToken(true);
      await Future.wait([
        websocketService.connect(token),
        _uploadFCMTokenToServer(),
      ]);

      // Mark as initialized
      _updateProgress(0.95, 'Finalizing...');
      await _markUserAsInitialized();

      _updateProgress(1.0, 'Ready!');
      // print("Full initialization completed");

      // Check for backups after successful initialization (only for new/restored users)
      if (newKeyBundle != null) {
        // New keys were generated, meaning this is fresh initialization
        // Check if there are backups to restore
        // print("[AuthWrapper] 🔍 Checking for available backups after login...");
        _checkForBackupsAfterLogin();
      }

      return true;

    } catch (e, st) {
      // print("Initialization FAILED: $e\n$st");
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
        // print("[AuthWrapper] Uploading FCM token to server: ${fcmToken.substring(0, 20)}...");

        // Get actual device ID
        final actualDeviceId = await SignalService.getDeviceId();
        // print("[AuthWrapper] Using device ID: $actualDeviceId");

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
          // print("[AuthWrapper] FCM token uploaded successfully");
        } else {
          // print("[AuthWrapper] FCM token upload failed: ${response.statusCode} - ${response.body}");
        }
      } else {
        // print("[AuthWrapper] No FCM token available yet");
      }
    } catch (e) {
      // print("[AuthWrapper] Error uploading FCM token: $e");
    }
  }

  Future<void> _fetchOfflineMessages() async {
    try {
      // print("[OFFLINE] Fetching offline messages (encryption skipped for now)...");

      // For now, just log that we would fetch messages
      // TODO: Implement when Signal Protocol encryption is ready
      // print("[OFFLINE] Message fetching temporarily disabled - waiting for Signal Protocol implementation");

    } catch (e) {
      // print("[OFFLINE] Fetch failed: $e");
    }
  }

  Future<bool> _checkIfProfileExists() async {
    final token = await widget.user.getIdToken(true);
    final url = Uri.parse('http://192.168.29.81:8080/profiles/me');
    final response = await http.get(url, headers: {'Authorization': 'Bearer $token'});
    return response.statusCode == 200;
  }

  // Check for backups after login (only for new users or after clear data)
  Future<void> _checkForBackupsAfterLogin() async {
    // Wait a bit for UI to settle
    await Future.delayed(const Duration(milliseconds: 800));

    if (!mounted) return;

    try {
      // Request storage permission first
      if (Platform.isAndroid) {
        final manageStorageStatus = await Permission.manageExternalStorage.status;
        if (!manageStorageStatus.isGranted) {
          // print('[BackupDetection] Storage permission not granted, skipping backup check');
          return;
        }
      }

      // Check for backups in Download/Zarq_Backups
      final downloadsDir = Directory('/storage/emulated/0/Download/Zarq_Backups');

      if (!await downloadsDir.exists()) {
        // print('[BackupDetection] No backup folder found');
        return;
      }

      final backups = await downloadsDir.list().toList();
      final backupFiles = backups.where((file) => file.path.endsWith('.encrypted')).toList();

      if (backupFiles.isEmpty) {
        // print('[BackupDetection] No backup files found');
        return;
      }

      // Sort by modification time (most recent first)
      backupFiles.sort((a, b) => b.statSync().modified.compareTo(a.statSync().modified));

      // print('[BackupDetection] Found ${backupFiles.length} backup(s) after login');

      // Check if the most recent backup was already restored
      final mostRecentBackup = backupFiles.first;
      final backupFileName = path.basename(mostRecentBackup.path);
      final backupModified = mostRecentBackup.statSync().modified.millisecondsSinceEpoch;

      final prefs = await SharedPreferences.getInstance();
      final lastRestoredBackupName = prefs.getString('last_restored_backup_name');
      final lastRestoredTimestamp = prefs.getInt('last_restored_backup_timestamp');

      // Skip if this exact backup was already restored
      if (lastRestoredBackupName == backupFileName && lastRestoredTimestamp == backupModified) {
        // print('[BackupDetection] ✅ Most recent backup was already restored. Skipping.');
        return;
      }

      // print('[BackupDetection] 🆕 Found new/unrestored backup: $backupFileName');

      // Show restore dialog
      if (mounted) {
        _showBackupRestoreDialog(backupFiles);
      }
    } catch (e) {
      // print('[BackupDetection] Error checking backups: $e');
    }
  }

  void _showBackupRestoreDialog(List<FileSystemEntity> backups) {
    final mostRecentBackup = backups.first;
    final backupStat = mostRecentBackup.statSync();
    final backupDate = backupStat.modified.toLocal();
    final backupSize = (backupStat.size / (1024 * 1024)).toStringAsFixed(2);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF0a1128).withOpacity(0.95),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(15),
          side: BorderSide(color: Colors.cyanAccent.withOpacity(0.5)),
        ),
        title: const Row(
          children: [
            Icon(Icons.backup, color: Colors.cyanAccent),
            SizedBox(width: 12),
            Text('Backup Found!', style: TextStyle(color: Colors.white)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'We found ${backups.length} backup(s). Would you like to restore?',
              style: const TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 16),
            const Divider(color: Colors.white30),
            const SizedBox(height: 12),
            Text(
              'Most Recent: ${path.basename(mostRecentBackup.path)}',
              style: const TextStyle(color: Colors.white, fontSize: 13),
            ),
            const SizedBox(height: 8),
            Text(
              'Date: ${backupDate.day}/${backupDate.month}/${backupDate.year} ${backupDate.hour}:${backupDate.minute.toString().padLeft(2, '0')}',
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
            Text(
              'Size: $backupSize MB',
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Skip', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.cyanAccent,
              foregroundColor: Colors.black,
            ),
            onPressed: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const SettingsScreen()),
              );
            },
            child: const Text('Go to Settings'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _initializationFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 40.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // App Name
                    const Text(
                      "Zarq",
                      style: TextStyle(
                        fontSize: 48,
                        fontWeight: FontWeight.bold,
                        color: Colors.cyanAccent,
                        letterSpacing: 2,
                      ),
                    ),
                    const SizedBox(height: 8),
                    // Tagline/Quote
                    const Text(
                      "Privacy First, Always Encrypted",
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w400,
                        color: Colors.white70,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 50),
                    const Text(
                      "Initializing Secure Messaging",
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 30),
                    ValueListenableBuilder<double>(
                      valueListenable: _initProgress,
                      builder: (context, progress, child) {
                        return Column(
                          children: [
                            Stack(
                              alignment: Alignment.center,
                              children: [
                                SizedBox(
                                  width: 120,
                                  height: 120,
                                  child: CircularProgressIndicator(
                                    value: progress,
                                    strokeWidth: 8,
                                    backgroundColor: Colors.grey.shade800,
                                    valueColor: const AlwaysStoppedAnimation<Color>(
                                      Colors.cyanAccent,
                                    ),
                                  ),
                                ),
                                Text(
                                  '${(progress * 100).toInt()}%',
                                  style: const TextStyle(
                                    fontSize: 28,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 24),
                            ValueListenableBuilder<String>(
                              valueListenable: _initStep,
                              builder: (context, step, child) {
                                return Text(
                                  step,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    color: Colors.white70,
                                  ),
                                );
                              },
                            ),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        if (snapshot.hasError) {
          // Determine user-friendly error message
          String friendlyMessage = 'Something went wrong';
          String suggestion = 'Please try again';
          IconData errorIcon = Icons.error_outline;

          final errorString = snapshot.error.toString().toLowerCase();

          if (errorString.contains('network') || errorString.contains('connection') || errorString.contains('internet')) {
            friendlyMessage = 'No Internet Connection';
            suggestion = 'Please check your internet and try again';
            errorIcon = Icons.wifi_off;
          } else if (errorString.contains('timeout')) {
            friendlyMessage = 'Connection Timeout';
            suggestion = 'Please check your internet and try again';
            errorIcon = Icons.hourglass_empty;
          } else if (errorString.contains('profile')) {
            friendlyMessage = 'Profile Setup Required';
            suggestion = 'Please complete your profile setup';
            errorIcon = Icons.account_circle;
          } else if (errorString.contains('permission')) {
            friendlyMessage = 'Permission Required';
            suggestion = 'Please grant required permissions';
            errorIcon = Icons.lock;
          }

          return Scaffold(
            backgroundColor: Colors.white,
            body: SafeArea(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(32.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(errorIcon, size: 80, color: Colors.orange),
                      const SizedBox(height: 24),
                      Text(
                        friendlyMessage,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        suggestion,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 16,
                          color: Colors.black54,
                        ),
                      ),
                      const SizedBox(height: 32),
                      ElevatedButton.icon(
                        onPressed: () {
                          // Retry initialization without logging out
                          setState(() {
                            _initializationFuture = _initializeUserServices();
                          });
                        },
                        icon: const Icon(Icons.refresh),
                        label: const Text('Try Again'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF667eea),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }

        final bool isReady = snapshot.data ?? false;
        if (isReady) {
          return const HomeScreen();
        } else {
          // User has Firebase account but no backend profile - complete registration
          return ProfileSetupScreen(
            user: widget.user,
            onSetupComplete: (String? displayName, String? avatarUrl, String? username) {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => RegisterScreen(
                    user: widget.user,
                    displayName: displayName,
                    avatarUrl: avatarUrl,
                    username: username,
                    onRegistrationComplete: () {
                      // print("[AuthWrapper] onRegistrationComplete triggered. Re-initializing services...");
                      // Pop RegisterScreen to go back to AuthWrapper
                      Navigator.of(context).pop();
                      // Trigger re-initialization which will connect WebSocket and show HomeScreen
                      setState(() {
                        _initializationFuture = _initializeUserServices();
                      });
                    },
                  ),
                ),
              );
            },
          );
        }
      },
    );
  }
}

// Backup Detection Wrapper - Checks for backups on login and offers restore
class BackupDetectionWrapper extends StatefulWidget {
  const BackupDetectionWrapper({super.key});

  @override
  State<BackupDetectionWrapper> createState() => _BackupDetectionWrapperState();
}

class _BackupDetectionWrapperState extends State<BackupDetectionWrapper> {
  bool _hasCheckedBackups = false;

  @override
  void initState() {
    super.initState();
    _checkForBackupsOnce();
  }

  Future<bool> _requestStoragePermission() async {
    try {
      if (Platform.isAndroid) {
        // print('[BackupDetection] Checking storage permission for Android 15...');

        // For Android 11+ (API 30+), we need MANAGE_EXTERNAL_STORAGE for Downloads folder
        final manageStorageStatus = await Permission.manageExternalStorage.status;
        // print('[BackupDetection] MANAGE_EXTERNAL_STORAGE status: $manageStorageStatus');

        if (manageStorageStatus.isGranted) {
          // print('[BackupDetection] Full storage access already granted');
          return true;
        }

        // Request full storage access
        // print('[BackupDetection] Requesting MANAGE_EXTERNAL_STORAGE permission...');
        final status = await Permission.manageExternalStorage.request();
        // print('[BackupDetection] Permission request result: $status');

        if (status.isGranted) {
          // print('[BackupDetection] Full storage access granted');
          return true;
        } else if (status.isPermanentlyDenied) {
          // print('[BackupDetection] Storage permission permanently denied');
          if (mounted) {
            _showPermissionDeniedDialog();
          }
          return false;
        } else if (status.isDenied) {
          // print('[BackupDetection] Storage permission denied by user');
          // Try to access anyway (might work with scoped storage)
          return true;
        } else {
          // print('[BackupDetection] Unknown permission status: $status');
          return true;
        }
      }
      return true;
    } catch (e) {
      // print('[BackupDetection] Error requesting permission: $e');
      // Fallback: try to access anyway
      return true;
    }
  }

  void _showPermissionDeniedDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF0a1128).withOpacity(0.95),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(15),
          side: BorderSide(color: Colors.cyanAccent.withOpacity(0.5)),
        ),
        title: const Text(
          'Storage Permission Required',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'Storage permission is needed to detect and restore backups. Please grant permission in app settings.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Colors.white70),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              openAppSettings();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.cyanAccent,
            ),
            child: const Text(
              'Open Settings',
              style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _checkForBackupsOnce() async {
    if (_hasCheckedBackups) return;
    _hasCheckedBackups = true;

    // Wait a bit for UI to settle
    await Future.delayed(const Duration(milliseconds: 500));

    if (!mounted) return;

    try {
      // Request storage permission first
      final permission = await _requestStoragePermission();
      if (!permission) {
        // print('[BackupDetection] Storage permission denied');
        return;
      }

      // Check for backups in Download/Zarq_Backups (not Downloads)
      final downloadsDir = Directory('/storage/emulated/0/Download/Zarq_Backups');

      if (!await downloadsDir.exists()) {
        // print('[BackupDetection] No backup folder found at: ${downloadsDir.path}');
        return;
      }

      // print('[BackupDetection] Checking backups in: ${downloadsDir.path}');

      final backups = await downloadsDir.list().toList();
      final backupFiles = backups.where((file) =>
        file.path.endsWith('.encrypted')
      ).toList();

      if (backupFiles.isEmpty) {
        // print('[BackupDetection] No backup files found');
        return;
      }

      // Sort by modification time (most recent first)
      backupFiles.sort((a, b) =>
        b.statSync().modified.compareTo(a.statSync().modified)
      );

      // print('[BackupDetection] Found ${backupFiles.length} backup(s)');

      // Check if the most recent backup was already restored
      final mostRecentBackup = backupFiles.first;
      final backupFileName = path.basename(mostRecentBackup.path);
      final backupModified = mostRecentBackup.statSync().modified.millisecondsSinceEpoch;

      final prefs = await SharedPreferences.getInstance();
      final lastRestoredBackupName = prefs.getString('last_restored_backup_name');
      final lastRestoredTimestamp = prefs.getInt('last_restored_backup_timestamp');

      // Skip if this exact backup was already restored
      if (lastRestoredBackupName == backupFileName &&
          lastRestoredTimestamp == backupModified) {
        // print('[BackupDetection] ✅ Most recent backup "$backupFileName" was already restored. Skipping dialog.');
        return;
      }

      // print('[BackupDetection] 🆕 Found new/unrestored backup: $backupFileName');

      // Show restore dialog
      if (mounted) {
        _showRestoreDialog(backupFiles);
      }
    } catch (e) {
      // print('[BackupDetection] Error checking backups: $e');
    }
  }

  void _showRestoreDialog(List<FileSystemEntity> backups) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF0a1128).withOpacity(0.95),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(15),
          side: BorderSide(color: Colors.cyanAccent.withOpacity(0.5)),
        ),
        title: Row(
          children: [
            const Icon(Icons.backup, color: Colors.cyanAccent),
            const SizedBox(width: 12),
            const Text(
              'Backups Found!',
              style: TextStyle(color: Colors.white),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'We found ${backups.length} backup(s). Would you like to restore?',
              style: const TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 16),
            const Divider(color: Colors.white30),
            const SizedBox(height: 8),
            const Text(
              'Most Recent Backup:',
              style: TextStyle(
                color: Colors.cyanAccent,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 8),
            _buildBackupInfo(backups.first),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'Skip',
              style: TextStyle(color: Colors.white70),
            ),
          ),
          if (backups.length > 1)
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                _showBackupsList(backups);
              },
              child: const Text(
                'View All',
                style: TextStyle(color: Colors.orangeAccent),
              ),
            ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _restoreBackup(backups.first.path);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.cyanAccent,
            ),
            child: const Text(
              'Restore',
              style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBackupInfo(FileSystemEntity backup) {
    final stat = backup.statSync();
    final backupService = BackupService();
    final size = backupService.formatBytes(stat.size);
    final date = stat.modified.toLocal();
    final fileName = path.basename(backup.path);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.cyanAccent.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            fileName,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Icon(Icons.access_time, color: Colors.white54, size: 14),
              const SizedBox(width: 6),
              Text(
                '${date.day}/${date.month}/${date.year} ${date.hour}:${date.minute.toString().padLeft(2, '0')}',
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Icon(Icons.storage, color: Colors.white54, size: 14),
              const SizedBox(width: 6),
              Text(
                size,
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showBackupsList(List<FileSystemEntity> backups) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF0a1128).withOpacity(0.95),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(15),
          side: BorderSide(color: Colors.cyanAccent.withOpacity(0.5)),
        ),
        title: const Text(
          'Select Backup to Restore',
          style: TextStyle(color: Colors.white),
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: backups.length,
            itemBuilder: (context, index) {
              final backup = backups[index];
              final stat = backup.statSync();
              final backupService = BackupService();
              final size = backupService.formatBytes(stat.size);
              final date = stat.modified.toLocal();
              final fileName = path.basename(backup.path);

              return Card(
                color: Colors.white.withOpacity(0.1),
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: Icon(
                    index == 0 ? Icons.backup : Icons.folder,
                    color: index == 0 ? Colors.cyanAccent : Colors.white54,
                  ),
                  title: Text(
                    fileName,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    '${date.day}/${date.month}/${date.year} ${date.hour}:${date.minute.toString().padLeft(2, '0')} • $size',
                    style: const TextStyle(color: Colors.white54, fontSize: 11),
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.restore, color: Colors.cyanAccent),
                    onPressed: () {
                      Navigator.pop(context);
                      _restoreBackup(backup.path);
                    },
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    _restoreBackup(backup.path);
                  },
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Colors.white70),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _restoreBackup(String filePath) async {
    try {
      // Ask for passphrase
      final passphrase = await _askForPassword();

      if (passphrase == null || passphrase.isEmpty) {
        return;
      }

      // Show progress dialog
      if (!mounted) return;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const AlertDialog(
          backgroundColor: Color(0xFF0a1128),
          content: Row(
            children: [
              CircularProgressIndicator(color: Colors.cyanAccent),
              SizedBox(width: 20),
              Expanded(
                child: Text(
                  'Restoring backup...\nThis may take a moment.',
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ],
          ),
        ),
      );

      final backupService = BackupService();
      final encryptedFile = File(filePath);
      final backupData = await backupService.decryptBackup(encryptedFile, passphrase);
      await backupService.restoreBackup(backupData);

      if (mounted) {
        Navigator.of(context).pop(); // Close progress dialog

        // Show success message briefly before restarting
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Backup restored successfully! Restarting app...'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );

        // Wait for snackbar to show, then restart
        await Future.delayed(const Duration(seconds: 2));

        // Restart the app
        Restart.restartApp();
      }
    } catch (e) {
      // print('[BackupDetection] Restore error: $e');
      if (mounted) {
        Navigator.of(context).pop(); // Close progress dialog

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Restore failed: ${e.toString().contains('Incorrect passphrase') ? 'Incorrect passphrase' : 'Error - $e'}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
  }

  Future<String?> _askForPassword() async {
    String? password;
    await showDialog(
      context: context,
      builder: (ctx) {
        final controller = TextEditingController();
        return AlertDialog(
          backgroundColor: const Color(0xFF0a1128).withOpacity(0.95),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
            side: BorderSide(color: Colors.cyanAccent.withOpacity(0.5)),
          ),
          title: const Text(
            'Enter Backup Passphrase',
            style: TextStyle(color: Colors.white),
          ),
          content: TextField(
            controller: controller,
            obscureText: true,
            autofocus: true,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'Backup passphrase',
              hintStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
              enabledBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: Colors.cyanAccent.withOpacity(0.5)),
              ),
              focusedBorder: const UnderlineInputBorder(
                borderSide: BorderSide(color: Colors.cyanAccent),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text(
                "Cancel",
                style: TextStyle(color: Colors.white70),
              ),
            ),
            ElevatedButton(
              onPressed: () {
                password = controller.text;
                Navigator.pop(ctx);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.cyanAccent,
              ),
              child: const Text(
                "Restore",
                style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        );
      },
    );
    return password;
  }

  @override
  Widget build(BuildContext context) {
    return const HomeScreen();
  }
}