import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'task_camera_screen.dart';
import 'task_global_feed_screen.dart';
import 'task_friends_feed_screen.dart';

class TasksScreen extends StatefulWidget {
  const TasksScreen({super.key});

  @override
  State<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends State<TasksScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  Map<String, dynamic>? _todayTask;
  Map<String, dynamic>? _userStats;
  bool _isLoadingTask = true;
  bool _isLoadingStats = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _loadTodayTask();
    _loadUserStats();
    _checkAndShowE2EENotice();
  }

  Future<void> _checkAndShowE2EENotice() async {
    final prefs = await SharedPreferences.getInstance();
    final hasSeenNotice = prefs.getBool('has_seen_tasks_e2ee_notice') ?? false;

    if (!hasSeenNotice && mounted) {
      // Show dialog after a short delay to let the screen load
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) {
          _showE2EENoticeDialog();
        }
      });
    }
  }

  void _showE2EENoticeDialog() {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    bool isHindi = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return GestureDetector(
              onDoubleTap: () {
                setState(() {
                  isHindi = !isHindi;
                });
              },
              child: AlertDialog(
                backgroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(screenWidth * 0.05),
                ),
                contentPadding: EdgeInsets.all(screenWidth * 0.06),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Icon
                    Container(
                      width: screenWidth * 0.18,
                      height: screenWidth * 0.18,
                      decoration: BoxDecoration(
                        color: Colors.blue.withOpacity(0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.info_outline_rounded,
                        color: Colors.blue,
                        size: screenWidth * 0.1,
                      ),
                    ),
                    SizedBox(height: screenHeight * 0.025),
                    // Title
                    Text(
                      isHindi ? 'कार्य गोपनीयता के बारे में' : 'About Task Privacy',
                      style: TextStyle(
                        color: Colors.black87,
                        fontWeight: FontWeight.bold,
                        fontSize: screenWidth * 0.055,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    SizedBox(height: screenHeight * 0.015),
                    // Message
                    Text(
                      isHindi
                          ? 'टास्क सबमिशन एंड-टू-एंड एन्क्रिप्टेड नहीं हैं। यह हमारे AI को आपके टास्क पूरा होने की पुष्टि करने और सटीक रूप से पॉइंट्स देने में मदद करता है।'
                          : 'Task submissions are not end-to-end encrypted. This allows our AI to verify your task completions and award points accurately.',
                      style: TextStyle(
                        color: Colors.grey[700],
                        fontSize: screenWidth * 0.038,
                        height: 1.5,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    SizedBox(height: screenHeight * 0.01),
                    // Additional info
                    Container(
                      padding: EdgeInsets.all(screenWidth * 0.035),
                      decoration: BoxDecoration(
                        color: Colors.blue.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(screenWidth * 0.03),
                        border: Border.all(
                          color: Colors.blue.withOpacity(0.2),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.lock_outline,
                            color: Colors.blue,
                            size: screenWidth * 0.045,
                          ),
                          SizedBox(width: screenWidth * 0.025),
                          Expanded(
                            child: Text(
                              isHindi
                                  ? 'आपके निजी संदेश पूरी तरह से एंड-टू-एंड एन्क्रिप्टेड रहते हैं।'
                                  : 'Your private messages remain fully end-to-end encrypted.',
                              style: TextStyle(
                                color: Colors.blue[800],
                                fontSize: screenWidth * 0.032,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: screenHeight * 0.015),
                    // Language hint
                    Text(
                      isHindi ? 'Double tap to switch to English' : 'हिंदी में देखने के लिए डबल टैप करें',
                      style: TextStyle(
                        color: Colors.grey[500],
                        fontSize: screenWidth * 0.028,
                        fontStyle: FontStyle.italic,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
                actions: [
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () async {
                        // Mark as seen
                        final prefs = await SharedPreferences.getInstance();
                        await prefs.setBool('has_seen_tasks_e2ee_notice', true);
                        if (mounted) {
                          Navigator.of(context).pop();
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                        padding: EdgeInsets.symmetric(vertical: screenHeight * 0.018),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(screenWidth * 0.03),
                        ),
                        elevation: 0,
                      ),
                      child: Text(
                        isHindi ? 'समझ गया' : 'Got it',
                        style: TextStyle(
                          fontSize: screenWidth * 0.042,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadTodayTask() async {
    setState(() => _isLoadingTask = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final token = await user.getIdToken();
      final response = await http.get(
        Uri.parse('https://zarqmessenger.com/tasks/daily'),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          _todayTask = data; // Now contains {"tasks": [...]}
          _isLoadingTask = false;
        });
      } else {
        setState(() => _isLoadingTask = false);
      }
    } catch (e) {
      print('[TasksScreen] Error loading today\'s task: $e');
      setState(() => _isLoadingTask = false);
    }
  }

  Future<void> _loadUserStats() async {
    setState(() => _isLoadingStats = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final token = await user.getIdToken();
      final response = await http.get(
        Uri.parse('https://zarqmessenger.com/tasks/stats'),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode == 200) {
        setState(() {
          _userStats = json.decode(response.body);
          _isLoadingStats = false;
        });
      } else {
        setState(() => _isLoadingStats = false);
      }
    } catch (e) {
      print('[TasksScreen] Error loading user stats: $e');
      setState(() => _isLoadingStats = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text('Daily Tasks', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline, color: Colors.blue),
            onPressed: _showE2EENoticeDialog,
            tooltip: 'Privacy Information',
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.blue,
          labelColor: Colors.blue,
          unselectedLabelColor: Colors.grey,
          labelStyle: TextStyle(fontSize: (screenWidth * 0.035).clamp(12.0, 16.0), fontWeight: FontWeight.w600),
          tabs: const [
            Tab(text: 'Today'),
            Tab(text: 'Global'),
            Tab(text: 'Friends'),
            Tab(text: 'Profile'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildTodayTaskTab(),
          _buildGlobalFeedTab(),
          _buildFriendsFeedTab(),
          _buildProfileStatsTab(),
        ],
      ),
    );
  }

  Widget _buildTodayTaskTab() {
    if (_isLoadingTask) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.blue),
      );
    }

    final tasks = _todayTask?['tasks'] as List<dynamic>?;
    if (tasks == null || tasks.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.assignment_outlined, size: 80, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              'No tasks available today',
              style: TextStyle(color: Colors.grey[700], fontSize: 18),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _loadTodayTask,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      );
    }

    final screenWidth = MediaQuery.of(context).size.width;

    return SingleChildScrollView(
      padding: EdgeInsets.all(screenWidth * 0.04),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Stats Summary Card
          Container(
            padding: EdgeInsets.all(screenWidth * 0.04),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.blue.shade200),
              boxShadow: [
                BoxShadow(
                  color: Colors.blue.withOpacity(0.1),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: _isLoadingStats
                ? const Center(child: CircularProgressIndicator(color: Colors.blue))
                : Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildStatItem('Points', '${_userStats?['total_points'] ?? 0}', Icons.star),
                      _buildStatItem('Streak', '${_userStats?['current_streak'] ?? 0}', Icons.local_fire_department),
                      _buildStatItem('Tasks', '${_userStats?['tasks_completed'] ?? 0}', Icons.check_circle),
                    ],
                  ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Pick One Task to Complete',
            style: TextStyle(
              color: Colors.black87,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          // 3 Task Cards
          ...tasks.map((task) => _buildCompactTaskCard(task as Map<String, dynamic>)).toList(),
        ],
      ),
    );
  }

  Widget _buildCompactTaskCard(Map<String, dynamic> task) {
    final isCompleted = task['completed'] == true;
    final screenWidth = MediaQuery.of(context).size.width;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isCompleted ? Colors.green.shade50 : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isCompleted ? Colors.green : _getDifficultyColor(task['difficulty']).withOpacity(0.5),
          width: 2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ListTile(
        contentPadding: EdgeInsets.symmetric(horizontal: screenWidth * 0.04, vertical: 8),
        leading: Container(
          width: 50,
          height: 50,
          decoration: BoxDecoration(
            color: _getDifficultyColor(task['difficulty']).withOpacity(0.2),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            isCompleted ? Icons.check_circle : Icons.emoji_events,
            color: isCompleted ? Colors.green : _getDifficultyColor(task['difficulty']),
            size: 28,
          ),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                task['title_en'] ?? '',
                style: TextStyle(
                  color: Colors.black87,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  decoration: isCompleted ? TextDecoration.lineThrough : null,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        subtitle: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: _getDifficultyColor(task['difficulty']),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                task['difficulty'].toString().toUpperCase(),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.star, color: Colors.amber, size: 14),
            const SizedBox(width: 2),
            Text(
              '${task['points']} pts',
              style: const TextStyle(color: Colors.amber, fontSize: 12, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        trailing: isCompleted
            ? const Icon(Icons.check_circle, color: Colors.green, size: 32)
            : IconButton(
                icon: const Icon(Icons.camera_alt, color: Colors.blue),
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => TaskCameraScreen(task: task),
                    ),
                  ).then((_) {
                    _loadTodayTask();
                    _loadUserStats();
                  });
                },
              ),
      ),
    );
  }

  Widget _buildStatItem(String label, String value, IconData icon) {
    return Column(
      children: [
        Icon(icon, color: Colors.blue, size: 32),
        const SizedBox(height: 8),
        Text(
          value,
          style: const TextStyle(
            color: Colors.black87,
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            color: Colors.grey[600],
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  Color _getDifficultyColor(String? difficulty) {
    switch (difficulty?.toLowerCase()) {
      case 'easy':
        return Colors.green;
      case 'medium':
        return Colors.orange;
      case 'hard':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  Widget _buildGlobalFeedTab() {
    return const TaskGlobalFeedScreen();
  }

  Widget _buildFriendsFeedTab() {
    return const TaskFriendsFeedScreen();
  }

  Widget _buildProfileStatsTab() {
    if (_isLoadingStats) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.blue),
      );
    }

    if (_userStats == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.person_outline, size: 80, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              'Could not load stats',
              style: TextStyle(color: Colors.grey[700], fontSize: 18),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _loadUserStats,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      );
    }

    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        screenWidth * 0.04,
        screenWidth * 0.04,
        screenWidth * 0.04,
        screenWidth * 0.04 + bottomPadding + 16, // Extra bottom padding for nav buttons
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Your Progress',
            style: TextStyle(
              color: Colors.black87,
              fontSize: (screenWidth * 0.07).clamp(24.0, 28.0),
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: screenHeight * 0.02),
          _buildProgressCard('Total Points', '${_userStats!['total_points'] ?? 0}', Icons.star, Colors.amber),
          SizedBox(height: screenHeight * 0.015),
          _buildProgressCard('Current Streak', '${_userStats!['current_streak'] ?? 0} days', Icons.local_fire_department, Colors.orange),
          SizedBox(height: screenHeight * 0.015),
          _buildProgressCard('Longest Streak', '${_userStats!['longest_streak'] ?? 0} days', Icons.trending_up, Colors.green),
          SizedBox(height: screenHeight * 0.015),
          GestureDetector(
            onTap: () => _showTasksBreakdownModal(context),
            child: _buildProgressCard('Tasks Completed', '${_userStats!['tasks_completed'] ?? 0}', Icons.check_circle, Colors.blue, showChevron: true),
          ),
          SizedBox(height: screenHeight * 0.03),
          Text(
            'Badges',
            style: TextStyle(
              color: Colors.black87,
              fontSize: (screenWidth * 0.06).clamp(20.0, 24.0),
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: screenHeight * 0.015),
          if (_userStats!['badges'] != null && (_userStats!['badges'] as List).isNotEmpty)
            Wrap(
              spacing: screenWidth * 0.04,
              runSpacing: screenWidth * 0.04,
              children: (_userStats!['badges'] as List).map<Widget>((badge) {
                return _buildBadgeCard(badge);
              }).toList(),
            )
          else
            Container(
              padding: EdgeInsets.symmetric(
                horizontal: screenWidth * 0.05,
                vertical: screenWidth * 0.045,
              ),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.grey.shade300, width: 1.5),
                boxShadow: [
                  BoxShadow(
                    color: Colors.grey.withOpacity(0.1),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Center(
                child: Column(
                  children: [
                    Icon(
                      Icons.emoji_events_outlined,
                      color: Colors.grey[400],
                      size: (screenWidth * 0.12).clamp(40.0, 48.0),
                    ),
                    SizedBox(height: screenWidth * 0.025),
                    Text(
                      'No badges yet\nComplete tasks to earn badges!',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.grey[700],
                        fontSize: (screenWidth * 0.035).clamp(13.0, 15.0),
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          SizedBox(height: screenHeight * 0.02), // Extra bottom spacing
        ],
      ),
    );
  }

  Widget _buildProgressCard(String title, String value, IconData icon, Color color, {bool showChevron = false}) {
    final screenWidth = MediaQuery.of(context).size.width;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: screenWidth * 0.04,
        vertical: screenWidth * 0.03,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.3), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: EdgeInsets.all(screenWidth * 0.025),
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              icon,
              color: color,
              size: (screenWidth * 0.065).clamp(24.0, 28.0),
            ),
          ),
          SizedBox(width: screenWidth * 0.035),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: (screenWidth * 0.032).clamp(11.0, 13.0),
                    fontWeight: FontWeight.w500,
                  ),
                ),
                SizedBox(height: screenWidth * 0.008),
                Text(
                  value,
                  style: TextStyle(
                    color: Colors.black87,
                    fontSize: (screenWidth * 0.055).clamp(18.0, 22.0),
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          if (showChevron)
            Icon(
              Icons.info_outline,
              color: color.withOpacity(0.7),
              size: (screenWidth * 0.055).clamp(20.0, 22.0),
            ),
        ],
      ),
    );
  }

  Widget _buildBadgeCard(Map<String, dynamic> badge) {
    final screenWidth = MediaQuery.of(context).size.width;

    return Container(
      width: (screenWidth * 0.22).clamp(80.0, 95.0),
      padding: EdgeInsets.symmetric(
        horizontal: screenWidth * 0.02,
        vertical: screenWidth * 0.025,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.blue.shade200, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            badge['icon'] ?? '🏆',
            style: TextStyle(fontSize: (screenWidth * 0.08).clamp(28.0, 32.0)),
          ),
          SizedBox(height: screenWidth * 0.015),
          Text(
            badge['name'] ?? 'Badge',
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.black87,
              fontSize: (screenWidth * 0.028).clamp(10.0, 11.5),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  void _showTasksBreakdownModal(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    // Get breakdown data from stats
    final breakdown = _userStats?['tasks_by_difficulty'] as Map<String, dynamic>?;
    final easyCount = breakdown?['easy'] ?? 0;
    final mediumCount = breakdown?['medium'] ?? 0;
    final hardCount = breakdown?['hard'] ?? 0;
    final totalTasks = easyCount + mediumCount + hardCount;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (BuildContext context) {
        return Container(
          height: (screenHeight * 0.55).clamp(400.0, 500.0),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(24),
              topRight: Radius.circular(24),
            ),
          ),
          child: Column(
            children: [
              // Handle bar
              Container(
                margin: EdgeInsets.only(top: screenWidth * 0.03),
                width: screenWidth * 0.15,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              SizedBox(height: screenHeight * 0.02),
              // Title
              Padding(
                padding: EdgeInsets.symmetric(horizontal: screenWidth * 0.05),
                child: Text(
                  'Tasks Breakdown',
                  style: TextStyle(
                    color: Colors.black87,
                    fontSize: (screenWidth * 0.06).clamp(20.0, 24.0),
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              SizedBox(height: screenHeight * 0.008),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: screenWidth * 0.05),
                child: Text(
                  'Completed tasks by difficulty',
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: (screenWidth * 0.035).clamp(13.0, 15.0),
                  ),
                ),
              ),
              SizedBox(height: screenHeight * 0.025),
              // Breakdown cards
              Expanded(
                child: SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(
                    screenWidth * 0.05,
                    0,
                    screenWidth * 0.05,
                    bottomPadding + screenHeight * 0.02,
                  ),
                  child: Column(
                    children: [
                      _buildBreakdownCard('Easy', easyCount, totalTasks, Colors.green, Icons.sentiment_satisfied_alt, screenWidth, screenHeight),
                      SizedBox(height: screenHeight * 0.015),
                      _buildBreakdownCard('Medium', mediumCount, totalTasks, Colors.orange, Icons.bolt, screenWidth, screenHeight),
                      SizedBox(height: screenHeight * 0.015),
                      _buildBreakdownCard('Hard', hardCount, totalTasks, Colors.red, Icons.whatshot, screenWidth, screenHeight),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildBreakdownCard(String difficulty, int count, int total, Color color, IconData icon, double screenWidth, double screenHeight) {
    final percentage = total > 0 ? (count / total * 100).toStringAsFixed(0) : '0';

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: screenWidth * 0.04,
        vertical: screenWidth * 0.035,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.3), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: EdgeInsets.all(screenWidth * 0.025),
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              icon,
              color: color,
              size: (screenWidth * 0.065).clamp(24.0, 28.0),
            ),
          ),
          SizedBox(width: screenWidth * 0.035),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  difficulty,
                  style: TextStyle(
                    color: Colors.black87,
                    fontSize: (screenWidth * 0.045).clamp(16.0, 18.0),
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: screenWidth * 0.008),
                Text(
                  '$count tasks completed',
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: (screenWidth * 0.032).clamp(11.0, 13.0),
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '$count',
                style: TextStyle(
                  color: color,
                  fontSize: (screenWidth * 0.065).clamp(22.0, 26.0),
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                '$percentage%',
                style: TextStyle(
                  color: Colors.grey[600],
                  fontSize: (screenWidth * 0.03).clamp(11.0, 12.0),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
