import '../widgets/backup_design.dart';
import '../widgets/notes_design.dart';
import '../services/user_settings_provider.dart';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:restart_app/restart_app.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:file_picker/file_picker.dart';
import '../services/backup_service.dart';
import '../services/backup_settings_provider.dart';
import '../services/backup_notification_service.dart';
import '../services/auto_backup_manager.dart';
import '../services/mediastore_backup_service.dart';
import '../services/secure_storage_service.dart';
import '../widgets/call_aware_screen.dart';
import 'backup_info_screen.dart';
import 'google_drive_backups_screen.dart';
import 'package:provider/provider.dart';
import '../widgets/opaque_toast.dart';

class BackupManagementScreen extends StatefulWidget {
  const BackupManagementScreen({super.key});

  @override
  State<BackupManagementScreen> createState() => _BackupManagementScreenState();
}

class _BackupManagementScreenState extends State<BackupManagementScreen>
    with SingleTickerProviderStateMixin {
  final BackupService _backupService = BackupService();
  List<Map<String, dynamic>> _backupsList = [];
  bool _isLoading = false;
  double _backupProgress = 0.0;
  String _backupStatus = '';
  bool _isBackupInProgress = false;
  bool _backupCancellationRequested = false;
  bool _isGoogleDriveSignedIn = false;
  String? _googleDriveEmail;
  bool _isBatteryOptimizationDisabled = true;
  bool _highlightNextBackup = false;
  late AnimationController _highlightController;
  late Animation<Color?> _highlightAnimation;
  static MethodChannel _backupChannel = MethodChannel('com.zarq/backup');

  @override
  void initState() {
    super.initState();
    _loadBackupsList();
    _loadCachedGoogleDriveStatus(); // Load cached state for instant UI (no verification needed)
    _checkBatteryOptimization();
    // Note: We don't verify Google Drive status here - it will be checked when user actually uses it

    // Initialize animation controller for highlight effect
    _highlightController = AnimationController(
      duration: Duration(milliseconds: 800),
      vsync: this,
    );

    _highlightAnimation =
        ColorTween(
          begin: _ui.blue.withOpacity(0.3),
          end: _ui.blue.withOpacity(0.1),
        ).animate(
          CurvedAnimation(
            parent: _highlightController,
            curve: Curves.easeInOut,
          ),
        );

    // Set up MethodChannel handler for notification cancel action
    _backupChannel.setMethodCallHandler(_handleBackupChannelMethod);
  }

  /// Handle method calls from native Android (e.g., cancel from notification)
  Future<dynamic> _handleBackupChannelMethod(MethodCall call) async {
    if (call.method == 'cancelBackup') {
      debugPrint('[BackupManagement] Cancel backup called from notification');
      if (_isBackupInProgress && !_backupCancellationRequested) {
        _cancelBackup();
      }
      return true;
    }
    return null;
  }

  @override
  void dispose() {
    _highlightController.dispose();
    // DON'T remove the handler here - backup operations continue in background
    // The handler needs to remain active so notification cancel button works
    // _backupChannel.setMethodCallHandler(null);
    super.dispose();
  }

  Future<void> _checkBatteryOptimization() async {
    final isDisabled =
        await BackupNotificationService.isBatteryOptimizationDisabled();
    setState(() {
      _isBatteryOptimizationDisabled = isDisabled;
    });
  }

  Future<void> _requestBatteryOptimizationExemption() async {
    try {
      // Open battery settings via MethodChannel
      await _backupChannel.invokeMethod('requestBatteryOptimizationExemption');

      // Show guidance message
      _showSnackbar(
        'Tap Battery → Set to "Unrestricted" & enable "Allow background activity"',
        isError: false,
      );

      // Recheck status after a delay (user might come back from settings)
      Future.delayed(Duration(seconds: 2), () {
        if (mounted) {
          _checkBatteryOptimization();
        }
      });
    } catch (e) {
      debugPrint('[BackupManagement] Error opening battery settings: $e');
      _showSnackbar('Failed to open battery settings', isError: true);
    }
  }

  /// Load cached Google Drive status from SharedPreferences for instant UI display
  Future<void> _loadCachedGoogleDriveStatus() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedSignedIn = prefs.getBool('google_drive_signed_in') ?? false;
      final cachedEmail = prefs.getString('google_drive_email');

      if (mounted) {
        setState(() {
          _isGoogleDriveSignedIn = cachedSignedIn;
          _googleDriveEmail = cachedEmail;
        });
      }

      debugPrint(
        '[BackupManagement] Loaded cached Google Drive status: signed_in=$cachedSignedIn, email=$cachedEmail',
      );
    } catch (e) {
      debugPrint(
        '[BackupManagement] Error loading cached Google Drive status: $e',
      );
    }
  }

  /// Update Google Drive cache (helper method to avoid code duplication)
  Future<void> _updateGoogleDriveCache(bool isSignedIn, String? email) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('google_drive_signed_in', isSignedIn);
      if (email != null) {
        await prefs.setString('google_drive_email', email);
      } else {
        await prefs.remove('google_drive_email');
      }
      debugPrint(
        '[BackupManagement] Updated Google Drive cache: signed_in=$isSignedIn, email=$email',
      );
    } catch (e) {
      debugPrint('[BackupManagement] Error updating Google Drive cache: $e');
    }
  }

  /// Check actual Google Drive status and update cache
  Future<void> _checkGoogleDriveStatus() async {
    final isSignedIn = await _backupService.isSignedInToGoogleDrive();
    final email = await _backupService.getGoogleDriveAccountEmail();

    // Save to cache
    await _updateGoogleDriveCache(isSignedIn, email);

    if (mounted) {
      setState(() {
        _isGoogleDriveSignedIn = isSignedIn;
        _googleDriveEmail = email;
      });
    }
  }

  Future<void> _loadBackupsList() async {
    setState(() => _isLoading = true);

    try {
      // TEMPORARY: Load from BOTH MediaStore (new) and file system (old)
      debugPrint(
        '[BackupManagement] Loading backups from MediaStore + old files...',
      );

      // List ALL backup files (MediaStore + old file system)
      final backups = await MediaStoreBackupService.listAllBackups();
      debugPrint(
        '[BackupManagement] Found ${backups.length} total backup files',
      );

      if (!mounted) return;
      setState(() {
        _backupsList = backups;
      });
    } catch (e) {
      debugPrint('[BackupManagement] Error loading backups: $e');
      if (!mounted) return;
      setState(() {
        _backupsList = [];
      });
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<bool> _requestStoragePermission() async {
    // Android/media directory doesn't require MANAGE_EXTERNAL_STORAGE permission
    // Apps can access their own Android/media/package_name/ directory without special permissions
    return true;
  }

  Future<void> _createBackup() async {
    _restoring = false;
    if (_destination == 'Google Drive') {
      if (!_isGoogleDriveSignedIn) {
        await _signInToGoogleDrive();
        if (!mounted || !_isGoogleDriveSignedIn) return;
      }
      await _createGoogleDriveBackup();
    } else {
      await _createLocalBackup();
    }
  }

  Future<void> _createLocalBackup() async {
    if (!await _requestStoragePermission()) {
      _showSnackbar('Storage permission required', isError: true);
      return;
    }

    final passphrase = await _askForPassword(
      title: 'Create Backup',
      hint: 'Enter a strong passphrase',
    );

    if (passphrase == null || passphrase.isEmpty) {
      _showSnackbar('Backup cancelled');
      return;
    }

    if (!mounted) return;

    setState(() {
      _isBackupInProgress = true;
      _backupCancellationRequested = false;
      _backupProgress = 0.0;
      _backupStatus = 'Initializing backup...';
    });

    try {
      // Show initial notification (persists even if user leaves screen)
      await BackupNotificationService.showProgressNotification(
        'Starting backup...',
        0,
      );

      // Check cancellation
      if (_backupCancellationRequested) {
        throw Exception('Backup cancelled by user');
      }

      // Simulate progress steps
      await _updateProgress(0.2, 'Collecting messages...');
      await BackupNotificationService.showProgressNotification(
        'Collecting messages...',
        20,
      );

      // Check cancellation
      if (_backupCancellationRequested) {
        throw Exception('Backup cancelled by user');
      }

      // Local backup: Messages only (no media) to prevent Out of Memory errors
      final backupData = await _backupService.createLocalBackup(
        includeMedia: false, // WhatsApp approach: Media stays on device
      );

      await _updateProgress(0.5, 'Encrypting backup...');
      await BackupNotificationService.showProgressNotification(
        'Encrypting backup...',
        50,
      );

      // Check cancellation
      if (_backupCancellationRequested) {
        throw Exception('Backup cancelled by user');
      }

      final encryptedFile = await _backupService.encryptBackup(
        backupData,
        passphrase,
      );

      // Check cancellation
      if (_backupCancellationRequested) {
        throw Exception('Backup cancelled by user');
      }

      // File operations should complete even if widget is disposed
      debugPrint(
        '[BackupManagement] Preparing to save encrypted file: ${encryptedFile.path}',
      );

      await BackupNotificationService.showProgressNotification(
        'Saving to local storage...',
        70,
      );

      // Check cancellation
      if (_backupCancellationRequested) {
        throw Exception('Backup cancelled by user');
      }

      final timestamp = DateTime.now()
          .toIso8601String()
          .replaceAll(':', '-')
          .split('.')[0];
      final fileName = 'backup_$timestamp.encrypted';
      debugPrint('[BackupManagement] Saving to MediaStore: $fileName');

      await BackupNotificationService.showProgressNotification(
        'Finalizing...',
        90,
      );

      // Save to MediaStore Downloads
      final uri = await MediaStoreBackupService.saveBackupFile(
        encryptedFile,
        fileName,
      );

      if (uri == null) {
        throw Exception('Failed to save backup to MediaStore');
      }

      debugPrint(
        '[BackupManagement] File saved successfully to MediaStore: $uri',
      );

      // Check cancellation before showing success
      if (_backupCancellationRequested) {
        throw Exception('Backup cancelled by user');
      }

      // Show success notification (visible even if user left screen)
      await BackupNotificationService.showSuccessNotification('Local');

      // Only update UI if still mounted
      if (mounted) {
        await _updateProgress(1.0, 'Backup completed!');
        _showSnackbar('Backup created successfully!', isError: false);
        await _loadBackupsList();
      } else {
        debugPrint(
          '[BackupManagement] Widget disposed, but backup saved successfully',
        );
      }
    } catch (e) {
      debugPrint('[BackupManagement] Backup error: $e');

      // Handle cancellation differently from errors
      if (e.toString().contains('cancelled by user')) {
        debugPrint('[BackupManagement] Backup cancelled by user');

        // Show cancellation notification
        await BackupNotificationService.showFailureNotification(
          'Local',
          'Backup cancelled',
        );

        if (mounted) {
          _showSnackbar('Backup cancelled', isError: false);
        }
      } else {
        // Show failure notification (visible even if user left screen)
        await BackupNotificationService.showFailureNotification(
          'Local',
          e.toString().length > 100 ? 'Backup error occurred' : e.toString(),
        );

        if (mounted) {
          _showSnackbar('Backup failed: $e', isError: true);
        }
      }
    } finally {
      if (mounted) {
        setState(() {
          _isBackupInProgress = false;
          _backupCancellationRequested = false;
          _backupProgress = 0.0;
          _backupStatus = '';
        });
      }
    }
  }

  Future<void> _createGoogleDriveBackup() async {
    // Check cache - if not signed in, prompt user
    if (!_isGoogleDriveSignedIn) {
      _showSnackbar('Please sign in to Google Drive first', isError: true);
      return;
    }

    // Optimistic execution: Trust cache and try to create backup
    // getDriveApi() inside createGoogleDriveBackup() will handle auth if needed

    // The approved media preference is selected on the Backup tab.
    final excludeMediaDays = _mediaDays;

    final passphrase = await _askForPassword(
      title: 'Create Google Drive Backup',
      hint: 'Enter a strong passphrase',
    );

    if (passphrase == null || passphrase.isEmpty) {
      _showSnackbar('Backup cancelled');
      return;
    }

    if (!mounted) return;

    setState(() {
      _isBackupInProgress = true;
      _backupCancellationRequested = false;
      _backupProgress = 0.0;
      _backupStatus = 'Initializing backup...';
    });

    try {
      // Show initial notification (persists even if user leaves screen)
      await BackupNotificationService.showProgressNotification(
        'Starting backup...',
        0,
      );

      // Check cancellation
      if (_backupCancellationRequested) {
        throw Exception('Backup cancelled by user');
      }

      await _updateProgress(0.1, 'Connecting to Google Drive...');
      await BackupNotificationService.showProgressNotification(
        'Connecting to Google Drive...',
        10,
      );

      // Check cancellation
      if (_backupCancellationRequested) {
        throw Exception('Backup cancelled by user');
      }

      // IMPORTANT: Pass cancellation checker to backup service
      // The service will check this before each major operation
      final fileId = await _backupService.createGoogleDriveBackup(
        passphrase: passphrase,
        excludeMediaOlderThanDays: excludeMediaDays,
        shouldCancel: () =>
            _backupCancellationRequested, // Check cancellation at each step
        onMediaProgress: (current, total, fileName) {
          // CRITICAL: Check cancellation during media upload
          if (_backupCancellationRequested) {
            debugPrint(
              '[BackupManagement] Cancellation detected during media upload, aborting...',
            );
            // Note: The backup service needs to check for cancellation internally
            // This callback just updates UI, actual cancellation happens in service
            return;
          }

          // Calculate progress
          final mediaProgress =
              0.3 + (current / total) * 0.6; // 30-90% for media upload
          final mediaStatus = 'Uploading media $current/$total: $fileName';
          final notificationProgress = (mediaProgress * 100).toInt();

          // CRITICAL: Update notification even if widget is disposed
          // User needs to see progress even after navigating away
          BackupNotificationService.showProgressNotification(
            'Uploading media files ($current/$total)',
            notificationProgress,
          );

          debugPrint(
            '[BackupManagement] Media upload: $current/$total - $fileName',
          );

          // Update UI state only if widget is still mounted
          if (mounted) {
            setState(() {
              _backupProgress = mediaProgress;
              _backupStatus = mediaStatus;
            });
          }
        },
      );

      if (fileId == null) {
        throw Exception('Failed to upload to Google Drive');
      }

      // Check cancellation
      if (_backupCancellationRequested) {
        throw Exception('Backup cancelled by user');
      }

      await _updateProgress(0.95, 'Finalizing...');
      await BackupNotificationService.showProgressNotification(
        'Finalizing...',
        95,
      );

      // Check cancellation before showing success
      if (_backupCancellationRequested) {
        throw Exception('Backup cancelled by user');
      }

      // Show success notification (visible even if user left screen)
      await BackupNotificationService.showSuccessNotification('Google Drive');

      if (mounted) {
        await _updateProgress(1.0, 'Backup uploaded with media!');
        _showSnackbar(
          'Backup uploaded to Google Drive successfully!',
          isError: false,
        );

        // Update cache after successful backup
        _updateGoogleDriveCache(_isGoogleDriveSignedIn, _googleDriveEmail);
      } else {
        debugPrint(
          '[BackupManagement] Widget disposed, but backup uploaded successfully',
        );
      }
    } catch (e) {
      debugPrint('[BackupManagement] Google Drive backup error: $e');

      // Handle cancellation differently from errors
      if (e.toString().contains('cancelled by user') ||
          e.toString().contains('upload cancelled')) {
        debugPrint('[BackupManagement] Google Drive backup cancelled by user');

        // Show cancellation notification
        await BackupNotificationService.showFailureNotification(
          'Google Drive',
          'Backup cancelled',
        );

        if (mounted) {
          _showSnackbar('Backup cancelled', isError: false);
        }
      } else {
        // Show failure notification (visible even if user left screen)
        await BackupNotificationService.showFailureNotification(
          'Google Drive',
          e.toString().length > 100 ? 'Backup error occurred' : e.toString(),
        );

        if (mounted) {
          _showSnackbar('Google Drive backup failed: $e', isError: true);
        }
      }
    } finally {
      if (mounted) {
        setState(() {
          _isBackupInProgress = false;
          _backupCancellationRequested = false;
          _backupProgress = 0.0;
          _backupStatus = '';
        });
      }
    }
  }

  Future<void> _updateProgress(double progress, String status) async {
    if (!mounted) {
      debugPrint(
        '[BackupManagement] Widget disposed, skipping UI update: $status',
      );
      return;
    }
    setState(() {
      _backupProgress = progress;
      _backupStatus = status;
    });
    await Future.delayed(Duration(milliseconds: 300));
  }

  void _cancelBackup() {
    debugPrint(
      '[BackupManagement] ⚠️ CANCEL BUTTON PRESSED - Setting cancellation flag to TRUE',
    );

    // CRITICAL: Only call setState if widget is still mounted
    // This can be called from notification when user has navigated away
    if (mounted) {
      setState(() {
        _backupCancellationRequested = true;
        _backupStatus = 'Cancelling...';
      });
    } else {
      // Widget disposed, just set flag directly (no UI update needed)
      _backupCancellationRequested = true;
      debugPrint(
        '[BackupManagement] Widget disposed, setting cancellation flag without setState',
      );
    }

    debugPrint(
      '[BackupManagement] ⚠️ Cancellation flag is now: $_backupCancellationRequested',
    );

    // Notify through notification (works even if widget is disposed)
    BackupNotificationService.showProgressNotification(
      'Cancelling...',
      (_backupProgress * 100).toInt(),
    );

    debugPrint('[BackupManagement] Backup/Restore cancellation requested');
  }

  Future<void> _restoreBackup(String uri) async {
    final passphrase = await _askForPassword(
      title: 'Restore Backup',
      hint: 'Enter your backup passphrase',
    );

    if (passphrase == null || passphrase.isEmpty) {
      _showSnackbar('Restore cancelled');
      return;
    }

    if (!mounted) return;

    setState(() {
      _isBackupInProgress = true;
      _backupCancellationRequested = false;
      _backupProgress = 0.0;
      _backupStatus = 'Preparing restore...';
    });

    File? encryptedFile;

    try {
      // Show initial notification
      await BackupNotificationService.showProgressNotification(
        'Starting restore...',
        0,
      );

      // Check cancellation
      if (_backupCancellationRequested) {
        debugPrint('[BackupManagement] Local restore cancelled at start');
        throw Exception('Restore cancelled by user');
      }

      await _updateProgress(0.1, 'Loading backup file...');
      await BackupNotificationService.showProgressNotification(
        'Loading backup file...',
        10,
      );

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
      encryptedFile = tempFile;

      // Check cancellation
      if (_backupCancellationRequested) {
        debugPrint(
          '[BackupManagement] Local restore cancelled after loading file',
        );
        throw Exception('Restore cancelled by user');
      }

      await _updateProgress(0.2, 'Reading encrypted data...');
      await BackupNotificationService.showProgressNotification(
        'Reading encrypted data...',
        20,
      );
      await Future.delayed(Duration(milliseconds: 500));

      // Check cancellation
      if (_backupCancellationRequested) {
        debugPrint(
          '[BackupManagement] Local restore cancelled before decryption',
        );
        throw Exception('Restore cancelled by user');
      }

      await _updateProgress(0.3, 'Decrypting backup...');
      await BackupNotificationService.showProgressNotification(
        'Decrypting backup...',
        30,
      );

      // Decrypt - this is a long operation, keep notification alive
      final backupData = await _backupService.decryptBackup(
        encryptedFile,
        passphrase,
      );

      // Immediately update notification after decrypt
      await BackupNotificationService.showProgressNotification(
        'Backup decrypted successfully',
        40,
      );

      // Check cancellation after decryption
      if (_backupCancellationRequested) {
        debugPrint(
          '[BackupManagement] Local restore cancelled after decryption',
        );
        throw Exception('Restore cancelled by user');
      }

      await _updateProgress(0.5, 'Preparing database...');
      await BackupNotificationService.showProgressNotification(
        'Preparing database...',
        50,
      );
      await Future.delayed(Duration(milliseconds: 300));

      // Check cancellation
      if (_backupCancellationRequested) {
        debugPrint(
          '[BackupManagement] Local restore cancelled after validation',
        );
        throw Exception('Restore cancelled by user');
      }

      await _updateProgress(0.6, 'Restoring messages...');
      await BackupNotificationService.showProgressNotification(
        'Restoring messages...',
        60,
      );

      // Check cancellation
      if (_backupCancellationRequested) {
        debugPrint('[BackupManagement] Local restore cancelled before restore');
        throw Exception('Restore cancelled by user');
      }

      // Restore - this is a long operation, keep notification alive
      await _backupService.restoreBackup(backupData);

      // Immediately update notification after restore
      await BackupNotificationService.showProgressNotification(
        'Messages restored successfully',
        80,
      );

      // Check cancellation after restore
      if (_backupCancellationRequested) {
        throw Exception('Restore cancelled by user');
      }

      await _updateProgress(0.9, 'Finalizing restore...');
      await BackupNotificationService.showProgressNotification(
        'Finalizing restore...',
        90,
      );
      await Future.delayed(Duration(milliseconds: 300));

      // Check cancellation
      if (_backupCancellationRequested) {
        throw Exception('Restore cancelled by user');
      }

      await _updateProgress(0.95, 'Completing restore...');
      await BackupNotificationService.showProgressNotification(
        'Completing restore...',
        95,
      );

      // Clean up temporary file
      try {
        if (await encryptedFile.exists()) {
          await encryptedFile.delete();
          debugPrint('[BackupManagement] Temporary restore file deleted');
        }
      } catch (e) {
        debugPrint('[BackupManagement] Failed to delete temp file: $e');
      }

      // Track this backup as restored (store URI instead of file path)
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('last_restored_backup_uri', uri);
      await prefs.setInt(
        'last_restored_backup_timestamp',
        DateTime.now().millisecondsSinceEpoch,
      );

      await _updateProgress(1.0, 'Restore completed!');

      // Show SUCCESS notification with sound
      await BackupNotificationService.showSuccessNotification('Restore');

      // Show message if widget is still mounted
      if (mounted) {
        _showSnackbar('Backup restored! Restarting app...', isError: false);
        await Future.delayed(Duration(seconds: 2));
      } else {
        debugPrint(
          '[BackupManagement] Widget disposed, restarting app anyway...',
        );
        await Future.delayed(Duration(seconds: 1));
      }

      // CRITICAL: Restart app even if widget is disposed
      debugPrint('[BackupManagement] Triggering app restart after restore...');
      try {
        Restart.restartApp();
        debugPrint('[BackupManagement] ✅ Restart command sent');
      } catch (e) {
        debugPrint('[BackupManagement] ❌ Failed to restart: $e');
      }
    } catch (e) {
      debugPrint('[BackupManagement] Restore error: $e');

      // Clean up temporary file on error
      try {
        if (encryptedFile != null && await encryptedFile.exists()) {
          await encryptedFile.delete();
          debugPrint(
            '[BackupManagement] Temporary restore file deleted after error',
          );
        }
      } catch (cleanupError) {
        debugPrint(
          '[BackupManagement] Failed to delete temp file on error: $cleanupError',
        );
      }

      // Handle cancellation differently from errors
      if (e.toString().contains('cancelled by user')) {
        debugPrint('[BackupManagement] Restore cancelled by user');

        // Show cancellation notification
        await BackupNotificationService.showFailureNotification(
          'Local',
          'Restore cancelled',
        );

        if (mounted) {
          _showSnackbar('Restore cancelled', isError: false);
        }
      } else {
        // Show failure notification
        await BackupNotificationService.showFailureNotification(
          'Local',
          e.toString().length > 100 ? 'Restore error occurred' : e.toString(),
        );

        if (mounted) {
          _showSnackbar('Restore failed: $e', isError: true);
        }
      }

      if (mounted) {
        setState(() {
          _isBackupInProgress = false;
          _backupCancellationRequested = false;
          _backupProgress = 0.0;
          _backupStatus = '';
        });
      }
    }
  }

  Future<void> _signInToGoogleDrive() async {
    try {
      if (!mounted) return;
      setState(() => _isLoading = true);

      // Trigger Google Sign-In
      final driveApi = await _backupService.getDriveApi();

      if (driveApi != null) {
        // Update status and cache after successful sign-in
        await _checkGoogleDriveStatus();
        if (mounted) _showSnackbar('Signed in to Google Drive successfully!');
      } else {
        if (mounted)
          _showSnackbar('Failed to sign in to Google Drive', isError: true);
      }
    } catch (e) {
      debugPrint('[BackupManagement] Google Drive sign-in error: $e');
      if (mounted) _showSnackbar('Sign-in failed: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _changeGoogleDriveAccount() async {
    final screenWidth = MediaQuery.of(context).size.width;
    final borderRadius = (screenWidth * 0.0375).clamp(12.0, 18.0);
    final titleSize = 20.0;
    final bodySize = 12.0;

    try {
      if (!mounted) return;

      // Show confirmation dialog explaining what will happen
      final confirm = await showBackupSheet<bool>(
        context: context,
        builder: (context) => BackupDialog(
          backgroundColor: _ui.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(borderRadius),
            side: BorderSide(color: _ui.blue.withOpacity(0.3)),
          ),
          title: Text(
            'Change Google Drive Account',
            style: TextStyle(color: _ui.ink, fontSize: titleSize),
          ),
          content: Text(
            'You will be signed out from the current account and can select a different Google account.\n\nImportant: If you cancel the account selection, you\'ll need to sign in again.',
            style: TextStyle(color: _ui.muted, fontSize: bodySize),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(
                'Cancel',
                style: TextStyle(color: _ui.muted, fontSize: bodySize),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(
                'Continue',
                style: TextStyle(color: _ui.blue, fontSize: bodySize),
              ),
            ),
          ],
        ),
      );

      if (confirm != true) return;

      if (!mounted) return;
      setState(() => _isLoading = true);

      // Store current email for comparison
      final currentEmail = _googleDriveEmail;

      // Sign out current account (necessary to show account picker)
      await _backupService.signOutFromGoogleDrive();

      // Show account picker
      final driveApi = await _backupService.getDriveApi();

      if (driveApi != null) {
        // Successfully signed in with account
        await _checkGoogleDriveStatus();
        final newEmail = _googleDriveEmail;

        if (newEmail != currentEmail) {
          if (mounted)
            _showSnackbar('Google Drive account changed to $newEmail');
        } else {
          if (mounted) _showSnackbar('Signed in with same account');
        }
      } else {
        // User cancelled account picker - no account is now signed in
        await _checkGoogleDriveStatus();
        if (mounted) {
          _showSnackbar(
            'Account selection cancelled. Please sign in to use Google Drive backup.',
            isError: true,
          );
        }
      }
    } catch (e) {
      debugPrint('[BackupManagement] Change account error: $e');
      if (mounted) _showSnackbar('Failed to change account: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _signOutFromGoogleDrive() async {
    final screenWidth = MediaQuery.of(context).size.width;
    final borderRadius = (screenWidth * 0.0375).clamp(12.0, 18.0);
    final titleSize = 20.0;
    final bodySize = 12.0;

    final confirm = await showBackupSheet<bool>(
      context: context,
      builder: (context) => BackupDialog(
        backgroundColor: _ui.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(borderRadius),
          side: BorderSide(color: _ui.blue.withOpacity(0.3)),
        ),
        title: Text(
          'Sign Out',
          style: TextStyle(color: _ui.ink, fontSize: titleSize),
        ),
        content: Text(
          'Are you sure you want to sign out from Google Drive?',
          style: TextStyle(color: _ui.muted, fontSize: bodySize),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              'Cancel',
              style: TextStyle(color: _ui.muted, fontSize: bodySize),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              'Sign Out',
              style: TextStyle(color: Color(0xFFBF6974), fontSize: bodySize),
            ),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await _backupService.signOutFromGoogleDrive();

        // Clear cache immediately for instant UI update
        await _updateGoogleDriveCache(false, null);

        // Update UI
        if (mounted) {
          setState(() {
            _isGoogleDriveSignedIn = false;
            _googleDriveEmail = null;
          });
        }

        _showSnackbar('Signed out from Google Drive');
      } catch (e) {
        // print('[BackupManagement] Sign-out error: $e');
        _showSnackbar('Sign-out failed: $e', isError: true);
      }
    }
  }

  Future<void> _viewGoogleDriveBackups() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => GoogleDriveBackupsScreen(
          accountEmail: _googleDriveEmail,
          onRestore: (folderId) async {
            await _restoreFromGoogleDrive(folderId);
          },
        ),
      ),
    );
  }

  /// Import a backup file from local device storage
  /// User can select any .encrypted file from device using file picker
  Future<void> _importBackupFromGoogleDrive() async {
    try {
      // Use file picker to browse any location
      // Note: Using FileType.any because 'encrypted' is not a standard extension
      final result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        dialogTitle: 'Select Backup File (.encrypted)',
      );

      if (result == null || result.files.isEmpty) {
        return;
      }

      final filePath = result.files.first.path;

      // Verify the file has .encrypted extension
      if (filePath == null || !filePath.endsWith('.encrypted')) {
        if (mounted) {
          _showSnackbar(
            'Please select a .encrypted backup file',
            isError: true,
          );
        }
        return;
      }

      if (!mounted) return;

      // Ask for passphrase
      final passphrase = await _askForPassword(
        title: 'Import Backup',
        hint: 'Enter your backup passphrase',
      );

      if (passphrase == null || passphrase.isEmpty) {
        _showSnackbar('Import cancelled');
        return;
      }

      if (!mounted) return;

      setState(() {
        _isBackupInProgress = true;
        _backupCancellationRequested = false;
        _backupProgress = 0.0;
        _backupStatus = 'Importing backup...';
      });

      try {
        await BackupNotificationService.showProgressNotification(
          'Importing backup...',
          0,
        );

        // Read the file
        final backupFile = File(filePath);
        if (!await backupFile.exists()) {
          throw Exception('Backup file not found');
        }

        await _updateProgress(0.2, 'Decrypting backup...');
        await BackupNotificationService.showProgressNotification(
          'Decrypting backup...',
          20,
        );

        // Decrypt and restore
        final backupData = await _backupService.decryptBackup(
          backupFile,
          passphrase,
        );

        await _updateProgress(0.4, 'Restoring database...');
        await _backupService.restoreBackup(backupData);

        await _updateProgress(1.0, 'Backup imported successfully!');

        // Show SUCCESS notification with sound
        await BackupNotificationService.showSuccessNotification('Import');

        if (mounted) {
          _showSnackbar(
            'Backup imported successfully! The app will restart now.',
          );
          await Future.delayed(Duration(seconds: 2));
          Restart.restartApp();
        }
      } catch (e) {
        debugPrint('[BackupManagement] Error importing backup: $e');

        // Show FAILURE notification with sound
        await BackupNotificationService.showFailureNotification(
          'Import',
          e.toString().length > 100 ? 'Import error occurred' : e.toString(),
        );

        if (mounted)
          _showSnackbar('Failed to import backup: $e', isError: true);
      } finally {
        if (mounted) {
          setState(() {
            _isBackupInProgress = false;
            _backupCancellationRequested = false;
          });
        }
      }
    } catch (e) {
      debugPrint('[BackupManagement] Error in import flow: $e');
      if (mounted) _showSnackbar('Failed to import backup: $e', isError: true);
    }
  }

  /// Select a backup file from local Zarq_Backups folder
  Future<String?> _selectLocalBackupFile() async {
    try {
      // List all backups from local storage (MediaStore + old file system)
      final backups = await MediaStoreBackupService.listAllBackups();

      if (backups.isEmpty) {
        _showSnackbar('No local backups found in Download/Zarq_Backups folder');
        return null;
      }

      if (!mounted) return null;

      // Show selection dialog
      final selectedBackup = await showBackupSheet<Map<String, dynamic>>(
        context: context,
        builder: (context) {
          final borderRadius = MediaQuery.of(context).size.width * 0.03;
          final spacing1 = MediaQuery.of(context).size.width * 0.03;
          final titleSize = 20.0;
          final bodySize = 12.0;
          final smallSize = 10.0;
          final iconSize2 = MediaQuery.of(context).size.width * 0.05;

          return BackupDialog(
            backgroundColor: _ui.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(borderRadius),
              side: BorderSide(color: _ui.blue.withOpacity(0.3)),
            ),
            title: Row(
              children: [
                Icon(Icons.folder, color: _ui.blue, size: iconSize2),
                SizedBox(width: spacing1),
                Text(
                  'Local Backups',
                  style: TextStyle(color: _ui.ink, fontSize: titleSize),
                ),
              ],
            ),
            content: Container(
              width: double.maxFinite,
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.5,
              ),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: backups.length,
                itemBuilder: (context, index) {
                  final backup = backups[index];
                  final fileName = backup['name'] as String;
                  final size = MediaStoreBackupService.formatBytes(
                    backup['size'] as int,
                  );
                  final date = DateTime.fromMillisecondsSinceEpoch(
                    backup['dateModified'] as int,
                  );
                  final formattedDate = _formatDateTime(date);

                  return Card(
                    color: _ui.soft,
                    margin: EdgeInsets.only(bottom: spacing1),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(borderRadius / 2),
                      side: BorderSide(color: _ui.blue.withOpacity(0.3)),
                    ),
                    child: ListTile(
                      leading: Icon(
                        Icons.backup,
                        color: _ui.blue,
                        size: iconSize2,
                      ),
                      title: Text(
                        fileName,
                        style: TextStyle(color: _ui.ink, fontSize: bodySize),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(height: spacing1 * 0.3),
                          Text(
                            formattedDate,
                            style: TextStyle(
                              color: _ui.muted,
                              fontSize: smallSize,
                            ),
                          ),
                          Text(
                            size,
                            style: TextStyle(
                              color: _ui.muted,
                              fontSize: smallSize,
                            ),
                          ),
                        ],
                      ),
                      trailing: Icon(
                        Icons.arrow_forward_ios,
                        color: _ui.blue,
                        size: iconSize2 * 0.7,
                      ),
                      onTap: () => Navigator.pop(context, backup),
                    ),
                  );
                },
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(
                  'Cancel',
                  style: TextStyle(color: _ui.blue, fontSize: bodySize),
                ),
              ),
            ],
          );
        },
      );

      if (selectedBackup == null) {
        return null;
      }

      // Get the file path from URI
      final uri = selectedBackup['uri'] as String;

      // Check if this is an old file system backup or MediaStore backup
      if (uri.startsWith('file://')) {
        // Old file system backup - direct path
        return uri.replaceFirst('file://', '');
      } else {
        // MediaStore backup - need to read bytes and save to temp file
        final bytes = await MediaStoreBackupService.readBackupFileUniversal(
          uri,
        );
        if (bytes == null) {
          throw Exception('Failed to read backup file');
        }

        // Save to temp file
        final tempDir = Directory.systemTemp;
        final tempFile = File(
          '${tempDir.path}/temp_backup_${DateTime.now().millisecondsSinceEpoch}.encrypted',
        );
        await tempFile.writeAsBytes(bytes);

        return tempFile.path;
      }
    } catch (e) {
      debugPrint('[BackupManagement] Error selecting local backup: $e');
      if (mounted)
        _showSnackbar('Failed to access local backups: $e', isError: true);
      return null;
    }
  }

  /// Show folder navigation dialog with breadcrumbs
  Future<drive.File?> _showFolderNavigationDialog(
    String folderId,
    String folderName,
  ) async {
    final items = await _backupService.listDriveFolderContents(folderId);

    if (!mounted) return null;

    if (items.isEmpty) {
      _showSnackbar('No folders or backup files found in "$folderName"');
      return null;
    }

    return await showBackupSheet<drive.File>(
      context: context,
      builder: (context) {
        final borderRadius = MediaQuery.of(context).size.width * 0.03;
        final spacing1 = MediaQuery.of(context).size.width * 0.03;
        final titleSize = 20.0;
        final bodySize = 12.0;
        final smallSize = 10.0;
        final iconSize2 = MediaQuery.of(context).size.width * 0.05;

        return BackupDialog(
          backgroundColor: _ui.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(borderRadius),
            side: BorderSide(color: _ui.blue.withOpacity(0.3)),
          ),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.folder_open, color: _ui.blue, size: iconSize2),
                  SizedBox(width: spacing1),
                  Expanded(
                    child: Text(
                      folderName,
                      style: TextStyle(color: _ui.ink, fontSize: titleSize),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              SizedBox(height: spacing1 * 0.5),
              Text(
                'Select a folder or backup file:',
                style: TextStyle(
                  color: _ui.muted,
                  fontSize: smallSize,
                  fontWeight: FontWeight.normal,
                ),
              ),
            ],
          ),
          content: Container(
            width: double.maxFinite,
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.5,
            ),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: items.length,
              itemBuilder: (context, index) {
                final item = items[index];
                final isFolder =
                    item.mimeType == 'application/vnd.google-apps.folder';
                final localDate = item.modifiedTime?.toLocal();
                final date = localDate != null
                    ? _formatDateTime(localDate)
                    : 'Unknown date';

                // Format file size
                String sizeStr = '';
                if (!isFolder && item.size != null) {
                  final sizeBytes = int.tryParse(item.size!) ?? 0;
                  if (sizeBytes > 0) {
                    sizeStr = _formatBytes(sizeBytes);
                  }
                }

                return Card(
                  color: _ui.soft,
                  margin: EdgeInsets.only(bottom: spacing1),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(borderRadius / 2),
                    side: BorderSide(
                      color: isFolder
                          ? _ui.blue.withOpacity(0.3)
                          : _ui.blue.withOpacity(0.3),
                    ),
                  ),
                  child: ListTile(
                    leading: Icon(
                      isFolder ? Icons.folder : Icons.backup,
                      color: isFolder ? _ui.blue : _ui.blue,
                      size: iconSize2,
                    ),
                    title: Text(
                      item.name ?? 'Unknown',
                      style: TextStyle(color: _ui.ink, fontSize: bodySize),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(height: spacing1 * 0.3),
                        Text(
                          date,
                          style: TextStyle(
                            color: _ui.muted,
                            fontSize: smallSize,
                          ),
                        ),
                        if (sizeStr.isNotEmpty)
                          Text(
                            sizeStr,
                            style: TextStyle(
                              color: _ui.muted,
                              fontSize: smallSize,
                            ),
                          ),
                      ],
                    ),
                    trailing: Icon(
                      Icons.arrow_forward_ios,
                      color: isFolder ? _ui.blue : _ui.blue,
                      size: iconSize2 * 0.7,
                    ),
                    onTap: () async {
                      if (isFolder) {
                        // Navigate into folder
                        Navigator.pop(context); // Close current dialog
                        final selected = await _showFolderNavigationDialog(
                          item.id!,
                          item.name ?? 'Folder',
                        );
                        if (selected != null && mounted) {
                          // Return the selected file from nested navigation
                          Navigator.pop(context, selected);
                        }
                      } else {
                        // Select this file
                        Navigator.pop(context, item);
                      }
                    },
                  ),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(
                'Back',
                style: TextStyle(color: _ui.blue, fontSize: bodySize),
              ),
            ),
          ],
        );
      },
    );
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024)
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  Future<void> _restoreFromGoogleDrive(String folderId) async {
    final passphrase = await _askForPassword(
      title: 'Restore from Google Drive',
      hint: 'Enter your backup passphrase',
    );

    if (passphrase == null || passphrase.isEmpty) {
      _showSnackbar('Restore cancelled');
      return;
    }

    if (!mounted) return;

    setState(() {
      _isBackupInProgress = true;
      _backupCancellationRequested = false;
      _backupProgress = 0.0;
      _backupStatus = 'Preparing restore...';
    });

    try {
      // Show initial notification
      await BackupNotificationService.showProgressNotification(
        'Starting Google Drive restore...',
        0,
      );

      // Check cancellation
      if (_backupCancellationRequested) {
        throw Exception('Restore cancelled by user');
      }

      await _updateProgress(0.1, 'Downloading from Google Drive...');
      await BackupNotificationService.showProgressNotification(
        'Downloading from Google Drive...',
        10,
      );

      // Check cancellation
      if (_backupCancellationRequested) {
        throw Exception('Restore cancelled by user');
      }

      // Use new restore method with media download progress tracking
      await _backupService.restoreFromGoogleDrive(
        backupFolderId: folderId,
        passphrase: passphrase,
        shouldCancel: () {
          debugPrint(
            '[BackupManagement] shouldCancel callback called, returning: $_backupCancellationRequested',
          );
          return _backupCancellationRequested;
        },
        onMediaProgress: (current, total, fileName) {
          // Check cancellation during media download
          if (_backupCancellationRequested) {
            debugPrint(
              '[BackupManagement] Cancellation detected during media download',
            );
            return;
          }

          // Update UI and notification with media download progress
          final mediaProgress =
              0.5 + (current / total) * 0.4; // 50-90% for media download
          final mediaStatus = 'Downloading media $current/$total: $fileName';
          final notificationProgress = (mediaProgress * 100).toInt();

          // CRITICAL: Always update notification even if widget is disposed
          BackupNotificationService.showProgressNotification(
            'Downloading media ($current/$total)',
            notificationProgress,
          );

          // Update UI only if still mounted
          if (mounted) {
            setState(() {
              _backupProgress = mediaProgress;
              _backupStatus = mediaStatus;
            });

            debugPrint(
              '[BackupManagement] Media download: $current/$total - $fileName',
            );
          }
        },
      );

      // Check cancellation after restore
      if (_backupCancellationRequested) {
        throw Exception('Restore cancelled by user');
      }

      await _updateProgress(1.0, 'Restore completed!');
      await BackupNotificationService.showProgressNotification(
        'Restore completed!',
        100,
      );

      // Show message if widget is still mounted
      if (mounted) {
        _showSnackbar(
          'Backup restored with media! Restarting app...',
          isError: false,
        );
        await Future.delayed(Duration(seconds: 2));
      } else {
        debugPrint(
          '[BackupManagement] Widget disposed, restarting app anyway...',
        );
        await Future.delayed(Duration(seconds: 1));
      }

      // CRITICAL: Restart app even if widget is disposed
      debugPrint(
        '[BackupManagement] Triggering app restart after Google Drive restore...',
      );
      try {
        Restart.restartApp();
        debugPrint('[BackupManagement] ✅ Restart command sent');
      } catch (e) {
        debugPrint('[BackupManagement] ❌ Failed to restart: $e');
      }
    } catch (e) {
      debugPrint('[BackupManagement] Google Drive restore error: $e');

      // Handle cancellation differently from errors
      if (e.toString().contains('cancelled by user') ||
          e.toString().contains('download cancelled')) {
        debugPrint('[BackupManagement] Google Drive restore cancelled by user');

        // Show cancellation notification
        await BackupNotificationService.showFailureNotification(
          'Google Drive',
          'Restore cancelled',
        );

        if (mounted) {
          _showSnackbar('Restore cancelled', isError: false);
        }
      } else {
        // Show failure notification
        await BackupNotificationService.showFailureNotification(
          'Google Drive',
          e.toString().length > 100 ? 'Restore error occurred' : e.toString(),
        );

        if (mounted) {
          _showSnackbar('Restore failed: $e', isError: true);
        }
      }

      if (mounted) {
        setState(() {
          _isBackupInProgress = false;
          _backupCancellationRequested = false;
          _backupProgress = 0.0;
          _backupStatus = '';
        });
      }
    }
  }

  Future<void> _deleteGoogleDriveBackup(String fileId) async {
    final screenWidth = MediaQuery.of(context).size.width;
    final borderRadius = (screenWidth * 0.0375).clamp(12.0, 18.0);
    final titleSize = 20.0;
    final bodySize = 12.0;

    final confirm = await showBackupSheet<bool>(
      context: context,
      builder: (context) => BackupDialog(
        backgroundColor: _ui.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(borderRadius),
          side: BorderSide(color: _ui.blue.withOpacity(0.3)),
        ),
        title: Text(
          'Delete Backup',
          style: TextStyle(color: _ui.ink, fontSize: titleSize),
        ),
        content: Text(
          'Are you sure you want to delete this backup from Google Drive? This action cannot be undone.',
          style: TextStyle(color: _ui.muted, fontSize: bodySize),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              'Cancel',
              style: TextStyle(color: _ui.muted, fontSize: bodySize),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              'Delete',
              style: TextStyle(color: Color(0xFFBF6974), fontSize: bodySize),
            ),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        final success = await _backupService.deleteFromGoogleDrive(fileId);
        if (success) {
          _showSnackbar('Backup deleted from Google Drive');
        } else {
          _showSnackbar('Failed to delete backup', isError: true);
        }
      } catch (e) {
        // print('[BackupManagement] Delete error: $e');
        _showSnackbar('Delete failed: $e', isError: true);
      }
    }
  }

  Future<void> _scanAndImportBackups() async {
    try {
      setState(() => _isLoading = true);
      _showSnackbar('Scanning for backup files...');

      final count = await MediaStoreBackupService.scanAndImportBackups();

      if (count > 0) {
        _showSnackbar('✅ Imported $count backup file${count > 1 ? 's' : ''}!');
        await _loadBackupsList();
      } else {
        _showSnackbar('No new backup files found to import', isError: false);
      }
    } catch (e) {
      debugPrint('[BackupManagement] Error scanning backups: $e');
      _showSnackbar('Failed to scan for backups: $e', isError: true);
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _deleteBackup(String uri) async {
    final screenWidth = MediaQuery.of(context).size.width;
    final borderRadius = (screenWidth * 0.0375).clamp(12.0, 18.0);
    final titleSize = 20.0;
    final bodySize = 12.0;

    final confirm = await showBackupSheet<bool>(
      context: context,
      builder: (context) => BackupDialog(
        backgroundColor: _ui.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(borderRadius),
          side: BorderSide(color: _ui.blue.withOpacity(0.3)),
        ),
        title: Text(
          'Delete Backup',
          style: TextStyle(color: _ui.ink, fontSize: titleSize),
        ),
        content: Text(
          'Are you sure you want to delete this backup? This action cannot be undone.',
          style: TextStyle(color: _ui.muted, fontSize: bodySize),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              'Cancel',
              style: TextStyle(color: _ui.muted, fontSize: bodySize),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              'Delete',
              style: TextStyle(color: Color(0xFFBF6974), fontSize: bodySize),
            ),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        // TEMPORARY: Delete from either MediaStore or old file system
        final success = await MediaStoreBackupService.deleteBackupFileUniversal(
          uri,
        );
        if (success) {
          _showSnackbar('Backup deleted');
          await _loadBackupsList();
        } else {
          _showSnackbar('Failed to delete backup', isError: true);
        }
      } catch (e) {
        _showSnackbar('Failed to delete backup: $e', isError: true);
      }
    }
  }

  Future<void> _renameBackup(String uri, String currentName) async {
    final screenWidth = MediaQuery.of(context).size.width;
    final borderRadius = (screenWidth * 0.0375).clamp(12.0, 18.0);
    final titleSize = 20.0;
    final bodySize = 12.0;

    final controller = TextEditingController(
      text: currentName.replaceAll('.encrypted', ''),
    );

    final newName = await showBackupSheet<String>(
      context: context,
      builder: (ctx) {
        return BackupDialog(
          backgroundColor: _ui.surface.withOpacity(0.95),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(borderRadius),
            side: BorderSide(color: _ui.blue.withOpacity(0.5)),
          ),
          title: Text(
            'Rename Backup',
            style: TextStyle(color: _ui.ink, fontSize: titleSize),
          ),
          content: TextField(
            controller: controller,
            autofocus: true,
            style: TextStyle(color: _ui.ink, fontSize: bodySize),
            decoration: _ui.field('Enter new name'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(
                'Cancel',
                style: TextStyle(color: _ui.muted, fontSize: bodySize),
              ),
            ),
            TextButton(
              onPressed: () {
                final text = controller.text.trim();
                if (text.isNotEmpty) {
                  Navigator.pop(ctx, text);
                }
              },
              child: Text(
                'Rename',
                style: TextStyle(color: _ui.blue, fontSize: bodySize),
              ),
            ),
          ],
        );
      },
    );

    if (newName != null &&
        newName.isNotEmpty &&
        newName != currentName.replaceAll('.encrypted', '')) {
      try {
        // Add .encrypted extension if not present
        final finalName = newName.endsWith('.encrypted')
            ? newName
            : '$newName.encrypted';

        final success = await MediaStoreBackupService.renameBackup(
          uri,
          finalName,
        );

        if (success) {
          // Small delay to allow MediaStore to update its index
          await Future.delayed(Duration(milliseconds: 500));
          await _loadBackupsList();
          _showSnackbar('Backup renamed successfully', isError: false);
        } else {
          _showSnackbar('Failed to rename backup', isError: true);
        }
      } catch (e) {
        _showSnackbar('Failed to rename backup: $e', isError: true);
      }
    }
  }

  Future<String?> _askForPassword({
    required String title,
    required String hint,
  }) async {
    final restoring =
        title.toLowerCase().contains('restore') ||
        title.toLowerCase().contains('import');
    final password = await showBackupSheet<String>(
      context: context,
      builder: (_) =>
          BackupPassphraseSheet(title: title, hint: hint, confirm: !restoring),
    );
    if (!mounted || password == null || !restoring) return password;
    final confirmed = await showNotesConfirmation(
      context,
      title: 'Restore this backup?',
      body:
          'Restore your saved conversations and encryption data from this backup? The app may restart when restoration finishes.',
      confirm: 'Restore backup',
      icon: Icons.restore,
    );
    if (confirmed) _restoring = true;
    return confirmed ? password : null;
  }

  void _showSnackbar(String message, {bool isError = false}) {
    if (!mounted) return;
    if (isError) {
      OpaqueToast.error(context, message);
    } else if (message.toLowerCase().contains('cancel') || message.contains('...')) {
      OpaqueToast.info(context, message);
    } else {
      OpaqueToast.success(context, message);
    }
  }

  /// Trigger highlight animation and haptic feedback when settings change
  Future<void> _triggerSettingsChangedFeedback(String message) async {
    // Haptic feedback
    HapticFeedback.mediumImpact();

    // Show snackbar
    _showSnackbar(message, isError: false);

    // Trigger highlight animation on "Next backup" box
    if (mounted) {
      setState(() {
        _highlightNextBackup = true;
      });

      _highlightController.forward(from: 0.0);

      // Reset highlight after animation completes
      await Future.delayed(Duration(milliseconds: 800));
      if (mounted) {
        setState(() {
          _highlightNextBackup = false;
        });
      }
    }
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  String _formatDateTime(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    // Format time in 12-hour format with AM/PM
    final hour12 = dateTime.hour == 0
        ? 12
        : (dateTime.hour > 12 ? dateTime.hour - 12 : dateTime.hour);
    final period = dateTime.hour >= 12 ? 'PM' : 'AM';
    final timeStr =
        '${hour12}:${dateTime.minute.toString().padLeft(2, '0')} $period';

    if (difference.inDays == 0) {
      return 'Today $timeStr';
    } else if (difference.inDays == 1) {
      return 'Yesterday $timeStr';
    } else if (difference.inDays < 7) {
      return '${difference.inDays} days ago';
    } else {
      return '${dateTime.day}/${dateTime.month}/${dateTime.year} $timeStr';
    }
  }

  String _formatNextBackupTime(DateTime nextBackup) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(Duration(days: 1));
    final nextBackupDate = DateTime(
      nextBackup.year,
      nextBackup.month,
      nextBackup.day,
    );

    final timeStr =
        '${nextBackup.hour.toString().padLeft(2, '0')}:${nextBackup.minute.toString().padLeft(2, '0')}';

    if (nextBackupDate == today) {
      return 'Tonight at $timeStr';
    } else if (nextBackupDate == tomorrow) {
      return 'Tomorrow at $timeStr';
    } else {
      final daysUntil = nextBackupDate.difference(today).inDays;
      return 'In $daysUntil days at $timeStr';
    }
  }

  NotesColors get _ui => NotesColors(context);
  bool _restoreTab = false;
  String _destination = 'On this device';
  int? _mediaDays;
  bool _actionPending = false;
  bool get _busy => _isBackupInProgress || _actionPending;

  Future<void> _runAction(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _actionPending = true);
    try {
      await action();
    } catch (_) {
      if (mounted)
        _showSnackbar(
          'Could not complete this action. Please try again.',
          isError: true,
        );
    } finally {
      if (mounted) setState(() => _actionPending = false);
    }
  }

  Future<void> _choose(
    String title,
    List<String> items,
    String current,
    ValueChanged<String> update,
  ) async {
    final choice = await showBackupSheet<String>(
      context: context,
      builder: (ctx) => NotesSheet(
        title: title,
        description: 'Choose what works for you.',
        icon: Icons.tune_rounded,
        child: Column(
          children: [
            for (final item in items)
              InkWell(
                onTap: () => Navigator.pop(ctx, item),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                    border: Border(bottom: BorderSide(color: _ui.line)),
                  ),
                  child: Row(
                    children: [
                      Expanded(child: Text(item, style: _ui.text(12))),
                      Icon(
                        item == current
                            ? Icons.radio_button_checked
                            : Icons.radio_button_off,
                        size: 17,
                        color: item == current ? _ui.blue : _ui.muted,
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
    if (mounted && choice != null) update(choice);
  }

  String get _mediaLabel => _mediaDays == null
      ? 'All media'
      : _mediaDays == 0
      ? 'No media'
      : 'Last $_mediaDays days';

  Future<void> _accountOptions() async {
    if (!_isGoogleDriveSignedIn) {
      await _signInToGoogleDrive();
      return;
    }
    final action = await showBackupSheet<String>(
      context: context,
      builder: (ctx) => NotesSheet(
        title: 'Google Drive',
        description: _googleDriveEmail ?? 'Connected account',
        icon: Icons.cloud_outlined,
        child: Column(
          children: [
            _settingRow(
              Icons.cloud_outlined,
              'View backups',
              onTap: () => Navigator.pop(ctx, 'view'),
              allowBusy: true,
            ),
            _settingRow(
              Icons.manage_accounts_outlined,
              'Change account',
              onTap: () => Navigator.pop(ctx, 'change'),
              allowBusy: true,
            ),
            _settingRow(
              Icons.logout,
              'Sign out',
              onTap: () => Navigator.pop(ctx, 'signout'),
              allowBusy: true,
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    if (action == 'view') await _viewGoogleDriveBackups();
    if (action == 'change') await _changeGoogleDriveAccount();
    if (action == 'signout') await _signOutFromGoogleDrive();
  }

  Widget _settingRow(
    IconData icon,
    String title, {
    String? subtitle,
    String? value,
    VoidCallback? onTap,
    Widget? trailing,
    bool showChevron = true,
    bool allowBusy = false,
  }) {
    final c = _ui;
    return InkWell(
      onTap: _busy && !allowBusy ? null : onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: c.line)),
        ),
        child: Row(
          crossAxisAlignment: subtitle != null ? CrossAxisAlignment.start : CrossAxisAlignment.center,
          children: [
            Padding(
              padding: EdgeInsets.only(top: subtitle != null ? 2.0 : 0.0),
              child: Icon(icon, size: 17, color: c.muted),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(title, style: c.text(12)),
                      ),
                      if (value != null) ...[
                        const SizedBox(width: 8),
                        Text(
                          value,
                          textAlign: TextAlign.right,
                          style: c.text(11, muted: true),
                        ),
                      ],
                    ],
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 3),
                    Text(subtitle, style: c.text(10, muted: true)),
                  ],
                ],
              ),
            ),
            if (trailing != null)
              trailing
            else if (onTap != null && showChevron)
              Padding(
                padding: EdgeInsets.only(
                  left: 6,
                  top: subtitle != null ? 1.0 : 0.0,
                ),
                child: Icon(Icons.chevron_right, size: 15, color: c.muted),
              ),
          ],
        ),
      ),
    );
  }

  Widget _sectionLabel(String text) => Padding(
    padding: const EdgeInsets.only(top: 24, bottom: 12),
    child: Text(
      text,
      style: _ui.text(9, muted: true).copyWith(letterSpacing: 1.3),
    ),
  );
  Widget _note(String text, {IconData icon = Icons.lock_outline}) => Padding(
    padding: const EdgeInsets.only(top: 20),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 13, color: _ui.muted),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            text,
            style: _ui.text(10, muted: true).copyWith(height: 1.7),
          ),
        ),
      ],
    ),
  );

  Future<void> _backupOptions(Map<String, dynamic> backup) async {
    final action = await showBackupSheet<String>(
      context: context,
      builder: (ctx) => NotesSheet(
        title: 'Backup options',
        description: backup['name'] as String,
        icon: Icons.inventory_2_outlined,
        child: Column(
          children: [
            for (final item in [
              ('Rename', Icons.edit_outlined),
              ('Restore', Icons.settings_backup_restore_rounded),
              ('Delete', Icons.delete_outline),
            ])
              _settingRow(
                item.$2,
                item.$1,
                allowBusy: true,
                showChevron: false,
                onTap: () => Navigator.pop(ctx, item.$1),
              ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    final uri = backup['uri'] as String;
    if (action == 'Rename') await _renameBackup(uri, backup['name'] as String);
    if (action == 'Restore') await _restoreBackup(uri);
    if (action == 'Delete') await _deleteBackup(uri);
  }

  @override
  Widget build(BuildContext context) {
    context.watch<UserSettingsProvider>();
    final settingsProvider = context.watch<BackupSettingsProvider>();
    final settings = settingsProvider.settings;
    final c = _ui;
    final backups = [..._backupsList]
      ..sort(
        (a, b) =>
            (b['dateModified'] as int).compareTo(a['dateModified'] as int),
      );
    final latest = backups.isEmpty ? null : backups.first;
    final hasPassphrase = settings.lastBackupPassphrase?.isNotEmpty == true;
    final scheduleText = hasPassphrase && settings.enabled
        ? '${settings.frequency.displayName} · Around 19:59, subject to Android scheduling'
        : null;
    return CallAwareScreen(
      screenName: 'BackupManagementScreen',
      child: Scaffold(
        backgroundColor: c.surface,
        appBar: BackupHeader(
          onHelp: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const BackupInfoScreen()),
          ),
        ),
        body: SafeArea(
          child: RefreshIndicator(
            color: c.blue,
            onRefresh: () async {
              if (!_busy) await _loadBackupsList();
            },
            child: ListView(
              padding: const EdgeInsets.fromLTRB(22, 22, 22, 24),
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                Text(
                  'Backup & restore',
                  style: c.text(22, bold: true).copyWith(letterSpacing: -.6),
                ),
                const SizedBox(height: 5),
                Text(
                  'Keep a copy of what matters.',
                  style: c.text(12, muted: true),
                ),
                Container(
                  margin: const EdgeInsets.only(top: 22, bottom: 24),
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    color: c.soft,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: [
                      for (final restore in [false, true])
                        Expanded(
                          child: InkWell(
                            borderRadius: BorderRadius.circular(13),
                            onTap: () => setState(() => _restoreTab = restore),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              decoration: BoxDecoration(
                                color: _restoreTab == restore
                                    ? c.surface
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(13),
                              ),
                              child: Text(
                                restore ? 'Restore' : 'Backup',
                                textAlign: TextAlign.center,
                                style: c.text(
                                  11,
                                  muted: _restoreTab != restore,
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                if (_isBackupInProgress)
                  Container(
                    margin: const EdgeInsets.only(bottom: 20),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: c.soft,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_backupStatus, style: c.text(12)),
                        const SizedBox(height: 14),
                        LinearProgressIndicator(
                          value: _backupProgress.clamp(0.0, 1.0),
                          color: c.blue,
                          backgroundColor: c.line,
                          minHeight: 4,
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Text(
                              '${(_backupProgress * 100).round()}%',
                              style: c.text(10, muted: true),
                            ),
                            const Spacer(),
                            TextButton(
                              onPressed: _backupCancellationRequested
                                  ? null
                                  : _cancelBackup,
                              child: Text(
                                _backupCancellationRequested
                                    ? 'Cancelling…'
                                    : _restoring
                                    ? 'Cancel restore'
                                    : 'Cancel backup',
                                style: c.text(11),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                if (_actionPending && !_isBackupInProgress)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: LinearProgressIndicator(
                      color: c.blue,
                      backgroundColor: c.soft,
                      minHeight: 2,
                    ),
                  ),
                if (!_restoreTab) ...[
                  Row(
                    children: [
                      BackupSymbol(
                        icon: latest == null
                            ? Icons.backup_outlined
                            : Icons.check,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _isLoading && latest == null
                                  ? 'Checking your backups…'
                                  : latest == null
                                  ? 'Your first backup starts here'
                                  : 'Last backup · ${_formatDateTime(DateTime.fromMillisecondsSinceEpoch(latest['dateModified'] as int))}',
                              style: c.text(13, bold: true),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              latest == null
                                  ? 'Keep your conversations close.'
                                  : '${MediaStoreBackupService.formatBytes(latest['size'] as int)} · On this device',
                              style: c.text(11, muted: true),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  BackupAction(
                    label: 'Create backup',
                    icon: Icons.file_upload_outlined,
                    primary: true,
                    onPressed: _busy ? null : () => _runAction(_createBackup),
                  ),
                  _sectionLabel('BACKUP PREFERENCES'),
                  _settingRow(
                    Icons.folder_outlined,
                    'Save to',
                    subtitle: 'Choose where to keep your backup',
                    value: _destination,
                    onTap: () => _choose(
                      'Save backup to',
                      ['On this device', 'Google Drive'],
                      _destination,
                      (v) => setState(() => _destination = v),
                    ),
                  ),
                  if (_destination == 'Google Drive')
                    _settingRow(
                      Icons.photo_outlined,
                      'Include media',
                      subtitle: 'For your Google Drive backup',
                      value: _mediaLabel,
                      onTap: () => _choose(
                        'Include media',
                        [
                          'All media',
                          'Last 7 days',
                          'Last 15 days',
                          'Last 30 days',
                          'No media',
                        ],
                        _mediaLabel,
                        (v) => setState(
                          () => _mediaDays = v == 'All media'
                              ? null
                              : v == 'No media'
                              ? 0
                              : int.parse(v.split(' ')[1]),
                        ),
                      ),
                    )
                  else
                    _settingRow(
                      Icons.photo_outlined,
                      'Include media',
                      value: 'Messages only',
                      showChevron: false,
                    ),
                  _settingRow(
                    Icons.schedule,
                    'Automatic backups',
                    subtitle: 'On this device · No internet required',
                    trailing: SizedBox(
                      height: 24,
                      child: Transform.scale(
                        scale: .7,
                        alignment: Alignment.centerRight,
                        child: Switch(
                          value: settings.enabled,
                          activeTrackColor: const Color(0xFF507FC3),
                          activeThumbColor: Colors.white,
                          onChanged: _busy
                              ? null
                              : (v) => _runAction(() async {
                                  await settingsProvider.setEnabled(v);
                                  await _triggerSettingsChangedFeedback(
                                    v
                                        ? 'Auto-backup enabled'
                                        : 'Auto-backup disabled',
                                  );
                                }),
                        ),
                      ),
                    ),
                  ),
                  if (settings.enabled) ...[
                    _settingRow(
                      Icons.schedule,
                      'Frequency',
                      value: settings.frequency.displayName,
                      onTap: () => _choose(
                        'Backup frequency',
                        ['Daily', 'Weekly', 'Monthly'],
                        settings.frequency.displayName,
                        (v) => _runAction(() async {
                          await settingsProvider.setFrequency(
                            v == 'Daily'
                                ? BackupFrequency.daily
                                : v == 'Weekly'
                                ? BackupFrequency.weekly
                                : BackupFrequency.monthly,
                          );
                          await _triggerSettingsChangedFeedback(
                            'Backup frequency updated',
                          );
                        }),
                      ),
                    ),
                    if (!hasPassphrase)
                      _settingRow(
                        Icons.lock_outline,
                        'Set backup passphrase',
                        subtitle: 'Required for automatic backups',
                        onTap: () => _runAction(() async {
                          final password = await _askForPassword(
                            title: 'Auto-backup passphrase',
                            hint: 'Enter a strong passphrase',
                          );
                          if (password != null && password.isNotEmpty)
                            await settingsProvider.setBackupPassphrase(
                              password,
                            );
                        }),
                      ),
                    Padding(
                      padding: const EdgeInsets.only(top: 14),
                      child: Text(
                        hasPassphrase
                            ? 'Passphrase configured. Keep it safe. It cannot be changed here.'
                            : 'Set a passphrase to schedule your first automatic backup.',
                        style: c.text(10, muted: true).copyWith(height: 1.7),
                      ),
                    ),
                    if (scheduleText != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          scheduleText,
                          style: c.text(10, muted: true),
                        ),
                      ),
                    if (settingsProvider.getLastBackupTimeFormatted() != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          'Last automatic backup · ${settingsProvider.getLastBackupTimeFormatted()}',
                          style: c.text(10, muted: true),
                        ),
                      ),
                    _settingRow(
                      Icons.battery_std,
                      'Background access',
                      subtitle: _isBatteryOptimizationDisabled
                          ? 'Background access is allowed'
                          : 'Allow backups while the app is closed',
                      onTap: () =>
                          _runAction(_requestBatteryOptimizationExemption),
                    ),
                  ],
                  _sectionLabel('GOOGLE DRIVE'),
                  _settingRow(
                    Icons.cloud_outlined,
                    _isGoogleDriveSignedIn
                        ? 'Connected account'
                        : 'Connect your account',
                    subtitle: _isGoogleDriveSignedIn
                        ? _googleDriveEmail ?? 'Google Drive'
                        : 'Keep a copy in Google Drive',
                    onTap: () => _runAction(_accountOptions),
                  ),
                  _note(
                    'Backups are protected by your passphrase. Keep it safe. You’ll need it to restore.',
                  ),
                ] else ...[
                  BackupAction(
                    label: 'Import backup file',
                    icon: Icons.folder_outlined,
                    onPressed: _busy
                        ? null
                        : () => _runAction(
                            () => _restoreAction(_importBackupFromGoogleDrive),
                          ),
                  ),
                  _settingRow(
                    Icons.folder_open_outlined,
                    'Find local backups',
                    subtitle: 'Scan for existing backup files',
                    onTap: () => _runAction(_scanAndImportBackups),
                  ),
                  _sectionLabel('AVAILABLE BACKUPS'),
                  if (_isLoading)
                    Padding(
                      padding: const EdgeInsets.all(25),
                      child: Center(
                        child: CircularProgressIndicator(
                          color: c.blue,
                          strokeWidth: 2,
                        ),
                      ),
                    )
                  else if (backups.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 42),
                      child: Column(
                        children: [
                          const BackupSymbol(icon: Icons.folder_outlined),
                          const SizedBox(height: 15),
                          Text(
                            'No backups here yet',
                            style: c.text(14, bold: true),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Import a saved backup file or check\nyour Google Drive backups.',
                            textAlign: TextAlign.center,
                            style: c
                                .text(12, muted: true)
                                .copyWith(height: 1.8),
                          ),
                        ],
                      ),
                    )
                  else
                    for (final backup in backups)
                      Container(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        decoration: BoxDecoration(
                          border: Border(bottom: BorderSide(color: c.line)),
                        ),
                        child: Row(
                          children: [
                            const BackupSymbol(
                              icon: Icons.insert_drive_file_outlined,
                            ),
                            const SizedBox(width: 11),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    backup['name'] as String,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: c.text(12),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${MediaStoreBackupService.formatBytes(backup['size'] as int)} · ${_formatDateTime(DateTime.fromMillisecondsSinceEpoch(backup['dateModified'] as int))}',
                                    style: c.text(10, muted: true),
                                  ),
                                ],
                              ),
                            ),
                            TextButton(
                              onPressed: _busy
                                  ? null
                                  : () => _runAction(
                                      () => _restoreAction(
                                        () => _restoreBackup(
                                          backup['uri'] as String,
                                        ),
                                      ),
                                    ),
                              child: Text(
                                'Restore',
                                style: c.text(11).copyWith(color: c.blue),
                              ),
                            ),
                            IconButton(
                              tooltip: 'Backup options',
                              constraints: const BoxConstraints(
                                minWidth: 28,
                                minHeight: 40,
                              ),
                              padding: EdgeInsets.zero,
                              onPressed: _busy
                                  ? null
                                  : () => _runAction(
                                      () => _backupOptions(backup),
                                    ),
                              icon: Icon(
                                Icons.more_vert,
                                size: 18,
                                color: c.muted,
                              ),
                            ),
                          ],
                        ),
                      ),
                  _settingRow(
                    Icons.cloud_outlined,
                    'Google Drive backups',
                    subtitle: 'Find a backup saved to your account',
                    onTap: () => _runAction(
                      () => _restoreAction(_viewGoogleDriveBackups),
                    ),
                  ),
                  _note(
                    'Restoring will recover your saved conversations and media onto this device.',
                    icon: Icons.restore_rounded,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  bool _restoring = false;
  Future<void> _restoreAction(Future<void> Function() action) async {
    if (mounted) setState(() => _restoring = true);
    try {
      await action();
    } finally {
      if (mounted) setState(() => _restoring = false);
    }
  }
}
