import 'deadline.dart';

enum TodoNodeStatus { active, completed, abandoned }

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
    this.scheduledStart,
    this.completedAt,
    this.abandonedAt,
    this.deletedAt,
    this.isArchived = false,
    this.isEventArchived = false,
    this.eventHue,
  });

  final String id;
  final String? parentId;
  final String title;
  final String notes;
  final Deadline? deadline;
  final DateTime? scheduledStart;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? completedAt;
  final DateTime? abandonedAt;
  final DateTime? deletedAt;
  final int manualOrder;
  final bool isArchived;
  final bool isEventArchived;
  final double? eventHue;

  bool get isDeleted => deletedAt != null;
  bool get isAbandoned => abandonedAt != null;
  TodoNodeStatus get status => abandonedAt != null
      ? TodoNodeStatus.abandoned
      : completedAt != null
      ? TodoNodeStatus.completed
      : TodoNodeStatus.active;

  TodoNode copyWith({
    String? parentId,
    bool clearParentId = false,
    String? title,
    String? notes,
    Deadline? deadline,
    bool clearDeadline = false,
    DateTime? scheduledStart,
    bool clearScheduledStart = false,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? completedAt,
    bool clearCompletedAt = false,
    DateTime? abandonedAt,
    bool clearAbandonedAt = false,
    DateTime? deletedAt,
    int? manualOrder,
    bool? isArchived,
    bool? isEventArchived,
    double? eventHue,
  }) {
    return TodoNode(
      id: id,
      parentId: clearParentId ? null : (parentId ?? this.parentId),
      title: title ?? this.title,
      notes: notes ?? this.notes,
      deadline: clearDeadline ? null : (deadline ?? this.deadline),
      scheduledStart: clearScheduledStart
          ? null
          : (scheduledStart ?? this.scheduledStart),
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      completedAt: clearCompletedAt ? null : (completedAt ?? this.completedAt),
      abandonedAt: clearAbandonedAt ? null : (abandonedAt ?? this.abandonedAt),
      deletedAt: deletedAt ?? this.deletedAt,
      manualOrder: manualOrder ?? this.manualOrder,
      isArchived: isArchived ?? this.isArchived,
      isEventArchived: isEventArchived ?? this.isEventArchived,
      eventHue: eventHue ?? this.eventHue,
    );
  }

  Map<String, Object?> toMap() => <String, Object?>{
    'id': id,
    'parent_id': parentId,
    'title': title,
    'notes': notes,
    'deadline_date': deadline?.storage.date,
    'deadline_at': deadline?.storage.instantMilliseconds,
    'scheduled_start_at': scheduledStart?.toUtc().millisecondsSinceEpoch,
    'created_at': createdAt.toUtc().millisecondsSinceEpoch,
    'updated_at': updatedAt.toUtc().millisecondsSinceEpoch,
    'completed_at': completedAt?.toUtc().millisecondsSinceEpoch,
    'abandoned_at': abandonedAt?.toUtc().millisecondsSinceEpoch,
    'deleted_at': deletedAt?.toUtc().millisecondsSinceEpoch,
    'manual_order': manualOrder,
    'is_archived': isArchived ? 1 : 0,
    'is_event_archived': isEventArchived ? 1 : 0,
    'event_hue': eventHue,
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
      deadline: Deadline.fromStorage(
        date: map['deadline_date'] as String?,
        instantMilliseconds: map['deadline_at'] as int?,
      ),
      createdAt: nullableDate('created_at')!,
      updatedAt: nullableDate('updated_at')!,
      completedAt: nullableDate('completed_at'),
      scheduledStart: nullableDate('scheduled_start_at'),
      abandonedAt: nullableDate('abandoned_at'),
      deletedAt: nullableDate('deleted_at'),
      manualOrder: map['manual_order']! as int,
      isArchived: map['is_archived'] == 1,
      isEventArchived: map['is_event_archived'] == 1,
      eventHue: (map['event_hue'] as num?)?.toDouble(),
    );
  }
}
