// lib/create_group_screen.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:zarq_messenger/home_screen.dart';
import 'dart:math' as math;

import 'chat_screen.dart';

// This Friend model should be consistent with the one in your other files.
class Friend {
  final String username;
  final String? avatarUrl;

  Friend({required this.username, this.avatarUrl});

  factory Friend.fromJson(Map<String, dynamic> json) {
    return Friend(
      username: json['username'] ?? 'Unknown User',
      avatarUrl: json['avatarUrl'],
    );
  }
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

  void _showCreatingGroupDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: Colors.grey[850],
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15.0),
          ),
          content: const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(
                  Colors.lightGreenAccent,
                ),
              ),
              SizedBox(height: 20),
              Text(
                "Creating group...",
                style: TextStyle(color: Colors.white70, fontSize: 16),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _createGroup() async {
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
    final hasImage = friend.avatarUrl != null && friend.avatarUrl!.isNotEmpty;
    final initial = friend.username.isNotEmpty
        ? friend.username[0].toUpperCase()
        : '?';
    final color = Color(friend.username.hashCode | 0xFF000000).withOpacity(1.0);

    return CircleAvatar(
      radius: 24,
      backgroundColor: hasImage ? Colors.transparent : color,
      backgroundImage: hasImage ? NetworkImage(friend.avatarUrl!) : null,
      child: hasImage
          ? null
          : Text(
              initial,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filteredFriends = _friendsList.where((friend) {
      final usernameLower = friend.username.toLowerCase();
      final queryLower = _searchQuery.toLowerCase();
      return usernameLower.contains(queryLower);
    }).toList();

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text(
          'Create New Group',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.check, color: Colors.white),
            tooltip: 'Create Group',
            onPressed:
                (_isCreatingGroup ||
                    _groupNameController.text.trim().isEmpty ||
                    _selectedFriends.isEmpty)
                ? null
                : _createGroup,
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
                      height: 150,
                      width: double.infinity,
                      errorBuilder: (context, error, stackTrace) => Container(),
                    ),
                  ),
                ),

                SafeArea(
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16.0,
                          vertical: 8.0,
                        ),
                        child: TextField(
                          controller: _groupNameController,
                          style: const TextStyle(color: Colors.white),
                          decoration: InputDecoration(
                            labelText: 'Group Name',
                            labelStyle: TextStyle(
                              color: Colors.white.withOpacity(0.7),
                            ),
                            hintText: 'e.g., The Avengers',
                            hintStyle: TextStyle(
                              color: Colors.white.withOpacity(0.5),
                            ),
                            filled: true,
                            fillColor: const Color(0xFF2E8B57).withOpacity(0.2),
                            prefixIcon: const Icon(
                              Icons.title,
                              color: Colors.white54,
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
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16.0,
                          vertical: 8.0,
                        ),
                        child: TextField(
                          controller: _searchController,
                          style: const TextStyle(color: Colors.white),
                          decoration: InputDecoration(
                            labelText: 'Search friends',
                            labelStyle: TextStyle(
                              color: Colors.white.withOpacity(0.7),
                            ),
                            hintText: 'Enter a username...',
                            hintStyle: TextStyle(
                              color: Colors.white.withOpacity(0.5),
                            ),
                            prefixIcon: const Icon(
                              Icons.search,
                              color: Colors.white54,
                            ),
                            suffixIcon: _searchController.text.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(
                                      Icons.clear,
                                      color: Colors.white54,
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
                      const Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: 16.0,
                          vertical: 12.0,
                        ),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'Select Members:',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
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
                                      margin: const EdgeInsets.symmetric(
                                        horizontal: 16.0,
                                        vertical: 6.0,
                                      ),
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
                                        padding: const EdgeInsets.all(12.0),
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
                                                    child: const Icon(
                                                      Icons.check,
                                                      color: Colors.black,
                                                      size: 16,
                                                    ),
                                                  ),
                                              ],
                                            ),
                                            const SizedBox(width: 16),
                                            Expanded(
                                              child: Text(
                                                friend.username,
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.w500,
                                                ),
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
    );
  }
}
