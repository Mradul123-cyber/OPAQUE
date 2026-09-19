import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/user_settings_provider.dart';
import '../widgets/backup_design.dart';
import '../widgets/notes_design.dart';
import '../widgets/call_aware_screen.dart';

/// Detailed help for the backup operations available in the app.
class BackupInfoScreen extends StatelessWidget {
  const BackupInfoScreen({super.key});
  @override
  Widget build(BuildContext context) {
    context.watch<UserSettingsProvider>();
    final c = NotesColors(context);
    Widget paragraph(String text) => Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(text, style: c.text(12, muted: true).copyWith(height: 1.8)),
    );
    Widget section(IconData icon, String title, List<Widget> children) =>
        Container(
          padding: const EdgeInsets.symmetric(vertical: 20),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: c.line)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, size: 18, color: c.blue),
                  const SizedBox(width: 10),
                  Expanded(child: Text(title, style: c.text(14, bold: true))),
                ],
              ),
              const SizedBox(height: 12),
              ...children,
            ],
          ),
        );
    Widget item(String title, String text) => Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: c.text(12, bold: true)),
          const SizedBox(height: 4),
          Text(text, style: c.text(12, muted: true).copyWith(height: 1.8)),
        ],
      ),
    );
    Widget faq(String question, String answer) => Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(bottom: 12),
        iconColor: c.blue,
        collapsedIconColor: c.muted,
        title: Text(question, style: c.text(12)),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              answer,
              style: c.text(12, muted: true).copyWith(height: 1.8),
            ),
          ),
        ],
      ),
    );
    return CallAwareScreen(
      screenName: 'BackupInfoScreen',
      child: Scaffold(
        backgroundColor: c.surface,
        appBar: const BackupHeader(),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(22, 22, 22, 28),
            children: [
              Text(
                'How backup works',
                style: c.text(22, bold: true).copyWith(letterSpacing: -.6),
              ),
              const SizedBox(height: 6),
              paragraph('A copy you can come back to.'),
              section(Icons.info_outline, 'About Opaque backups', [
                paragraph(
                  'Backups keep a passphrase-protected copy of your conversations, attachments and encryption state. Create one on your device or save a separate copy to Google Drive.',
                ),
              ]),
              section(Icons.inventory_2_outlined, 'What’s included', [
                item(
                  'Conversations and messages',
                  'Your saved messages and conversation information.',
                ),
                item(
                  'Media attachments',
                  'Google Drive backups let you choose all media, the last 7, 15 or 30 days, or no media. Local backups save messages and encryption keys only.',
                ),
                item(
                  'Encryption state',
                  'Signal Protocol keys and session data needed by the restored conversations.',
                ),
              ]),
              section(Icons.lock_outline, 'Security & privacy', [
                item(
                  'Passphrase protection',
                  'Backup data is encrypted using your passphrase. You need the same passphrase to restore it. Opaque cannot recover a forgotten passphrase.',
                ),
                item(
                  'Manual backups',
                  'Enter a passphrase each time you create or restore a manual backup. Confirm it when creating a backup to avoid a typing mistake.',
                ),
                item(
                  'Automatic backups',
                  'Your configured passphrase is stored using the app’s secure storage for scheduled backups. It cannot be changed from this screen. Keep a separate safe record of it.',
                ),
              ]),
              section(Icons.schedule, 'Manual & automatic backups', [
                item(
                  'Manual',
                  'Choose On this device or Google Drive under Save to, then tap Create backup. Google Drive requires a connected account and an internet connection.',
                ),
                item(
                  'Automatic',
                  'Enable automatic backups, choose daily, weekly or monthly, and set a backup passphrase. Automatic backups save locally and do not need internet.',
                ),
                item(
                  'Background access',
                  'Android controls when scheduled work runs. Battery restrictions can delay it. Use Background access to review the app’s battery settings.',
                ),
              ]),
              section(Icons.folder_outlined, 'Where to keep your backups', [
                item(
                  'On this device',
                  'Quick to create and restore without internet. A backup on the same device cannot protect you if that device is lost or damaged.',
                ),
                item(
                  'Google Drive',
                  'A separate copy that can survive device loss or reinstalling the app. Connect the correct Google account and keep enough storage available. Drive backups are created manually.',
                ),
                item(
                  'Keeping both copies',
                  'Create a local backup and a Google Drive backup separately if you want both. There is no combined destination in this screen.',
                ),
                paragraph(
                  'Files stored by the app can be removed or become inaccessible after uninstalling. Keep an accessible copy outside the app before uninstalling or changing devices.',
                ),
              ]),
              section(Icons.restore, 'Restore a backup', [
                item(
                  '1. Find your backup',
                  'Open the Restore tab. Select a local backup, browse Google Drive backups, or choose Import backup file to select a saved .encrypted file.',
                ),
                item(
                  '2. Enter its passphrase',
                  'Use the passphrase that protected this specific backup, then confirm the restore.',
                ),
                item(
                  '3. Let restoration finish',
                  'Keep the app open while it reads the backup and restores your conversations. Drive restores also download the media included in that backup. The app may restart afterwards.',
                ),
              ]),
              section(Icons.edit_outlined, 'Manage saved backups', [
                paragraph(
                  'Open a local backup’s options to rename, restore or delete it. Google Drive backups can be browsed, restored or deleted. Deleting a backup removes that saved copy; it does not delete your current conversations.',
                ),
              ]),
              section(Icons.tips_and_updates_outlined, 'Good backup habits', [
                paragraph(
                  'Use a strong, memorable passphrase and store it safely. Make a fresh backup before changing phones or uninstalling the app. Check the date of your latest backup and allow enough storage for media.',
                ),
                paragraph(
                  'Keep another copy away from your phone. Share neither your passphrase nor your backup with someone you do not trust.',
                ),
              ]),
              section(Icons.help_outline, 'Common questions', [
                faq(
                  'What if I forget the passphrase?',
                  'That backup cannot be decrypted without its passphrase. If you still have access to your conversations, create a new manual backup with a passphrase you can keep safely.',
                ),
                faq(
                  'Why are automatic backups local only?',
                  'The current automatic-backup feature saves on your device without needing a network or Google account. Create Google Drive copies manually.',
                ),
                faq(
                  'Can I import a backup after reinstalling?',
                  'If you still have an accessible backup file, choose Import backup file and select it. A file does not need to appear in the local backup list to be imported.',
                ),
                faq(
                  'Is media saved in local backups?',
                  'No. Local backups save conversation messages, contacts, and encryption state only. To back up media files, use Google Drive.',
                ),
                faq(
                  'Will my media come back?',
                  'Only media included in the selected backup can be restored. Google Drive restore downloads the media saved with that backup.',
                ),
                faq(
                  'Why can a backup be large?',
                  'Photos, videos, documents and audio contribute to backup size. For Google Drive, choose recent media or no media to reduce what is included.',
                ),
                faq(
                  'Can I change my Google account?',
                  'Tap the connected account on the Backup tab, then Change account. Sign out is also available. Existing Drive files stay in their original account.',
                ),
              ]),
              Padding(
                padding: const EdgeInsets.only(top: 20),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.lock_outline, color: c.blue, size: 16),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        'Keep your backup and its passphrase safe. Both are needed to bring your conversations back.',
                        style: c.text(11, muted: true).copyWith(height: 1.8),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
