import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:restart_app/restart_app.dart';
import '../services/backup_service.dart';
import '../services/backup_settings_provider.dart';
import '../services/backup_notification_service.dart';
import '../widgets/call_aware_screen.dart';
import 'backup_info_screen.dart';
import 'package:provider/provider.dart';

class BackupManagementScreen extends StatefulWidget {
  const BackupManagementScreen({super.key});

  @override
  State<BackupManagementScreen> createState() => _BackupManagementScreenState();
}

class _BackupManagementScreenState extends State<BackupManagementScreen> {
  final BackupService _backupService = BackupService();
  List<FileSystemEntity> _backupsList = [];
  bool _isLoading = false;
  double _backupProgress = 0.0;
  String _backupStatus = '';
  bool _isBackupInProgress = false;
  bool _isGoogleDriveSignedIn = false;
  String? _googleDriveEmail;
  bool _isBatteryOptimizationDisabled = true;

  @override
  void initState() {
    super.initState();
    _loadBackupsList();
    _checkGoogleDriveStatus();
    _checkBatteryOptimization();
  }

  Future<void> _checkBatteryOptimization() async {
    final isDisabled = await BackupNotificationService.isBatteryOptimizationDisabled();
    setState(() {
      _isBatteryOptimizationDisabled = isDisabled;
    });
  }

  Future<void> _checkGoogleDriveStatus() async {
    final isSignedIn = await _backupService.isSignedInToGoogleDrive();
    final email = await _backupService.getGoogleDriveAccountEmail();
    setState(() {
      _isGoogleDriveSignedIn = isSignedIn;
      _googleDriveEmail = email;
    });
  }

  Future<void> _loadBackupsList() async {
    setState(() => _isLoading = true);

    try {
      // Request storage permission first (needed after reinstall)
      final storageStatus = await Permission.manageExternalStorage.status;

      if (!storageStatus.isGranted) {
        // print('[BackupManagement] Storage permission not granted, requesting...');
        final result = await Permission.manageExternalStorage.request();

        if (!result.isGranted) {
          // print('[BackupManagement] Storage permission denied');
          _showSnackbar('Storage permission required to access backups', isError: true);
          setState(() => _isLoading = false);
          return;
        }
        // print('[BackupManagement] Storage permission granted');
      }

      final downloadsDir = Directory('/storage/emulated/0/Download/Zarq_Backups');
      if (await downloadsDir.exists()) {
        // print('[BackupManagement] Found backups directory, listing files...');
        final backups = await downloadsDir.list().toList();
        backups.sort((a, b) => b.statSync().modified.compareTo(a.statSync().modified));

        // print('[BackupManagement] Found ${backups.length} backup files');
        setState(() {
          _backupsList = backups;
        });
      } else {
        // print('[BackupManagement] Backups directory does not exist');
        setState(() {
          _backupsList = [];
        });
      }
    } catch (e) {
      // print('[BackupManagement] Error loading backups: $e');
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

    setState(() {
      _isBackupInProgress = true;
      _backupProgress = 0.0;
      _backupStatus = 'Initializing backup...';
    });

    try {
      // Simulate progress steps
      await _updateProgress(0.2, 'Collecting messages...');
      final backupData = await _backupService.createLocalBackup();

      await _updateProgress(0.5, 'Encrypting backup...');
      final encryptedFile = await _backupService.encryptBackup(backupData, passphrase);

      await _updateProgress(0.8, 'Saving backup file...');
      final downloadsDir = Directory('/storage/emulated/0/Download/Zarq_Backups');
      if (!await downloadsDir.exists()) {
        await downloadsDir.create(recursive: true);
      }

      final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-').split('.')[0];
      final backupPath = '${downloadsDir.path}/backup_$timestamp.encrypted';
      await encryptedFile.copy(backupPath);

      await _updateProgress(1.0, 'Backup completed!');

      _showSnackbar('Backup created successfully!', isError: false);
      await _loadBackupsList();
    } catch (e) {
      // print('[BackupManagement] Backup error: $e');
      _showSnackbar('Backup failed: $e', isError: true);
    } finally {
      setState(() {
        _isBackupInProgress = false;
        _backupProgress = 0.0;
        _backupStatus = '';
      });
    }
  }

  Future<void> _createGoogleDriveBackup() async {
    final passphrase = await _askForPassword(
      title: 'Create Google Drive Backup',
      hint: 'Enter a strong passphrase',
    );

    if (passphrase == null || passphrase.isEmpty) {
      _showSnackbar('Backup cancelled');
      return;
    }

    setState(() {
      _isBackupInProgress = true;
      _backupProgress = 0.0;
      _backupStatus = 'Initializing backup...';
    });

    try {
      await _updateProgress(0.1, 'Collecting messages...');
      final backupData = await _backupService.createLocalBackup();

      await _updateProgress(0.3, 'Encrypting backup...');
      final encryptedFile = await _backupService.encryptBackup(backupData, passphrase);

      await _updateProgress(0.5, 'Connecting to Google Drive...');
      await Future.delayed(const Duration(milliseconds: 500));

      await _updateProgress(0.6, 'Uploading to Google Drive...');
      final fileId = await _backupService.uploadToGoogleDrive(encryptedFile);

      if (fileId == null) {
        throw Exception('Failed to upload to Google Drive');
      }

      await _updateProgress(1.0, 'Backup uploaded!');

      _showSnackbar('Backup uploaded to Google Drive successfully!', isError: false);
      await _checkGoogleDriveStatus();
    } catch (e) {
      // print('[BackupManagement] Google Drive backup error: $e');
      _showSnackbar('Google Drive backup failed: $e', isError: true);
    } finally {
      setState(() {
        _isBackupInProgress = false;
        _backupProgress = 0.0;
        _backupStatus = '';
      });
    }
  }

  Future<void> _updateProgress(double progress, String status) async {
    setState(() {
      _backupProgress = progress;
      _backupStatus = status;
    });
    await Future.delayed(const Duration(milliseconds: 300));
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

    setState(() {
      _isBackupInProgress = true;
      _backupProgress = 0.0;
      _backupStatus = 'Preparing restore...';
    });

    try {
      await _updateProgress(0.1, 'Loading backup file...');
      final encryptedFile = File(filePath);

      await _updateProgress(0.2, 'Reading encrypted data...');
      await Future.delayed(const Duration(milliseconds: 500));

      await _updateProgress(0.3, 'Decrypting backup...');
      final backupData = await _backupService.decryptBackup(encryptedFile, passphrase);

      await _updateProgress(0.5, 'Validating backup data...');
      await Future.delayed(const Duration(milliseconds: 500));

      await _updateProgress(0.6, 'Restoring messages...');
      await Future.delayed(const Duration(milliseconds: 300));

      await _updateProgress(0.7, 'Restoring attachments...');
      await _backupService.restoreBackup(backupData);

      await _updateProgress(0.85, 'Restoring Signal Protocol state...');
      await Future.delayed(const Duration(milliseconds: 500));

      await _updateProgress(0.95, 'Finalizing restore...');

      // Track this backup as restored
      final backupFileName = path.basename(filePath);
      final backupModified = encryptedFile.statSync().modified.millisecondsSinceEpoch;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('last_restored_backup_name', backupFileName);
      await prefs.setInt('last_restored_backup_timestamp', backupModified);

      await _updateProgress(1.0, 'Restore completed!');
      await Future.delayed(const Duration(milliseconds: 800));

      if (mounted) {
        _showSnackbar('Backup restored! Restarting app...', isError: false);
        await Future.delayed(const Duration(seconds: 2));
        Restart.restartApp();
      }
    } catch (e) {
      // print('[BackupManagement] Restore error: $e');
      _showSnackbar('Restore failed: $e', isError: true);
      setState(() {
        _isBackupInProgress = false;
        _backupProgress = 0.0;
        _backupStatus = '';
      });
    }
  }

  Future<void> _signInToGoogleDrive() async {
    try {
      setState(() => _isLoading = true);

      // Trigger Google Sign-In
      final driveApi = await _backupService.getDriveApi();

      if (driveApi != null) {
        await _checkGoogleDriveStatus();
        _showSnackbar('Signed in to Google Drive successfully!');
      } else {
        _showSnackbar('Failed to sign in to Google Drive', isError: true);
      }
    } catch (e) {
      // print('[BackupManagement] Google Drive sign-in error: $e');
      _showSnackbar('Sign-in failed: $e', isError: true);
    } finally {
      setState(() => _isLoading = false);
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
        await _checkGoogleDriveStatus();
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
      setState(() => _isLoading = true);

      final backups = await _backupService.listBackupsFromGoogleDrive();

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
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: backups.length,
              itemBuilder: (context, index) {
                final backup = backups[index];
                final size = backup.size != null ? _formatFileSize(int.parse(backup.size!)) : 'Unknown';
                final date = backup.createdTime != null
                    ? _formatDateTime(backup.createdTime!)
                    : 'Unknown date';

                return Card(
                  color: const Color(0xFF1B263B),
                  margin: EdgeInsets.only(bottom: spacing1),
                  child: ListTile(
                    leading: Icon(Icons.cloud, color: Colors.cyanAccent, size: iconSize1),
                    title: Text(
                      backup.name ?? 'Unknown',
                      style: TextStyle(color: Colors.white, fontSize: bodySize),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(height: spacing1 * 0.5),
                        Text(date, style: TextStyle(color: Colors.white54, fontSize: smallSize)),
                        Text(size, style: TextStyle(color: Colors.white54, fontSize: smallSize)),
                      ],
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: Icon(Icons.download, color: Colors.cyanAccent, size: iconSize2),
                          onPressed: () {
                            Navigator.pop(context);
                            _restoreFromGoogleDrive(backup.id!);
                          },
                        ),
                        IconButton(
                          icon: Icon(Icons.delete, color: Colors.redAccent, size: iconSize2),
                          onPressed: () {
                            Navigator.pop(context);
                            _deleteGoogleDriveBackup(backup.id!);
                          },
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
      // print('[BackupManagement] Error listing Google Drive backups: $e');
      _showSnackbar('Failed to load backups: $e', isError: true);
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _restoreFromGoogleDrive(String fileId) async {
    final passphrase = await _askForPassword(
      title: 'Restore from Google Drive',
      hint: 'Enter your backup passphrase',
    );

    if (passphrase == null || passphrase.isEmpty) {
      _showSnackbar('Restore cancelled');
      return;
    }

    setState(() {
      _isBackupInProgress = true;
      _backupProgress = 0.0;
      _backupStatus = 'Preparing restore...';
    });

    try {
      await _updateProgress(0.1, 'Downloading from Google Drive...');
      final downloadedFile = await _backupService.downloadFromGoogleDrive(fileId);

      if (downloadedFile == null) {
        throw Exception('Failed to download backup');
      }

      await _updateProgress(0.3, 'Decrypting backup...');
      final backupData = await _backupService.decryptBackup(downloadedFile, passphrase);

      await _updateProgress(0.6, 'Restoring messages...');
      await _backupService.restoreBackup(backupData);

      await _updateProgress(1.0, 'Restore completed!');

      if (mounted) {
        _showSnackbar('Backup restored! Restarting app...', isError: false);
        await Future.delayed(const Duration(seconds: 2));
        Restart.restartApp();
      }
    } catch (e) {
      // print('[BackupManagement] Google Drive restore error: $e');
      _showSnackbar('Restore failed: $e', isError: true);
      setState(() {
        _isBackupInProgress = false;
        _backupProgress = 0.0;
        _backupStatus = '';
      });
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
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF0a1128),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(borderRadius),
          side: BorderSide(color: Colors.cyanAccent.withOpacity(0.3)),
        ),
        title: Text(title, style: TextStyle(color: Colors.white, fontSize: titleSize)),
        content: TextField(
          obscureText: true,
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
          ),
          onChanged: (value) => password = value,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: TextStyle(color: Colors.white70, fontSize: bodySize)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('OK', style: TextStyle(color: Colors.cyanAccent, fontSize: bodySize)),
          ),
        ],
      ),
    );
    return password;
  }

  void _showSnackbar(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.green,
      ),
    );
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
                          Text(
                            _backupStatus,
                            style: TextStyle(color: Colors.white70, fontSize: bodyTextSize),
                          ),
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
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: _isBackupInProgress ? null : _viewGoogleDriveBackups,
                                  icon: Icon(Icons.cloud_download, size: iconSize2),
                                  label: Text('View Backups', style: TextStyle(fontSize: bodyTextSize)),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: Colors.cyanAccent,
                                    side: const BorderSide(color: Colors.cyanAccent),
                                    padding: EdgeInsets.symmetric(vertical: spacing2),
                                  ),
                                ),
                              ),
                              SizedBox(width: spacing1),
                              OutlinedButton(
                                onPressed: _signOutFromGoogleDrive,
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.red,
                                  side: const BorderSide(color: Colors.red),
                                  padding: EdgeInsets.all(spacing2),
                                ),
                                child: Icon(Icons.logout, size: iconSize2),
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
                              onChanged: (value) => settingsProvider.setEnabled(value),
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
                              onChanged: (value) {
                                if (value != null) settingsProvider.setFrequency(value);
                              },
                            ),
                          ),

                          // Destination
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(Icons.storage, color: Colors.cyanAccent, size: iconSize2),
                            title: Text('Destination', style: TextStyle(color: Colors.white70, fontSize: bodyTextSize)),
                            trailing: DropdownButton<BackupDestination>(
                              value: settings.destination,
                              dropdownColor: const Color(0xFF1B263B),
                              style: TextStyle(color: Colors.white, fontSize: bodyTextSize),
                              underline: Container(height: 1, color: Colors.cyanAccent),
                              items: BackupDestination.values.map((dest) {
                                return DropdownMenuItem(
                                  value: dest,
                                  child: Text(dest.displayName),
                                );
                              }).toList(),
                              onChanged: (value) {
                                if (value != null) settingsProvider.setDestination(value);
                              },
                            ),
                          ),

                          // WiFi Only
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            secondary: Icon(Icons.wifi, color: Colors.cyanAccent, size: iconSize2),
                            title: Text('WiFi Only', style: TextStyle(color: Colors.white70, fontSize: bodyTextSize)),
                            subtitle: Text(
                              settings.wifiOnly ? 'Backups only on WiFi' : 'Backups on WiFi or mobile data',
                              style: TextStyle(color: Colors.white38, fontSize: smallTextSize),
                            ),
                            value: settings.wifiOnly,
                            activeColor: Colors.cyanAccent,
                            onChanged: (value) => settingsProvider.setWifiOnly(value),
                          ),

                          // Media Age Limit
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(Icons.image, color: Colors.cyanAccent, size: iconSize2),
                            title: Text('Media Age Limit', style: TextStyle(color: Colors.white70, fontSize: bodyTextSize)),
                            subtitle: Text(
                              settings.mediaAgeLimitDays == null
                                ? 'Include all media'
                                : 'Last ${settings.mediaAgeLimitDays} days',
                              style: TextStyle(color: Colors.white38, fontSize: smallTextSize),
                            ),
                            trailing: DropdownButton<int?>(
                              value: settings.mediaAgeLimitDays,
                              dropdownColor: const Color(0xFF1B263B),
                              style: TextStyle(color: Colors.white, fontSize: bodyTextSize),
                              underline: Container(height: 1, color: Colors.cyanAccent),
                              items: [
                                const DropdownMenuItem(value: null, child: Text('All')),
                                const DropdownMenuItem(value: 7, child: Text('7 days')),
                                const DropdownMenuItem(value: 30, child: Text('30 days')),
                                const DropdownMenuItem(value: 90, child: Text('90 days')),
                              ],
                              onChanged: (value) => settingsProvider.setMediaAgeLimitDays(value),
                            ),
                          ),

                          Divider(color: Colors.white24, height: spacing2 * 2),

                          // Set Passphrase Button
                          OutlinedButton.icon(
                            onPressed: () async {
                              final passphrase = await _askForPassword(
                                title: 'Set Auto-Backup Passphrase',
                                hint: 'Enter passphrase for auto-backups',
                              );
                              if (passphrase != null && passphrase.isNotEmpty) {
                                await settingsProvider.setBackupPassphrase(passphrase);
                                _showSnackbar('Auto-backup passphrase set');
                              }
                            },
                            icon: Icon(Icons.lock, size: iconSize2),
                            label: Text(
                              settings.lastBackupPassphrase == null
                                  ? 'Set Passphrase (Required)'
                                  : 'Update Passphrase',
                              style: TextStyle(fontSize: bodyTextSize),
                            ),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: settings.lastBackupPassphrase == null
                                  ? Colors.orange
                                  : Colors.cyanAccent,
                              side: BorderSide(
                                color: settings.lastBackupPassphrase == null
                                    ? Colors.orange
                                    : Colors.cyanAccent,
                              ),
                              minimumSize: Size(double.infinity, buttonHeight * 0.75),
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
                              child: Row(
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
                                          'Auto-backup may not run reliably. Disable battery optimization for best results.',
                                          style: TextStyle(color: Colors.white70, fontSize: smallTextSize),
                                        ),
                                      ],
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
                                        Text(modified, style: TextStyle(color: Colors.white54, fontSize: smallTextSize)),
                                      ],
                                    ),
                                    SizedBox(height: spacing1 * 0.5),
                                    Row(
                                      children: [
                                        Icon(Icons.storage, size: iconSize3, color: Colors.white54),
                                        SizedBox(width: spacing1 * 0.5),
                                        Text(size, style: TextStyle(color: Colors.white54, fontSize: smallTextSize)),
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
