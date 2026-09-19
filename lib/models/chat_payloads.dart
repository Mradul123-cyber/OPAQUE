import 'dart:convert';

/// Base class or parser for Opaque E2EE structured chat payloads.
/// All structured chat messages (Location, Contact, Poll, Poll Vote)
/// are serialized as JSON strings and encrypted end-to-end via
/// Signal Protocol / Sender Keys just like regular messages.
class ChatPayloadParser {
  static const String typeLocation = 'location';
  static const String typeContact = 'contact';
  static const String typePoll = 'poll';
  static const String typePollVote = 'poll_vote';

  /// Check if the decrypted plaintext content is a structured Opaque payload.
  static bool isStructuredPayload(String content) {
    if (!content.trim().startsWith('{') || !content.trim().endsWith('}')) {
      return false;
    }
    try {
      if (content.length > 32768) return false;
      final decoded = jsonDecode(content);
      if (decoded is Map<String, dynamic> && decoded.containsKey('opaque_type')) {
        return true;
      }
    } catch (_) {}
    return false;
  }

  /// Extracts the `opaque_type` from the decrypted content if present.
  static String? getPayloadType(String content) {
    if (!content.trim().startsWith('{') || !content.trim().endsWith('}')) {
      return null;
    }
    try {
      if (content.length > 32768) return null;
      final decoded = jsonDecode(content);
      if (decoded is Map<String, dynamic>) {
        return decoded['opaque_type'] as String?;
      }
    } catch (_) {}
    return null;
  }

  /// Generates a clean preview string for notifications and conversation lists.
  static String getPreviewText(String? content) {
    if (content == null || content.isEmpty) return 'No messages yet';
    if (!isStructuredPayload(content)) return content;

    try {
      final decoded = jsonDecode(content) as Map<String, dynamic>;
      final type = decoded['opaque_type'] as String?;

      switch (type) {
        case typeLocation:
          final name = decoded['name'] as String?;
          return name != null && name.isNotEmpty ? '📍 Location: $name' : '📍 Location';
        case typeContact:
          final name = decoded['name'] as String?;
          return name != null && name.isNotEmpty ? '👤 Contact: $name' : '👤 Contact';
        case typePoll:
          final question = decoded['question'] as String?;
          return question != null && question.isNotEmpty ? '📊 Poll: $question' : '📊 Poll';
        case typePollVote:
          return '🗳️ Voted on poll';
        default:
          return content;
      }
    } catch (_) {
      return content;
    }
  }
}

/// E2EE Location payload
class LocationPayload {
  final double latitude;
  final double longitude;
  final String? name;
  final String? address;

  LocationPayload({
    required this.latitude,
    required this.longitude,
    this.name,
    this.address,
  });

  Map<String, dynamic> toJson() => {
    'opaque_type': ChatPayloadParser.typeLocation,
    'lat': latitude,
    'lng': longitude,
    if (name != null && name!.isNotEmpty) 'name': name,
    if (address != null && address!.isNotEmpty) 'address': address,
  };

  String serialize() => jsonEncode(toJson());

  static LocationPayload? tryParse(String content) {
    try {
      if (content.length > 32768) return null;
      final decoded = jsonDecode(content);
      if (decoded is Map<String, dynamic> &&
          decoded['opaque_type'] == ChatPayloadParser.typeLocation) {
        final lat = (decoded['lat'] as num).toDouble();
        final lng = (decoded['lng'] as num).toDouble();
        if (!lat.isFinite || !lng.isFinite || lat < -90 || lat > 90 || lng < -180 || lng > 180) return null;
        return LocationPayload(
          latitude: lat,
          longitude: lng,
          name: decoded['name'] as String?,
          address: decoded['address'] as String?,
        );
      }
    } catch (_) {}
    return null;
  }
}

/// E2EE Contact payload
class ContactPayload {
  final String name;
  final List<String> phones;
  final List<String> emails;
  final String? organization;

  ContactPayload({
    required this.name,
    this.phones = const [],
    this.emails = const [],
    this.organization,
  });

  Map<String, dynamic> toJson() => {
    'opaque_type': ChatPayloadParser.typeContact,
    'name': name,
    if (phones.isNotEmpty) 'phones': phones,
    if (emails.isNotEmpty) 'emails': emails,
    if (organization != null && organization!.isNotEmpty) 'org': organization,
  };

  String serialize() => jsonEncode(toJson());

  static ContactPayload? tryParse(String content) {
    try {
      if (content.length > 32768) return null;
      final decoded = jsonDecode(content);
      if (decoded is Map<String, dynamic> &&
          decoded['opaque_type'] == ChatPayloadParser.typeContact) {
        final rawPhones = decoded['phones'] as List<dynamic>? ?? [];
        final rawEmails = decoded['emails'] as List<dynamic>? ?? [];
        if (rawPhones.length > 30 || rawEmails.length > 30) return null;
        if (rawPhones.any((p) => p is! String || p.length > 100) || rawEmails.any((p) => p is! String || p.length > 320)) return null;
        return ContactPayload(
          name: decoded['name'] as String? ?? 'Contact',
          phones: rawPhones.map((e) => e.toString()).toList(),
          emails: rawEmails.map((e) => e.toString()).toList(),
          organization: decoded['org'] as String?,
        );
      }
    } catch (_) {}
    return null;
  }
}

/// E2EE Poll Option
class PollOption {
  final int id;
  final String text;

  PollOption({required this.id, required this.text});

  Map<String, dynamic> toJson() => {'id': id, 'text': text};

  factory PollOption.fromJson(Map<String, dynamic> json) => PollOption(
    id: json['id'] as int? ?? 0,
    text: json['text'] as String? ?? '',
  );
}

/// E2EE Poll payload
class PollPayload {
  final String pollId;
  final String question;
  final List<PollOption> options;
  final bool allowMultiple;
  final String? creatorUid;
  final String? createdAt;

  PollPayload({
    required this.pollId,
    required this.question,
    required this.options,
    this.allowMultiple = false,
    this.creatorUid,
    this.createdAt,
  });

  Map<String, dynamic> toJson() => {
    'opaque_type': ChatPayloadParser.typePoll,
    'poll_id': pollId,
    'question': question,
    'options': options.map((o) => o.toJson()).toList(),
    'allow_multiple': allowMultiple,
    if (creatorUid != null) 'creator_uid': creatorUid,
    if (createdAt != null) 'created_at': createdAt,
  };

  String serialize() => jsonEncode(toJson());

  static PollPayload? tryParse(String content) {
    try {
      if (content.length > 32768) return null;
      final decoded = jsonDecode(content);
      if (decoded is Map<String, dynamic> &&
          decoded['opaque_type'] == ChatPayloadParser.typePoll) {
        final rawOptions = decoded['options'] as List<dynamic>? ?? [];
        final question = decoded['question'] as String? ?? '';
        final pollId = decoded['poll_id'] as String? ?? '';
        if (question.trim().isEmpty || question.length > 1000 || pollId.isEmpty || pollId.length > 200 || rawOptions.length < 2 || rawOptions.length > 10) return null;
        final options = rawOptions.map((o) => PollOption.fromJson(o as Map<String, dynamic>)).toList();
        if (options.any((o) => o.text.trim().isEmpty || o.text.length > 500) || options.map((o) => o.id).toSet().length != options.length) return null;
        return PollPayload(
          pollId: decoded['poll_id'] as String? ?? '',
          question: decoded['question'] as String? ?? '',
          options: rawOptions
              .map((o) => PollOption.fromJson(o as Map<String, dynamic>))
              .toList(),
          allowMultiple: decoded['allow_multiple'] as bool? ?? false,
          creatorUid: decoded['creator_uid'] as String?,
          createdAt: decoded['created_at'] as String?,
        );
      }
    } catch (_) {}
    return null;
  }
}

/// E2EE Poll Vote payload
class PollVotePayload {
  final String pollId;
  final List<int> selectedOptionIds;
  final String? voterUid;

  PollVotePayload({
    required this.pollId,
    required this.selectedOptionIds,
    this.voterUid,
  });

  Map<String, dynamic> toJson() => {
    'opaque_type': ChatPayloadParser.typePollVote,
    'poll_id': pollId,
    'selected_option_ids': selectedOptionIds,
    if (voterUid != null) 'voter_uid': voterUid,
  };

  String serialize() => jsonEncode(toJson());

  static PollVotePayload? tryParse(String content) {
    try {
      if (content.length > 32768) return null;
      final decoded = jsonDecode(content);
      if (decoded is Map<String, dynamic> &&
          decoded['opaque_type'] == ChatPayloadParser.typePollVote) {
        final rawIds = decoded['selected_option_ids'] as List<dynamic>? ?? [];
        if (rawIds.length > 10 || rawIds.any((id) => id is! int)) return null;
        return PollVotePayload(
          pollId: decoded['poll_id'] as String? ?? '',
          selectedOptionIds: rawIds.map((id) => id as int).toList(),
          voterUid: decoded['voter_uid'] as String?,
        );
      }
    } catch (_) {}
    return null;
  }
}
