import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:restart_app/restart_app.dart';
import '../services/backup_service.dart';
import '../services/backup_settings_provider.dart';
import '../services/backup_notification_service.dart';
import '../services/auto_backup_manager.dart';
import '../widgets/call_aware_screen.dart';
import 'backup_info_screen.dart';
import 'package:provider/provider.dart';

class BackupManagementScreen extends StatefulWidget {
  const BackupManagementScreen({super.key});

  @override
  State<BackupManagementScreen> createState() => _BackupManagementScreenState();
}

class _BackupManagementScreenState extends State<BackupManagementScreen> with SingleTickerProviderStateMixin {
  final BackupService _backupService = BackupService();
  List<FileSystemEntity> _backupsList = [];
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
  static const MethodChannel _backupChannel = MethodChannel('com.zarq/backup');

  @override
  void initState() {
    super.initState();
    _loadBackupsList();
    _loadCachedGoogleDriveStatus(); // Load cached state for instant UI (no verification needed)
    _checkBatteryOptimization();
    // Note: We don't verify Google Drive status here - it will be checked when user actually uses it

    // Initialize animation controller for highlight effect
    _highlightController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );

    _highlightAnimation = ColorTween(
      begin: Colors.cyanAccent.withOpacity(0.3),
      end: Colors.cyanAccent.withOpacity(0.1),
    ).animate(CurvedAnimation(
      parent: _highlightController,
      curve: Curves.easeInOut,
    ));

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
    final isDisabled = await BackupNotificationService.isBatteryOptimizationDisabled();
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
      Future.delayed(const Duration(seconds: 2), () {
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

      debugPrint('[BackupManagement] Loaded cached Google Drive status: signed_in=$cachedSignedIn, email=$cachedEmail');
    } catch (e) {
      debugPrint('[BackupManagement] Error loading cached Google Drive status: $e');
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
      debugPrint('[BackupManagement] Updated Google Drive cache: signed_in=$isSignedIn, email=$email');
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
      // Request storage permission first (needed after reinstall)
      final storageStatus = await Permission.manageExternalStorage.status;
      debugPrint('[BackupManagement] Storage permission status: ${storageStatus.isGranted}');

      if (!storageStatus.isGranted) {
        debugPrint('[BackupManagement] Storage permission not granted, requesting...');
        final result = await Permission.manageExternalStorage.request();

        if (!result.isGranted) {
          debugPrint('[BackupManagement] Storage permission denied');
          _showSnackbar('Storage permission required to access backups', isError: true);
          setState(() => _isLoading = false);
          return;
        }
        debugPrint('[BackupManagement] Storage permission granted');
      }

      final downloadsDir = Directory('/storage/emulated/0/Download/Zarq_Backups');
      debugPrint('[BackupManagement] Checking backups directory: ${downloadsDir.path}');

      if (await downloadsDir.exists()) {
        debugPrint('[BackupManagement] Found backups directory, listing files...');
        final backups = await downloadsDir.list().toList();
        debugPrint('[BackupManagement] Raw file list: ${backups.map((f) => f.path).join(", ")}');

        backups.sort((a, b) => b.statSync().modified.compareTo(a.statSync().modified));

        debugPrint('[BackupManagement] Found ${backups.length} backup files');
        setState(() {
          _backupsList = backups;
        });
      } else {
        debugPrint('[BackupManagement] Backups directory does not exist');
        setState(() {
          _backupsList = [];
        });
      }
    } catch (e) {
      debugPrint('[BackupManagement] Error loading backups: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<bool> _requestStoragePermission() async {
    if (!Platform.isAndroid) return true;

    final status = await Permission.manageExternalStorage.status;
    if (status.isGranted) return true;

    final result = await Permission.manageExternalStorage.request();
    return result.isGranted;
  }

  Future<void> _createBackup() async {
    final screenWidth = MediaQuery.of(context).size.width;
    final borderRadius = (screenWidth * 0.0375).clamp(12.0, 18.0);
    final titleSize = (screenWidth * 0.045).clamp(16.0, 20.0);
    final bodySize = (screenWidth * 0.035).clamp(13.0, 16.0);
    final subtitleSize = (screenWidth * 0.03).clamp(11.0, 14.0);
    final iconSize = (screenWidth * 0.05).clamp(18.0, 24.0);

    // Show option dialog for local or Google Drive backup
    final backupType = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF0a1128),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(borderRadius),
          side: BorderSide(color: Colors.cyanAccent.withOpacity(0.3)),
        ),
        title: Text('Choose Backup Location', style: TextStyle(color: Colors.white, fontSize: titleSize)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(Icons.phone_android, color: Colors.cyanAccent, size: iconSize),
              title: Text('Local Storage', style: TextStyle(color: Colors.white, fontSize: bodySize)),
              subtitle: Text('Save to device', style: TextStyle(color: Colors.white70, fontSize: subtitleSize)),
              onTap: () => Navigator.pop(context, 'local'),
            ),
            ListTile(
              leading: Icon(Icons.cloud, color: Colors.cyanAccent, size: iconSize),
              title: Text('Google Drive', style: TextStyle(color: Colors.white, fontSize: bodySize)),
              subtitle: Text(
                _isGoogleDriveSignedIn ? 'Signed in as $_googleDriveEmail' : 'Sign in required',
                style: TextStyle(color: Colors.white70, fontSize: subtitleSize),
              ),
              onTap: () => Navigator.pop(context, 'drive'),
            ),
          ],
        ),
      ),
    );

    if (backupType == null) return;

    if (backupType == 'local') {
      await _createLocalBackup();
    } else {
      await _createGoogleDriveBackup();
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
      await BackupNotificationService.showProgressNotification('Starting backup...', 0);

      // Check cancellation
      if (_backupCancellationRequested) {
        throw Exception('Backup cancelled by user');
      }

      // Simulate progress steps
      await _updateProgress(0.2, 'Collecting messages...');
      await BackupNotificationService.showProgressNotification('Collecting messages...', 20);

      // Check cancellation
      if (_backupCancellationRequested) {
        throw Exception('Backup cancelled by user');
      }

      // Local backup: Messages only (no media) to prevent Out of Memory errors
      final backupData = await _backupService.createLocalBackup(
        includeMedia: false, // WhatsApp approach: Media stays on device
      );

      await _updateProgress(0.5, 'Encrypting backup...');
      await BackupNotificationService.showProgressNotification('Encrypting backup...', 50);

      // Check cancellation
      if (_backupCancellationRequested) {
        throw Exception('Backup cancelled by user');
      }

      final encryptedFile = await _backupService.encryptBackup(backupData, passphrase);

      // Check cancellation
      if (_backupCancellationRequested) {
        throw Exception('Backup cancelled by user');
      }

      // File operations should complete even if widget is disposed
      debugPrint('[BackupManagement] Preparing to copy encrypted file from: ${encryptedFile.path}');

      await BackupNotificationService.showProgressNotification('Saving to local storage...', 70);

      // Check cancellation
      if (_backupCancellationRequested) {
        throw Exception('Backup cancelled by user');
      }

      final downloadsDir = Directory('/storage/emulated/0/Download/Zarq_Backups');
      debugPrint('[BackupManagement] Target directory: ${downloadsDir.path}');

      if (!await downloadsDir.exists()) {
        debugPrint('[BackupManagement] Directory does not exist, creating...');
        await downloadsDir.create(recursive: true);
        debugPrint('[BackupManagement] Directory created successfully');
      } else {
        debugPrint('[BackupManagement] Directory already exists');
      }

      final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-').split('.')[0];
      final backupPath = '${downloadsDir.path}/backup_$timestamp.encrypted';
      debugPrint('[BackupManagement] Copying file to: $backupPath');

      await BackupNotificationService.showProgressNotification('Finalizing...', 90);

      final copiedFile = await encryptedFile.copy(backupPath);
      debugPrint('[BackupManagement] File copied successfully to: ${copiedFile.path}');

      // Verify file exists
      final fileExists = await File(backupPath).exists();
      final fileSize = await File(backupPath).length();
      debugPrint('[BackupManagement] Verification - File exists: $fileExists, Size: $fileSize bytes');

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
        debugPrint('[BackupManagement] Widget disposed, but backup saved successfully to: $backupPath');
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

    final screenWidth = MediaQuery.of(context).size.width;
    final borderRadius = (screenWidth * 0.0375).clamp(12.0, 18.0);
    final titleSize = (screenWidth * 0.045).clamp(16.0, 20.0);
    final bodySize = (screenWidth * 0.035).clamp(13.0, 16.0);
    final subtitleSize = (screenWidth * 0.03).clamp(11.0, 14.0);
    final iconSize = (screenWidth * 0.05).clamp(18.0, 24.0);

    // Show media inclusion options dialog
    final mediaOption = await showDialog<int?>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF0a1128),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(borderRadius),
          side: BorderSide(color: Colors.cyanAccent.withOpacity(0.3)),
        ),
        title: Text('Include Media Files', style: TextStyle(color: Colors.white, fontSize: titleSize)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Choose which media files to include in backup:',
              style: TextStyle(color: Colors.white70, fontSize: subtitleSize),
            ),
            SizedBox(height: 16),
            ListTile(
              leading: Icon(Icons.check_circle, color: Colors.green, size: iconSize),
              title: Text('All Media', style: TextStyle(color: Colors.white, fontSize: bodySize)),
              subtitle: Text('Include all photos, videos, audio', style: TextStyle(color: Colors.white70, fontSize: subtitleSize)),
              onTap: () => Navigator.pop(context, null), // null = all media
            ),
            ListTile(
              leading: Icon(Icons.calendar_today, color: Colors.cyanAccent, size: iconSize),
              title: Text('Last 7 Days', style: TextStyle(color: Colors.white, fontSize: bodySize)),
              subtitle: Text('Only recent media (smaller backup)', style: TextStyle(color: Colors.white70, fontSize: subtitleSize)),
              onTap: () => Navigator.pop(context, 7),
            ),
            ListTile(
              leading: Icon(Icons.calendar_today, color: Colors.cyanAccent, size: iconSize),
              title: Text('Last 15 Days', style: TextStyle(color: Colors.white, fontSize: bodySize)),
              subtitle: Text('Recent media from past 2 weeks', style: TextStyle(color: Colors.white70, fontSize: subtitleSize)),
              onTap: () => Navigator.pop(context, 15),
            ),
            ListTile(
              leading: Icon(Icons.calendar_today, color: Colors.cyanAccent, size: iconSize),
              title: Text('Last 30 Days', style: TextStyle(color: Colors.white, fontSize: bodySize)),
              subtitle: Text('Recent media from past month', style: TextStyle(color: Colors.white70, fontSize: subtitleSize)),
              onTap: () => Navigator.pop(context, 30),
            ),
            ListTile(
              leading: Icon(Icons.cancel, color: Colors.orange, size: iconSize),
              title: Text('No Media', style: TextStyle(color: Colors.white, fontSize: bodySize)),
              subtitle: Text('Messages only (smallest backup)', style: TextStyle(color: Colors.white70, fontSize: subtitleSize)),
              onTap: () => Navigator.pop(context, -1), // -1 = no media
            ),
          ],
        ),
      ),
    );

    // Determine the actual media filter value based on user selection
    int? excludeMediaDays;
    if (mediaOption == -1) {
      // No media: use 0 days to exclude all media (all media is older than 0 days)
      excludeMediaDays = 0;
    } else {
      // null, 7, 15, 30: use as-is
      excludeMediaDays = mediaOption;
    }

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
      await BackupNotificationService.showProgressNotification('Starting backup...', 0);

      // Check cancellation
      if (_backupCancellationRequested) {
        throw Exception('Backup cancelled by user');
      }

      await _updateProgress(0.1, 'Connecting to Google Drive...');
      await BackupNotificationService.showProgressNotification('Connecting to Google Drive...', 10);

      // Check cancellation
      if (_backupCancellationRequested) {
        throw Exception('Backup cancelled by user');
      }

      // IMPORTANT: Pass cancellation checker to backup service
      // The service will check this before each major operation
      final fileId = await _backupService.createGoogleDriveBackup(
        passphrase: passphrase,
        excludeMediaOlderThanDays: excludeMediaDays,
        shouldCancel: () => _backupCancellationRequested, // Check cancellation at each step
        onMediaProgress: (current, total, fileName) {
          // CRITICAL: Check cancellation during media upload
          if (_backupCancellationRequested) {
            debugPrint('[BackupManagement] Cancellation detected during media upload, aborting...');
            // Note: The backup service needs to check for cancellation internally
            // This callback just updates UI, actual cancellation happens in service
            return;
          }

          // Calculate progress
          final mediaProgress = 0.3 + (current / total) * 0.6; // 30-90% for media upload
          final mediaStatus = 'Uploading media $current/$total: $fileName';
          final notificationProgress = (mediaProgress * 100).toInt();

          // CRITICAL: Update notification even if widget is disposed
          // User needs to see progress even after navigating away
          BackupNotificationService.showProgressNotification(
            'Uploading media files ($current/$total)',
            notificationProgress,
          );

          debugPrint('[BackupManagement] Media upload: $current/$total - $fileName');

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
      await BackupNotificationService.showProgressNotification('Finalizing...', 95);

      // Check cancellation before showing success
      if (_backupCancellationRequested) {
        throw Exception('Backup cancelled by user');
      }

      // Show success notification (visible even if user left screen)
      await BackupNotificationService.showSuccessNotification('Google Drive');

      if (mounted) {
        await _updateProgress(1.0, 'Backup uploaded with media!');
        _showSnackbar('Backup uploaded to Google Drive successfully!', isError: false);

        // Update cache after successful backup
        _updateGoogleDriveCache(_isGoogleDriveSignedIn, _googleDriveEmail);
      } else {
        debugPrint('[BackupManagement] Widget disposed, but backup uploaded successfully');
      }
    } catch (e) {
      debugPrint('[BackupManagement] Google Drive backup error: $e');

      // Handle cancellation differently from errors
      if (e.toString().contains('cancelled by user') || e.toString().contains('upload cancelled')) {
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
      debugPrint('[BackupManagement] Widget disposed, skipping UI update: $status');
      return;
    }
    setState(() {
      _backupProgress = progress;
      _backupStatus = status;
    });
    await Future.delayed(const Duration(milliseconds: 300));
  }

  void _cancelBackup() {
    debugPrint('[BackupManagement] ⚠️ CANCEL BUTTON PRESSED - Setting cancellation flag to TRUE');

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
      debugPrint('[BackupManagement] Widget disposed, setting cancellation flag without setState');
    }

    debugPrint('[BackupManagement] ⚠️ Cancellation flag is now: $_backupCancellationRequested');

    // Notify through notification (works even if widget is disposed)
    BackupNotificationService.showProgressNotification('Cancelling...', (_backupProgress * 100).toInt());

    debugPrint('[BackupManagement] Backup/Restore cancellation requested');
  }

  Future<void> _restoreBackup(String filePath) async {
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

    try {
      // Show initial notification
      await BackupNotificationService.showProgressNotification('Starting restore...', 0);

      // Check cancellation
      if (_backupCancellationRequested) {
        debugPrint('[BackupManagement] Local restore cancelled at start');
        throw Exception('Restore cancelled by user');
      }

      await _updateProgress(0.1, 'Loading backup file...');
      await BackupNotificationService.showProgressNotification('Loading backup file...', 10);
      final encryptedFile = File(filePath);

      // Check cancellation
      if (_backupCancellationRequested) {
        debugPrint('[BackupManagement] Local restore cancelled after loading file');
        throw Exception('Restore cancelled by user');
      }

      await _updateProgress(0.2, 'Reading encrypted data...');
      await BackupNotificationService.showProgressNotification('Reading encrypted data...', 20);
      await Future.delayed(const Duration(milliseconds: 500));

      // Check cancellation
      if (_backupCancellationRequested) {
        debugPrint('[BackupManagement] Local restore cancelled before decryption');
        throw Exception('Restore cancelled by user');
      }

      await _updateProgress(0.3, 'Decrypting backup...');
      await BackupNotificationService.showProgressNotification('Decrypting backup...', 30);

      // Decrypt - this is a long operation, keep notification alive
      final backupData = await _backupService.decryptBackup(encryptedFile, passphrase);

      // Immediately update notification after decrypt
      await BackupNotificationService.showProgressNotification('Backup decrypted successfully', 40);

      // Check cancellation after decryption
      if (_backupCancellationRequested) {
        debugPrint('[BackupManagement] Local restore cancelled after decryption');
        throw Exception('Restore cancelled by user');
      }

      await _updateProgress(0.5, 'Preparing database...');
      await BackupNotificationService.showProgressNotification('Preparing database...', 50);
      await Future.delayed(const Duration(milliseconds: 300));

      // Check cancellation
      if (_backupCancellationRequested) {
        debugPrint('[BackupManagement] Local restore cancelled after validation');
        throw Exception('Restore cancelled by user');
      }

      await _updateProgress(0.6, 'Restoring messages...');
      await BackupNotificationService.showProgressNotification('Restoring messages...', 60);

      // Check cancellation
      if (_backupCancellationRequested) {
        debugPrint('[BackupManagement] Local restore cancelled before restore');
        throw Exception('Restore cancelled by user');
      }

      // Restore - this is a long operation, keep notification alive
      await _backupService.restoreBackup(backupData);

      // Immediately update notification after restore
      await BackupNotificationService.showProgressNotification('Messages restored successfully', 80);

      // Check cancellation after restore
      if (_backupCancellationRequested) {
        throw Exception('Restore cancelled by user');
      }

      await _updateProgress(0.9, 'Finalizing restore...');
      await BackupNotificationService.showProgressNotification('Finalizing restore...', 90);
      await Future.delayed(const Duration(milliseconds: 300));

      // Check cancellation
      if (_backupCancellationRequested) {
        throw Exception('Restore cancelled by user');
      }

      await _updateProgress(0.95, 'Completing restore...');
      await BackupNotificationService.showProgressNotification('Completing restore...', 95);

      // Track this backup as restored
      final backupFileName = path.basename(filePath);
      final backupModified = encryptedFile.statSync().modified.millisecondsSinceEpoch;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('last_restored_backup_name', backupFileName);
      await prefs.setInt('last_restored_backup_timestamp', backupModified);

      await _updateProgress(1.0, 'Restore completed!');

      // Show message if widget is still mounted
      if (mounted) {
        _showSnackbar('Backup restored! Restarting app...', isError: false);
        await Future.delayed(const Duration(seconds: 2));
      } else {
        debugPrint('[BackupManagement] Widget disposed, restarting app anyway...');
        await Future.delayed(const Duration(seconds: 1));
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

      // Handle cancellation differently from errors
      if (e.toString().contains('cancelled by user')) {
        debugPrint('[BackupManagement] Restore cancelled by user');

        // Show cancellation notification
        await BackupNotificationService.showFailureNotification('Local', 'Restore cancelled');

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
        if (mounted) _showSnackbar('Failed to sign in to Google Drive', isError: true);
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
    final titleSize = (screenWidth * 0.045).clamp(16.0, 20.0);
    final bodySize = (screenWidth * 0.035).clamp(13.0, 16.0);

    try {
      if (!mounted) return;

      // Show confirmation dialog explaining what will happen
      final confirm = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: const Color(0xFF0a1128),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(borderRadius),
            side: BorderSide(color: Colors.cyanAccent.withOpacity(0.3)),
          ),
          title: Text('Change Google Drive Account', style: TextStyle(color: Colors.white, fontSize: titleSize)),
          content: Text(
            'You will be signed out from the current account and can select a different Google account.\n\nImportant: If you cancel the account selection, you\'ll need to sign in again.',
            style: TextStyle(color: Colors.white70, fontSize: bodySize),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text('Cancel', style: TextStyle(color: Colors.white70, fontSize: bodySize)),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text('Continue', style: TextStyle(color: Colors.cyanAccent, fontSize: bodySize)),
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
          if (mounted) _showSnackbar('Google Drive account changed to $newEmail');
        } else {
          if (mounted) _showSnackbar('Signed in with same account');
        }
      } else {
        // User cancelled account picker - no account is now signed in
        await _checkGoogleDriveStatus();
        if (mounted) {
          _showSnackbar('Account selection cancelled. Please sign in to use Google Drive backup.', isError: true);
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
    final titleSize = (screenWidth * 0.045).clamp(16.0, 20.0);
    final bodySize = (screenWidth * 0.035).clamp(13.0, 16.0);

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF0a1128),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(borderRadius),
          side: BorderSide(color: Colors.cyanAccent.withOpacity(0.3)),
        ),
        title: Text('Sign Out', style: TextStyle(color: Colors.white, fontSize: titleSize)),
        content: Text(
          'Are you sure you want to sign out from Google Drive?',
          style: TextStyle(color: Colors.white70, fontSize: bodySize),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel', style: TextStyle(color: Colors.white70, fontSize: bodySize)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Sign Out', style: TextStyle(color: Colors.red, fontSize: bodySize)),
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
    final screenWidth = MediaQuery.of(context).size.width;
    final borderRadius = (screenWidth * 0.0375).clamp(12.0, 18.0);
    final borderRadius2 = (screenWidth * 0.025).clamp(8.0, 12.0);
    final titleSize = (screenWidth * 0.045).clamp(16.0, 20.0);
    final bodySize = (screenWidth * 0.035).clamp(13.0, 16.0);
    final smallSize = (screenWidth * 0.03).clamp(11.0, 14.0);
    final iconSize1 = (screenWidth * 0.05).clamp(18.0, 24.0);
    final iconSize2 = (screenWidth * 0.045).clamp(16.0, 20.0);
    final spacing1 = (MediaQuery.of(context).size.height * 0.0125).clamp(8.0, 12.0);

    try {
      if (!mounted) return;
      setState(() => _isLoading = true);

      // Optimistic execution: Trust cache and try to list backups
      // getDriveApi() inside listBackupsFromGoogleDrive() will handle auth if needed
      final backups = await _backupService.listBackupsFromGoogleDrive();

      // Update cache after successful operation
      if (_isGoogleDriveSignedIn) {
        _updateGoogleDriveCache(true, _googleDriveEmail);
      }

      if (backups.isEmpty) {
        _showSnackbar('No backups found in Google Drive');
        return;
      }

      if (!mounted) return;

      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: const Color(0xFF0a1128),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(borderRadius),
            side: BorderSide(color: Colors.cyanAccent.withOpacity(0.3)),
          ),
          title: Text('Google Drive Backups', style: TextStyle(color: Colors.white, fontSize: titleSize)),
          content: Container(
            width: double.maxFinite,
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.6,
            ),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: backups.length,
              itemBuilder: (context, index) {
                final backup = backups[index];

                // CRITICAL: Convert UTC time from Drive API to local time
                final localDate = backup.createdTime != null
                    ? backup.createdTime!.toLocal() // Convert UTC to local
                    : null;
                final date = localDate != null
                    ? _formatDateTime(localDate)
                    : 'Unknown date';

                return Card(
                  color: const Color(0xFF1B263B),
                  margin: EdgeInsets.only(bottom: spacing1),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(borderRadius2),
                    side: BorderSide(color: Colors.cyanAccent.withOpacity(0.2)),
                  ),
                  child: Padding(
                    padding: EdgeInsets.all(spacing1),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Backup name with folder icon
                        Row(
                          children: [
                            Icon(Icons.cloud_done, color: Colors.cyanAccent, size: iconSize1),
                            SizedBox(width: spacing1),
                            Expanded(
                              child: Text(
                                backup.name ?? 'Unknown',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: bodySize,
                                  fontWeight: FontWeight.bold,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: spacing1),

                        // Date and type info
                        Row(
                          children: [
                            Icon(Icons.access_time, color: Colors.white54, size: iconSize2 * 0.8),
                            SizedBox(width: spacing1 * 0.5),
                            Text(
                              date,
                              style: TextStyle(color: Colors.white70, fontSize: smallSize),
                            ),
                          ],
                        ),
                        SizedBox(height: spacing1 * 0.5),
                        Row(
                          children: [
                            Icon(Icons.photo_library, color: Colors.green, size: iconSize2 * 0.8),
                            SizedBox(width: spacing1 * 0.5),
                            Text(
                              'Full backup with media',
                              style: TextStyle(color: Colors.green, fontSize: smallSize),
                            ),
                          ],
                        ),
                        SizedBox(height: spacing1),

                        // Action buttons
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () {
                                  Navigator.pop(context);
                                  _restoreFromGoogleDrive(backup.id!);
                                },
                                icon: Icon(Icons.download, size: iconSize2 * 0.9),
                                label: Text('Restore', style: TextStyle(fontSize: smallSize)),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.cyanAccent,
                                  side: BorderSide(color: Colors.cyanAccent),
                                  padding: EdgeInsets.symmetric(
                                    vertical: spacing1 * 0.8,
                                    horizontal: spacing1,
                                  ),
                                ),
                              ),
                            ),
                            SizedBox(width: spacing1),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () {
                                  Navigator.pop(context);
                                  _deleteGoogleDriveBackup(backup.id!);
                                },
                                icon: Icon(Icons.delete, size: iconSize2 * 0.9),
                                label: Text('Delete', style: TextStyle(fontSize: smallSize)),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.redAccent,
                                  side: BorderSide(color: Colors.redAccent),
                                  padding: EdgeInsets.symmetric(
                                    vertical: spacing1 * 0.8,
                                    horizontal: spacing1,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Close', style: TextStyle(color: Colors.cyanAccent, fontSize: bodySize)),
            ),
          ],
        ),
      );
    } catch (e) {
      debugPrint('[BackupManagement] Error listing Google Drive backups: $e');
      if (mounted) _showSnackbar('Failed to load backups: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
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
      await BackupNotificationService.showProgressNotification('Starting Google Drive restore...', 0);

      // Check cancellation
      if (_backupCancellationRequested) {
        throw Exception('Restore cancelled by user');
      }

      await _updateProgress(0.1, 'Downloading from Google Drive...');
      await BackupNotificationService.showProgressNotification('Downloading from Google Drive...', 10);

      // Check cancellation
      if (_backupCancellationRequested) {
        throw Exception('Restore cancelled by user');
      }

      // Use new restore method with media download progress tracking
      await _backupService.restoreFromGoogleDrive(
        backupFolderId: folderId,
        passphrase: passphrase,
        shouldCancel: () {
          debugPrint('[BackupManagement] shouldCancel callback called, returning: $_backupCancellationRequested');
          return _backupCancellationRequested;
        },
        onMediaProgress: (current, total, fileName) {
          // Check cancellation during media download
          if (_backupCancellationRequested) {
            debugPrint('[BackupManagement] Cancellation detected during media download');
            return;
          }

          // Update UI and notification with media download progress
          final mediaProgress = 0.5 + (current / total) * 0.4; // 50-90% for media download
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

            debugPrint('[BackupManagement] Media download: $current/$total - $fileName');
          }
        },
      );

      // Check cancellation after restore
      if (_backupCancellationRequested) {
        throw Exception('Restore cancelled by user');
      }

      await _updateProgress(1.0, 'Restore completed!');
      await BackupNotificationService.showProgressNotification('Restore completed!', 100);

      // Show message if widget is still mounted
      if (mounted) {
        _showSnackbar('Backup restored with media! Restarting app...', isError: false);
        await Future.delayed(const Duration(seconds: 2));
      } else {
        debugPrint('[BackupManagement] Widget disposed, restarting app anyway...');
        await Future.delayed(const Duration(seconds: 1));
      }

      // CRITICAL: Restart app even if widget is disposed
      debugPrint('[BackupManagement] Triggering app restart after Google Drive restore...');
      try {
        Restart.restartApp();
        debugPrint('[BackupManagement] ✅ Restart command sent');
      } catch (e) {
        debugPrint('[BackupManagement] ❌ Failed to restart: $e');
      }
    } catch (e) {
      debugPrint('[BackupManagement] Google Drive restore error: $e');

      // Handle cancellation differently from errors
      if (e.toString().contains('cancelled by user') || e.toString().contains('download cancelled')) {
        debugPrint('[BackupManagement] Google Drive restore cancelled by user');

        // Show cancellation notification
        await BackupNotificationService.showFailureNotification('Google Drive', 'Restore cancelled');

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
    final titleSize = (screenWidth * 0.045).clamp(16.0, 20.0);
    final bodySize = (screenWidth * 0.035).clamp(13.0, 16.0);

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF0a1128),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(borderRadius),
          side: BorderSide(color: Colors.cyanAccent.withOpacity(0.3)),
        ),
        title: Text('Delete Backup', style: TextStyle(color: Colors.white, fontSize: titleSize)),
        content: Text(
          'Are you sure you want to delete this backup from Google Drive? This action cannot be undone.',
          style: TextStyle(color: Colors.white70, fontSize: bodySize),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel', style: TextStyle(color: Colors.white70, fontSize: bodySize)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Delete', style: TextStyle(color: Colors.redAccent, fontSize: bodySize)),
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

  Future<void> _deleteBackup(String filePath) async {
    final screenWidth = MediaQuery.of(context).size.width;
    final borderRadius = (screenWidth * 0.0375).clamp(12.0, 18.0);
    final titleSize = (screenWidth * 0.045).clamp(16.0, 20.0);
    final bodySize = (screenWidth * 0.035).clamp(13.0, 16.0);

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF0a1128),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(borderRadius),
          side: BorderSide(color: Colors.cyanAccent.withOpacity(0.3)),
        ),
        title: Text('Delete Backup', style: TextStyle(color: Colors.white, fontSize: titleSize)),
        content: Text(
          'Are you sure you want to delete this backup? This action cannot be undone.',
          style: TextStyle(color: Colors.white70, fontSize: bodySize),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel', style: TextStyle(color: Colors.white70, fontSize: bodySize)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Delete', style: TextStyle(color: Colors.redAccent, fontSize: bodySize)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await File(filePath).delete();
        _showSnackbar('Backup deleted');
        await _loadBackupsList();
      } catch (e) {
        _showSnackbar('Failed to delete backup: $e', isError: true);
      }
    }
  }

  Future<String?> _askForPassword({required String title, required String hint}) async {
    final screenWidth = MediaQuery.of(context).size.width;
    final borderRadius = (screenWidth * 0.0375).clamp(12.0, 18.0);
    final titleSize = (screenWidth * 0.045).clamp(16.0, 20.0);
    final bodySize = (screenWidth * 0.035).clamp(13.0, 16.0);

    String? password;
    bool obscurePassword = true;

    final result = await showDialog<String?>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          backgroundColor: const Color(0xFF0a1128),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(borderRadius),
            side: BorderSide(color: Colors.cyanAccent.withOpacity(0.3)),
          ),
          title: Text(title, style: TextStyle(color: Colors.white, fontSize: titleSize)),
          content: TextField(
            obscureText: obscurePassword,
            style: TextStyle(color: Colors.white, fontSize: bodySize),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: TextStyle(color: Colors.white38, fontSize: bodySize),
              enabledBorder: const UnderlineInputBorder(
                borderSide: BorderSide(color: Colors.cyanAccent),
              ),
              focusedBorder: const UnderlineInputBorder(
                borderSide: BorderSide(color: Colors.cyanAccent, width: 2),
              ),
              suffixIcon: IconButton(
                icon: Icon(
                  obscurePassword ? Icons.visibility : Icons.visibility_off,
                  color: Colors.white54,
                ),
                onPressed: () {
                  setState(() {
                    obscurePassword = !obscurePassword;
                  });
                },
              ),
            ),
            onChanged: (value) => password = value,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, null), // CRITICAL: Return null for cancel
              child: Text('Cancel', style: TextStyle(color: Colors.white70, fontSize: bodySize)),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, password), // CRITICAL: Return password for OK
              child: Text('OK', style: TextStyle(color: Colors.cyanAccent, fontSize: bodySize)),
            ),
          ],
        ),
      ),
    );

    // CRITICAL: Return the dialog result (null for cancel, password for OK)
    return result;
  }

  void _showSnackbar(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.green,
        duration: const Duration(seconds: 2),
      ),
    );
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
      await Future.delayed(const Duration(milliseconds: 800));
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

    if (difference.inDays == 0) {
      return 'Today at ${dateTime.hour}:${dateTime.minute.toString().padLeft(2, '0')}';
    } else if (difference.inDays == 1) {
      return 'Yesterday at ${dateTime.hour}:${dateTime.minute.toString().padLeft(2, '0')}';
    } else if (difference.inDays < 7) {
      return '${difference.inDays} days ago';
    } else {
      return '${dateTime.day}/${dateTime.month}/${dateTime.year}';
    }
  }

  String _formatNextBackupTime(DateTime nextBackup) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));
    final nextBackupDate = DateTime(nextBackup.year, nextBackup.month, nextBackup.day);

    final timeStr = '${nextBackup.hour.toString().padLeft(2, '0')}:${nextBackup.minute.toString().padLeft(2, '0')}';

    if (nextBackupDate == today) {
      return 'Tonight at $timeStr';
    } else if (nextBackupDate == tomorrow) {
      return 'Tomorrow at $timeStr';
    } else {
      final daysUntil = nextBackupDate.difference(today).inDays;
      return 'In $daysUntil days at $timeStr';
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    final appBarTitleSize = (screenWidth * 0.05).clamp(18.0, 24.0);
    final sectionTitleSize = (screenWidth * 0.045).clamp(16.0, 20.0);
    final bodyTextSize = (screenWidth * 0.035).clamp(13.0, 16.0);
    final smallTextSize = (screenWidth * 0.03).clamp(11.0, 14.0);
    final iconSize1 = (screenWidth * 0.05).clamp(18.0, 24.0);
    final iconSize2 = (screenWidth * 0.045).clamp(16.0, 20.0);
    final iconSize3 = (screenWidth * 0.035).clamp(14.0, 18.0);
    final padding1 = (screenWidth * 0.04).clamp(12.0, 20.0);
    final padding2 = (screenWidth * 0.05).clamp(16.0, 24.0);
    final borderRadius1 = (screenWidth * 0.025).clamp(8.0, 12.0);
    final borderRadius2 = (screenWidth * 0.03).clamp(10.0, 14.0);
    final borderRadius3 = (screenWidth * 0.0375).clamp(12.0, 18.0);
    final buttonHeight = (screenHeight * 0.065).clamp(45.0, 60.0);
    final spacing1 = (screenHeight * 0.0125).clamp(8.0, 12.0);
    final spacing2 = (screenHeight * 0.02).clamp(12.0, 18.0);

    return CallAwareScreen(
      screenName: 'BackupManagementScreen',
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: const Color(0xFF0a1128),
        elevation: 0,
        title: Text('Backup Management', style: TextStyle(color: Colors.white, fontSize: appBarTitleSize)),
        iconTheme: const IconThemeData(color: Colors.cyanAccent),
        actions: [
          IconButton(
            icon: Icon(Icons.help_outline, color: Colors.cyanAccent, size: iconSize1),
            tooltip: 'How Backup Works',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const BackupInfoScreen()),
              );
            },
          ),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF0a1128),
              Color(0xFF1a1f3a),
              Color(0xFF0d1b2a),
              Color(0xFF16213e),
            ],
            stops: [0.0, 0.3, 0.6, 1.0],
          ),
        ),
        child: SingleChildScrollView(
          child: Column(
            children: [
              // Progress indicator section
              if (_isBackupInProgress)
                Container(
                  padding: EdgeInsets.all(padding1),
                  color: const Color(0xFF0a1128),
                  child: Column(
                    children: [
                      LinearProgressIndicator(
                        value: _backupProgress,
                        backgroundColor: Colors.white24,
                        color: Colors.cyanAccent,
                        minHeight: spacing1,
                      ),
                      SizedBox(height: spacing2),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              _backupStatus,
                              style: TextStyle(color: Colors.white70, fontSize: bodyTextSize),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          SizedBox(width: spacing1),
                          Text(
                            '${(_backupProgress * 100).toInt()}%',
                            style: TextStyle(
                              color: Colors.cyanAccent,
                              fontWeight: FontWeight.bold,
                              fontSize: bodyTextSize,
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: spacing2),
                      OutlinedButton.icon(
                        onPressed: _backupCancellationRequested ? null : _cancelBackup,
                        icon: Icon(Icons.cancel, size: iconSize2),
                        label: Text(
                          _backupCancellationRequested ? 'Cancelling...' : 'Cancel Backup/Restore',
                          style: TextStyle(fontSize: bodyTextSize),
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.red,
                          side: const BorderSide(color: Colors.red),
                          minimumSize: Size(double.infinity, buttonHeight * 0.7),
                        ),
                      ),
                    ],
                  ),
                ),

          // Create backup button
          Padding(
            padding: EdgeInsets.all(padding2),
            child: ElevatedButton.icon(
              onPressed: _isBackupInProgress ? null : _createBackup,
              icon: Icon(Icons.backup, size: iconSize1),
              label: Text('Create New Backup', style: TextStyle(fontSize: bodyTextSize)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.cyanAccent,
                foregroundColor: Colors.black,
                padding: EdgeInsets.symmetric(horizontal: padding1, vertical: padding1),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(borderRadius2)),
                minimumSize: Size(double.infinity, buttonHeight),
              ),
            ),
          ),

          // Google Drive section
          Padding(
            padding: EdgeInsets.symmetric(horizontal: padding2),
            child: Card(
              color: const Color(0xFF0a1128),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(borderRadius3),
                side: BorderSide(color: Colors.cyanAccent.withOpacity(0.2)),
              ),
              child: Padding(
                padding: EdgeInsets.all(padding2),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.cloud, color: Colors.cyanAccent, size: iconSize1),
                        SizedBox(width: spacing2),
                        Text(
                          'Google Drive',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: sectionTitleSize,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const Spacer(),
                        if (_isGoogleDriveSignedIn)
                          Container(
                            padding: EdgeInsets.symmetric(horizontal: spacing1, vertical: spacing1 * 0.5),
                            decoration: BoxDecoration(
                              color: Colors.green.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(borderRadius3),
                              border: Border.all(color: Colors.green),
                            ),
                            child: Text(
                              'Connected',
                              style: TextStyle(color: Colors.green, fontSize: smallTextSize),
                            ),
                          ),
                      ],
                    ),
                    SizedBox(height: spacing2),
                    if (_isGoogleDriveSignedIn)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Signed in as:',
                            style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: smallTextSize),
                          ),
                          SizedBox(height: spacing1 * 0.5),
                          Text(
                            _googleDriveEmail ?? '',
                            style: TextStyle(color: Colors.white, fontSize: bodyTextSize),
                          ),
                          SizedBox(height: spacing2),
                          OutlinedButton.icon(
                            onPressed: _isBackupInProgress ? null : _viewGoogleDriveBackups,
                            icon: Icon(Icons.cloud_download, size: iconSize2),
                            label: Text('View Backups', style: TextStyle(fontSize: bodyTextSize)),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.cyanAccent,
                              side: const BorderSide(color: Colors.cyanAccent),
                              minimumSize: Size(double.infinity, buttonHeight * 0.75),
                            ),
                          ),
                          SizedBox(height: spacing1),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: _isBackupInProgress ? null : _changeGoogleDriveAccount,
                                  icon: Icon(Icons.swap_horiz, size: iconSize2),
                                  label: Text('Change Account', style: TextStyle(fontSize: bodyTextSize)),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: Colors.cyanAccent,
                                    side: const BorderSide(color: Colors.cyanAccent),
                                    padding: EdgeInsets.symmetric(
                                      horizontal: padding1 * 0.5,
                                      vertical: spacing2,
                                    ),
                                    minimumSize: Size(0, buttonHeight * 0.7),
                                  ),
                                ),
                              ),
                              SizedBox(width: spacing1),
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: _isBackupInProgress ? null : _signOutFromGoogleDrive,
                                  icon: Icon(Icons.logout, size: iconSize2),
                                  label: Text('Sign Out', style: TextStyle(fontSize: bodyTextSize)),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: Colors.red,
                                    side: const BorderSide(color: Colors.red),
                                    padding: EdgeInsets.symmetric(
                                      horizontal: padding1 * 0.5,
                                      vertical: spacing2,
                                    ),
                                    minimumSize: Size(0, buttonHeight * 0.7),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      )
                    else
                      OutlinedButton.icon(
                        onPressed: _signInToGoogleDrive,
                        icon: Icon(Icons.login, size: iconSize1),
                        label: Text('Sign in to Google Drive', style: TextStyle(fontSize: bodyTextSize)),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.cyanAccent,
                          side: const BorderSide(color: Colors.cyanAccent),
                          minimumSize: Size(double.infinity, buttonHeight * 0.85),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          SizedBox(height: padding2),

          // Auto-Backup Settings section
          Padding(
            padding: EdgeInsets.symmetric(horizontal: padding2),
            child: Consumer<BackupSettingsProvider>(
              builder: (context, settingsProvider, child) {
                final settings = settingsProvider.settings;
                final lastBackup = settingsProvider.getLastBackupTimeFormatted();

                return Card(
                  color: const Color(0xFF0a1128),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(borderRadius3),
                    side: BorderSide(color: Colors.cyanAccent.withOpacity(0.2)),
                  ),
                  child: Padding(
                    padding: EdgeInsets.all(padding2),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.schedule, color: Colors.cyanAccent, size: iconSize1),
                            SizedBox(width: spacing2),
                            Text(
                              'Auto-Backup',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: sectionTitleSize,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const Spacer(),
                            Switch(
                              value: settings.enabled,
                              onChanged: (value) async {
                                await settingsProvider.setEnabled(value);
                                if (value) {
                                  _triggerSettingsChangedFeedback('Auto-backup enabled');
                                } else {
                                  HapticFeedback.lightImpact();
                                  _showSnackbar('Auto-backup disabled');
                                }
                              },
                              activeColor: Colors.cyanAccent,
                            ),
                          ],
                        ),
                        if (settings.enabled) ...[
                          Divider(color: Colors.white24, height: spacing2 * 2),

                          // Frequency
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(Icons.repeat, color: Colors.cyanAccent, size: iconSize2),
                            title: Text('Frequency', style: TextStyle(color: Colors.white70, fontSize: bodyTextSize)),
                            trailing: DropdownButton<BackupFrequency>(
                              value: settings.frequency,
                              dropdownColor: const Color(0xFF1B263B),
                              style: TextStyle(color: Colors.white, fontSize: bodyTextSize),
                              underline: Container(height: 1, color: Colors.cyanAccent),
                              items: [
                                BackupFrequency.daily,
                                BackupFrequency.weekly,
                                BackupFrequency.monthly,
                              ].map((freq) {
                                return DropdownMenuItem(
                                  value: freq,
                                  child: Text(freq.displayName),
                                );
                              }).toList(),
                              onChanged: (value) async {
                                if (value != null) {
                                  await settingsProvider.setFrequency(value);
                                  _triggerSettingsChangedFeedback(
                                    'Backup frequency updated to ${value.displayName}',
                                  );
                                }
                              },
                            ),
                          ),

                          // Info: Auto-backup is local only
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(Icons.info_outline, color: Colors.cyanAccent, size: iconSize2),
                            title: Text('Backup Location', style: TextStyle(color: Colors.white70, fontSize: bodyTextSize)),
                            subtitle: Text(
                              'Local storage only • No internet required',
                              style: TextStyle(color: Colors.white54, fontSize: smallTextSize),
                            ),
                          ),

                          Divider(color: Colors.white24, height: spacing2 * 2),

                          // Set Passphrase Button (One-time only)
                          if (settings.lastBackupPassphrase == null)
                            OutlinedButton.icon(
                              onPressed: () async {
                                final passphrase = await _askForPassword(
                                  title: 'Set Auto-Backup Passphrase',
                                  hint: 'Enter passphrase for auto-backups',
                                );
                                if (passphrase != null && passphrase.isNotEmpty) {
                                  await settingsProvider.setBackupPassphrase(passphrase);
                                  HapticFeedback.heavyImpact();
                                  _showSnackbar('Auto-backup passphrase set successfully');
                                }
                              },
                              icon: Icon(Icons.lock, size: iconSize2),
                              label: Text(
                                'Set Passphrase (Required)',
                                style: TextStyle(fontSize: bodyTextSize),
                              ),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.orange,
                                side: const BorderSide(color: Colors.orange),
                                minimumSize: Size(double.infinity, buttonHeight * 0.75),
                              ),
                            )
                          else
                            // Passphrase already set - show info
                            Container(
                              padding: EdgeInsets.all(spacing2),
                              decoration: BoxDecoration(
                                color: Colors.green.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(borderRadius1),
                                border: Border.all(color: Colors.green.withOpacity(0.3)),
                              ),
                              child: Row(
                                children: [
                                  Icon(Icons.check_circle, color: Colors.green, size: iconSize2),
                                  SizedBox(width: spacing2),
                                  Expanded(
                                    child: Text(
                                      'Passphrase configured',
                                      style: TextStyle(
                                        color: Colors.green,
                                        fontWeight: FontWeight.bold,
                                        fontSize: bodyTextSize,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),


                          // Last Backup Info
                          if (lastBackup != null) ...[
                            SizedBox(height: spacing2),
                            Row(
                              children: [
                                Icon(Icons.access_time, color: Colors.white54, size: iconSize3),
                                SizedBox(width: spacing1),
                                Text(
                                  'Last backup: $lastBackup',
                                  style: TextStyle(color: Colors.white54, fontSize: smallTextSize),
                                ),
                              ],
                            ),
                          ],

                          // Battery Optimization Warning (Android only)
                          if (!_isBatteryOptimizationDisabled) ...[
                            SizedBox(height: padding2),
                            Container(
                              padding: EdgeInsets.all(spacing2),
                              decoration: BoxDecoration(
                                color: Colors.orange.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(borderRadius1),
                                border: Border.all(color: Colors.orange.withOpacity(0.3)),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Icon(Icons.battery_alert, color: Colors.orange, size: iconSize2),
                                      SizedBox(width: spacing2),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              'Battery Optimization Active',
                                              style: TextStyle(
                                                color: Colors.orange,
                                                fontWeight: FontWeight.bold,
                                                fontSize: bodyTextSize,
                                              ),
                                            ),
                                            SizedBox(height: spacing1 * 0.5),
                                            Text(
                                              'For best results:\n1. Set battery to "Unrestricted"\n2. Enable "Allow background activity"',
                                              style: TextStyle(color: Colors.white70, fontSize: smallTextSize),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                  SizedBox(height: spacing2),
                                  ElevatedButton.icon(
                                    onPressed: _requestBatteryOptimizationExemption,
                                    icon: Icon(Icons.settings, size: iconSize3),
                                    label: Text('Open Battery Settings'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.orange,
                                      foregroundColor: Colors.white,
                                      padding: EdgeInsets.symmetric(horizontal: spacing2, vertical: spacing1),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(borderRadius1),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          SizedBox(height: padding2),

          // Local backups header
          Padding(
            padding: EdgeInsets.symmetric(horizontal: padding2),
            child: Row(
              children: [
                Icon(Icons.phone_android, color: Colors.cyanAccent, size: iconSize2),
                SizedBox(width: spacing1),
                Text(
                  'Local Backups',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: sectionTitleSize,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: spacing1),

              // Backups list
              _isLoading
                  ? Padding(
                      padding: EdgeInsets.all(padding1 * 2),
                      child: const Center(child: CircularProgressIndicator(color: Colors.cyanAccent)),
                    )
                  : _backupsList.isEmpty
                      ? Padding(
                          padding: EdgeInsets.all(padding1 * 2),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.backup_outlined, size: (screenWidth * 0.2).clamp(60.0, 100.0), color: Colors.white24),
                              SizedBox(height: padding2),
                              Text(
                                'No backups found',
                                style: TextStyle(color: Colors.white54, fontSize: sectionTitleSize),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          padding: EdgeInsets.symmetric(horizontal: padding2),
                          itemCount: _backupsList.length,
                          itemBuilder: (context, index) {
                            final backup = _backupsList[index];
                            final stat = backup.statSync();
                            final size = _formatFileSize(stat.size);
                            final modified = _formatDateTime(stat.modified);

                            return Card(
                              color: const Color(0xFF0a1128),
                              margin: EdgeInsets.only(bottom: spacing2),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(borderRadius3),
                                side: BorderSide(color: Colors.cyanAccent.withOpacity(0.2)),
                              ),
                              child: ListTile(
                                contentPadding: EdgeInsets.all(padding2),
                                leading: CircleAvatar(
                                  backgroundColor: Colors.cyanAccent.withOpacity(0.2),
                                  child: Icon(Icons.backup, color: Colors.cyanAccent, size: iconSize1),
                                ),
                                title: Text(
                                  path.basename(backup.path),
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: bodyTextSize,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    SizedBox(height: spacing1),
                                    Row(
                                      children: [
                                        Icon(Icons.access_time, size: iconSize3, color: Colors.white54),
                                        SizedBox(width: spacing1 * 0.5),
                                        Expanded(
                                          child: Text(
                                            modified,
                                            style: TextStyle(color: Colors.white54, fontSize: smallTextSize),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                    SizedBox(height: spacing1 * 0.5),
                                    Row(
                                      children: [
                                        Icon(Icons.storage, size: iconSize3, color: Colors.white54),
                                        SizedBox(width: spacing1 * 0.5),
                                        Expanded(
                                          child: Text(
                                            size,
                                            style: TextStyle(color: Colors.white54, fontSize: smallTextSize),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: Icon(Icons.restore, color: Colors.cyanAccent, size: iconSize1),
                                      onPressed: _isBackupInProgress ? null : () => _restoreBackup(backup.path),
                                      tooltip: 'Restore',
                                    ),
                                    IconButton(
                                      icon: Icon(Icons.delete, color: Colors.redAccent, size: iconSize1),
                                      onPressed: _isBackupInProgress ? null : () => _deleteBackup(backup.path),
                                      tooltip: 'Delete',
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
              SizedBox(height: padding2), // Bottom padding
            ],
          ),
        ),
      ),
      ),
    );
  }
}
