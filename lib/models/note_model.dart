class Note {
  final int? id;
  final String title;
  final String content;
  final String? category;
  final bool isPinned;
  final bool isLocked;
  final String? flowchartJson; // JSON representation of flowchart
  final DateTime createdAt;
  final DateTime updatedAt;

  Note({
    this.id,
    required this.title,
    required this.content,
    this.category,
    this.isPinned = false,
    this.isLocked = false,
    this.flowchartJson,
    required this.createdAt,
    required this.updatedAt,
  });

  // Convert Note to Map for database
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'content': content,
      'category': category,
      'is_pinned': isPinned ? 1 : 0,
      'is_locked': isLocked ? 1 : 0,
      'flowchart_json': flowchartJson,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  // Create Note from Map
  factory Note.fromMap(Map<String, dynamic> map) {
    return Note(
      id: map['id'] as int?,
      title: map['title'] as String,
      content: map['content'] as String,
      category: map['category'] as String?,
      isPinned: (map['is_pinned'] as int) == 1,
      isLocked: (map['is_locked'] as int?) == 1,
      flowchartJson: map['flowchart_json'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
    );
  }

  // Copy with method for updates
  Note copyWith({
    int? id,
    String? title,
    String? content,
    String? category,
    bool? isPinned,
    bool? isLocked,
    String? flowchartJson,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Note(
      id: id ?? this.id,
      title: title ?? this.title,
      content: content ?? this.content,
      category: category ?? this.category,
      isPinned: isPinned ?? this.isPinned,
      isLocked: isLocked ?? this.isLocked,
      flowchartJson: flowchartJson ?? this.flowchartJson,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  String toString() {
    return 'Note{id: $id, title: $title, category: $category, isPinned: $isPinned}';
  }
}

class NoteCategory {
  final int? id;
  final String name;
  final String? colorCode; // Hex color code for UI (e.g., "#FF5722")
  final DateTime createdAt;

  NoteCategory({
    this.id,
    required this.name,
    this.colorCode,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'color_code': colorCode,
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory NoteCategory.fromMap(Map<String, dynamic> map) {
    return NoteCategory(
      id: map['id'] as int?,
      name: map['name'] as String,
      colorCode: map['color_code'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }

  @override
  String toString() {
    return 'NoteCategory{id: $id, name: $name}';
  }
}
