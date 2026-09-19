import 'package:flutter/material.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:provider/provider.dart';
import '../services/backup_service.dart';
import '../services/user_settings_provider.dart';
import '../widgets/backup_design.dart';
import '../widgets/notes_design.dart';
import '../widgets/call_aware_screen.dart';
import 'backup_info_screen.dart';

/// Full screen view for browsing and managing Google Drive backups.
class GoogleDriveBackupsScreen extends StatefulWidget {
  const GoogleDriveBackupsScreen({
    super.key,
    this.accountEmail,
    required this.onRestore,
  });

  final String? accountEmail;
  final ValueChanged<String> onRestore;

  @override
  State<GoogleDriveBackupsScreen> createState() => _GoogleDriveBackupsScreenState();
}

class _GoogleDriveBackupsScreenState extends State<GoogleDriveBackupsScreen> {
  final BackupService _backupService = BackupService();
  List<drive.File> _backups = [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadBackups();
  }

  Future<void> _loadBackups() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final backups = await _backupService.listBackupsFromGoogleDrive();
      if (mounted) {
        setState(() {
          _backups = backups;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Could not load backups from Google Drive.';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _confirmAndDelete(drive.File backup) async {
    final fileId = backup.id;
    if (fileId == null) return;

    final confirmed = await showNotesConfirmation(
      context,
      title: 'Delete cloud backup',
      body: 'Are you sure you want to delete this backup from Google Drive? This action cannot be undone.',
      confirm: 'Delete',
      danger: true,
      icon: Icons.delete_outline,
    );

    if (confirmed != true || !mounted) return;

    try {
      final success = await _backupService.deleteFromGoogleDrive(fileId);
      if (!mounted) return;
      if (success) {
        setState(() {
          _backups.removeWhere((b) => b.id == fileId);
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Backup deleted from Google Drive'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Color(0xFF283241),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to delete backup. Please try again.'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Color(0xFFBF6974),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Delete failed: $e'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: const Color(0xFFBF6974),
          ),
        );
      }
    }
  }

  Future<void> _showBackupOptions(drive.File backup) async {
    final action = await showBackupSheet<String>(
      context: context,
      builder: (ctx) => NotesSheet(
        title: 'Cloud backup options',
        description: backup.name ?? 'Google Drive backup',
        icon: Icons.cloud_outlined,
        child: Column(
          children: [
            InkWell(
              onTap: () => Navigator.pop(ctx, 'restore'),
              child: _sheetActionRow(
                Icons.settings_backup_restore_rounded,
                'Restore this backup',
                subtitle: 'Recover your messages and media onto this device',
              ),
            ),
            InkWell(
              onTap: () => Navigator.pop(ctx, 'delete'),
              child: _sheetActionRow(
                Icons.delete_outline,
                'Delete backup',
                subtitle: 'Permanently remove from Google Drive',
                danger: true,
              ),
            ),
          ],
        ),
      ),
    );

    if (!mounted || action == null) return;
    if (action == 'restore') {
      _startRestore(backup);
    } else if (action == 'delete') {
      await _confirmAndDelete(backup);
    }
  }

  void _startRestore(drive.File backup) {
    final fileId = backup.id;
    if (fileId == null) return;
    Navigator.pop(context); // Close the Google Drive screen to show restore progress
    widget.onRestore(fileId);
  }

  String _formatDateTime(DateTime dt) {
    final now = DateTime.now();
    final isToday = dt.year == now.year && dt.month == now.month && dt.day == now.day;
    final isYesterday = dt.year == now.year && dt.month == now.month && dt.day == now.day - 1;
    final time = '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    if (isToday) return 'Today at $time';
    if (isYesterday) return 'Yesterday at $time';
    final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${months[dt.month - 1]} ${dt.day}, ${dt.year} at $time';
  }

  Widget _sheetActionRow(
    IconData icon,
    String title, {
    String? subtitle,
    bool danger = false,
  }) {
    final c = NotesColors(context);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: c.line)),
      ),
      child: Row(
        children: [
          Icon(
            icon,
            size: 18,
            color: danger ? const Color(0xFFBF6974) : c.muted,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: c.text(12).copyWith(
                    color: danger ? const Color(0xFFBF6974) : c.ink,
                    fontWeight: danger ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(subtitle, style: c.text(10, muted: true)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    context.watch<UserSettingsProvider>();
    final c = NotesColors(context);

    return CallAwareScreen(
      screenName: 'GoogleDriveBackupsScreen',
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
            onRefresh: _loadBackups,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(22, 16, 22, 32),
              children: [
                // Top Heading
                Text(
                  'Google Drive backups',
                  style: c.text(22, bold: true).copyWith(letterSpacing: -.6),
                ),
                const SizedBox(height: 4),
                Text(
                  'Restore conversations and media saved to your cloud account.',
                  style: c.text(12, muted: true).copyWith(height: 1.6),
                ),
                const SizedBox(height: 18),

                // Connected Account Card
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: c.soft,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: c.line),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: c.blue.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(Icons.cloud_outlined, color: c.blue, size: 20),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Connected account',
                              style: c.text(10, muted: true),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              widget.accountEmail ?? 'Google Drive',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: c.text(12, bold: true),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: c.surface,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: c.line),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 6,
                              height: 6,
                              decoration: const BoxDecoration(
                                color: Color(0xFF50C878),
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 5),
                            Text('Connected', style: c.text(9, muted: true)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                // Section Label
                Padding(
                  padding: const EdgeInsets.only(top: 24, bottom: 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'AVAILABLE BACKUPS',
                        style: c.text(9, muted: true).copyWith(letterSpacing: 1.3),
                      ),
                      if (!_isLoading && _backups.isNotEmpty)
                        Text(
                          '${_backups.length} ${_backups.length == 1 ? 'backup' : 'backups'}',
                          style: c.text(10, muted: true),
                        ),
                    ],
                  ),
                ),

                if (_isLoading)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 50),
                    child: Center(
                      child: CircularProgressIndicator(
                        color: c.blue,
                        strokeWidth: 2,
                      ),
                    ),
                  )
                else if (_errorMessage != null)
                  _buildErrorState(c)
                else if (_backups.isEmpty)
                  _buildEmptyState(c)
                else
                  ..._backups.map((backup) => _buildBackupCard(backup, c)),

                const SizedBox(height: 16),
                _buildNote(
                  'Google Drive backups are protected by your passphrase. You will need it to restore your conversations.',
                  icon: Icons.lock_outline,
                  c: c,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBackupCard(drive.File backup, NotesColors c) {
    final localDate = backup.createdTime?.toLocal();
    final dateStr = localDate != null ? _formatDateTime(localDate) : 'Unknown date';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: c.soft,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 8, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: c.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: c.line),
                  ),
                  child: Icon(
                    Icons.cloud_done_outlined,
                    color: c.blue,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        backup.name ?? 'Google Drive Backup',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: c.text(13, bold: true),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(Icons.schedule, size: 12, color: c.muted),
                          const SizedBox(width: 4),
                          Text(dateStr, style: c.text(11, muted: true)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: c.surface,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: c.line),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.photo_library_outlined, size: 11, color: c.blue),
                            const SizedBox(width: 5),
                            Text(
                              'Includes media & conversations',
                              style: c.text(10, muted: true).copyWith(color: c.blue),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Options',
                  icon: Icon(Icons.more_vert, size: 18, color: c.muted),
                  onPressed: () => _showBackupOptions(backup),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: c.line),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                TextButton.icon(
                  onPressed: () => _confirmAndDelete(backup),
                  icon: const Icon(Icons.delete_outline, size: 15, color: Color(0xFFBF6974)),
                  label: Text(
                    'Delete',
                    style: c.text(11).copyWith(color: const Color(0xFFBF6974)),
                  ),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
                const Spacer(),
                FilledButton.icon(
                  onPressed: () => _startRestore(backup),
                  icon: const Icon(Icons.settings_backup_restore_rounded, size: 15, color: Colors.white),
                  label: const Text(
                    'Restore',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF507FC3),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(NotesColors c) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Column(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: c.soft,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(Icons.cloud_off_outlined, color: c.muted, size: 24),
          ),
          const SizedBox(height: 16),
          Text(
            'No backups found',
            style: c.text(14, bold: true),
          ),
          const SizedBox(height: 8),
          Text(
            'Backups saved to Google Drive will appear here.\nYou can create one by selecting "Google Drive" under Save to.',
            textAlign: TextAlign.center,
            style: c.text(11, muted: true).copyWith(height: 1.7),
          ),
          const SizedBox(height: 20),
          OutlinedButton.icon(
            onPressed: _loadBackups,
            icon: const Icon(Icons.refresh, size: 14),
            label: const Text('Refresh', style: TextStyle(fontSize: 12)),
            style: OutlinedButton.styleFrom(
              foregroundColor: c.blue,
              side: BorderSide(color: c.line),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState(NotesColors c) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Column(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: const Color(0xFFBF6974).withOpacity(0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.error_outline, color: Color(0xFFBF6974), size: 24),
          ),
          const SizedBox(height: 16),
          Text(
            _errorMessage ?? 'Something went wrong',
            style: c.text(13, bold: true),
          ),
          const SizedBox(height: 8),
          Text(
            'Check your connection and try again.',
            style: c.text(11, muted: true),
          ),
          const SizedBox(height: 18),
          OutlinedButton.icon(
            onPressed: _loadBackups,
            icon: const Icon(Icons.refresh, size: 14),
            label: const Text('Retry', style: TextStyle(fontSize: 12)),
            style: OutlinedButton.styleFrom(
              foregroundColor: c.blue,
              side: BorderSide(color: c.line),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNote(String text, {required IconData icon, required NotesColors c}) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 14, color: c.muted),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: c.text(10, muted: true).copyWith(height: 1.7),
            ),
          ),
        ],
      ),
    );
  }
}
