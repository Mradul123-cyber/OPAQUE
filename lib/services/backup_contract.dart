import 'dart:convert';
import 'package:crypto/crypto.dart';

/// Portable v2 backups remain readable; 2.1 writes complete database rows.
class BackupContract {
  static const version = '2.1.0';

  static Map<String, dynamic> validateSecurityState(String encoded) {
    final state = jsonDecode(encoded) as Map<String, dynamic>;
    if (state['protocol_state'] is! Map ||
        state['identity_key_pair'] is! String ||
        state['device_id'] is! int ||
        (state['device_id'] as int) < 1 ||
        state['registration_id'] is! int ||
        (state['registration_id'] as int) < 1) {
      throw const FormatException('Backup is missing required recovery keys.');
    }
    final identity =
        jsonDecode(state['identity_key_pair'] as String)
            as Map<String, dynamic>;
    if (identity['private_key'] is! String ||
        identity['public_key'] is! String ||
        base64Decode(identity['private_key'] as String).length != 32 ||
        base64Decode(identity['public_key'] as String).length != 33) {
      throw const FormatException('Backup identity keys are invalid.');
    }
    return state;
  }

  static String databasePassword(String encoded) {
    final state = validateSecurityState(encoded);
    final identity =
        jsonDecode(state['identity_key_pair'] as String)
            as Map<String, dynamic>;
    return sha256.convert([
      ...base64Decode(identity['private_key'] as String),
      ...utf8.encode('zarq_database_encryption_v1'),
    ]).toString();
  }

  static void validate({
    required String version,
    required String owner,
    required String currentUid,
    required String securityState,
    required List<Map<String, dynamic>> messages,
  }) {
    if (owner != currentUid) {
      throw const FormatException('This backup belongs to another account.');
    }
    if (!{'1.0.0', '2.0.0', BackupContract.version}.contains(version)) {
      throw const FormatException('This backup format is not supported.');
    }
    validateSecurityState(securityState);
    final ids = <int>{};
    for (final row in messages) {
      if (row['id'] is! int ||
          row['conversationId'] is! int ||
          row['username'] is! String ||
          row['content'] is! String ||
          row['timestamp'] is! String ||
          DateTime.tryParse(row['timestamp'] as String) == null ||
          !ids.add(row['id'] as int)) {
        throw const FormatException(
          'Backup contains invalid or duplicate message records.',
        );
      }
    }
  }

  static Map<String, dynamic> migrateMessage(Map<String, dynamic> row) {
    final migrated = Map<String, dynamic>.from(row);
    const aliases = {
      'reply_to_message_content': 'replied_message_content',
      'reply_to_sender_username': 'replied_message_sender_name',
      'group_id': 'media_group_id',
      'recipient_uid': 'media_recipient_uid',
    };
    for (final entry in aliases.entries) {
      if (migrated.containsKey(entry.key)) {
        final value = migrated.remove(entry.key);
        migrated.putIfAbsent(entry.value, () => value);
      }
    }
    return migrated;
  }
}
