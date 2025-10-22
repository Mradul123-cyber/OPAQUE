import 'package:flutter/material.dart';
import 'tutorial_e2ee_screen.dart';
import 'tutorial_chat_screen.dart';
import 'tutorial_ai_screen.dart';
import 'tutorial_backup_screen.dart';
import 'tutorial_signal_screen.dart';

class TutorialScreen extends StatelessWidget {
  const TutorialScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'How Zarq Works',
          style: TextStyle(color: Colors.black),
        ),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20.0),
        children: [
          _buildTutorialCard(
            context: context,
            icon: Icons.lock_rounded,
            title: 'E2EE Functionality',
            color: Colors.cyanAccent,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const TutorialE2EEScreen()),
            ),
          ),
          const SizedBox(height: 16),
          _buildTutorialCard(
            context: context,
            icon: Icons.person_add_alt_1,
            title: 'Social Connections',
            color: Colors.greenAccent,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const TutorialChatScreen()),
            ),
          ),
          const SizedBox(height: 16),
          _buildTutorialCard(
            context: context,
            icon: Icons.psychology_rounded,
            title: 'AI Assistant',
            color: Colors.purpleAccent,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const TutorialAIScreen()),
            ),
          ),
          const SizedBox(height: 16),
          _buildTutorialCard(
            context: context,
            icon: Icons.backup_rounded,
            title: 'Backup/Restore',
            color: Colors.blueAccent,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const TutorialBackupScreen()),
            ),
          ),
          const SizedBox(height: 16),
          _buildTutorialCard(
            context: context,
            icon: Icons.verified_user_rounded,
            title: 'Signal Protocol (Techy)',
            color: Colors.orangeAccent,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const TutorialSignalScreen()),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTutorialCard({
    required BuildContext context,
    required IconData icon,
    required String title,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Dismissible(
      key: Key(title),
      direction: DismissDirection.horizontal,
      confirmDismiss: (direction) async {
        onTap();
        return false; // Don't actually dismiss
      },
      background: Container(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: 20),
        decoration: BoxDecoration(
          color: color.withOpacity(0.2),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Icon(
          Icons.arrow_forward,
          color: color,
          size: 30,
        ),
      ),
      secondaryBackground: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: color.withOpacity(0.2),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Icon(
          Icons.arrow_forward,
          color: color,
          size: 30,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.all(20.0),
            decoration: BoxDecoration(
              color: Colors.black,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: color.withOpacity(0.5),
                width: 2,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 28,
                  color: color,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
                Icon(
                  Icons.arrow_forward_ios,
                  color: Colors.white.withOpacity(0.6),
                  size: 18,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
