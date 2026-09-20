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
import 'package:flutter_quill/flutter_quill.dart';
import 'package:zarq_messenger/services/SignalService.dart';
import 'package:zarq_messenger/services/key_rotation_service.dart';
import 'package:zarq_messenger/services/user_settings_provider.dart';
import 'package:zarq_messenger/services/backup_service.dart';
import 'package:zarq_messenger/services/backup_settings_provider.dart';
import 'package:zarq_messenger/services/auto_backup_manager.dart';
import 'package:zarq_messenger/services/backup_notification_service.dart';
import 'package:zarq_messenger/services/mediastore_backup_service.dart';
import 'package:path/path.dart' as path;
import 'package:permission_handler/permission_handler.dart';
import 'package:restart_app/restart_app.dart';

import 'firebase_options.dart';
import 'home_screen.dart';
import 'login_screen.dart';
import 'message_model.dart';
import 'providers/chat_provider.dart';
import 'providers/home_provider.dart';
import 'screens/opaque_auth_screen.dart';
import 'services/opaque_auth_service.dart';
import 'widgets/opaque_auth_design.dart';
import 'services/conversation_service.dart';
import 'services/database_service.dart';
import 'services/websocket_service.dart';
import 'services/device_service.dart';
import 'services/sent_message_service.dart';
import 'services/global_call_manager.dart';
import 'services/system_overlay_service.dart';
import 'services/share_service.dart';
import 'widgets/global_call_overlay.dart';
import 'widgets/opaque_toast.dart';
import 'chat_screen.dart';
import 'setting_screen.dart';
import 'screens/backup_management_screen.dart';
import 'screens/share_conversation_picker_screen.dart';
import 'package:google_fonts/google_fonts.dart';

// Import the NavigationHandler
import 'services/navigation_handler.dart';
import 'package:zarq_messenger/app_config.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // Initialize auto-backup workmanager
  await AutoBackupManager.initialize();

  SentMessageService.initialize();

  // Initialize share service
  await ShareService.initialize();

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
        ChangeNotifierProxyProvider2<
          ConversationService,
          WebSocketService,
          HomeProvider
        >(
          create: (context) => HomeProvider(
            conversationService: Provider.of<ConversationService>(
              context,
              listen: false,
            ),
            webSocketService: Provider.of<WebSocketService>(
              context,
              listen: false,
            ),
          ),
          update: (_, conversationService, webSocketService, homeProvider) =>
              homeProvider!
                ..updateServices(conversationService, webSocketService),
        ),
      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});
  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  // IMPORTANT: Use a SEPARATE channel for Kotlin->Flutter triggers
  // to avoid conflicts with the bidirectional com.zarq/backup channel
  static const MethodChannel _backupTriggerChannel = MethodChannel(
    'com.zarq/backup_trigger',
  );

  StreamSubscription<SharedContent>? _shareSubscription;

  @override
  void initState() {
    super.initState();
    _setupBackupHandler();
    _setupShareListener();
  }

  @override
  void dispose() {
    _shareSubscription?.cancel();
    super.dispose();
  }

  void _setupShareListener() {
    debugPrint('📤 [MyApp] Setting up share content listener...');
    _shareSubscription = ShareService.sharedContentStream.listen((
      sharedContent,
    ) {
      debugPrint('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      debugPrint(
        '📤 [MyApp] 🔥 STREAM FIRED! Received shared content: ${sharedContent.type}',
      );
      debugPrint('📤 [MyApp] URI: ${sharedContent.uri}');
      debugPrint(
        '📤 [MyApp] Navigator key: ${MyApp.navigatorKey.currentState}',
      );
      debugPrint('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');

      // Navigate to conversation picker screen
      final navigatorState = MyApp.navigatorKey.currentState;
      if (navigatorState != null) {
        debugPrint(
          '📤 [MyApp] ✅ Navigating to ShareConversationPickerScreen...',
        );
        navigatorState.push(
          MaterialPageRoute(
            builder: (context) {
              debugPrint(
                '📤 [MyApp] 🏗️ Building ShareConversationPickerScreen...',
              );
              return ShareConversationPickerScreen(
                sharedContent: sharedContent,
              );
            },
          ),
        );
      } else {
        debugPrint('📤 [MyApp] ❌ Navigator state is null! Cannot navigate.');
      }
    });
    debugPrint('📤 [MyApp] ✅ Share listener setup complete');

    // NOW check for pending shared content (after listener is set up)
    debugPrint('📤 [MyApp] Checking for pending shared content...');
    ShareService.checkForPendingSharedContent().then((_) {
      debugPrint('📤 [MyApp] ✅ Pending content check complete');
    });
  }

  void _setupBackupHandler() {
    debugPrint(
      '🔧 [MyApp] Setting up PERSISTENT backup MethodChannel handler...',
    );
    debugPrint(
      '🔧 [MyApp] Channel: com.zarq/backup_trigger (one-way Kotlin->Flutter)',
    );
    debugPrint('🔧 [MyApp] Handler address: ${_backupTriggerChannel.hashCode}');
    _backupTriggerChannel.setMethodCallHandler((call) async {
      debugPrint('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      debugPrint('📞 [MyApp] ⚡ HANDLER TRIGGERED! Method: ${call.method}');
      debugPrint('📞 [MyApp] Timestamp: ${DateTime.now()}');
      debugPrint('📞 [MyApp] Thread: ${Zone.current}');
      debugPrint('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');

      if (call.method == 'executeAutoBackupNow') {
        debugPrint('');
        debugPrint(
          '╔════════════════════════════════════════════════════════════╗',
        );
        debugPrint(
          '║ 🔥 FLUTTER RECEIVED AUTO-BACKUP TRIGGER!                  ║',
        );
        debugPrint(
          '╚════════════════════════════════════════════════════════════╝',
        );
        debugPrint('');

        try {
          debugPrint('[MyApp] Step 1: Creating BackupService instance...');
          final backupService = BackupService();

          debugPrint('[MyApp] Step 2: Loading auto-backup settings...');
          final settings = await backupService.getAutoBackupSettings();
          debugPrint('[MyApp] Settings loaded - Enabled: ${settings.enabled}');

          if (settings.enabled) {
            // Show initial progress notification
            await BackupNotificationService.showProgressNotification(
              'Starting auto-backup...',
              0,
            );

            debugPrint('[MyApp] Step 3: Creating local backup...');

            // Create local backup (WhatsApp approach: Media stays on device, only messages + keys)
            await BackupNotificationService.showProgressNotification(
              'Collecting messages...',
              20,
            );
            final backupData = await backupService.createLocalBackup(
              includeMedia:
                  false, // Consistent with manual backup - media stays on device
            );
            debugPrint('[MyApp] Step 4: Backup data created');

            // Encrypt the backup
            debugPrint('[MyApp] Step 5: Encrypting backup...');
            await BackupNotificationService.showProgressNotification(
              'Encrypting backup...',
              50,
            );
            final encryptedFile = await backupService.encryptBackup(
              backupData,
              settings.lastBackupPassphrase ?? '',
            );
            debugPrint('[MyApp] Step 6: Backup encrypted');

            // Save to MediaStore Downloads (persists after uninstall, no permissions needed)
            debugPrint('[MyApp] Step 7: Saving to MediaStore Downloads...');
            await BackupNotificationService.showProgressNotification(
              'Saving to local storage...',
              70,
            );

            // Use "auto_backup_" prefix to differentiate from manual backups
            final timestamp = DateTime.now()
                .toIso8601String()
                .replaceAll(':', '-')
                .split('.')[0];
            final fileName = 'auto_backup_$timestamp.encrypted';

            final uri = await MediaStoreBackupService.saveBackupFile(
              encryptedFile,
              fileName,
            );
            if (uri != null) {
              debugPrint('[MyApp] Backup saved to MediaStore: $uri');
            } else {
              debugPrint('[MyApp] ❌ Failed to save backup to MediaStore');
              throw Exception('Failed to save backup to MediaStore');
            }

            // Clean up old auto-backups (keep only 2 most recent)
            debugPrint('[MyApp] Step 8: Cleaning up old auto-backups...');
            await _cleanupOldAutoBackups();

            // Update last backup time
            debugPrint('[MyApp] Step 9: Updating last backup time...');
            await BackupNotificationService.showProgressNotification(
              'Finalizing...',
              95,
            );
            await backupService.updateLastBackupTime(DateTime.now());

            debugPrint('');
            debugPrint(
              '╔════════════════════════════════════════════════════════════╗',
            );
            debugPrint(
              '║ ✅ AUTO-BACKUP COMPLETED SUCCESSFULLY!                    ║',
            );
            debugPrint(
              '╠════════════════════════════════════════════════════════════╣',
            );
            debugPrint(
              '╚════════════════════════════════════════════════════════════╝',
            );
            debugPrint('');

            // Show success notification
            await BackupNotificationService.showSuccessNotification('Auto');
          } else {
            debugPrint(
              '[MyApp] ⚠️ Auto-backup is disabled in settings, skipping',
            );
          }
        } catch (e, stackTrace) {
          debugPrint('');
          debugPrint(
            '╔════════════════════════════════════════════════════════════╗',
          );
          debugPrint(
            '║ ❌ AUTO-BACKUP FAILED!                                    ║',
          );
          debugPrint(
            '╠════════════════════════════════════════════════════════════╣',
          );
          debugPrint('║ Error: $e');
          debugPrint('║ Stack: $stackTrace');
          debugPrint(
            '╚════════════════════════════════════════════════════════════╝',
          );
          debugPrint('');

          // Show failure notification
          await BackupNotificationService.showFailureNotification(
            'Auto',
            e.toString().length > 100 ? 'Backup error occurred' : e.toString(),
          );
        }
      } else {
        debugPrint('[MyApp] ⚠️ Received unknown method: ${call.method}');
      }

      return null;
    });
    debugPrint('✅ [MyApp] Backup MethodChannel handler set up complete');
  }

  /// Clean up old auto-backups, keeping only the 2 most recent
  /// Manual backups (filename starts with "backup_") are NOT deleted
  Future<void> _cleanupOldAutoBackups() async {
    try {
      debugPrint('[MyApp] Cleaning up old auto-backups...');

      // List all backup files from MediaStore
      final allBackups = await MediaStoreBackupService.listBackupFiles();

      // Filter only auto-backups (filename starts with "auto_backup_")
      final autoBackups = allBackups
          .where(
            (backup) => (backup['name'] as String).startsWith('auto_backup_'),
          )
          .toList();

      debugPrint('[MyApp] Found ${autoBackups.length} auto-backup files');

      // If 2 or fewer auto-backups exist, don't delete anything
      if (autoBackups.length <= 2) {
        debugPrint(
          '[MyApp] Only ${autoBackups.length} auto-backups, no cleanup needed',
        );
        return;
      }

      // Sort by modification time (newest first)
      autoBackups.sort((a, b) {
        final aTime = a['dateModified'] as int;
        final bTime = b['dateModified'] as int;
        return bTime.compareTo(aTime);
      });

      // Keep only the 2 most recent, delete the rest
      final backupsToDelete = autoBackups.sublist(2);
      debugPrint(
        '[MyApp] Deleting ${backupsToDelete.length} old auto-backups (keeping 2 most recent)',
      );

      for (final backup in backupsToDelete) {
        try {
          final uri = backup['uri'] as String;
          final name = backup['name'] as String;
          final deleted = await MediaStoreBackupService.deleteBackupFile(uri);
          if (deleted) {
            debugPrint('[MyApp] ✅ Deleted old auto-backup: $name');
          } else {
            debugPrint('[MyApp] ❌ Failed to delete $name');
          }
        } catch (e) {
          debugPrint('[MyApp] ❌ Failed to delete backup: $e');
        }
      }

      debugPrint('[MyApp] Auto-backup cleanup complete');
    } catch (e) {
      debugPrint('[MyApp] Error during cleanup: $e');
      // Don't rethrow - cleanup failure shouldn't stop backup creation
    }
  }

  @override
  Widget build(BuildContext context) {
    // Initialize navigation handler for Kotlin communication
    NavigationHandler.initialize(MyApp.navigatorKey);

    return Consumer<UserSettingsProvider>(
      builder: (context, userSettings, _) {
        return MaterialApp(
          title: 'OPAQUE',
          theme: userSettings.isDarkMode ? opaqueDarkTheme : opaqueLightTheme,
          themeMode: userSettings.isDarkMode ? ThemeMode.dark : ThemeMode.light,
          navigatorKey: MyApp.navigatorKey,
          localizationsDelegates: const [FlutterQuillLocalizations.delegate],
          home: const AuthGate(),
          builder: (context, child) {
            return Consumer<GlobalCallManager>(
              builder: (context, callManager, _) {
                // print('[Main] Builder - isInCall: ${callManager.isInCall}');
                return PopScope(
                  canPop:
                      !callManager.isInCall || GlobalCallOverlay.isMinimized,
                  onPopInvokedWithResult: (didPop, result) {
                    // print('[Main] 🔙 PopScope triggered - didPop: $didPop');
                    if (!didPop &&
                        callManager.isInCall &&
                        !GlobalCallOverlay.isMinimized) {
                      // print('[Main] 🔙 Call is maximized - minimizing overlay');
                      GlobalCallOverlay.minimize();
                    }
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
              final args =
                  ModalRoute.of(context)?.settings.arguments
                      as Map<String, dynamic>?;

              if (args != null) {
                final conversationId = args['conversation_id'] as int?;
                // print('[Route] Notification navigation to conversation: $conversationId');

                if (conversationId != null) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    Navigator.of(context).pushReplacementNamed(
                      '/home_with_conversation',
                      arguments: {'target_conversation_id': conversationId},
                    );
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
      },
    );
  }
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: OpaqueAuthService.interactive,
      builder: (context, interactive, _) => StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        initialData: FirebaseAuth.instance.currentUser,
        builder: (context, snapshot) {
          if (interactive || !snapshot.hasData) return const LoginScreen();
          final user = snapshot.data!;
          if (OpaqueAuthService.needsEmailVerification(user)) {
            return OpaqueAuthScreen(
              key: ValueKey('verify_${user.uid}'),
              user: user,
            );
          }
          return AuthWrapper(key: ValueKey(user.uid), user: user);
        },
      ),
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
  final ValueNotifier<bool> _showProgressBar = ValueNotifier<bool>(true);

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
    _showProgressBar.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    // Forward lifecycle events to GlobalCallManager
    final callManager = Provider.of<GlobalCallManager>(context, listen: false);
    callManager.handleAppLifecycleState(state);

    // Handle WebSocket reconnection when app comes to foreground
    final websocketService = Provider.of<WebSocketService>(
      context,
      listen: false,
    );

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
      final registrationId = await platform.invokeMethod<int>(
        'getRegistrationId',
      );

      // print("[AuthWrapper] Retrieved IDs - Device: $deviceId, Registration: $registrationId");

      if (deviceId == null ||
          deviceId <= 0 ||
          registrationId == null ||
          registrationId <= 0) {
        // print("[AuthWrapper] ⚠️ Invalid device ID or registration ID");
        return null;
      }

      // Call a special method to get key bundle WITHOUT regenerating device ID
      // This will use existing identity keys and device ID (restored from backup)
      final keyBundle = await platform.invokeMethod<Map<dynamic, dynamic>>(
        'getKeyBundleForRegistration',
      );

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
      final isInitialized =
          prefs.getBool('user_${widget.user.uid}_initialized') ?? false;

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
  Future<void> _markUndeliveredMessagesAsDelivered(
    WebSocketService websocketService,
    DatabaseService dbService,
  ) async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) return;

      final prefs = await SharedPreferences.getInstance();
      final undeliveredMessages = await dbService.getAllUndeliveredMessages(
        currentUser.uid,
      );

      for (final message in undeliveredMessages) {
        // Check if we already marked this message as delivered
        final deliveredKey = 'delivered_${message.id}';
        final lastDeliveredTimestamp = prefs.getInt(deliveredKey);

        if (lastDeliveredTimestamp != null) {
          final lastDelivered = DateTime.fromMillisecondsSinceEpoch(
            lastDeliveredTimestamp,
          );
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

        await dbService.updateMessageStatus(
          message.id,
          MessageStatus.delivered,
        );
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
      final websocketService = Provider.of<WebSocketService>(
        context,
        listen: false,
      );
      final globalCallManager = Provider.of<GlobalCallManager>(
        context,
        listen: false,
      );

      // Connect WebSocket to GlobalCallManager for call signaling
      websocketService.setGlobalCallManager(globalCallManager);

      // Quick check
      final alreadyInitialized = await _isUserAlreadyInitialized();

      if (alreadyInitialized) {
        // print("Fast startup for returning user");

        // Check if device needs re-registration (after restore)
        final prefs = await SharedPreferences.getInstance();
        final needsReregistration =
            prefs.getBool('needs_device_reregistration') ?? false;

        // Hide progress bar for normal fast startup, show for restore flow
        _showProgressBar.value = needsReregistration;

        // Run these in PARALLEL
        _updateProgress(0.1, 'Starting up...');
        await Future.wait([
          dbService.init(),
          _checkIfProfileExists().then((exists) {
            if (!exists) throw Exception("Profile missing");
          }),
          _testSignalProtocol(),
          widget.user
              .getIdToken(true)
              .then((token) => websocketService.connect(token)),
        ]);

        _updateProgress(0.3, 'Verifying session...');

        if (needsReregistration) {
          // print("[AuthWrapper] 🔄 Device needs re-registration after restore");

          _updateProgress(0.4, 'Restoring encryption keys...');
          await Future.delayed(const Duration(milliseconds: 400));

          // Get existing key bundle and register to backend
          _updateProgress(0.5, 'Preparing device registration...');
          final keyBundle = await _getExistingKeyBundle();

          if (keyBundle != null) {
            final oneTimeKeys =
                (keyBundle['one_time_prekeys'] as List<dynamic>? ?? [])
                    .map(
                      (key) => {
                        'key_id': key['key_id'],
                        'public_key_b64': key['public_key_b64'],
                      },
                    )
                    .toList();

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
              signedPreKeySignatureB64:
                  keyBundle['signed_prekey_signature_b64'] as String,
              oneTimePreKeys: oneTimeKeys,
            );

            // print("[AuthWrapper] ✅ Device re-registered successfully");

            _updateProgress(0.75, 'Synchronizing sessions...');
            await Future.delayed(const Duration(milliseconds: 400));

            // 🔧 FIX: Upload FCM token after restore (only when re-registration happens)
            print("[AuthWrapper] 📤 Uploading FCM token after restore...");
            await _uploadFCMTokenToServer();

            // Clear the flag
            await prefs.setBool('needs_device_reregistration', false);
          } else {
            // print("[AuthWrapper] ⚠️ Could not get key bundle for re-registration");
          }
        } else {
          // Normal fast startup without re-registration
          _updateProgress(0.5, 'Loading encryption keys...');

          _updateProgress(0.7, 'Preparing secure connection...');
        }

        _updateProgress(0.85, 'Loading conversations...');

        // Only these need to be sequential (depend on WebSocket)
        await _markUndeliveredMessagesAsDelivered(websocketService, dbService);

        _updateProgress(0.95, 'Finalizing...');

        _updateProgress(1.0, 'Ready!');

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
        final oneTimeKeys =
            (keyBundleToRegister['one_time_prekeys'] as List<dynamic>? ?? [])
                .map(
                  (key) => {
                    'key_id': key['key_id'],
                    'public_key_b64': key['public_key_b64'],
                  },
                )
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
          signedPreKeySignatureB64:
              keyBundleToRegister['signed_prekey_signature_b64'] as String,
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
      if (user == null) {
        print("[AuthWrapper] ⚠️ No user logged in, skipping FCM upload");
        return;
      }

      // Get FCM token from Kotlin
      const utilityChannel = MethodChannel('com.zarq/utility');
      final fcmToken = await utilityChannel.invokeMethod('getFCMToken');

      if (fcmToken != null && fcmToken.isNotEmpty) {
        print(
          "[AuthWrapper] 📤 Uploading FCM token to server: ${fcmToken.substring(0, 20)}...",
        );

        // Get actual device ID
        final actualDeviceId = await SignalService.getDeviceId();
        print("[AuthWrapper] Using device ID: $actualDeviceId");

        final token = await user.getIdToken();
        final url = Uri.parse('${AppConfig.baseUrl}/v1/fcm/token');

        final response = await http.post(
          url,
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'fcm_token': fcmToken,
            'device_id': actualDeviceId,
            'platform': 'android',
          }),
        );

        if (response.statusCode == 200) {
          print("[AuthWrapper] ✅ FCM token uploaded successfully");
        } else {
          print(
            "[AuthWrapper] ❌ FCM token upload failed: ${response.statusCode} - ${response.body}",
          );
        }
      } else {
        print(
          "[AuthWrapper] ⚠️ No FCM token available yet - will retry on next app start",
        );
        // Schedule retry after 2 seconds (token might be generated soon)
        Future.delayed(const Duration(seconds: 2), () {
          _uploadFCMTokenToServer();
        });
      }
    } catch (e) {
      print("[AuthWrapper] ❌ Error uploading FCM token: $e");
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

  Future<bool> _checkIfProfileExists() =>
      OpaqueAuthService.profileExists(widget.user);

  // Check for backups after login (only for new users or after clear data)
  Future<void> _checkForBackupsAfterLogin() async {
    // Wait a bit for UI to settle
    await Future.delayed(const Duration(milliseconds: 800));

    if (!mounted) return;

    try {
      // Check for backups in MediaStore
      debugPrint(
        '[BackupDetection] 🔍 Checking for backups (MediaStore + old files)...',
      );

      final backupFiles = await MediaStoreBackupService.listAllBackups();
      debugPrint(
        '[BackupDetection] 📋 Found ${backupFiles.length} total backup files',
      );

      if (backupFiles.isEmpty) {
        debugPrint('[BackupDetection] ⚠️ No backup files found');
        return;
      }

      debugPrint(
        '[BackupDetection] ✅ Found ${backupFiles.length} backup(s) after login',
      );

      // Backups are already sorted by modification time (newest first) from MediaStore
      final mostRecentBackup = backupFiles.first;
      final backupUri = mostRecentBackup['uri'] as String;
      final backupModified = mostRecentBackup['dateModified'] as int;

      final prefs = await SharedPreferences.getInstance();
      final lastRestoredBackupUri = prefs.getString('last_restored_backup_uri');
      final lastRestoredTimestamp = prefs.getInt(
        'last_restored_backup_timestamp',
      );

      // Skip if this exact backup was already restored
      if (lastRestoredBackupUri == backupUri &&
          lastRestoredTimestamp == backupModified) {
        debugPrint(
          '[BackupDetection] ✅ Most recent backup was already restored. Skipping.',
        );
        return;
      }

      debugPrint('[BackupDetection] 🆕 Found new/unrestored backup');

      // Show restore dialog
      if (mounted) {
        final targetContext = MyApp.navigatorKey.currentContext ?? context;
        _showBackupRestoreDialog(targetContext, backupFiles);
      }
    } catch (e) {
      debugPrint('[BackupDetection] Error checking backups: $e');
    }
  }

  void _showBackupRestoreDialog(
    BuildContext targetContext,
    List<Map<String, dynamic>> backups,
  ) {
    final mostRecentBackup = backups.first;
    final backupDate = DateTime.fromMillisecondsSinceEpoch(
      mostRecentBackup['dateModified'] as int,
    ).toLocal();
    final backupSize = MediaStoreBackupService.formatBytes(
      mostRecentBackup['size'] as int? ?? 0,
    );
    final backupName =
        mostRecentBackup['name'] as String? ?? 'Encrypted Backup';

    final months = const [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final formattedDate =
        '${backupDate.day} ${months[backupDate.month - 1]} ${backupDate.year}, ${backupDate.hour.toString().padLeft(2, '0')}:${backupDate.minute.toString().padLeft(2, '0')}';

    showDialog(
      context: targetContext,
      barrierDismissible: false,
      builder: (context) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final surfaceColor = isDark ? const Color(0xFF19202A) : Colors.white;
        final cardColor = isDark
            ? const Color(0xFF222B38)
            : const Color(0xFFF4F6F9);
        final borderColor = isDark
            ? const Color(0xFF2E3847)
            : const Color(0xFFE5E7EB);
        final primaryTextColor = isDark
            ? const Color(0xFFE0E6EF)
            : const Color(0xFF1A1C22);
        final secondaryTextColor = isDark
            ? const Color(0xFF97A3B6)
            : const Color(0xFF73747C);
        final brandAccent = isDark
            ? const Color(0xFF9BBCFF)
            : const Color(0xFF335FE8);
        final lockAccent = isDark
            ? const Color(0xFF88BCA8)
            : const Color(0xFF2E7D5B);

        return Dialog(
          backgroundColor: surfaceColor,
          surfaceTintColor: Colors.transparent,
          elevation: 6,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 24,
            vertical: 24,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: BorderSide(color: borderColor),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(22, 24, 22, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: brandAccent.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: brandAccent.withOpacity(0.2),
                          ),
                        ),
                        child: Icon(
                          Icons.settings_backup_restore_rounded,
                          color: brandAccent,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'OPAQUE BACKUP',
                              style: TextStyle(
                                fontFamily: 'Inter',
                                fontSize: 10.5,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1.2,
                                color: brandAccent,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Backup Found',
                              style: TextStyle(
                                fontFamily: 'Inter',
                                fontSize: 19,
                                fontWeight: FontWeight.w600,
                                letterSpacing: -0.4,
                                color: primaryTextColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'We detected an encrypted backup from your previous account session. Would you like to restore your chats and media?',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 13,
                      height: 1.45,
                      color: secondaryTextColor,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: cardColor,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: borderColor),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: lockAccent.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.lock_outline_rounded,
                                    size: 12,
                                    color: lockAccent,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Encrypted Backup',
                                    style: TextStyle(
                                      fontFamily: 'Inter',
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w600,
                                      color: lockAccent,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const Spacer(),
                            if (backups.length > 1)
                              Text(
                                '${backups.length} backups available',
                                style: TextStyle(
                                  fontFamily: 'Inter',
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                  color: secondaryTextColor,
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text(
                          backupName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                            color: primaryTextColor,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Divider(height: 1, color: borderColor),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Icon(
                              Icons.schedule_rounded,
                              size: 14,
                              color: secondaryTextColor,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                formattedDate,
                                style: TextStyle(
                                  fontFamily: 'Inter',
                                  fontSize: 12,
                                  color: secondaryTextColor,
                                ),
                              ),
                            ),
                            Icon(
                              Icons.sd_storage_outlined,
                              size: 14,
                              color: secondaryTextColor,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              backupSize,
                              style: TextStyle(
                                fontFamily: 'Inter',
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: secondaryTextColor,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 22),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: primaryTextColor,
                            side: BorderSide(color: borderColor),
                            padding: const EdgeInsets.symmetric(vertical: 13),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          onPressed: () => Navigator.pop(context),
                          child: Text(
                            'Skip',
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: secondaryTextColor,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: brandAccent,
                            foregroundColor: isDark
                                ? const Color(0xFF0F172A)
                                : Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 13),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            elevation: 0,
                          ),
                          onPressed: () {
                            Navigator.pop(context);
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) =>
                                    const BackupManagementScreen(),
                              ),
                            );
                          },
                          child: Text(
                            'Review & Restore',
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: isDark
                                  ? const Color(0xFF0F172A)
                                  : Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _initializationFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return ValueListenableBuilder<double>(
            valueListenable: _initProgress,
            builder: (_, progress, __) => AuthStartupView(progress: progress),
          );
        }
        if (snapshot.hasError) {
          return AuthStartupView(
            error: OpaqueAuthService.errorMessage(snapshot.error!),
            onRetry: () {
              if (mounted)
                setState(() {
                  _initializationFuture = _initializeUserServices();
                });
            },
            onSignOut: () async {
              await FirebaseAuth.instance.signOut();
              if (mounted)
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const AuthGate()),
                  (_) => false,
                );
            },
          );
        }

        final bool isReady = snapshot.data ?? false;
        if (isReady) {
          return const HomeScreen();
        } else {
          // User has Firebase account but no backend profile - complete registration
          return OpaqueAuthScreen(
            user: widget.user,
            onComplete: () {
              if (mounted)
                setState(() {
                  _initializationFuture = _initializeUserServices();
                });
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
    // Android/media directory doesn't require MANAGE_EXTERNAL_STORAGE permission
    // Apps can read/write to their own Android/media/package_name/ directory without special permissions
    // This is Google Play compliant and follows WhatsApp's approach
    return true;
  }

  void _showPermissionDeniedDialog() {
    showDialog(
      context: context,
      builder: (context) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final surfaceColor = isDark ? const Color(0xFF19202A) : Colors.white;
        final borderColor = isDark
            ? const Color(0xFF2E3847)
            : const Color(0xFFE5E7EB);
        final primaryTextColor = isDark
            ? const Color(0xFFE0E6EF)
            : const Color(0xFF1A1C22);
        final secondaryTextColor = isDark
            ? const Color(0xFF97A3B6)
            : const Color(0xFF73747C);
        final brandAccent = isDark
            ? const Color(0xFF9BBCFF)
            : const Color(0xFF335FE8);

        return Dialog(
          backgroundColor: surfaceColor,
          surfaceTintColor: Colors.transparent,
          elevation: 6,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 24,
            vertical: 24,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: BorderSide(color: borderColor),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(22, 24, 22, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: brandAccent.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: brandAccent.withOpacity(0.2),
                          ),
                        ),
                        child: Icon(
                          Icons.folder_shared_outlined,
                          color: brandAccent,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'PERMISSIONS',
                              style: TextStyle(
                                fontFamily: 'Inter',
                                fontSize: 10.5,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1.2,
                                color: brandAccent,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Storage Permission',
                              style: TextStyle(
                                fontFamily: 'Inter',
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                                letterSpacing: -0.3,
                                color: primaryTextColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Storage permission is needed to detect and restore backups. Please grant permission in app settings.',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 13,
                      height: 1.45,
                      color: secondaryTextColor,
                    ),
                  ),
                  const SizedBox(height: 22),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: primaryTextColor,
                            side: BorderSide(color: borderColor),
                            padding: const EdgeInsets.symmetric(vertical: 13),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          onPressed: () => Navigator.pop(context),
                          child: Text(
                            'Cancel',
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: secondaryTextColor,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: brandAccent,
                            foregroundColor: isDark
                                ? const Color(0xFF0F172A)
                                : Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 13),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            elevation: 0,
                          ),
                          onPressed: () {
                            Navigator.pop(context);
                            openAppSettings();
                          },
                          child: Text(
                            'Open Settings',
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: isDark
                                  ? const Color(0xFF0F172A)
                                  : Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
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

      // TEMPORARY: Check for backups in BOTH MediaStore (new) and file system (old)
      final backupFiles = await MediaStoreBackupService.listAllBackups();

      if (backupFiles.isEmpty) {
        return;
      }

      // Backups are already sorted by modification time (newest first) from MediaStore
      final mostRecentBackup = backupFiles.first;
      final backupUri = mostRecentBackup['uri'] as String;
      final backupModified = mostRecentBackup['dateModified'] as int;

      final prefs = await SharedPreferences.getInstance();
      final lastRestoredBackupUri = prefs.getString('last_restored_backup_uri');
      final lastRestoredTimestamp = prefs.getInt(
        'last_restored_backup_timestamp',
      );

      // Skip if this exact backup was already restored
      if (lastRestoredBackupUri == backupUri &&
          lastRestoredTimestamp == backupModified) {
        return;
      }

      // Show restore dialog
      if (mounted) {
        _showRestoreDialog(backupFiles);
      }
    } catch (e) {
      // print('[BackupDetection] Error checking backups: $e');
    }
  }

  void _showRestoreDialog(List<Map<String, dynamic>> backups) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final surfaceColor = isDark ? const Color(0xFF19202A) : Colors.white;
        final borderColor = isDark
            ? const Color(0xFF2E3847)
            : const Color(0xFFE5E7EB);
        final primaryTextColor = isDark
            ? const Color(0xFFE0E6EF)
            : const Color(0xFF1A1C22);
        final secondaryTextColor = isDark
            ? const Color(0xFF97A3B6)
            : const Color(0xFF73747C);
        final brandAccent = isDark
            ? const Color(0xFF9BBCFF)
            : const Color(0xFF335FE8);

        return Dialog(
          backgroundColor: surfaceColor,
          surfaceTintColor: Colors.transparent,
          elevation: 6,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 24,
            vertical: 24,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: BorderSide(color: borderColor),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(22, 24, 22, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: brandAccent.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: brandAccent.withOpacity(0.2),
                          ),
                        ),
                        child: Icon(
                          Icons.settings_backup_restore_rounded,
                          color: brandAccent,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'OPAQUE BACKUP',
                              style: TextStyle(
                                fontFamily: 'Inter',
                                fontSize: 10.5,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1.2,
                                color: brandAccent,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Backup Found',
                              style: TextStyle(
                                fontFamily: 'Inter',
                                fontSize: 19,
                                fontWeight: FontWeight.w600,
                                letterSpacing: -0.4,
                                color: primaryTextColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'We detected an encrypted backup from your previous account session. Would you like to restore your chats and media?',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 13,
                      height: 1.45,
                      color: secondaryTextColor,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildBackupInfo(backups.first),
                  const SizedBox(height: 22),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: primaryTextColor,
                            side: BorderSide(color: borderColor),
                            padding: const EdgeInsets.symmetric(vertical: 13),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          onPressed: () => Navigator.pop(context),
                          child: Text(
                            'Skip',
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: secondaryTextColor,
                            ),
                          ),
                        ),
                      ),
                      if (backups.length > 1) ...[
                        const SizedBox(width: 8),
                        OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: brandAccent,
                            side: BorderSide(
                              color: brandAccent.withOpacity(0.4),
                            ),
                            padding: const EdgeInsets.symmetric(
                              vertical: 13,
                              horizontal: 12,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          onPressed: () {
                            Navigator.pop(context);
                            _showBackupsList(backups);
                          },
                          child: Text(
                            'View All',
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: brandAccent,
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(width: 8),
                      Expanded(
                        child: FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: brandAccent,
                            foregroundColor: isDark
                                ? const Color(0xFF0F172A)
                                : Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 13),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            elevation: 0,
                          ),
                          onPressed: () {
                            Navigator.pop(context);
                            _restoreBackup(backups.first['uri'] as String);
                          },
                          child: Text(
                            'Restore',
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: isDark
                                  ? const Color(0xFF0F172A)
                                  : Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildBackupInfo(Map<String, dynamic> backup) {
    final fileName = backup['name'] as String? ?? 'Encrypted Backup';
    final size = MediaStoreBackupService.formatBytes(
      backup['size'] as int? ?? 0,
    );
    final date = DateTime.fromMillisecondsSinceEpoch(
      backup['dateModified'] as int? ?? 0,
    ).toLocal();

    final months = const [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final formattedDate =
        '${date.day} ${months[date.month - 1]} ${date.year}, ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';

    return Builder(
      builder: (context) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final cardColor = isDark
            ? const Color(0xFF222B38)
            : const Color(0xFFF4F6F9);
        final borderColor = isDark
            ? const Color(0xFF2E3847)
            : const Color(0xFFE5E7EB);
        final primaryTextColor = isDark
            ? const Color(0xFFE0E6EF)
            : const Color(0xFF1A1C22);
        final secondaryTextColor = isDark
            ? const Color(0xFF97A3B6)
            : const Color(0xFF73747C);
        final lockAccent = isDark
            ? const Color(0xFF88BCA8)
            : const Color(0xFF2E7D5B);

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: cardColor,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: borderColor),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: lockAccent.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.lock_outline_rounded,
                          size: 12,
                          color: lockAccent,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Encrypted Backup',
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 10.5,
                            fontWeight: FontWeight.w600,
                            color: lockAccent,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                fileName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: primaryTextColor,
                ),
              ),
              const SizedBox(height: 10),
              Divider(height: 1, color: borderColor),
              const SizedBox(height: 10),
              Row(
                children: [
                  Icon(
                    Icons.schedule_rounded,
                    size: 14,
                    color: secondaryTextColor,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      formattedDate,
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 12,
                        color: secondaryTextColor,
                      ),
                    ),
                  ),
                  Icon(
                    Icons.sd_storage_outlined,
                    size: 14,
                    color: secondaryTextColor,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    size,
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: secondaryTextColor,
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  void _showBackupsList(List<Map<String, dynamic>> backups) {
    showDialog(
      context: context,
      builder: (context) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final surfaceColor = isDark ? const Color(0xFF19202A) : Colors.white;
        final cardColor = isDark
            ? const Color(0xFF222B38)
            : const Color(0xFFF4F6F9);
        final borderColor = isDark
            ? const Color(0xFF2E3847)
            : const Color(0xFFE5E7EB);
        final primaryTextColor = isDark
            ? const Color(0xFFE0E6EF)
            : const Color(0xFF1A1C22);
        final secondaryTextColor = isDark
            ? const Color(0xFF97A3B6)
            : const Color(0xFF73747C);
        final brandAccent = isDark
            ? const Color(0xFF9BBCFF)
            : const Color(0xFF335FE8);

        final months = const [
          'Jan',
          'Feb',
          'Mar',
          'Apr',
          'May',
          'Jun',
          'Jul',
          'Aug',
          'Sep',
          'Oct',
          'Nov',
          'Dec',
        ];

        return Dialog(
          backgroundColor: surfaceColor,
          surfaceTintColor: Colors.transparent,
          elevation: 6,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 24,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: BorderSide(color: borderColor),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420, maxHeight: 520),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: brandAccent.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          Icons.history_rounded,
                          color: brandAccent,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Available Backups',
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            letterSpacing: -0.3,
                            color: primaryTextColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Flexible(
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: backups.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final backup = backups[index];
                        final fileName = backup['name'] as String? ?? 'Backup';
                        final size = MediaStoreBackupService.formatBytes(
                          backup['size'] as int? ?? 0,
                        );
                        final date = DateTime.fromMillisecondsSinceEpoch(
                          backup['dateModified'] as int? ?? 0,
                        ).toLocal();
                        final formattedDate =
                            '${date.day} ${months[date.month - 1]} ${date.year}, ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
                        final uri = backup['uri'] as String;

                        return Material(
                          color: cardColor,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                            side: BorderSide(color: borderColor),
                          ),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(14),
                            onTap: () {
                              Navigator.pop(context);
                              _restoreBackup(uri);
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 12,
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    index == 0
                                        ? Icons.settings_backup_restore_rounded
                                        : Icons.folder_outlined,
                                    color: index == 0
                                        ? brandAccent
                                        : secondaryTextColor,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          fileName,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontFamily: 'Inter',
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600,
                                            color: primaryTextColor,
                                          ),
                                        ),
                                        const SizedBox(height: 3),
                                        Text(
                                          '$formattedDate • $size',
                                          style: TextStyle(
                                            fontFamily: 'Inter',
                                            fontSize: 11,
                                            color: secondaryTextColor,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Icon(
                                    Icons.arrow_forward_ios_rounded,
                                    size: 13,
                                    color: secondaryTextColor,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: primaryTextColor,
                        side: BorderSide(color: borderColor),
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      onPressed: () => Navigator.pop(context),
                      child: Text(
                        'Cancel',
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: secondaryTextColor,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _restoreBackup(String uri) async {
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
        builder: (context) {
          final isDark = Theme.of(context).brightness == Brightness.dark;
          final surfaceColor = isDark ? const Color(0xFF19202A) : Colors.white;
          final borderColor = isDark
              ? const Color(0xFF2E3847)
              : const Color(0xFFE5E7EB);
          final primaryTextColor = isDark
              ? const Color(0xFFE0E6EF)
              : const Color(0xFF1A1C22);
          final secondaryTextColor = isDark
              ? const Color(0xFF97A3B6)
              : const Color(0xFF73747C);
          final brandAccent = isDark
              ? const Color(0xFF9BBCFF)
              : const Color(0xFF335FE8);

          return Dialog(
            backgroundColor: surfaceColor,
            surfaceTintColor: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: BorderSide(color: borderColor),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 22),
              child: Row(
                children: [
                  SizedBox(
                    width: 28,
                    height: 28,
                    child: CircularProgressIndicator(
                      color: brandAccent,
                      strokeWidth: 2.5,
                    ),
                  ),
                  const SizedBox(width: 20),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Restoring backup...',
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: primaryTextColor,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          'Decrypting database and media...',
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 12,
                            color: secondaryTextColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );

      final backupService = BackupService();

      // TEMPORARY: Read backup from either MediaStore or old file system
      final bytes = await MediaStoreBackupService.readBackupFileUniversal(uri);
      if (bytes == null) {
        throw Exception('Failed to read backup');
      }

      // Write to temporary file for decryption
      final tempDir = Directory.systemTemp;
      final tempFile = File(
        '${tempDir.path}/temp_restore_${DateTime.now().millisecondsSinceEpoch}.encrypted',
      );
      await tempFile.writeAsBytes(bytes);

      final backupData = await backupService.decryptBackup(
        tempFile,
        passphrase,
      );
      await backupService.restoreBackup(backupData);

      // Clean up temp file
      try {
        if (await tempFile.exists()) {
          await tempFile.delete();
        }
      } catch (e) {
        // Ignore cleanup errors
      }

      // Show SUCCESS notification with sound
      await BackupNotificationService.showSuccessNotification('Restore');

      if (mounted) {
        Navigator.of(context).pop(); // Close progress dialog

        // Show success message briefly before restarting
        OpaqueToast.success(
          context,
          'Backup restored successfully! Restarting app...',
        );

        // Wait for toast to show, then restart
        await Future.delayed(const Duration(seconds: 2));

        // Restart the app
        Restart.restartApp();
      }
    } catch (e) {
      // print('[BackupDetection] Restore error: $e');

      // Show FAILURE notification with sound
      await BackupNotificationService.showFailureNotification(
        'Restore',
        e.toString().contains('Incorrect passphrase')
            ? 'Incorrect password'
            : 'Restore error occurred',
      );

      if (mounted) {
        Navigator.of(context).pop(); // Close progress dialog

        OpaqueToast.error(
          context,
          'Restore failed: ${e.toString().contains('Incorrect passphrase') ? 'Incorrect passphrase' : 'Error - $e'}',
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
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        final surfaceColor = isDark ? const Color(0xFF19202A) : Colors.white;
        final cardColor = isDark
            ? const Color(0xFF222B38)
            : const Color(0xFFF4F6F9);
        final borderColor = isDark
            ? const Color(0xFF2E3847)
            : const Color(0xFFE5E7EB);
        final primaryTextColor = isDark
            ? const Color(0xFFE0E6EF)
            : const Color(0xFF1A1C22);
        final secondaryTextColor = isDark
            ? const Color(0xFF97A3B6)
            : const Color(0xFF73747C);
        final brandAccent = isDark
            ? const Color(0xFF9BBCFF)
            : const Color(0xFF335FE8);

        return Dialog(
          backgroundColor: surfaceColor,
          surfaceTintColor: Colors.transparent,
          elevation: 6,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 24,
            vertical: 24,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: BorderSide(color: borderColor),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(22, 24, 22, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: brandAccent.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: brandAccent.withOpacity(0.2),
                          ),
                        ),
                        child: Icon(
                          Icons.lock_outline_rounded,
                          color: brandAccent,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'SECURITY',
                              style: TextStyle(
                                fontFamily: 'Inter',
                                fontSize: 10.5,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1.2,
                                color: brandAccent,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Enter Passphrase',
                              style: TextStyle(
                                fontFamily: 'Inter',
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                                letterSpacing: -0.3,
                                color: primaryTextColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Enter your 64-character or custom passphrase to decrypt and restore this backup.',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 13,
                      height: 1.45,
                      color: secondaryTextColor,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: controller,
                    obscureText: true,
                    autofocus: true,
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 14,
                      color: primaryTextColor,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Backup passphrase',
                      hintStyle: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 13,
                        color: secondaryTextColor,
                      ),
                      filled: true,
                      fillColor: cardColor,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(color: borderColor),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(color: borderColor),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(color: brandAccent, width: 1.5),
                      ),
                    ),
                  ),
                  const SizedBox(height: 22),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: primaryTextColor,
                            side: BorderSide(color: borderColor),
                            padding: const EdgeInsets.symmetric(vertical: 13),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          onPressed: () => Navigator.pop(ctx),
                          child: Text(
                            'Cancel',
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: secondaryTextColor,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: brandAccent,
                            foregroundColor: isDark
                                ? const Color(0xFF0F172A)
                                : Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 13),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            elevation: 0,
                          ),
                          onPressed: () {
                            password = controller.text;
                            Navigator.pop(ctx);
                          },
                          child: Text(
                            'Restore',
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: isDark
                                  ? const Color(0xFF0F172A)
                                  : Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
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
