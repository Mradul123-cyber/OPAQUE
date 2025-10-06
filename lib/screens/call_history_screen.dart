import 'package:flutter/material.dart';
import '../widgets/call_aware_screen.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../services/call_history_service.dart';
import '../services/global_call_manager.dart';
import '../services/webrtc_service.dart';

class CallHistoryScreen extends StatefulWidget {
  const CallHistoryScreen({Key? key}) : super(key: key);

  @override
  _CallHistoryScreenState createState() => _CallHistoryScreenState();
}

class _CallHistoryScreenState extends State<CallHistoryScreen> {
  List<CallLogModel> _callLogs = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadCallHistory();
  }

  Future<void> _loadCallHistory() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final logs = await CallHistoryService.getCallHistory();

      setState(() {
        _callLogs = logs;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final titleFontSize = (screenWidth * 0.05).clamp(18.0, 24.0);

    return CallAwareScreen(
      screenName: 'CallHistoryScreen',
      child: Scaffold(
        backgroundColor: Colors.lightBlue[50],
        appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.lightBlue[50],
        iconTheme: const IconThemeData(color: Colors.black),
        title: Text(
          'Call History',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.black,
            fontSize: titleFontSize,
          ),
        ),
      ),
      body: SafeArea(child: _buildBody()),
      ),
    );
  }

  Widget _buildBody() {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    // Responsive sizing for error/empty states
    final stateMargin = screenWidth * 0.08;
    final statePadding = screenWidth * 0.06;
    final errorIconSize = (screenWidth * 0.12).clamp(40.0, 56.0);
    final errorIconPadding = (screenWidth * 0.04).clamp(14.0, 20.0);
    final errorTitleSize = (screenWidth * 0.045).clamp(16.0, 22.0);
    final errorTextSize = (screenWidth * 0.035).clamp(12.0, 16.0);
    final buttonPadding = EdgeInsets.symmetric(
      horizontal: screenWidth * 0.06,
      vertical: screenHeight * 0.015,
    );
    final emptyIconSize = (screenWidth * 0.14).clamp(48.0, 64.0);
    final emptyIconPadding = (screenWidth * 0.05).clamp(18.0, 24.0);
    final emptyTitleSize = (screenWidth * 0.05).clamp(18.0, 24.0);
    final spacing1 = (screenHeight * 0.01).clamp(6.0, 10.0);
    final spacing2 = (screenHeight * 0.025).clamp(18.0, 28.0);
    final spacing3 = (screenHeight * 0.03).clamp(20.0, 30.0);

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Container(
          margin: EdgeInsets.all(stateMargin.clamp(24.0, 40.0)),
          padding: EdgeInsets.all(statePadding.clamp(20.0, 32.0)),
          decoration: BoxDecoration(
            color: Colors.red.withOpacity(0.05),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.red.withOpacity(0.2)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: EdgeInsets.all(errorIconPadding),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.error_outline, size: errorIconSize, color: Colors.red),
              ),
              SizedBox(height: spacing2),
              Text(
                'Error loading calls',
                style: TextStyle(
                  fontSize: errorTitleSize,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey[800],
                ),
              ),
              SizedBox(height: spacing1),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: errorTextSize, color: Colors.grey[600]),
              ),
              SizedBox(height: spacing2),
              ElevatedButton.icon(
                onPressed: _loadCallHistory,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                  padding: buttonPadding,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_callLogs.isEmpty) {
      return Center(
        child: Container(
          margin: EdgeInsets.all(stateMargin.clamp(24.0, 40.0)),
          padding: EdgeInsets.all(statePadding.clamp(24.0, 40.0)),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.lightBlue[200]!, width: 1),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: EdgeInsets.all(emptyIconPadding),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.phone_in_talk, size: emptyIconSize, color: Colors.blue[300]),
              ),
              SizedBox(height: spacing3),
              Text(
                'No call history',
                style: TextStyle(
                  fontSize: emptyTitleSize,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey[800],
                ),
              ),
              SizedBox(height: spacing1),
              Text(
                'Your call history will appear here',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: errorTextSize, color: Colors.grey[600]),
              ),
            ],
          ),
        ),
      );
    }

    final bottomPadding = MediaQuery.of(context).padding.bottom;
    final listPaddingH = (screenWidth * 0.03).clamp(10.0, 16.0);
    final listPaddingV = (screenHeight * 0.01).clamp(6.0, 10.0);

    return RefreshIndicator(
      onRefresh: _loadCallHistory,
      child: ListView.builder(
        padding: EdgeInsets.only(
          left: listPaddingH,
          right: listPaddingH,
          top: listPaddingV,
          bottom: bottomPadding + listPaddingV,
        ),
        itemCount: _callLogs.length,
        itemBuilder: (context, index) {
          final log = _callLogs[index];
          return _buildCallLogItem(log, index);
        },
      ),
    );
  }

  Widget _buildCallLogItem(CallLogModel log, int index) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    // Responsive sizing for call log items
    final itemMargin = EdgeInsets.symmetric(
      horizontal: screenWidth * 0.03,
      vertical: screenHeight * 0.008,
    );
    final itemPadding = EdgeInsets.symmetric(
      horizontal: screenWidth * 0.03,
      vertical: screenHeight * 0.01,
    );
    final avatarRadius = (screenWidth * 0.06).clamp(20.0, 28.0);
    final avatarFontSize = (screenWidth * 0.05).clamp(18.0, 22.0);
    final nameFontSize = (screenWidth * 0.0375).clamp(14.0, 17.0);
    final statusFontSize = (screenWidth * 0.03).clamp(11.0, 14.0);
    final statusIconSize = (screenWidth * 0.0325).clamp(12.0, 15.0);
    final statusIconPadding = (screenWidth * 0.01).clamp(3.0, 5.0);
    final timestampLabelSize = (screenWidth * 0.0275).clamp(10.0, 13.0);
    final timestampTimeSize = (screenWidth * 0.025).clamp(9.0, 12.0);
    final callButtonIconSize = (screenWidth * 0.045).clamp(16.0, 20.0);
    final callButtonPadding = (screenWidth * 0.015).clamp(5.0, 8.0);
    final callButtonSize = (screenWidth * 0.08).clamp(30.0, 36.0);
    final spacingSmall = (screenHeight * 0.0025).clamp(2.0, 4.0);
    final spacingMedium = (screenWidth * 0.015).clamp(4.0, 8.0);
    final spacingLarge = (screenWidth * 0.02).clamp(6.0, 10.0);

    final isVideo = log.callType == 'video';
    final isMissed = log.callStatus == 'missed' && log.direction == 'incoming';
    final isCancelled = log.callStatus == 'missed' && log.direction == 'outgoing';
    final isRejected = log.callStatus == 'rejected';
    final isCompleted = log.callStatus == 'completed';
    final isOutgoing = log.direction == 'outgoing';

    Color iconColor;
    IconData callIcon;
    bool shouldBold = false;
    Color cardBgColor;
    Color cardBorderColor;

    if (isMissed) {
      // Incoming call that was missed
      iconColor = Colors.red[700]!;
      callIcon = isVideo ? Icons.videocam_off : Icons.phone_missed;
      shouldBold = true;
      cardBgColor = Colors.red[50]!;
      cardBorderColor = Colors.red[200]!;
    } else if (isRejected) {
      // Call was declined/rejected
      iconColor = Colors.orange[700]!;
      callIcon = isVideo ? Icons.videocam_off : Icons.call_end;
      shouldBold = log.direction == 'incoming'; // Bold if we rejected it
      cardBgColor = Colors.orange[50]!;
      cardBorderColor = Colors.orange[200]!;
    } else if (isCancelled) {
      // Outgoing call that was cancelled
      iconColor = Colors.grey[700]!;
      callIcon = isVideo ? Icons.videocam_off : Icons.call_end;
      cardBgColor = Colors.grey[50]!;
      cardBorderColor = Colors.grey[200]!;
    } else if (isCompleted && isOutgoing) {
      // Completed outgoing call
      iconColor = Colors.green[700]!;
      callIcon = isVideo ? Icons.videocam : Icons.call_made;
      cardBgColor = Colors.green[50]!;
      cardBorderColor = Colors.green[200]!;
    } else if (isCompleted) {
      // Completed incoming call
      iconColor = Colors.blue[700]!;
      callIcon = isVideo ? Icons.videocam : Icons.call_received;
      cardBgColor = Colors.blue[50]!;
      cardBorderColor = Colors.blue[200]!;
    } else {
      // Default for any other status
      iconColor = Colors.grey[700]!;
      callIcon = isVideo ? Icons.videocam : Icons.phone;
      cardBgColor = Colors.grey[50]!;
      cardBorderColor = Colors.grey[200]!;
    }

    return Container(
      margin: itemMargin,
      decoration: BoxDecoration(
        color: cardBgColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cardBorderColor, width: 1),
        boxShadow: [
          BoxShadow(
            color: iconColor.withOpacity(0.2),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
          child: ListTile(
            contentPadding: itemPadding,
            leading: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.black, width: 2),
              ),
              child: CircleAvatar(
                radius: avatarRadius,
                backgroundImage: log.otherUserAvatar != null
                    ? NetworkImage(log.otherUserAvatar!)
                    : null,
                backgroundColor: log.otherUserAvatar == null
                    ? Color(log.otherUserName.hashCode | 0xFF000000)
                    : null,
                child: log.otherUserAvatar == null
                    ? Text(
                        log.otherUserName.isNotEmpty
                            ? log.otherUserName[0].toUpperCase()
                            : '?',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: avatarFontSize,
                          fontWeight: FontWeight.w500,
                        ),
                      )
                    : null,
              ),
            ),
            title: Text(
              log.otherUserName,
              style: TextStyle(
                fontWeight: shouldBold ? FontWeight.bold : FontWeight.w600,
                fontSize: nameFontSize,
                color: Colors.black87,
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
            subtitle: Padding(
              padding: EdgeInsets.only(top: spacingMedium),
              child: Row(
                children: [
                  Container(
                    padding: EdgeInsets.all(statusIconPadding),
                    decoration: BoxDecoration(
                      color: iconColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Icon(callIcon, size: statusIconSize, color: iconColor),
                  ),
                  SizedBox(width: spacingMedium),
                  Flexible(
                    child: Text(
                      log.statusText,
                      style: TextStyle(
                        color: (isMissed || isRejected) ? iconColor : Colors.grey[700],
                        fontWeight: shouldBold ? FontWeight.w500 : FontWeight.normal,
                        fontSize: statusFontSize,
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ),
                ],
              ),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      _formatTimestamp(log.startedAt)['label']!,
                      style: TextStyle(
                        fontSize: timestampLabelSize,
                        color: Colors.grey[700],
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    SizedBox(height: spacingSmall),
                    Text(
                      _formatTimestamp(log.startedAt)['time']!,
                      style: TextStyle(
                        fontSize: timestampTimeSize,
                        color: Colors.grey[600],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
                SizedBox(width: spacingLarge),
                Container(
                  decoration: BoxDecoration(
                    color: iconColor,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.black, width: 1),
                  ),
                  child: IconButton(
                    icon: Icon(
                      isVideo ? Icons.videocam : Icons.phone,
                      color: Colors.white,
                      size: callButtonIconSize,
                    ),
                    tooltip: isVideo ? 'Video call' : 'Voice call',
                    onPressed: () => _initiateCall(context, log, isVideo ? CallType.video : CallType.voice),
                    padding: EdgeInsets.all(callButtonPadding),
                    constraints: BoxConstraints(minWidth: callButtonSize, minHeight: callButtonSize),
                  ),
                ),
              ],
            ),
            onTap: () {
              // Optionally navigate to chat
            },
          ),
        );
    }

  void _initiateCall(BuildContext context, CallLogModel log, CallType callType) async {
    final callManager = Provider.of<GlobalCallManager>(context, listen: false);

    // Check if already in a call
    if (callManager.isInCall) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You are already in a call'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    // Check if conversationId exists
    if (log.conversationId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cannot initiate call: conversation not found'),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    try {
      await callManager.startOutgoingCall(
        recipientUid: log.otherUserUid,
        recipientName: log.otherUserName,
        conversationId: log.conversationId!,
        callType: callType,
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to initiate call: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  Map<String, String> _formatTimestamp(DateTime timestamp) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final callDate = DateTime(timestamp.year, timestamp.month, timestamp.day);

    final difference = today.difference(callDate).inDays;
    final timeStr = DateFormat('h:mm a').format(timestamp);

    if (difference == 0) {
      return {'label': 'Today', 'time': timeStr};
    } else if (difference == 1) {
      return {'label': 'Yesterday', 'time': timeStr};
    } else if (difference < 7) {
      final dayName = DateFormat('EEEE').format(timestamp);
      return {'label': dayName, 'time': timeStr};
    } else {
      final dateStr = DateFormat('MMM d').format(timestamp);
      return {'label': dateStr, 'time': timeStr};
    }
  }
}
