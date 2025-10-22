class MomentModel {
  final String id;
  final String userId;
  final String username;
  final String? displayName;
  final String? userAvatarUrl;
  final String mediaType; // 'image' or 'video'
  final String visibility; // 'friends' or 'global'

  // For global moments
  final String? mediaUrl;

  // For friends moments (E2EE)
  final String? encryptedMediaUrl;
  final String? encryptedMediaKey;
  final String? encryptedMediaIv;

  final String? caption;
  final String? thumbnailUrl;
  final DateTime createdAt;
  final DateTime expiresAt;
  final int viewCount;
  final bool viewedByMe;

  MomentModel({
    required this.id,
    required this.userId,
    required this.username,
    this.displayName,
    this.userAvatarUrl,
    required this.mediaType,
    required this.visibility,
    this.mediaUrl,
    this.encryptedMediaUrl,
    this.encryptedMediaKey,
    this.encryptedMediaIv,
    this.caption,
    this.thumbnailUrl,
    required this.createdAt,
    required this.expiresAt,
    required this.viewCount,
    required this.viewedByMe,
  });

  factory MomentModel.fromJson(Map<String, dynamic> json) {
    return MomentModel(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      username: json['username'] as String,
      displayName: json['display_name'] as String?,
      userAvatarUrl: json['user_avatar_url'] as String?,
      mediaType: json['media_type'] as String,
      visibility: json['visibility'] as String,
      mediaUrl: json['media_url'] as String?,
      encryptedMediaUrl: json['encrypted_media_url'] as String?,
      encryptedMediaKey: json['encrypted_media_key'] as String?,
      encryptedMediaIv: json['encrypted_media_iv'] as String?,
      caption: json['caption'] as String?,
      thumbnailUrl: json['thumbnail_url'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      expiresAt: DateTime.parse(json['expires_at'] as String),
      viewCount: json['view_count'] as int? ?? 0,
      viewedByMe: json['viewed_by_me'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'username': username,
      'display_name': displayName,
      'user_avatar_url': userAvatarUrl,
      'media_type': mediaType,
      'visibility': visibility,
      'media_url': mediaUrl,
      'encrypted_media_url': encryptedMediaUrl,
      'encrypted_media_key': encryptedMediaKey,
      'encrypted_media_iv': encryptedMediaIv,
      'caption': caption,
      'thumbnail_url': thumbnailUrl,
      'created_at': createdAt.toIso8601String(),
      'expires_at': expiresAt.toIso8601String(),
      'view_count': viewCount,
      'viewed_by_me': viewedByMe,
    };
  }

  // Get time remaining until expiry
  Duration get timeRemaining => expiresAt.difference(DateTime.now());

  // Check if moment is expired
  bool get isExpired => DateTime.now().isAfter(expiresAt);

  // Get human-readable time ago (e.g., "2h ago", "23h ago")
  String get timeAgo {
    final diff = DateTime.now().difference(createdAt);
    if (diff.inHours < 1) {
      return '${diff.inMinutes}m ago';
    } else if (diff.inHours < 24) {
      return '${diff.inHours}h ago';
    } else {
      return '${diff.inDays}d ago';
    }
  }
}

class MomentViewer {
  final String userId;
  final String username;
  final String? displayName;
  final String? userAvatarUrl;
  final DateTime viewedAt;

  MomentViewer({
    required this.userId,
    required this.username,
    this.displayName,
    this.userAvatarUrl,
    required this.viewedAt,
  });

  factory MomentViewer.fromJson(Map<String, dynamic> json) {
    return MomentViewer(
      userId: json['user_id'] as String,
      username: json['username'] as String,
      displayName: json['display_name'] as String?,
      userAvatarUrl: json['user_avatar_url'] as String?,
      viewedAt: DateTime.parse(json['viewed_at'] as String),
    );
  }
}
