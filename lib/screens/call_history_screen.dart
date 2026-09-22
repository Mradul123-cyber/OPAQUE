import '../widgets/opaque_navigation.dart';
import '../widgets/opaque_toast.dart';
import 'package:flutter/material.dart';
import '../widgets/call_aware_screen.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../services/call_history_service.dart';
import '../services/global_call_manager.dart';
import '../services/webrtc_service.dart';
import '../services/user_settings_provider.dart';

class CallHistoryScreen extends StatefulWidget {
  const CallHistoryScreen({super.key, this.embedded = false});
  final bool embedded;

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

      if (!mounted) return;
      logs.sort((a, b) => b.startedAt.compareTo(a.startedAt));
      setState(() {
        _callLogs = logs;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) => Consumer<UserSettingsProvider>(builder: (context, settings, _) {
    final dark = settings.isDarkMode;
    final surface = dark ? const Color(0xFF19202A) : Colors.white;
    return CallAwareScreen(screenName: 'CallHistoryScreen', child: Scaffold(
      backgroundColor: surface,
      appBar: widget.embedded ? null : AppBar(backgroundColor: surface, foregroundColor: dark ? Colors.white : const Color(0xFF424D60), elevation: 0, scrolledUnderElevation: 0),
      body: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(padding: const EdgeInsets.fromLTRB(20, 22, 20, 17), child: Text('Calls', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w500, letterSpacing: -.5, color: dark ? const Color(0xFFE0E6EF) : const Color(0xFF343D4C)))),
        Expanded(child: _buildBody(dark)),
      ]),
    ));
  });

  Widget _buildBody(bool dark) {
    final indicatorColor = dark ? Colors.white : Colors.black;
    final indicatorBg = dark ? const Color(0xFF283241) : Colors.white;

    if (_isLoading) {
      return Center(
        child: CircularProgressIndicator(
          color: indicatorColor,
          strokeWidth: 2.5,
        ),
      );
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: Color(0xFFC5757E), size: 30),
              const SizedBox(height: 12),
              Text('Could not load calls', style: TextStyle(fontSize: 16, color: dark ? Colors.white : const Color(0xFF535E70))),
              const SizedBox(height: 8), Text(_error!, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, color: Color(0xFF969EAC))),
              TextButton.icon(
                onPressed: _loadCallHistory,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
                style: TextButton.styleFrom(
                  foregroundColor: indicatorColor,
                ),
              ),
            ],
          ),
        ),
      );
    }
    if (_callLogs.isEmpty) {
      return RefreshIndicator(
        color: indicatorColor,
        backgroundColor: indicatorBg,
        onRefresh: _loadCallHistory,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 60),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 74,
                        height: 74,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(26),
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: dark
                                ? const [Color(0xFF283241), Color(0xFF212B39)]
                                : const [Color(0xFFF1F4FA), Color(0xFFE9EEF7)],
                          ),
                        ),
                        child: const OpaqueIcon(
                          'calls',
                          size: 30,
                          strokeWidth: 1.35,
                          color: Color(0xFF8B9BB5),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'No calls yet',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          letterSpacing: -.3,
                          color: dark
                              ? const Color(0xFFE0E6EF)
                              : const Color(0xFF535E70),
                        ),
                      ),
                      const SizedBox(height: 9),
                      const Text(
                        'Your voice and video calls will appear here.\nCall a friend to start a conversation.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.8,
                          color: Color(0xFF969EAC),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      color: indicatorColor,
      backgroundColor: indicatorBg,
      onRefresh: _loadCallHistory,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: _callLogs.length,
        itemBuilder: (context, index) {
          final log = _callLogs[index];
          final date = DateUtils.dateOnly(log.startedAt);
          final startsDay = index == 0 ||
              date != DateUtils.dateOnly(_callLogs[index - 1].startedAt);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (startsDay)
                Padding(
                  padding: const EdgeInsets.only(top: 10, bottom: 7),
                  child: Text(
                    _formatTimestamp(log.startedAt)['label']!,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF9A9FAA),
                    ),
                  ),
                ),
              _buildCallLogItem(log, dark),
            ],
          );
        },
      ),
    );
  }

  Widget _buildCallLogItem(CallLogModel log, bool dark) {
    final video = log.callType == 'video';
    final missed = log.callStatus == 'missed' && log.direction == 'incoming';
    final outgoing = log.direction == 'outgoing';
    final label = log.callStatus == 'completed' ? (outgoing ? 'Outgoing' : 'Incoming') : log.statusText;
    final duration = log.callStatus == 'completed' && log.formattedDuration.isNotEmpty ? ' · ${log.formattedDuration}' : '';
    final avatar = log.otherUserAvatar;
    final fallback = Center(child: Text(log.otherUserName.isEmpty ? '?' : log.otherUserName.characters.first.toUpperCase(), style: const TextStyle(fontSize: 14, color: Color(0xFF727F96))));
    return Container(padding: const EdgeInsets.symmetric(vertical: 14), decoration: BoxDecoration(border: Border(bottom: BorderSide(color: dark ? const Color(0xFF303947) : const Color(0xFFF0F1F4)))),
      child: Row(children: [
        Container(width: 41, height: 41, clipBehavior: Clip.antiAlias, decoration: const BoxDecoration(shape: BoxShape.circle, gradient: LinearGradient(colors: [Color(0xFFF0F3FA), Color(0xFFE7EBF4)])),
          child: avatar != null && avatar.isNotEmpty
              ? CachedNetworkImage(
                  imageUrl: avatar,
                  fit: BoxFit.cover,
                  memCacheWidth: 120,
                  memCacheHeight: 120,
                  maxWidthDiskCache: 250,
                  maxHeightDiskCache: 250,
                  placeholder: (_, _) => fallback,
                  errorWidget: (_, _, _) => fallback,
                )
              : fallback),
        const SizedBox(width: 11),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(log.otherUserName, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: missed ? const Color(0xFFC5757E) : dark ? const Color(0xFFE0E6EF) : const Color(0xFF343D4C))),
          const SizedBox(height: 5),
          Row(children: [
            OpaqueIcon(missed ? 'missed' : outgoing ? 'sent' : 'received', size: 12, color: missed ? const Color(0xFFC5757E) : const Color(0xFF728D84)),
            const SizedBox(width: 4),
            Flexible(child: Text('$label · ${DateFormat('HH:mm').format(log.startedAt)}$duration', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10, color: Color(0xFF959CA9)))),
          ]),
        ])),
        IconButton(tooltip: '${video ? 'Video' : 'Voice'} call ${log.otherUserName}', constraints: const BoxConstraints(minWidth: 36, minHeight: 44),
          onPressed: () => _initiateCall(context, log, video ? CallType.video : CallType.voice),
          icon: OpaqueIcon(video ? 'video' : 'calls', size: 19, color: const Color(0xFF7184A3))),
      ]),
    );
  }

  void _initiateCall(
    BuildContext context,
    CallLogModel log,
    CallType callType,
  ) async {
    final callManager = Provider.of<GlobalCallManager>(context, listen: false);

    // Check if already in a call
    if (callManager.isInCall) {
      OpaqueToast.warning(context, 'You are already in a call');
      return;
    }

    // Check if conversationId exists
    if (log.conversationId == null) {
      OpaqueToast.warning(context, 'Cannot initiate call: conversation not found');
      return;
    }

    try {
      await callManager.startOutgoingCall(
        recipientUid: log.otherUserUid,
        recipientName: log.otherUserName,
        conversationId: log.conversationId!,
        callType: callType,
        recipientAvatarUrl: log.otherUserAvatar,
      );
    } catch (e) {
      if (context.mounted) {
        OpaqueToast.error(context, 'Failed to initiate call: $e');
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
