import 'package:flutter/foundation.dart';

import '../../app/node_write_result.dart';
import '../../domain/todo_node.dart';

typedef CreateInlineTask =
    Future<NodeWriteResult<TodoNode>> Function(String parentId, String title);
typedef RenameInlineTask =
    Future<NodeWriteResult<void>> Function(String nodeId, String title);

class EventCardEditingSession extends ChangeNotifier {
  factory EventCardEditingSession({
    required CreateInlineTask create,
    required RenameInlineTask rename,
    ValueChanged<TodoNode>? onCreated,
  }) => EventCardEditingSession._(create, rename, onCreated);

  EventCardEditingSession._(this._create, this._rename, this._onCreated);

  final CreateInlineTask _create;
  final RenameInlineTask _rename;
  final ValueChanged<TodoNode>? _onCreated;

  String? _draftParentId;
  String _draftText = '';
  bool _draftSubmitting = false;
  int _draftRevision = 0;
  String? _renameNodeId;
  String? _renameOriginalTitle;
  String _renameText = '';
  bool _renameSubmitting = false;
  bool _renameFailed = false;
  int _renameRevision = 0;
  bool _disposed = false;

  String? get draftParentId => _draftParentId;
  String get draftText => _draftText;
  bool get draftSubmitting => _draftSubmitting;
  String? get renameNodeId => _renameNodeId;
  String get renameText => _renameText;
  bool get renameSubmitting => _renameSubmitting;
  bool get renameFailed => _renameFailed;

  void updateDraft(String value) {
    _draftText = value;
  }

  void updateRename(String value) {
    _renameText = value;
    if (_renameFailed) {
      _renameFailed = false;
      _notify();
    }
  }

  Future<bool> openDraft(String parentId) async {
    if (_draftParentId == parentId) return true;
    if (_renameNodeId != null && !await finishRename()) return false;
    if (_draftParentId != null && !await finishDraft()) return false;
    _draftRevision += 1;
    _draftParentId = parentId;
    _draftText = '';
    _notify();
    return true;
  }

  Future<bool> openRename(TodoNode node) async {
    if (_renameNodeId == node.id) return true;
    if (_draftParentId != null && !await finishDraft()) return false;
    if (_renameNodeId != null && !await finishRename()) return false;
    _renameRevision += 1;
    _renameNodeId = node.id;
    _renameOriginalTitle = node.title;
    _renameText = node.title;
    _renameFailed = false;
    _notify();
    return true;
  }

  Future<bool> finishActive() async {
    if (_draftParentId != null && !await finishDraft()) return false;
    if (_renameNodeId != null && !await finishRename()) return false;
    return true;
  }

  Future<bool> finishDraft() async {
    final parentId = _draftParentId;
    if (parentId == null) return true;
    if (_draftSubmitting) return false;
    final title = _draftText.trim();
    if (title.isEmpty) {
      cancelDraft();
      return true;
    }
    _draftSubmitting = true;
    final revision = _draftRevision;
    _notify();
    final result = await _create(parentId, title);
    if (_disposed) return false;
    if (revision != _draftRevision) {
      if (result case NodeWriteSuccess<TodoNode>(:final value)) {
        _onCreated?.call(value);
      }
      return false;
    }
    switch (result) {
      case NodeWriteSuccess<TodoNode>(:final value):
        _onCreated?.call(value);
      case NodeWriteFailure<TodoNode>():
        _draftSubmitting = false;
        _notify();
        return false;
    }
    cancelDraft();
    return true;
  }

  Future<bool> finishRename() async {
    final nodeId = _renameNodeId;
    final originalTitle = _renameOriginalTitle;
    if (nodeId == null || originalTitle == null) return true;
    if (_renameSubmitting) return false;
    final title = _renameText.trim();
    if (title.isEmpty || title == originalTitle) {
      cancelRename();
      return true;
    }
    _renameSubmitting = true;
    _renameFailed = false;
    final revision = _renameRevision;
    _notify();
    final result = await _rename(nodeId, title);
    if (_disposed) return false;
    if (revision != _renameRevision) return false;
    if (result is NodeWriteFailure<void>) {
      _renameSubmitting = false;
      _renameFailed = true;
      _notify();
      return false;
    }
    cancelRename();
    return true;
  }

  void cancelDraft() {
    if (_draftParentId == null) return;
    _draftRevision += 1;
    _draftParentId = null;
    _draftText = '';
    _draftSubmitting = false;
    _notify();
  }

  void cancelRename() {
    if (_renameNodeId == null) return;
    _renameRevision += 1;
    _renameNodeId = null;
    _renameOriginalTitle = null;
    _renameText = '';
    _renameSubmitting = false;
    _renameFailed = false;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
