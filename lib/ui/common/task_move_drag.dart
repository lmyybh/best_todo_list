import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/app_controller.dart';
import '../../app/node_persistence_workspace.dart';
import '../../app/node_write_result.dart';
import '../../domain/todo_node.dart';

class TaskMoveDragData {
  TaskMoveDragData(this.nodeId);

  final String nodeId;
  bool canceled = false;
}

class _TaskMoveDragSession {
  static TaskMoveDragData? active;

  static void start(TaskMoveDragData data) {
    active = data;
    HardwareKeyboard.instance.addHandler(_handleKeyEvent);
  }

  static void finish() {
    active = null;
    HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
  }

  static bool _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent ||
        event.logicalKey != LogicalKeyboardKey.escape ||
        active == null) {
      return false;
    }
    active!.canceled = true;
    return true;
  }
}

class TaskMoveDragHandle extends StatelessWidget {
  const TaskMoveDragHandle({
    required this.node,
    required this.child,
    this.enabled = true,
    super.key,
  });

  final TodoNode node;
  final Widget child;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    if (!enabled) return child;
    final data = TaskMoveDragData(node.id);
    return Draggable<TaskMoveDragData>(
      data: data,
      rootOverlay: true,
      dragAnchorStrategy: pointerDragAnchorStrategy,
      onDragStarted: () => _TaskMoveDragSession.start(data),
      onDragEnd: (_) => _TaskMoveDragSession.finish(),
      feedback: Material(
        color: Theme.of(context).colorScheme.surface,
        elevation: 10,
        shadowColor: Colors.black26,
        borderRadius: BorderRadius.circular(8),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 260),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Icon(Icons.drag_indicator, size: 16),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    node.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.35, child: child),
      child: child,
    );
  }
}

class TaskMoveDropTarget extends StatelessWidget {
  const TaskMoveDropTarget({
    required this.controller,
    required this.parentId,
    required this.child,
    this.borderRadius = const BorderRadius.all(Radius.circular(8)),
    super.key,
  });

  final AppController controller;
  final String parentId;
  final Widget child;
  final BorderRadius borderRadius;

  @override
  Widget build(BuildContext context) => DragTarget<TaskMoveDragData>(
    onWillAcceptWithDetails: (details) =>
        _canMoveTo(
          controller,
          nodeId: details.data.nodeId,
          newParentId: parentId,
        ) &&
        !details.data.canceled,
    onAcceptWithDetails: (details) {
      if (details.data.canceled) return;
      unawaited(
        _moveTo(
          context,
          controller,
          nodeId: details.data.nodeId,
          newParentId: parentId,
        ),
      );
    },
    builder: (context, candidates, _) => Stack(
      fit: StackFit.passthrough,
      children: <Widget>[
        child,
        Positioned.fill(
          child: IgnorePointer(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              decoration: BoxDecoration(
                color: candidates.isEmpty
                    ? Colors.transparent
                    : Theme.of(
                        context,
                      ).colorScheme.primary.withValues(alpha: 0.08),
                borderRadius: borderRadius,
                border: candidates.isEmpty
                    ? null
                    : Border.all(
                        color: Theme.of(context).colorScheme.primary,
                        width: 1.5,
                      ),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

enum _TaskMovePlacement { before, inside, after }

class TaskMoveRowDropTarget extends StatefulWidget {
  const TaskMoveRowDropTarget({
    required this.controller,
    required this.target,
    required this.child,
    super.key,
  });

  final AppController controller;
  final TodoNode target;
  final Widget child;

  @override
  State<TaskMoveRowDropTarget> createState() => _TaskMoveRowDropTargetState();
}

class _TaskMoveRowDropTargetState extends State<TaskMoveRowDropTarget> {
  _TaskMovePlacement placement = _TaskMovePlacement.inside;

  _TaskMovePlacement _placementAt(Offset globalPosition) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || box.size.height == 0) {
      return _TaskMovePlacement.inside;
    }
    final dy = box.globalToLocal(globalPosition).dy;
    if (dy < box.size.height * 0.25) return _TaskMovePlacement.before;
    if (dy > box.size.height * 0.75) return _TaskMovePlacement.after;
    return _TaskMovePlacement.inside;
  }

  ({String? parentId, int? index}) _destination(
    TaskMoveDragData data,
    _TaskMovePlacement nextPlacement,
  ) {
    if (nextPlacement == _TaskMovePlacement.inside) {
      return (parentId: widget.target.id, index: null);
    }
    final tree = widget.controller.tree;
    final siblings = tree.childrenOf(widget.target.parentId);
    var index = siblings.indexWhere((node) => node.id == widget.target.id);
    if (nextPlacement == _TaskMovePlacement.after) index++;
    final source = tree.nodes[data.nodeId];
    final sourceIndex = source?.parentId == widget.target.parentId
        ? siblings.indexWhere((node) => node.id == data.nodeId)
        : -1;
    if (sourceIndex >= 0 && sourceIndex < index) index--;
    return (parentId: widget.target.parentId, index: index);
  }

  bool _canAccept(TaskMoveDragData data, Offset globalPosition) {
    if (data.canceled) return false;
    final nextPlacement = _placementAt(globalPosition);
    placement = nextPlacement;
    final destination = _destination(data, nextPlacement);
    return _canMoveTo(
      widget.controller,
      nodeId: data.nodeId,
      newParentId: destination.parentId,
    );
  }

  @override
  Widget build(BuildContext context) => DragTarget<TaskMoveDragData>(
    onWillAcceptWithDetails: (details) =>
        _canAccept(details.data, details.offset),
    onMove: (details) {
      final nextPlacement = _placementAt(details.offset);
      if (nextPlacement != placement) setState(() => placement = nextPlacement);
    },
    onLeave: (_) => placement = _TaskMovePlacement.inside,
    onAcceptWithDetails: (details) {
      if (details.data.canceled) return;
      final destination = _destination(
        details.data,
        _placementAt(details.offset),
      );
      placement = _TaskMovePlacement.inside;
      unawaited(
        _moveTo(
          context,
          widget.controller,
          nodeId: details.data.nodeId,
          newParentId: destination.parentId,
          newIndex: destination.index,
        ),
      );
    },
    builder: (context, candidates, _) {
      final targeted = candidates.isNotEmpty;
      final primary = Theme.of(context).colorScheme.primary;
      return Stack(
        fit: StackFit.passthrough,
        children: <Widget>[
          widget.child,
          if (targeted)
            Positioned.fill(
              child: IgnorePointer(
                child: placement == _TaskMovePlacement.inside
                    ? DecoratedBox(
                        decoration: BoxDecoration(
                          color: primary.withValues(alpha: 0.08),
                          border: Border.all(color: primary, width: 1.5),
                          borderRadius: BorderRadius.circular(8),
                        ),
                      )
                    : Align(
                        alignment: placement == _TaskMovePlacement.before
                            ? Alignment.topCenter
                            : Alignment.bottomCenter,
                        child: Container(
                          height: 2,
                          decoration: BoxDecoration(
                            color: primary,
                            borderRadius: BorderRadius.circular(1),
                          ),
                        ),
                      ),
              ),
            ),
        ],
      );
    },
  );
}

bool _canMoveTo(
  AppController controller, {
  required String nodeId,
  required String? newParentId,
}) {
  final tree = controller.tree;
  final node = tree.nodes[nodeId];
  if (node == null || nodeId == newParentId) {
    return false;
  }
  return newParentId == null ||
      !tree.isDescendant(nodeId: newParentId, ancestorId: nodeId);
}

Future<void> _moveTo(
  BuildContext context,
  AppController controller, {
  required String nodeId,
  required String? newParentId,
  int? newIndex,
}) async {
  final result = await controller.move(
    nodeId: nodeId,
    newParentId: newParentId,
    newIndex: newIndex,
  );
  if (!context.mounted || result is NodeWriteSuccess<void>) return;
  final error = (result as NodeWriteFailure<void>).error;
  final message = error is NodeRuleException ? error.message : '移动失败，请重试';
  ScaffoldMessenger.maybeOf(
    context,
  )?.showSnackBar(SnackBar(content: Text(message)));
}
