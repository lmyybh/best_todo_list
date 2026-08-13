class TodoNode {
  const TodoNode({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    required this.manualOrder,
    this.notes = '',
    this.parentId,
    this.deadline,
    this.completedAt,
    this.deletedAt,
  });

  final String id;
  final String? parentId;
  final String title;
  final String notes;
  final DateTime? deadline;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? completedAt;
  final DateTime? deletedAt;
  final int manualOrder;

  bool get isDeleted => deletedAt != null;

  TodoNode copyWith({
    String? parentId,
    bool clearParentId = false,
    String? title,
    String? notes,
    DateTime? deadline,
    bool clearDeadline = false,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? completedAt,
    bool clearCompletedAt = false,
    DateTime? deletedAt,
    bool clearDeletedAt = false,
    int? manualOrder,
  }) {
    return TodoNode(
      id: id,
      parentId: clearParentId ? null : (parentId ?? this.parentId),
      title: title ?? this.title,
      notes: notes ?? this.notes,
      deadline: clearDeadline ? null : (deadline ?? this.deadline),
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      completedAt: clearCompletedAt ? null : (completedAt ?? this.completedAt),
      deletedAt: clearDeletedAt ? null : (deletedAt ?? this.deletedAt),
      manualOrder: manualOrder ?? this.manualOrder,
    );
  }

  Map<String, Object?> toMap() => <String, Object?>{
    'id': id,
    'parent_id': parentId,
    'title': title,
    'notes': notes,
    'deadline': deadline?.toUtc().millisecondsSinceEpoch,
    'created_at': createdAt.toUtc().millisecondsSinceEpoch,
    'updated_at': updatedAt.toUtc().millisecondsSinceEpoch,
    'completed_at': completedAt?.toUtc().millisecondsSinceEpoch,
    'deleted_at': deletedAt?.toUtc().millisecondsSinceEpoch,
    'manual_order': manualOrder,
  };

  factory TodoNode.fromMap(Map<String, Object?> map) {
    DateTime? nullableDate(String key) {
      final value = map[key] as int?;
      return value == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(value, isUtc: true);
    }

    return TodoNode(
      id: map['id']! as String,
      parentId: map['parent_id'] as String?,
      title: map['title']! as String,
      notes: map['notes'] as String? ?? '',
      deadline: nullableDate('deadline'),
      createdAt: nullableDate('created_at')!,
      updatedAt: nullableDate('updated_at')!,
      completedAt: nullableDate('completed_at'),
      deletedAt: nullableDate('deleted_at'),
      manualOrder: map['manual_order']! as int,
    );
  }
}
