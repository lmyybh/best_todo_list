import 'package:flutter/foundation.dart';

class EventBoardReorderSession {
  String? _draggedId;
  List<String>? _startIds;
  List<String>? _orderedIds;
  bool _canceled = false;

  bool get active => _draggedId != null;
  List<String>? get orderedIds =>
      _orderedIds == null ? null : List<String>.unmodifiable(_orderedIds!);

  void start(String draggedId, List<String> orderedIds) {
    _draggedId = draggedId;
    _startIds = List<String>.of(orderedIds);
    _orderedIds = List<String>.of(orderedIds);
    _canceled = false;
  }

  bool previewAround(String targetId, {required bool after}) {
    final draggedId = _draggedId;
    final current = _orderedIds;
    if (draggedId == null || current == null || draggedId == targetId) {
      return false;
    }
    final next = List<String>.of(current)..remove(draggedId);
    final targetIndex = next.indexOf(targetId);
    if (targetIndex < 0) return false;
    next.insert(targetIndex + (after ? 1 : 0), draggedId);
    if (listEquals(next, current)) return false;
    _orderedIds = next;
    return true;
  }

  bool previewAtEnd() {
    final draggedId = _draggedId;
    final current = _orderedIds;
    if (draggedId == null || current == null) return false;
    final next = List<String>.of(current)
      ..remove(draggedId)
      ..add(draggedId);
    if (listEquals(next, current)) return false;
    _orderedIds = next;
    return true;
  }

  void cancel() {
    if (!active) return;
    _canceled = true;
    _orderedIds = _startIds == null ? null : List<String>.of(_startIds!);
  }

  List<String>? reorderFromKeyboard({
    required String id,
    required int direction,
    required bool toEdge,
    required List<String> orderedIds,
  }) {
    final oldIndex = orderedIds.indexOf(id);
    if (oldIndex < 0) return null;
    final newIndex = toEdge
        ? (direction < 0 ? 0 : orderedIds.length - 1)
        : (oldIndex + direction).clamp(0, orderedIds.length - 1);
    if (newIndex == oldIndex) return null;
    return List<String>.of(orderedIds)
      ..removeAt(oldIndex)
      ..insert(newIndex, id);
  }

  List<String>? finish({required bool droppedInside}) {
    final orderedIds = _orderedIds;
    final startIds = _startIds;
    final result =
        !_canceled &&
            droppedInside &&
            orderedIds != null &&
            startIds != null &&
            !listEquals(orderedIds, startIds)
        ? List<String>.unmodifiable(orderedIds)
        : null;
    _clear();
    return result;
  }

  void _clear() {
    _draggedId = null;
    _startIds = null;
    _orderedIds = null;
    _canceled = false;
  }
}
