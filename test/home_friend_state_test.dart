import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:zarq_messenger/home_screen.dart';
import 'package:zarq_messenger/providers/home_provider.dart';
import 'package:zarq_messenger/services/conversation_service.dart';
import 'package:zarq_messenger/services/websocket_service.dart';

class FakeConversations extends ConversationService {
  final pending = Completer<List<ConversationInfo>>();
  int calls = 0;
  @override
  Future<List<ConversationInfo>> fetchConversations() async {
    if (calls++ > 0) return pending.future;
    return [ConversationInfo(conversationId: 1, chatTitle: 'Friend',
      isGroup: false, partnerUid: 'friend', isFriend: true,
      unreadCount: 2, hasUnreadMessages: true, lastMessage: 'Hello')];
  }
}

class FakeSocket implements WebSocketService {
  @override
  Stream<dynamic> get stream => const Stream.empty();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('Friend removal updates current and cached status while keeping chat history', () async {
    final service = FakeConversations();
    final provider = HomeProvider(conversationService: service, webSocketService: FakeSocket());
    await provider.fetchInitialConversations();
    provider.markConversationAsRead(1);
    expect(provider.conversations.single.isFriend, isTrue);
    provider.markFriendRemoved('friend');
    expect(provider.conversations.single.isFriend, isFalse);
    expect(provider.conversations.single.lastMessage, 'Hello');
    await provider.fetchInitialConversations();
    expect(provider.conversations.single.isFriend, isFalse);
    service.pending.complete(provider.conversations);
    await Future<void>.delayed(Duration.zero);
    provider.dispose();
  });
  test('Missing or false friendship status never grants the removal action', () {
    final json = <String, dynamic>{'conversationId': 1, 'isGroup': false, 'chatTitle': 'Person'};
    expect(ConversationInfo.fromJson(json).isFriend, isFalse);
    expect(ConversationInfo.fromJson({...json, 'isFriend': true}).isFriend, isTrue);
    expect(ConversationInfo.fromJson({...json, 'isFriend': false}).isFriend, isFalse);
  });
}
