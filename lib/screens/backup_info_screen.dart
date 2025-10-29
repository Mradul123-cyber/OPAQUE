import 'package:flutter/material.dart';
import '../widgets/call_aware_screen.dart';

/// Backup Information Screen - Explains how Zarq Messenger backup works
class BackupInfoScreen extends StatelessWidget {
  const BackupInfoScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    final appBarTitleSize = (screenWidth * 0.05).clamp(18.0, 24.0);
    final sectionTitleSize = (screenWidth * 0.055).clamp(20.0, 26.0);
    final cardTitleSize = (screenWidth * 0.045).clamp(16.0, 20.0);
    final bodyTextSize = (screenWidth * 0.0375).clamp(14.0, 17.0);
    final smallTextSize = (screenWidth * 0.0325).clamp(12.0, 15.0);
    final tinyTextSize = (screenWidth * 0.03).clamp(11.0, 14.0);
    final iconSize1 = (screenWidth * 0.07).clamp(24.0, 32.0);
    final iconSize2 = (screenWidth * 0.06).clamp(20.0, 28.0);
    final iconSize3 = (screenWidth * 0.055).clamp(18.0, 24.0);
    final iconSize4 = (screenWidth * 0.04).clamp(14.0, 18.0);
    final padding1 = (screenWidth * 0.04).clamp(12.0, 20.0);
    final padding2 = (screenWidth * 0.035).clamp(10.0, 16.0);
    final borderRadius1 = (screenWidth * 0.03).clamp(10.0, 14.0);
    final borderRadius2 = (screenWidth * 0.035).clamp(12.0, 16.0);
    final spacing1 = (screenHeight * 0.03).clamp(20.0, 28.0);
    final spacing2 = (screenHeight * 0.015).clamp(10.0, 16.0);
    final spacing3 = (screenHeight * 0.01).clamp(6.0, 10.0);
    final spacing4 = (screenHeight * 0.04).clamp(24.0, 36.0);

    return CallAwareScreen(
      screenName: 'BackupInfoScreen',
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: const Color(0xFF0a1128),
        elevation: 0,
        title: Text('How Backup Works', style: TextStyle(color: Colors.white, fontSize: appBarTitleSize)),
        iconTheme: const IconThemeData(color: Colors.cyanAccent),
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
          padding: EdgeInsets.all(padding1),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Introduction
              _buildSection(
                context: context,
                icon: Icons.info_outline,
                title: 'About Zarq Backups',
                content: 'Zarq Messenger provides secure, end-to-end encrypted backups of your messages, '
                    'media, and Signal Protocol encryption state. Your data is protected with a passphrase '
                    'that only you know.',
              ),

              SizedBox(height: spacing1),

              // What's Included
              _buildSection(
                context: context,
                icon: Icons.check_circle_outline,
                title: 'What\'s Backed Up',
                content: '',
                children: [
                  _buildListItem(context, '💬 All conversations and messages'),
                  _buildListItem(context, '📎 Media attachments (images, videos, documents, audio)'),
                  _buildListItem(context, '🔐 Signal Protocol encryption keys'),
                  _buildListItem(context, '👤 Conversation metadata and info'),
                ],
              ),

              SizedBox(height: spacing1),

              // Security
              _buildSection(
                context: context,
                icon: Icons.security,
                title: 'Security & Privacy',
                content: '',
                children: [
                  _buildInfoCard(
                    context: context,
                    title: 'End-to-End Encryption',
                    description: 'Your backup is encrypted with AES-256 encryption using your passphrase. '
                        'Without your passphrase, the backup cannot be decrypted.',
                    color: Colors.green,
                  ),
                  SizedBox(height: spacing2),
                  _buildInfoCard(
                    context: context,
                    title: 'Hardware-Backed Security',
                    description: 'Auto-backup passphrases are stored in Android Keystore (hardware-backed encryption). '
                        'Manual backup passphrases are never stored - you enter them each time.',
                    color: Colors.blue,
                  ),
                  SizedBox(height: spacing2),
                  _buildInfoCard(
                    context: context,
                    title: 'Zero-Knowledge Architecture',
                    description: 'We cannot recover your backup if you lose your passphrase. '
                        'This ensures complete privacy.',
                    color: Colors.orange,
                  ),
                ],
              ),

              SizedBox(height: spacing1),

              // Backup Types
              _buildSection(
                context: context,
                icon: Icons.backup,
                title: 'Backup Types',
                content: '',
                children: [
                  _buildFeatureCard(
                    context: context,
                    icon: Icons.touch_app,
                    title: 'Manual Backup',
                    description: 'Create a backup anytime by clicking "Create New Backup"',
                    features: [
                      '• Choose destination (Local/Google Drive/Both)',
                      '• Set custom passphrase each time',
                      '• Includes all messages and media',
                      '• Instant backup creation',
                    ],
                  ),
                  SizedBox(height: padding1),
                  _buildFeatureCard(
                    context: context,
                    icon: Icons.schedule,
                    title: 'Auto-Backup',
                    description: 'Automatic backups when you open the app',
                    features: [
                      '• Daily, weekly, or monthly frequency',
                      '• Runs automatically when you open the app',
                      '• Local storage only (no internet needed)',
                      '• Passphrase stored securely in Android Keystore',
                    ],
                  ),
                ],
              ),

              SizedBox(height: spacing1),

              // Storage Options
              _buildSection(
                context: context,
                icon: Icons.cloud_queue,
                title: 'Storage Options',
                content: '',
                children: [
                  _buildStorageOption(
                    context: context,
                    icon: Icons.phone_android,
                    title: 'Local Storage',
                    pros: ['Fast backup', 'No internet needed', 'Works offline', 'Quick restore'],
                    cons: ['Inaccessible after reinstall', 'Lost if phone is damaged', 'Not portable to new device'],
                  ),
                  SizedBox(height: spacing2),
                  _buildStorageOption(
                    context: context,
                    icon: Icons.cloud,
                    title: 'Google Drive (Recommended)',
                    pros: ['Persists after uninstall', 'Access from anywhere', 'Safe from device loss', 'Permanent storage'],
                    cons: ['Requires Google account', 'Internet connection needed', 'Manual backup only'],
                  ),
                  SizedBox(height: spacing2),
                  _buildStorageOption(
                    context: context,
                    icon: Icons.backup_table,
                    title: 'Both (Best Protection)',
                    pros: ['Double protection', 'Quick local restore', 'Permanent cloud backup', 'Maximum safety'],
                    cons: ['Uses more time for backup', 'Requires internet'],
                  ),
                ],
              ),

              SizedBox(height: spacing1),

              // Media Files Storage
              _buildSection(
                context: context,
                icon: Icons.perm_media,
                title: 'Media Files Storage',
                content: '',
                children: [
                  _buildInfoCard(
                    context: context,
                    title: 'App-Specific Storage',
                    description: 'Media files (images, videos, documents, audio) are stored in app-specific storage '
                        '(Android/media/com.zarq.messenger). After uninstall, the app loses access to these files. '
                        'They remain on device but are not accessible by the app. This is required by Google Play policies.',
                    color: Colors.orange,
                  ),
                  SizedBox(height: spacing2),
                  _buildInfoCard(
                    context: context,
                    title: 'Google Drive for Persistence',
                    description: 'To keep your media files after reinstalling the app, you MUST back up to Google Drive. '
                        'When you restore from Google Drive, all media files are re-downloaded automatically.',
                    color: Colors.blue,
                  ),
                  SizedBox(height: spacing2),
                  _buildInfoCard(
                    context: context,
                    title: 'Import Backup Files',
                    description: 'You can import backup files from anywhere on your device using the "Import Backup File" '
                        'button. This includes old local backups that remain on device after reinstall, or backups downloaded from Google Drive.',
                    color: Colors.green,
                  ),
                ],
              ),

              SizedBox(height: spacing1),

              // Best Practices
              _buildSection(
                context: context,
                icon: Icons.tips_and_updates,
                title: 'Best Practices',
                content: '',
                children: [
                  _buildTipCard(context, '🔑 Use a Strong Passphrase',
                      'Choose a memorable but complex passphrase. Mix letters, numbers, and symbols.'),
                  _buildTipCard(context, '☁️ Always Use Google Drive',
                      'Local backups become inaccessible after reinstall. Use Google Drive for permanent backup storage.'),
                  _buildTipCard(context, '📝 Save Your Passphrase',
                      'Write down your passphrase in a safe place. You cannot recover it if lost.'),
                  _buildTipCard(context, '💾 Regular Google Drive Backups',
                      'Manually backup to Google Drive weekly to ensure you can restore after reinstall.'),
                  _buildTipCard(context, '✅ Test Restore',
                      'Periodically test restoring from Google Drive backup to ensure it works.'),
                ],
              ),

              SizedBox(height: spacing1),

              // How to Restore
              _buildSection(
                context: context,
                icon: Icons.restore,
                title: 'How to Restore',
                content: '',
                children: [
                  _buildNumberedStep(context, 1, 'Navigate to Backup Management'),
                  _buildNumberedStep(context, 2, 'Option A: View Google Drive Backups → Select backup'),
                  _buildNumberedStep(context, 3, 'Option B: Import Backup File → Download from Drive → Select file'),
                  _buildNumberedStep(context, 4, 'Enter your backup passphrase'),
                  _buildNumberedStep(context, 5, 'Wait for restore to complete (app will restart)'),
                  _buildNumberedStep(context, 6, 'All messages and media will be restored automatically'),
                ],
              ),

              SizedBox(height: spacing1),

              // FAQ
              _buildSection(
                context: context,
                icon: Icons.help_outline,
                title: 'Frequently Asked Questions',
                content: '',
                children: [
                  _buildFAQ(
                    context,
                    'Can I use different passphrases for different backups?',
                    'Yes! Each manual backup can have a unique passphrase. Auto-backups use one passphrase stored securely in Android Keystore.',
                  ),
                  _buildFAQ(
                    context,
                    'What happens if I forget my passphrase?',
                    'Unfortunately, there is no way to recover a backup without the passphrase. This is by design to ensure your privacy.',
                  ),
                  _buildFAQ(
                    context,
                    'How much space do backups use?',
                    'Backup size depends on messages and media. Text messages are small (~KB), but media can be larger (~MB-GB). Use media age filters to reduce size.',
                  ),
                  _buildFAQ(
                    context,
                    'Are backups compressed?',
                    'No, backups are encrypted but not compressed. The encryption ensures security while maintaining data integrity.',
                  ),
                  _buildFAQ(
                    context,
                    'Can I share my backup file?',
                    'While you can share the encrypted file, it\'s useless without your passphrase. Never share your passphrase!',
                  ),
                  _buildFAQ(
                    context,
                    'Why is auto-backup local storage only?',
                    'Auto-backup saves to local storage for 100% reliability - no internet needed, no authentication issues, works offline. For cloud backups, use manual backup which offers both Local and Google Drive options.',
                  ),
                  _buildFAQ(
                    context,
                    'What happens to my media files after uninstall?',
                    'Media files (images, videos, documents) in app-specific storage become inaccessible after uninstall. The files remain on device but the app cannot access them anymore. This is required by Google Play policies. Always back up to Google Drive to preserve your media.',
                  ),
                  _buildFAQ(
                    context,
                    'Will my media be restored from Google Drive backup?',
                    'Yes! When you restore from a Google Drive backup, all messages AND media files are automatically re-downloaded and restored. This is why Google Drive backups are recommended.',
                  ),
                  _buildFAQ(
                    context,
                    'Can I access old local backups after reinstalling?',
                    'Yes! Use the "Import Backup File" feature. Local backup files remain on device but the app cannot detect them automatically after reinstall. Simply select the backup file using Import Backup File and restore. Alternatively, back up to Google Drive before uninstalling for easier access.',
                  ),
                  _buildFAQ(
                    context,
                    'How do I import a backup file?',
                    'Download your .encrypted backup file from Google Drive to your device. In Backup Management, tap "Import Backup File", select the downloaded file, and enter your passphrase. The app will restore everything.',
                  ),
                ],
              ),

              SizedBox(height: spacing1),

              // Warning Card
              _buildWarningCard(context),

              SizedBox(height: spacing4),
            ],
          ),
        ),
      ),
      )
    );
  }

  Widget _buildSection({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String content,
    List<Widget>? children,
  }) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final sectionTitleSize = (screenWidth * 0.055).clamp(20.0, 26.0);
    final bodyTextSize = (screenWidth * 0.0375).clamp(14.0, 17.0);
    final iconSize1 = (screenWidth * 0.07).clamp(24.0, 32.0);
    final spacing2 = (screenHeight * 0.015).clamp(10.0, 16.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: Colors.cyanAccent, size: iconSize1),
            SizedBox(width: spacing2),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: sectionTitleSize,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        if (content.isNotEmpty) ...[
          SizedBox(height: spacing2),
          Text(
            content,
            style: TextStyle(color: Colors.white70, fontSize: bodyTextSize, height: 1.5),
          ),
        ],
        if (children != null) ...[
          SizedBox(height: spacing2),
          ...children,
        ],
      ],
    );
  }

  Widget _buildListItem(BuildContext context, String text) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final bodyTextSize = (screenWidth * 0.0375).clamp(14.0, 17.0);
    final spacing3 = (screenHeight * 0.01).clamp(6.0, 10.0);

    return Padding(
      padding: EdgeInsets.symmetric(vertical: spacing3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: spacing3),
          Expanded(
            child: Text(
              text,
              style: TextStyle(color: Colors.white70, fontSize: bodyTextSize),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard({
    required BuildContext context,
    required String title,
    required String description,
    required Color color,
  }) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final cardTitleSize = (screenWidth * 0.045).clamp(16.0, 20.0);
    final smallTextSize = (screenWidth * 0.0325).clamp(12.0, 15.0);
    final iconSize2 = (screenWidth * 0.06).clamp(20.0, 28.0);
    final padding1 = (screenWidth * 0.04).clamp(12.0, 20.0);
    final borderRadius2 = (screenWidth * 0.035).clamp(12.0, 16.0);
    final spacing3 = (screenHeight * 0.01).clamp(6.0, 10.0);

    return Container(
      padding: EdgeInsets.all(padding1),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(borderRadius2),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.shield, color: color, size: iconSize2 * 0.85),
              SizedBox(width: spacing3),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: color,
                    fontSize: cardTitleSize,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: spacing3),
          Text(
            description,
            style: TextStyle(color: Colors.white70, fontSize: smallTextSize, height: 1.4),
          ),
        ],
      ),
    );
  }

  Widget _buildFeatureCard({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String description,
    required List<String> features,
  }) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final cardTitleSize = (screenWidth * 0.045).clamp(16.0, 20.0);
    final smallTextSize = (screenWidth * 0.0325).clamp(12.0, 15.0);
    final tinyTextSize = (screenWidth * 0.03).clamp(11.0, 14.0);
    final iconSize3 = (screenWidth * 0.055).clamp(18.0, 24.0);
    final padding1 = (screenWidth * 0.04).clamp(12.0, 20.0);
    final borderRadius2 = (screenWidth * 0.035).clamp(12.0, 16.0);
    final spacing2 = (screenHeight * 0.015).clamp(10.0, 16.0);
    final spacing3 = (screenHeight * 0.01).clamp(6.0, 10.0);

    return Container(
      padding: EdgeInsets.all(padding1),
      decoration: BoxDecoration(
        color: const Color(0xFF1B263B).withOpacity(0.5),
        borderRadius: BorderRadius.circular(borderRadius2),
        border: Border.all(color: Colors.cyanAccent.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: Colors.cyanAccent, size: iconSize3),
              SizedBox(width: spacing2),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: cardTitleSize,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: spacing3),
          Text(
            description,
            style: TextStyle(color: Colors.white70, fontSize: smallTextSize),
          ),
          SizedBox(height: spacing2),
          ...features.map((feature) => Padding(
            padding: EdgeInsets.only(bottom: spacing3 * 0.5),
            child: Text(
              feature,
              style: TextStyle(color: Colors.white60, fontSize: tinyTextSize),
            ),
          )),
        ],
      ),
    );
  }

  Widget _buildStorageOption({
    required BuildContext context,
    required IconData icon,
    required String title,
    required List<String> pros,
    required List<String> cons,
  }) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final cardTitleSize = (screenWidth * 0.045).clamp(16.0, 20.0);
    final smallTextSize = (screenWidth * 0.0325).clamp(12.0, 15.0);
    final tinyTextSize = (screenWidth * 0.03).clamp(11.0, 14.0);
    final iconSize3 = (screenWidth * 0.055).clamp(18.0, 24.0);
    final iconSize4 = (screenWidth * 0.04).clamp(14.0, 18.0);
    final padding1 = (screenWidth * 0.04).clamp(12.0, 20.0);
    final padding2 = (screenWidth * 0.035).clamp(10.0, 16.0);
    final borderRadius2 = (screenWidth * 0.035).clamp(12.0, 16.0);
    final spacing2 = (screenHeight * 0.015).clamp(10.0, 16.0);
    final spacing3 = (screenHeight * 0.01).clamp(6.0, 10.0);

    return Container(
      padding: EdgeInsets.all(padding1),
      decoration: BoxDecoration(
        color: const Color(0xFF1B263B).withOpacity(0.5),
        borderRadius: BorderRadius.circular(borderRadius2),
        border: Border.all(color: Colors.white24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: Colors.cyanAccent, size: iconSize3),
              SizedBox(width: padding2),
              Text(
                title,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: cardTitleSize,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          SizedBox(height: spacing2),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.check_circle, color: Colors.green, size: iconSize4),
                        SizedBox(width: spacing3),
                        Text('Pros', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: smallTextSize)),
                      ],
                    ),
                    SizedBox(height: spacing3),
                    ...pros.map((pro) => Padding(
                      padding: EdgeInsets.only(bottom: spacing3 * 0.4),
                      child: Text('• $pro', style: TextStyle(color: Colors.white60, fontSize: tinyTextSize)),
                    )),
                  ],
                ),
              ),
              SizedBox(width: padding1),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.cancel, color: Colors.red, size: iconSize4),
                        SizedBox(width: spacing3),
                        Text('Cons', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: smallTextSize)),
                      ],
                    ),
                    SizedBox(height: spacing3),
                    ...cons.map((con) => Padding(
                      padding: EdgeInsets.only(bottom: spacing3 * 0.4),
                      child: Text('• $con', style: TextStyle(color: Colors.white60, fontSize: tinyTextSize)),
                    )),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTipCard(BuildContext context, String title, String description) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final bodyTextSize = (screenWidth * 0.0375).clamp(14.0, 17.0);
    final smallTextSize = (screenWidth * 0.0325).clamp(12.0, 15.0);
    final padding2 = (screenWidth * 0.035).clamp(10.0, 16.0);
    final borderRadius1 = (screenWidth * 0.03).clamp(10.0, 14.0);
    final spacing2 = (screenHeight * 0.015).clamp(10.0, 16.0);
    final spacing3 = (screenHeight * 0.01).clamp(6.0, 10.0);

    return Container(
      margin: EdgeInsets.only(bottom: spacing2),
      padding: EdgeInsets.all(padding2),
      decoration: BoxDecoration(
        color: Colors.amber.withOpacity(0.1),
        borderRadius: BorderRadius.circular(borderRadius1),
        border: Border.all(color: Colors.amber.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: Colors.amber,
              fontSize: bodyTextSize,
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: spacing3),
          Text(
            description,
            style: TextStyle(color: Colors.white70, fontSize: smallTextSize, height: 1.3),
          ),
        ],
      ),
    );
  }

  Widget _buildNumberedStep(BuildContext context, int number, String text) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final bodyTextSize = (screenWidth * 0.0375).clamp(14.0, 17.0);
    final smallTextSize = (screenWidth * 0.0325).clamp(12.0, 15.0);
    final circleSize = (screenWidth * 0.07).clamp(24.0, 32.0);
    final spacing2 = (screenHeight * 0.015).clamp(10.0, 16.0);
    final spacing3 = (screenHeight * 0.01).clamp(6.0, 10.0);

    return Padding(
      padding: EdgeInsets.only(bottom: spacing2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: circleSize,
            height: circleSize,
            decoration: BoxDecoration(
              color: Colors.cyanAccent,
              borderRadius: BorderRadius.circular(circleSize / 2),
            ),
            child: Center(
              child: Text(
                '$number',
                style: TextStyle(
                  color: Colors.black,
                  fontWeight: FontWeight.bold,
                  fontSize: smallTextSize,
                ),
              ),
            ),
          ),
          SizedBox(width: spacing2),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(top: spacing3 * 0.5),
              child: Text(
                text,
                style: TextStyle(color: Colors.white70, fontSize: bodyTextSize),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFAQ(BuildContext context, String question, String answer) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final bodyTextSize = (screenWidth * 0.0375).clamp(14.0, 17.0);
    final smallTextSize = (screenWidth * 0.0325).clamp(12.0, 15.0);
    final spacing2 = (screenHeight * 0.015).clamp(10.0, 16.0);
    final spacing3 = (screenHeight * 0.01).clamp(6.0, 10.0);

    return Container(
      margin: EdgeInsets.only(bottom: spacing2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Q: ', style: TextStyle(color: Colors.cyanAccent, fontWeight: FontWeight.bold, fontSize: bodyTextSize)),
              Expanded(
                child: Text(
                  question,
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: bodyTextSize),
                ),
              ),
            ],
          ),
          SizedBox(height: spacing3),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('A: ', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: smallTextSize)),
              Expanded(
                child: Text(
                  answer,
                  style: TextStyle(color: Colors.white70, fontSize: smallTextSize, height: 1.4),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildWarningCard(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final cardTitleSize = (screenWidth * 0.045).clamp(16.0, 20.0);
    final smallTextSize = (screenWidth * 0.0325).clamp(12.0, 15.0);
    final iconSize1 = (screenWidth * 0.07).clamp(24.0, 32.0);
    final padding1 = (screenWidth * 0.04).clamp(12.0, 20.0);
    final borderRadius2 = (screenWidth * 0.035).clamp(12.0, 16.0);
    final spacing2 = (screenHeight * 0.015).clamp(10.0, 16.0);

    return Container(
      padding: EdgeInsets.all(padding1),
      decoration: BoxDecoration(
        color: Colors.red.withOpacity(0.1),
        borderRadius: BorderRadius.circular(borderRadius2),
        border: Border.all(color: Colors.red.withOpacity(0.4), width: 2),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.red, size: iconSize1),
              SizedBox(width: spacing2),
              Expanded(
                child: Text(
                  'Important Warning',
                  style: TextStyle(
                    color: Colors.red,
                    fontSize: cardTitleSize,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: spacing2),
          Text(
            '⚠️ NEVER share your backup passphrase with anyone!\n'
            '⚠️ We CANNOT recover your passphrase if you lose it!\n'
            '⚠️ Store your passphrase in a safe, secure location!\n'
            '⚠️ Test your backup before relying on it!',
            style: TextStyle(color: Colors.white70, fontSize: smallTextSize, height: 1.5),
          ),
        ],
      ),
      );
  }
}
