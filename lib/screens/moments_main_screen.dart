import 'package:flutter/material.dart';
import 'package:zarq_messenger/screens/moments_camera_screen.dart';
import 'package:zarq_messenger/screens/moments_friends_feed_screen.dart';
import 'package:zarq_messenger/screens/moments_global_feed_screen.dart';
import 'package:provider/provider.dart';
import 'package:zarq_messenger/providers/home_provider.dart';

class MomentsMainScreen extends StatefulWidget {
  const MomentsMainScreen({Key? key}) : super(key: key);

  @override
  State<MomentsMainScreen> createState() => _MomentsMainScreenState();
}

class _MomentsMainScreenState extends State<MomentsMainScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('Moments', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.purple,
          labelColor: Colors.black,
          unselectedLabelColor: Colors.grey,
          tabs: [
            Tab(
              icon: Icon(Icons.add_a_photo),
              text: 'Create',
            ),
            Tab(
              icon: Icon(Icons.people),
              text: 'Friends',
            ),
            Tab(
              icon: Icon(Icons.public),
              text: 'Global',
            ),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildCreateTab(),
          MomentsFriendsFeedScreen(),
          MomentsGlobalFeedScreen(),
        ],
      ),
    );
  }

  Widget _buildCreateTab() {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    // Responsive sizing
    final iconSize = (screenWidth * 0.2).clamp(60.0, 100.0);
    final titleFontSize = (screenWidth * 0.06).clamp(20.0, 28.0);
    final subtitleFontSize = (screenWidth * 0.035).clamp(12.0, 16.0);
    final buttonFontSize = (screenWidth * 0.04).clamp(14.0, 18.0);
    final chipFontSize = (screenWidth * 0.03).clamp(10.0, 14.0);
    final chipIconSize = (screenWidth * 0.04).clamp(14.0, 18.0);

    final verticalSpacing = (screenHeight * 0.03).clamp(16.0, 32.0);
    final smallSpacing = (screenHeight * 0.015).clamp(10.0, 16.0);
    final buttonPaddingH = (screenWidth * 0.08).clamp(24.0, 40.0);
    final buttonPaddingV = (screenHeight * 0.015).clamp(12.0, 20.0);
    final chipPaddingH = (screenWidth * 0.03).clamp(10.0, 16.0);
    final chipPaddingV = (screenHeight * 0.008).clamp(5.0, 8.0);

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.camera_alt, color: Colors.grey[400], size: iconSize),
          SizedBox(height: verticalSpacing),
          Text(
            'Share a Moment',
            style: TextStyle(
              color: Colors.black,
              fontSize: titleFontSize,
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: smallSpacing),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: screenWidth * 0.1),
            child: Text(
              'Photos and videos disappear after 24 hours',
              style: TextStyle(color: Colors.grey[600], fontSize: subtitleFontSize),
              textAlign: TextAlign.center,
            ),
          ),
          SizedBox(height: verticalSpacing * 1.5),
          ElevatedButton.icon(
            onPressed: () async {
              // Get friends list
              final homeProvider = Provider.of<HomeProvider>(context, listen: false);
              final friendsList = homeProvider.conversations
                  .where((c) => !c.isGroup && c.partnerUid != null)
                  .map((c) => c.partnerUid!)
                  .toList();

              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => MomentsCameraScreen(friendsList: friendsList),
                ),
              );
            },
            icon: Icon(Icons.camera, size: buttonFontSize),
            label: Text('Open Camera'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.purple,
              padding: EdgeInsets.symmetric(horizontal: buttonPaddingH, vertical: buttonPaddingV),
              textStyle: TextStyle(fontSize: buttonFontSize, fontWeight: FontWeight.bold),
            ),
          ),
          SizedBox(height: smallSpacing),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildInfoChip(Icons.lock, 'Friends Only', Colors.blue, chipIconSize, chipFontSize, chipPaddingH, chipPaddingV),
              SizedBox(width: smallSpacing),
              _buildInfoChip(Icons.public, 'Or Global', Colors.purple, chipIconSize, chipFontSize, chipPaddingH, chipPaddingV),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInfoChip(IconData icon, String label, Color color, double iconSize, double fontSize, double paddingH, double paddingV) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: paddingH, vertical: paddingV),
      decoration: BoxDecoration(
        color: color.withOpacity(0.2),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: iconSize),
          SizedBox(width: paddingV),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: fontSize,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
