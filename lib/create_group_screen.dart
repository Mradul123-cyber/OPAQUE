// lib/create_group_screen.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:zarq_messenger/home_screen.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'dart:math' as math;
import 'package:provider/provider.dart';
import 'services/user_settings_provider.dart';

import 'chat_screen.dart';
import 'widgets/call_aware_screen.dart';

// This Friend model should be consistent with the one in your other files.
class Friend {
  final String username;
  final String? avatarUrl;
  final String? displayName;

  Friend({required this.username, this.avatarUrl, this.displayName});

  factory Friend.fromJson(Map<String, dynamic> json) {
    return Friend(
      username: json['username'] ?? 'Unknown User',
      avatarUrl: json['avatarUrl'],
      displayName: json['displayName'],
    );
  }

  String get displayNameOrUsername => displayName ?? username;
}

// The Leaf animation classes and painter can remain as they were,
// as they are purely for visual effect.
class Leaf {
  final math.Random random;
  final double size;
  final double speed;
  double x;
  double y;
  final double rotationDirection;
  final Color color;

  Leaf(this.random, double screenWidth, double screenHeight)
    : size = 20.0 + random.nextDouble() * 15,
      speed = 1.0 + random.nextDouble() * 2,
      x = random.nextDouble() * screenWidth,
      y = random.nextDouble() * screenHeight,
      rotationDirection = random.nextBool() ? 1.0 : -1.0,
      color = Colors.lightGreenAccent.withOpacity(
        0.5 + random.nextDouble() * 0.5,
      );

  void updatePosition(double screenWidth, double screenHeight) {
    y += speed;
    x += math.sin(y / 50) * speed * rotationDirection * 0.1;
    if (y > screenHeight) {
      y = -size;
      x = random.nextDouble() * screenWidth;
    }
  }
}

class LeafPainter extends CustomPainter {
  final List<Leaf> leaves;

  LeafPainter(this.leaves);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();
    for (final leaf in leaves) {
      paint.color = leaf.color;

      final iconPainter = TextPainter(
        text: TextSpan(
          text: '🌿',
          style: TextStyle(fontSize: leaf.size, color: leaf.color),
        ),
        textDirection: TextDirection.ltr,
      );
      iconPainter.layout();

      canvas.save();
      canvas.translate(leaf.x, leaf.y);
      canvas.rotate(leaf.y / 50 * leaf.rotationDirection);
      iconPainter.paint(canvas, Offset.zero);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class CreateGroupScreen extends StatefulWidget {
  final WebSocketChannel channel;
  final VoidCallback onGroupCreated;

  const CreateGroupScreen({
    super.key,
    required this.channel,
    required this.onGroupCreated,
  });

  @override
  State<CreateGroupScreen> createState() => _CreateGroupScreenState();
}

class _CreateGroupScreenState extends State<CreateGroupScreen>
    with TickerProviderStateMixin {
  final _groupNameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _searchController = TextEditingController();
  List<Friend> _friendsList = [];
  final Set<String> _selectedFriends = {};
  bool _isLoading = true;
  bool _isCreatingGroup = false;
  String _searchQuery = '';

  final List<Leaf> _leaves = [];
  late final AnimationController _animationController;
  late final Animation<Color?> _colorAnimation;

  @override
  void initState() {
    super.initState();
    _fetchFriendsList();
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text;
      });
    });

    // --- Start of Bug Fix ---
    // This listener is crucial. It tells the UI to rebuild every time
    // the text in the group name field changes, which allows the
    // "Create" button to correctly enable or disable itself.
    _groupNameController.addListener(() {
      setState(() {});
    });
    // --- End of Bug Fix ---

    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 15),
    )..repeat();

    _colorAnimation =
        ColorTween(
          begin: const Color(0xFF0F380F),
          end: const Color(0xFF2E8B57),
        ).animate(
          CurvedAnimation(
            parent: _animationController,
            curve: Curves.easeInOut,
          ),
        );

    final random = math.Random();
    _animationController.addListener(() {
      if (mounted) {
        setState(() {
          for (final leaf in _leaves) {
            leaf.updatePosition(
              MediaQuery.of(context).size.width,
              MediaQuery.of(context).size.height,
            );
          }
        });
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        final screenWidth = MediaQuery.of(context).size.width;
        final screenHeight = MediaQuery.of(context).size.height;
        for (int i = 0; i < 30; i++) {
          _leaves.add(Leaf(random, screenWidth, screenHeight));
        }
      }
    });
  }

  @override
  void dispose() {
    _groupNameController.dispose();
    _descriptionController.dispose();
    _searchController.dispose();
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _fetchFriendsList() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() {
        _isLoading = false;
      });
      return;
    }
    final token = await user.getIdToken();

    try {
      final url = Uri.parse('http://192.168.29.81:8080/friends/list');
      final response = await http.get(
        url,
        headers: {'Authorization': 'Bearer $token'},
      );
      if (response.statusCode == 200 && mounted) {
        final List<dynamic> friendsFromServer = json.decode(response.body);
        setState(() {
          _friendsList = friendsFromServer
              .map((fJson) => Friend.fromJson(fJson as Map<String, dynamic>))
              .toList();
          _isLoading = false;
        });
      } else {
        if (mounted)
          setState(() {
            _isLoading = false;
          });
      }
    } catch (e) {
      if (mounted)
        setState(() {
          _isLoading = false;
        });
    }
  }

  void _showDescriptionDialog() {
    final tempDescriptionController = TextEditingController();
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    final dialogTitleSize = (screenWidth * 0.045).clamp(16.0, 20.0);
    final dialogTextSize = (screenWidth * 0.035).clamp(12.0, 16.0);
    final spacing1 = (screenHeight * 0.02).clamp(14.0, 20.0);

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: Colors.grey[850],
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16.0),
          ),
          title: Text(
            'Add Group Description',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: dialogTitleSize,
              color: Colors.white,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Would you like to add a description for this group? (Optional)',
                style: TextStyle(
                  fontSize: dialogTextSize,
                  color: Colors.white70,
                ),
              ),
              SizedBox(height: spacing1),
              TextField(
                controller: tempDescriptionController,
                maxLines: 3,
                style: TextStyle(fontSize: dialogTextSize),
                decoration: InputDecoration(
                  hintText: 'e.g., For discussing project updates',
                  hintStyle: TextStyle(fontSize: dialogTextSize),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Colors.blue, width: 2),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                _createGroupWithDescription(''); // Skip description
              },
              child: Text('Skip', style: TextStyle(fontSize: dialogTextSize)),
            ),
            ElevatedButton(
              onPressed: () {
                final description = tempDescriptionController.text.trim();
                Navigator.pop(context);
                _createGroupWithDescription(description);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
              ),
              child: Text('Add & Create', style: TextStyle(fontSize: dialogTextSize)),
            ),
          ],
        );
      },
    );
  }

  void _showCreatingGroupDialog() {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final dialogTextSize = (screenWidth * 0.04).clamp(14.0, 18.0);
    final spacing1 = (screenHeight * 0.025).clamp(18.0, 24.0);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: Colors.grey[850],
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15.0),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(
                  Colors.lightGreenAccent,
                ),
              ),
              SizedBox(height: spacing1),
              Text(
                "Creating group...",
                style: TextStyle(color: Colors.white, fontSize: dialogTextSize),
              ),
            ],
          ),
        );
      },
    );
  }

  void _createGroup() {
    if (_isCreatingGroup) return;

    if (_groupNameController.text.trim().isEmpty || _selectedFriends.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Please enter a group name and select at least one friend.',
          ),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Show description dialog first
    _showDescriptionDialog();
  }

  Future<void> _createGroupWithDescription(String description) async {
    setState(() => _isCreatingGroup = true);
    _showCreatingGroupDialog();

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (mounted) {
        Navigator.of(context).pop();
        setState(() {
          _isCreatingGroup = false;
        });
      }
      return;
    }
    final token = await user.getIdToken();

    try {
      final url = Uri.parse('http://192.168.29.81:8080/conversations/create-group');
      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: json.encode({
          'groupName': _groupNameController.text.trim(),
          'description': description,
          'memberUsernames': _selectedFriends.toList(),
        }),
      );

      if (!mounted) return;
      Navigator.of(context).pop();

      if (response.statusCode == 201) {
        final data = json.decode(response.body);

        // This is now an integer, matching our unified backend.
        final int conversationId = data['conversationId'];
        final String groupName = data['groupName'];
        final String creatorUid = data['creatorUid'];

        widget.onGroupCreated();

        final newConversationInfo = ConversationInfo(
          conversationId: conversationId,
          chatTitle: groupName,
          isGroup: true, // This is a group chat
          creatorUid: creatorUid,
          partnerUid: null, // No partner in a group chat
        );

        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (context) => ChatScreen(
              channel: widget.channel,
              conversationInfo: newConversationInfo, // Pass the object here
            ),
          ),
        );
      } else if (response.statusCode == 409) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('A group with this name already exists.'),
            backgroundColor: Colors.orange,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to create group: ${response.body}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error creating group: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isCreatingGroup = false;
        });
      }
    }
  }

  Widget _buildAvatar(Friend friend) {
    final screenWidth = MediaQuery.of(context).size.width;
    final avatarRadius = (screenWidth * 0.06).clamp(20.0, 28.0);
    final avatarFontSize = (screenWidth * 0.06).clamp(20.0, 28.0);
    final progressSize = (screenWidth * 0.05).clamp(18.0, 24.0);

    final hasImage = friend.avatarUrl != null && friend.avatarUrl!.isNotEmpty;
    final displayText = friend.displayNameOrUsername;
    final initial = displayText.isNotEmpty
        ? displayText[0].toUpperCase()
        : '?';
    final color = Color(displayText.hashCode | 0xFF000000).withOpacity(1.0);

    if (hasImage) {
      return CachedNetworkImage(
        imageUrl: friend.avatarUrl!,
        imageBuilder: (context, imageProvider) => CircleAvatar(
          radius: avatarRadius,
          backgroundImage: imageProvider,
          backgroundColor: Colors.transparent,
        ),
        placeholder: (context, url) => CircleAvatar(
          radius: avatarRadius,
          backgroundColor: color,
          child: SizedBox(
            width: progressSize,
            height: progressSize,
            child: const CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
            ),
          ),
        ),
        errorWidget: (context, url, error) => CircleAvatar(
          radius: avatarRadius,
          backgroundColor: color,
          child: Text(
            initial,
            style: TextStyle(
              color: Colors.white,
              fontSize: avatarFontSize,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      );
    }

    return CircleAvatar(
      radius: avatarRadius,
      backgroundColor: color,
      child: Text(
        initial,
        style: TextStyle(
          color: Colors.white,
          fontSize: avatarFontSize,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filteredFriends = _friendsList.where((friend) {
      final queryLower = _searchQuery.toLowerCase();
      return friend.displayNameOrUsername.toLowerCase().contains(queryLower) ||
             friend.username.toLowerCase().contains(queryLower);
    }).toList();

    return Consumer<UserSettingsProvider>(
      builder: (context, userSettings, child) {
        final groupScreenStyle = userSettings.groupScreenStyle;

        if (groupScreenStyle == 'static') {
          return _buildStaticVersion(filteredFriends);
        } else {
          return _buildDynamicVersion(filteredFriends);
        }
      },
    );
  }

  Widget _buildDynamicVersion(List<Friend> filteredFriends) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    // Responsive sizing
    final appBarTitleSize = (screenWidth * 0.05).clamp(18.0, 24.0);
    final textFieldPadding = EdgeInsets.symmetric(
      horizontal: screenWidth * 0.04,
      vertical: screenHeight * 0.01,
    );
    final textFieldFontSize = (screenWidth * 0.04).clamp(14.0, 18.0);
    final iconSize = (screenWidth * 0.06).clamp(20.0, 26.0);
    final labelFontSize = (screenWidth * 0.04).clamp(14.0, 18.0);
    final listItemMargin = EdgeInsets.symmetric(
      horizontal: screenWidth * 0.04,
      vertical: screenHeight * 0.008,
    );
    final listItemPadding = EdgeInsets.all(screenWidth * 0.03);
    final nameFontSize = (screenWidth * 0.04).clamp(14.0, 18.0);
    final usernameFontSize = (screenWidth * 0.0325).clamp(12.0, 15.0);
    final checkIconSize = (screenWidth * 0.04).clamp(14.0, 18.0);
    final spacing1 = (screenWidth * 0.04).clamp(12.0, 18.0);
    final treeImageHeight = (screenHeight * 0.18).clamp(120.0, 180.0);

    return CallAwareScreen(
      screenName: 'CreateGroupScreen',
      child: Scaffold(
        backgroundColor: Colors.transparent,
        extendBodyBehindAppBar: true,
        appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Create New Group',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: appBarTitleSize,
              ),
            ),
            Text(
              '${_selectedFriends.length + 1}/100 members',
              style: TextStyle(
                color: Colors.white70,
                fontSize: appBarTitleSize * 0.6,
              ),
            ),
          ],
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          Padding(
            padding: EdgeInsets.only(right: screenWidth * 0.02),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: (_groupNameController.text.trim().isNotEmpty &&
                        _selectedFriends.isNotEmpty &&
                        !_isCreatingGroup)
                    ? Colors.lightGreenAccent
                    : Colors.transparent,
                boxShadow: (_groupNameController.text.trim().isNotEmpty &&
                           _selectedFriends.isNotEmpty &&
                           !_isCreatingGroup)
                    ? [
                        BoxShadow(
                          color: Colors.lightGreenAccent.withOpacity(0.5),
                          blurRadius: 8,
                          spreadRadius: 2,
                        ),
                      ]
                    : null,
              ),
              child: IconButton(
                icon: Icon(
                  Icons.check,
                  color: (_groupNameController.text.trim().isNotEmpty &&
                          _selectedFriends.isNotEmpty &&
                          !_isCreatingGroup)
                      ? Colors.green[900]
                      : Colors.white,
                ),
                tooltip: 'Create Group',
                onPressed: (_isCreatingGroup ||
                            _groupNameController.text.trim().isEmpty ||
                            _selectedFriends.isEmpty)
                    ? null
                    : _createGroup,
              ),
            ),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.white))
          : Stack(
              children: [
                AnimatedBuilder(
                  animation: _colorAnimation,
                  builder: (BuildContext context, Widget? child) {
                    return Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            _colorAnimation.value!,
                            const Color(0xFF0F380F),
                          ],
                        ),
                      ),
                    );
                  },
                ),

                AnimatedBuilder(
                  animation: _animationController,
                  builder: (context, child) {
                    return CustomPaint(
                      painter: LeafPainter(_leaves),
                      child: Container(),
                    );
                  },
                ),

                Positioned.fill(
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: Image.network(
                      'https://placehold.co/1000x200/0F380F/0F380F?text=Trees',
                      fit: BoxFit.cover,
                      height: treeImageHeight,
                      width: double.infinity,
                      errorBuilder: (context, error, stackTrace) => Container(),
                    ),
                  ),
                ),

                SafeArea(
                  child: Column(
                    children: [
                      Padding(
                        padding: textFieldPadding,
                        child: TextField(
                          controller: _groupNameController,
                          style: TextStyle(color: Colors.white, fontSize: textFieldFontSize),
                          decoration: InputDecoration(
                            labelText: 'Group Name',
                            labelStyle: TextStyle(
                              color: Colors.white.withOpacity(0.7),
                              fontSize: labelFontSize,
                            ),
                            hintText: 'e.g., The Avengers',
                            hintStyle: TextStyle(
                              color: Colors.white.withOpacity(0.5),
                              fontSize: textFieldFontSize,
                            ),
                            filled: true,
                            fillColor: const Color(0xFF2E8B57).withOpacity(0.2),
                            prefixIcon: Icon(
                              Icons.title,
                              color: Colors.white54,
                              size: iconSize,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(30.0),
                              borderSide: BorderSide.none,
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(30.0),
                              borderSide: const BorderSide(
                                color: Colors.white24,
                                width: 1.0,
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(30.0),
                              borderSide: const BorderSide(
                                color: Colors.lightGreenAccent,
                                width: 2.0,
                              ),
                            ),
                          ),
                        ),
                      ),
                      Padding(
                        padding: textFieldPadding,
                        child: TextField(
                          controller: _searchController,
                          style: TextStyle(color: Colors.white, fontSize: textFieldFontSize),
                          decoration: InputDecoration(
                            labelText: 'Search friends',
                            labelStyle: TextStyle(
                              color: Colors.white.withOpacity(0.7),
                              fontSize: labelFontSize,
                            ),
                            hintText: 'Enter a username...',
                            hintStyle: TextStyle(
                              color: Colors.white.withOpacity(0.5),
                              fontSize: textFieldFontSize,
                            ),
                            prefixIcon: Icon(
                              Icons.search,
                              color: Colors.white54,
                              size: iconSize,
                            ),
                            suffixIcon: _searchController.text.isNotEmpty
                                ? IconButton(
                                    icon: Icon(
                                      Icons.clear,
                                      color: Colors.white54,
                                      size: iconSize,
                                    ),
                                    onPressed: () {
                                      _searchController.clear();
                                    },
                                  )
                                : null,
                            filled: true,
                            fillColor: const Color(0xFF2E8B57).withOpacity(0.2),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(30.0),
                              borderSide: BorderSide.none,
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(30.0),
                              borderSide: const BorderSide(
                                color: Colors.white24,
                                width: 1.0,
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(30.0),
                              borderSide: const BorderSide(
                                color: Colors.lightGreenAccent,
                                width: 2.0,
                              ),
                            ),
                          ),
                        ),
                      ),
                      Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: screenWidth * 0.04,
                          vertical: screenHeight * 0.015,
                        ),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'Select Members:',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: labelFontSize,
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        child: filteredFriends.isEmpty
                            ? Center(
                                child: Text(
                                  _searchQuery.isNotEmpty
                                      ? "No friends found matching your search."
                                      : "You don't have any friends to add.",
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(0.7),
                                    fontSize: textFieldFontSize,
                                  ),
                                ),
                              )
                            : ListView.builder(
                                itemCount: filteredFriends.length,
                                itemBuilder: (context, index) {
                                  final friend = filteredFriends[index];
                                  final isSelected = _selectedFriends.contains(
                                    friend.username,
                                  );

                                  return GestureDetector(
                                    onTap: () {
                                      setState(() {
                                        if (isSelected) {
                                          _selectedFriends.remove(
                                            friend.username,
                                          );
                                        } else {
                                          _selectedFriends.add(friend.username);
                                        }
                                      });
                                    },
                                    child: AnimatedContainer(
                                      duration: const Duration(
                                        milliseconds: 200,
                                      ),
                                      margin: listItemMargin,
                                      decoration: BoxDecoration(
                                        color: isSelected
                                            ? const Color(
                                                0xFF2E8B57,
                                              ).withOpacity(0.2)
                                            : Colors.transparent,
                                        borderRadius: BorderRadius.circular(
                                          12.0,
                                        ),
                                        border: Border.all(
                                          color: isSelected
                                              ? Colors.lightGreenAccent
                                              : Colors.white12,
                                          width: 2.0,
                                        ),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black.withOpacity(
                                              0.3,
                                            ),
                                            blurRadius: 5,
                                            spreadRadius: 1,
                                          ),
                                        ],
                                      ),
                                      child: Padding(
                                        padding: listItemPadding,
                                        child: Row(
                                          children: [
                                            Stack(
                                              alignment: Alignment.bottomRight,
                                              children: [
                                                _buildAvatar(friend),
                                                if (isSelected)
                                                  Container(
                                                    decoration: BoxDecoration(
                                                      color: Colors
                                                          .lightGreenAccent,
                                                      shape: BoxShape.circle,
                                                      border: Border.all(
                                                        color:
                                                            Colors.green[800]!,
                                                        width: 2,
                                                      ),
                                                    ),
                                                    child: Icon(
                                                      Icons.check,
                                                      color: Colors.black,
                                                      size: checkIconSize,
                                                    ),
                                                  ),
                                              ],
                                            ),
                                            SizedBox(width: spacing1),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    friend.displayName ?? friend.username,
                                                    style: TextStyle(
                                                      color: Colors.white,
                                                      fontSize: nameFontSize,
                                                      fontWeight: FontWeight.w600,
                                                    ),
                                                  ),
                                                  if (friend.displayName != null)
                                                    Text(
                                                      '@${friend.username}',
                                                      style: TextStyle(
                                                        color: Colors.white.withOpacity(0.7),
                                                        fontSize: usernameFontSize,
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
                                },
                              ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
      ),
    );
  }

  Widget _buildStaticVersion(List<Friend> filteredFriends) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    // Responsive sizing
    final appBarTitleSize = (screenWidth * 0.05).clamp(18.0, 24.0);
    final textFieldFontSize = (screenWidth * 0.04).clamp(14.0, 18.0);
    final iconSize = (screenWidth * 0.06).clamp(20.0, 26.0);
    final labelFontSize = (screenWidth * 0.04).clamp(14.0, 18.0);
    final listItemMargin = EdgeInsets.symmetric(
      horizontal: screenWidth * 0.04,
      vertical: screenHeight * 0.008,
    );
    final listItemPadding = EdgeInsets.all(screenWidth * 0.03);
    final nameFontSize = (screenWidth * 0.04).clamp(14.0, 18.0);
    final usernameFontSize = (screenWidth * 0.0325).clamp(12.0, 15.0);
    final checkIconSize = (screenWidth * 0.04).clamp(14.0, 18.0);
    final spacing1 = (screenWidth * 0.04).clamp(12.0, 18.0);
    final spacing2 = (screenWidth * 0.03).clamp(10.0, 14.0);
    final cardPadding = EdgeInsets.symmetric(
      horizontal: screenWidth * 0.04,
      vertical: screenHeight * 0.015,
    );
    final cardIconSize = (screenWidth * 0.05).clamp(18.0, 24.0);

    return CallAwareScreen(
      screenName: 'CreateGroupScreen',
      child: Scaffold(
        backgroundColor: Colors.lightBlue[50],
        appBar: AppBar(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Create New Group',
                style: TextStyle(
                  color: Colors.black,
                  fontWeight: FontWeight.bold,
                  fontSize: appBarTitleSize,
                ),
              ),
              Text(
                '${_selectedFriends.length + 1}/100 members',
                style: TextStyle(
                  color: Colors.black54,
                  fontSize: appBarTitleSize * 0.6,
                ),
              ),
            ],
          ),
          backgroundColor: Colors.lightBlue[50],
          elevation: 0,
          iconTheme: const IconThemeData(color: Colors.black),
          actions: [
            Padding(
              padding: EdgeInsets.only(right: screenWidth * 0.02),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: (_groupNameController.text.trim().isNotEmpty &&
                          _selectedFriends.isNotEmpty &&
                          !_isCreatingGroup)
                      ? Colors.green
                      : Colors.transparent,
                  boxShadow: (_groupNameController.text.trim().isNotEmpty &&
                             _selectedFriends.isNotEmpty &&
                             !_isCreatingGroup)
                      ? [
                          BoxShadow(
                            color: Colors.green.withOpacity(0.4),
                            blurRadius: 8,
                            spreadRadius: 2,
                          ),
                        ]
                      : null,
                ),
                child: IconButton(
                  icon: Icon(
                    Icons.check,
                    color: (_groupNameController.text.trim().isNotEmpty &&
                            _selectedFriends.isNotEmpty &&
                            !_isCreatingGroup)
                        ? Colors.white
                        : Colors.black45,
                  ),
                  tooltip: 'Create Group',
                  onPressed: (_isCreatingGroup ||
                              _groupNameController.text.trim().isEmpty ||
                              _selectedFriends.isEmpty)
                      ? null
                      : _createGroup,
                ),
              ),
            ),
          ],
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : SafeArea(
                child: Column(
                  children: [
                    Padding(
                      padding: EdgeInsets.only(
                        left: 16.0,
                        right: 16.0,
                        top: 8.0,
                        bottom: MediaQuery.of(context).padding.bottom + 8.0,
                      ),
                      child: Column(
                        children: [
                          // Group Name Field - PURPLE
                          TextField(
                            controller: _groupNameController,
                            style: TextStyle(color: Colors.black87, fontSize: textFieldFontSize),
                            decoration: InputDecoration(
                              labelText: 'Group Name',
                              labelStyle: TextStyle(color: Colors.black54, fontSize: labelFontSize),
                              hintText: 'e.g., The Avengers',
                              hintStyle: TextStyle(color: Colors.black38, fontSize: textFieldFontSize),
                              filled: true,
                              fillColor: Colors.purple[50],
                              prefixIcon: Icon(Icons.title, color: Colors.purple[700], size: iconSize),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12.0),
                                borderSide: BorderSide.none,
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12.0),
                                borderSide: BorderSide(color: Colors.purple[200]!, width: 1.0),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12.0),
                                borderSide: BorderSide(color: Colors.purple[400]!, width: 2.0),
                              ),
                            ),
                          ),
                          SizedBox(height: spacing2),
                          // Search Field - ORANGE
                          TextField(
                            controller: _searchController,
                            style: TextStyle(color: Colors.black87, fontSize: textFieldFontSize),
                            decoration: InputDecoration(
                              labelText: 'Search friends',
                              labelStyle: TextStyle(color: Colors.black54, fontSize: labelFontSize),
                              hintText: 'Enter a username...',
                              hintStyle: TextStyle(color: Colors.black38, fontSize: textFieldFontSize),
                              prefixIcon: Icon(Icons.search, color: Colors.orange[700], size: iconSize),
                              suffixIcon: _searchController.text.isNotEmpty
                                  ? IconButton(
                                      icon: Icon(Icons.clear, color: Colors.black54, size: iconSize),
                                      onPressed: () {
                                        _searchController.clear();
                                      },
                                    )
                                  : null,
                              filled: true,
                              fillColor: Colors.orange[50],
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12.0),
                                borderSide: BorderSide.none,
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12.0),
                                borderSide: BorderSide(color: Colors.orange[200]!, width: 1.0),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12.0),
                                borderSide: BorderSide(color: Colors.orange[400]!, width: 2.0),
                              ),
                            ),
                          ),
                          SizedBox(height: spacing1),
                          // "Select Members" Card
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Container(
                              padding: cardPadding,
                              decoration: BoxDecoration(
                                color: Colors.amber[50],
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.amber[200]!, width: 1),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.amber.withOpacity(0.2),
                                    blurRadius: 4,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.people, color: Colors.amber[800], size: cardIconSize),
                                  SizedBox(width: spacing2),
                                  Text(
                                    'Select Members:',
                                    style: TextStyle(
                                      color: Colors.amber[900],
                                      fontWeight: FontWeight.bold,
                                      fontSize: labelFontSize,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: filteredFriends.isEmpty
                          ? Center(
                              child: Text(
                                _searchQuery.isNotEmpty
                                    ? "No friends found matching your search."
                                    : "You don't have any friends to add.",
                                textAlign: TextAlign.center,
                                style: TextStyle(color: Colors.black54, fontSize: textFieldFontSize),
                              ),
                            )
                          : ListView.builder(
                              itemCount: filteredFriends.length,
                              itemBuilder: (context, index) {
                                final friend = filteredFriends[index];
                                final isSelected = _selectedFriends.contains(friend.username);

                                return GestureDetector(
                                  onTap: () {
                                    setState(() {
                                      if (isSelected) {
                                        _selectedFriends.remove(friend.username);
                                      } else {
                                        // Check limit: 99 friends + 1 creator = 100 total
                                        if (_selectedFriends.length >= 99) {
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            const SnackBar(
                                              content: Text('Maximum 100 members allowed (including you)'),
                                              backgroundColor: Colors.orange,
                                            ),
                                          );
                                          return;
                                        }
                                        _selectedFriends.add(friend.username);
                                      }
                                    });
                                  },
                                  child: Container(
                                    margin: listItemMargin,
                                    decoration: BoxDecoration(
                                      color: isSelected ? Colors.green[100] : Colors.green[50],
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: isSelected ? Colors.green[400]! : Colors.green[200]!,
                                        width: 1,
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.green.withOpacity(0.2),
                                          blurRadius: 4,
                                          offset: const Offset(0, 2),
                                        ),
                                      ],
                                    ),
                                    child: Padding(
                                      padding: listItemPadding,
                                      child: Row(
                                        children: [
                                          Stack(
                                            alignment: Alignment.bottomRight,
                                            children: [
                                              Container(
                                                decoration: BoxDecoration(
                                                  shape: BoxShape.circle,
                                                  border: Border.all(
                                                    color: Colors.black,
                                                    width: 2.0,
                                                  ),
                                                ),
                                                child: _buildAvatar(friend),
                                              ),
                                              if (isSelected)
                                                Container(
                                                  decoration: BoxDecoration(
                                                    color: Colors.green,
                                                    shape: BoxShape.circle,
                                                    border: Border.all(
                                                      color: Colors.black,
                                                      width: 2,
                                                    ),
                                                  ),
                                                  child: Icon(
                                                    Icons.check,
                                                    color: Colors.white,
                                                    size: checkIconSize,
                                                  ),
                                                ),
                                            ],
                                          ),
                                          SizedBox(width: spacing1),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  friend.displayName ?? friend.username,
                                                  style: TextStyle(
                                                    color: isSelected ? Colors.green[900] : Colors.black87,
                                                    fontSize: nameFontSize,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                                if (friend.displayName != null)
                                                  Text(
                                                    '@${friend.username}',
                                                    style: TextStyle(
                                                      color: isSelected ? Colors.green[700] : Colors.black54,
                                                      fontSize: usernameFontSize,
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
                              },
                            ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}
