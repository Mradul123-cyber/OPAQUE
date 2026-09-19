import 'package:flutter_test/flutter_test.dart';
import 'package:zarq_messenger/models/chat_payloads.dart';

void main() {
  group('E2EE Chat Payloads', () {
    test('LocationPayload serialize and deserialize', () {
      final payload = LocationPayload(
        latitude: 37.7749,
        longitude: -122.4194,
        name: 'Market Street',
        address: 'San Francisco, CA',
      );

      final jsonStr = payload.serialize();
      expect(ChatPayloadParser.isStructuredPayload(jsonStr), isTrue);
      expect(ChatPayloadParser.getPayloadType(jsonStr), equals(ChatPayloadParser.typeLocation));

      final parsed = LocationPayload.tryParse(jsonStr);
      expect(parsed, isNotNull);
      expect(parsed!.latitude, closeTo(37.7749, 0.0001));
      expect(parsed.longitude, closeTo(-122.4194, 0.0001));
      expect(parsed.name, equals('Market Street'));
      expect(parsed.address, equals('San Francisco, CA'));

      expect(ChatPayloadParser.getPreviewText(jsonStr), equals('📍 Location: Market Street'));
    });

    test('ContactPayload serialize and deserialize', () {
      final payload = ContactPayload(
        name: 'Sarah Connor',
        phones: ['+1-555-0143'],
        emails: ['sarah@example.com'],
        organization: 'Resistance',
      );

      final jsonStr = payload.serialize();
      expect(ChatPayloadParser.isStructuredPayload(jsonStr), isTrue);
      expect(ChatPayloadParser.getPayloadType(jsonStr), equals(ChatPayloadParser.typeContact));

      final parsed = ContactPayload.tryParse(jsonStr);
      expect(parsed, isNotNull);
      expect(parsed!.name, equals('Sarah Connor'));
      expect(parsed.phones, contains('+1-555-0143'));
      expect(parsed.emails, contains('sarah@example.com'));
      expect(parsed.organization, equals('Resistance'));

      expect(ChatPayloadParser.getPreviewText(jsonStr), equals('👤 Contact: Sarah Connor'));
    });

    test('PollPayload serialize and deserialize', () {
      final payload = PollPayload(
        pollId: 'poll_12345',
        question: 'What time is dinner?',
        options: [
          PollOption(id: 1, text: '6:00 PM'),
          PollOption(id: 2, text: '7:30 PM'),
        ],
        allowMultiple: true,
        creatorUid: 'user_abc',
      );

      final jsonStr = payload.serialize();
      expect(ChatPayloadParser.isStructuredPayload(jsonStr), isTrue);
      expect(ChatPayloadParser.getPayloadType(jsonStr), equals(ChatPayloadParser.typePoll));

      final parsed = PollPayload.tryParse(jsonStr);
      expect(parsed, isNotNull);
      expect(parsed!.pollId, equals('poll_12345'));
      expect(parsed.question, equals('What time is dinner?'));
      expect(parsed.options.length, equals(2));
      expect(parsed.options[0].text, equals('6:00 PM'));
      expect(parsed.allowMultiple, isTrue);

      expect(ChatPayloadParser.getPreviewText(jsonStr), equals('📊 Poll: What time is dinner?'));
    });

    test('PollVotePayload serialize and deserialize', () {
      final vote = PollVotePayload(
        pollId: 'poll_12345',
        selectedOptionIds: [1, 2],
        voterUid: 'voter_xyz',
      );

      final jsonStr = vote.serialize();
      expect(ChatPayloadParser.isStructuredPayload(jsonStr), isTrue);
      expect(ChatPayloadParser.getPayloadType(jsonStr), equals(ChatPayloadParser.typePollVote));

      final parsed = PollVotePayload.tryParse(jsonStr);
      expect(parsed, isNotNull);
      expect(parsed!.pollId, equals('poll_12345'));
      expect(parsed.selectedOptionIds, equals([1, 2]));
      expect(parsed.voterUid, equals('voter_xyz'));

      expect(ChatPayloadParser.getPreviewText(jsonStr), equals('🗳️ Voted on poll'));
    });

    test('ChatPayloadParser handles regular plaintext gracefully', () {
      const normalMessage = 'Hey, how are you?';
      expect(ChatPayloadParser.isStructuredPayload(normalMessage), isFalse);
      expect(ChatPayloadParser.getPayloadType(normalMessage), isNull);
      expect(ChatPayloadParser.getPreviewText(normalMessage), equals('Hey, how are you?'));
      expect(LocationPayload.tryParse(normalMessage), isNull);
      expect(ContactPayload.tryParse(normalMessage), isNull);
      expect(PollPayload.tryParse(normalMessage), isNull);
    });
  });
}
