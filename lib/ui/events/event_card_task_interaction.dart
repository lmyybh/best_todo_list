import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/app_controller.dart';
import '../../app/node_write_result.dart';
import '../../app/app_theme.dart';
import '../../domain/node_tree.dart';
import '../../domain/todo_node.dart';
import '../common/delete_node.dart';
import '../common/formatters.dart';
import '../common/task_move_drag.dart';
import 'event_card_editing_session.dart';

const int _maximumPreviewDepth = 2;
const Duration _scrollHandoffIdleDuration = Duration(milliseconds: 200);

class EventCardTaskInteraction extends StatefulWidget {
  const EventCardTaskInteraction({
    required this.controller,
    required this.rootEventId,
    super.key,
  });

  final AppController controller;
  final String rootEventId;

  @override
  State<EventCardTaskInteraction> createState() =>
      _EventCardTaskInteractionState();
}

class _EventCardTaskInteractionState extends State<EventCardTaskInteraction> {
  final Set<String> collapsedIds = <String>{};
  final Set<String> expandedBeyondPreviewIds = <String>{};
  final ScrollController treeScrollController = ScrollController();
  final TextEditingController inlineDraftController = TextEditingController();
  final TextEditingController inlineRenameController = TextEditingController();
  final GlobalKey inlineDraftKey = GlobalKey();
  final GlobalKey treeViewportKey = GlobalKey();
  late final EventCardEditingSession editingSession;
  late final FocusNode inlineDraftFocusNode = FocusNode(
    debugLabel: 'event-inline-task-draft',
  )..addListener(_handleInlineDraftFocusChange);
  late final FocusNode inlineRenameFocusNode = FocusNode(
    debugLabel: 'event-inline-task-rename',
  )..addListener(_handleInlineRenameFocusChange);
  Timer? highlightTimer;
  Timer? scrollHandoffTimer;
  String? highlightedId;
  int? guardedScrollDirection;

  @override
  void initState() {
    super.initState();
    editingSession = EventCardEditingSession(
      create: (parentId, title) => widget.controller.create(
        parentId: parentId,
        title: title,
        selectCreated: false,
      ),
      rename: (nodeId, title) => widget.controller.updateTitle(nodeId, title),
      onCreated: (node) => highlightCreated(node.id),
    )..addListener(_handleEditingChanged);
  }

  void _handleEditingChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    highlightTimer?.cancel();
    scrollHandoffTimer?.cancel();
    editingSession.removeListener(_handleEditingChanged);
    editingSession.dispose();
    inlineDraftFocusNode.removeListener(_handleInlineDraftFocusChange);
    inlineDraftFocusNode.dispose();
    inlineDraftController.dispose();
    inlineRenameFocusNode.removeListener(_handleInlineRenameFocusChange);
    inlineRenameFocusNode.dispose();
    inlineRenameController.dispose();
    treeScrollController.dispose();
    super.dispose();
  }

  void _handleTreePointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent ||
        !treeScrollController.hasClients ||
        event.scrollDelta.dy == 0) {
      return;
    }
    final position = treeScrollController.position;
    final direction = event.scrollDelta.dy.sign.toInt();
    final atBoundary = direction > 0
        ? position.pixels >= position.maxScrollExtent
        : position.pixels <= position.minScrollExtent;

    if (guardedScrollDirection == direction && atBoundary) {
      _guardScrollBoundary(direction);
      GestureBinding.instance.pointerSignalResolver.register(event, (
        resolvedEvent,
      ) {
        if (resolvedEvent is PointerScrollEvent) {
          resolvedEvent.respond(allowPlatformDefault: false);
        }
      });
      return;
    }
    if (guardedScrollDirection != null && guardedScrollDirection != direction) {
      _clearScrollBoundaryGuard();
    }
    if (atBoundary) return;

    final target = (position.pixels + event.scrollDelta.dy).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    final reachesBoundary = direction > 0
        ? target >= position.maxScrollExtent
        : target <= position.minScrollExtent;
    if (reachesBoundary) _guardScrollBoundary(direction);
  }

  void _guardScrollBoundary(int direction) {
    guardedScrollDirection = direction;
    scrollHandoffTimer?.cancel();
    scrollHandoffTimer = Timer(
      _scrollHandoffIdleDuration,
      _clearScrollBoundaryGuard,
    );
  }

  void _clearScrollBoundaryGuard() {
    guardedScrollDirection = null;
    scrollHandoffTimer?.cancel();
    scrollHandoffTimer = null;
  }

  void _handleInlineDraftFocusChange() {
    if (inlineDraftFocusNode.hasFocus ||
        editingSession.draftParentId == null ||
        editingSession.draftSubmitting) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted &&
          !inlineDraftFocusNode.hasFocus &&
          editingSession.draftParentId != null &&
          !editingSession.draftSubmitting) {
        unawaited(_finishInlineDraft());
      }
    });
  }

  Future<void> _openInlineDraft(String parentId) async {
    if (editingSession.draftParentId == parentId) {
      inlineDraftFocusNode.requestFocus();
      return;
    }
    _syncEditingText();
    if (!await editingSession.openDraft(parentId) || !mounted) return;
    inlineDraftController.text = editingSession.draftText;
    setState(() {
      collapsedIds.remove(parentId);
      expandedBeyondPreviewIds.add(parentId);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || editingSession.draftParentId != parentId) return;
      inlineDraftFocusNode.requestFocus();
      _revealInlineDraft();
    });
  }

  void _revealInlineDraft() {
    if (!treeScrollController.hasClients) return;
    final draftBox =
        inlineDraftKey.currentContext?.findRenderObject() as RenderBox?;
    final viewportBox =
        treeViewportKey.currentContext?.findRenderObject() as RenderBox?;
    if (draftBox == null || viewportBox == null) return;
    final draftRect = MatrixUtils.transformRect(
      draftBox.getTransformTo(viewportBox),
      Offset.zero & draftBox.size,
    );
    final delta = draftRect.bottom > viewportBox.size.height
        ? draftRect.bottom - viewportBox.size.height
        : draftRect.top < 0
        ? draftRect.top
        : 0.0;
    if (delta == 0) return;
    final position = treeScrollController.position;
    final target = (position.pixels + delta).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    unawaited(
      treeScrollController.animateTo(
        target,
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 150),
        curve: Curves.easeOut,
      ),
    );
  }

  void _revealInlineDraftAfterLayout() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && editingSession.draftParentId != null) {
        _revealInlineDraft();
      }
    });
  }

  Future<void> _finishInlineDraft() async {
    editingSession.updateDraft(inlineDraftController.text);
    final finished = await editingSession.finishDraft();
    if (!mounted) return;
    if (!finished) {
      if (editingSession.draftParentId != null) {
        inlineDraftFocusNode.requestFocus();
      }
      return;
    }
    inlineDraftController.clear();
    inlineDraftFocusNode.unfocus();
  }

  void _closeInlineDraft() {
    if (editingSession.draftParentId == null) return;
    editingSession.cancelDraft();
    inlineDraftController.clear();
    inlineDraftFocusNode.unfocus();
  }

  void _handleInlineRenameFocusChange() {
    if (inlineRenameFocusNode.hasFocus ||
        editingSession.renameNodeId == null ||
        editingSession.renameSubmitting) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted &&
          !inlineRenameFocusNode.hasFocus &&
          editingSession.renameNodeId != null &&
          !editingSession.renameSubmitting) {
        unawaited(_finishInlineRename());
      }
    });
  }

  Future<void> _openInlineRename(TodoNode node) async {
    if (editingSession.renameNodeId == node.id) {
      inlineRenameFocusNode.requestFocus();
      return;
    }
    _syncEditingText();
    if (!await editingSession.openRename(node) || !mounted) return;
    inlineDraftController.clear();
    inlineRenameController.text = editingSession.renameText;
    inlineRenameController.selection = TextSelection(
      baseOffset: 0,
      extentOffset: editingSession.renameText.length,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && editingSession.renameNodeId == node.id) {
        inlineRenameFocusNode.requestFocus();
      }
    });
  }

  Future<void> _finishInlineRename() async {
    editingSession.updateRename(inlineRenameController.text);
    final finished = await editingSession.finishRename();
    if (!mounted) return;
    if (!finished) {
      if (editingSession.renameNodeId != null) {
        inlineRenameFocusNode.requestFocus();
      }
      return;
    }
    inlineRenameController.clear();
    inlineRenameFocusNode.unfocus();
  }

  void _closeInlineRename() {
    if (editingSession.renameNodeId == null) return;
    editingSession.cancelRename();
    inlineRenameController.clear();
    inlineRenameFocusNode.unfocus();
  }

  Future<void> _deleteTaskNode(TodoNode node) async {
    _syncEditingText();
    if (!await editingSession.finishActive() || !mounted) return;
    inlineDraftController.clear();
    inlineRenameController.clear();
    await confirmDeleteNode(context, widget.controller, node);
  }

  Future<void> _abandonTaskNode(TodoNode node) async {
    _syncEditingText();
    if (!await editingSession.finishActive() || !mounted) return;
    inlineDraftController.clear();
    inlineRenameController.clear();
    final result = await widget.controller.setTaskStatus(
      node.id,
      TodoNodeStatus.abandoned,
    );
    if (!mounted || result is NodeWriteFailure) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('任务已放弃'),
        action: SnackBarAction(
          label: '撤销',
          onPressed: () =>
              widget.controller.setTaskStatus(node.id, TodoNodeStatus.active),
        ),
      ),
    );
  }

  void _syncEditingText() {
    if (editingSession.draftParentId != null) {
      editingSession.updateDraft(inlineDraftController.text);
    }
    if (editingSession.renameNodeId != null) {
      editingSession.updateRename(inlineRenameController.text);
    }
  }

  void highlightCreated(String nodeId) {
    highlightTimer?.cancel();
    setState(() => highlightedId = nodeId);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || highlightedId != nodeId) return;
      final created = widget.controller.tree.nodes[nodeId];
      if (created?.parentId != widget.rootEventId ||
          !treeScrollController.hasClients) {
        return;
      }
      unawaited(
        treeScrollController.animateTo(
          treeScrollController.position.maxScrollExtent,
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 180),
          curve: Curves.easeOut,
        ),
      );
    });
    highlightTimer = Timer(const Duration(milliseconds: 900), () {
      if (mounted) setState(() => highlightedId = null);
    });
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) => _buildContent(context),
  );

  Widget _buildContent(BuildContext context) {
    final controller = widget.controller;
    final tree = controller.tree;
    final children = tree.visibleChildrenOf(widget.rootEventId);
    final colors = AppColors.of(context);
    final interaction = _EventTaskTreeInteraction(
      controller: controller,
      tree: tree,
      collapsedIds: collapsedIds,
      expandedBeyondPreviewIds: expandedBeyondPreviewIds,
      highlightedId: highlightedId,
      inlineDraftParentId: editingSession.draftParentId,
      inlineRenameNodeId: editingSession.renameNodeId,
      inlineDraftBuilder: (depth) => _InlineTaskDraftRow(
        key: inlineDraftKey,
        depth: depth,
        controller: inlineDraftController,
        focusNode: inlineDraftFocusNode,
        submitting: editingSession.draftSubmitting,
        onChanged: editingSession.updateDraft,
        onSubmit: _finishInlineDraft,
        onCancel: _closeInlineDraft,
        onRevealed: _revealInlineDraftAfterLayout,
      ),
      inlineRenameBuilder: (node) => _InlineTaskRenameField(
        nodeId: node.id,
        controller: inlineRenameController,
        focusNode: inlineRenameFocusNode,
        submitting: editingSession.renameSubmitting,
        failed: editingSession.renameFailed,
        onChanged: editingSession.updateRename,
        fontWeight: tree.childrenOf(node.id).isEmpty
            ? FontWeight.w500
            : FontWeight.w600,
        onSubmit: _finishInlineRename,
        onCancel: _closeInlineRename,
      ),
      onCreateChild: (parentId) => unawaited(_openInlineDraft(parentId)),
      onRename: (task) => unawaited(_openInlineRename(task)),
      onDelete: (task) => unawaited(_deleteTaskNode(task)),
      onAbandon: (task) => unawaited(_abandonTaskNode(task)),
      onToggleExpanded: (nodeId, depth) => setState(() {
        if (depth >= _maximumPreviewDepth &&
            !expandedBeyondPreviewIds.contains(nodeId)) {
          expandedBeyondPreviewIds.add(nodeId);
          collapsedIds.remove(nodeId);
        } else if (!collapsedIds.add(nodeId)) {
          collapsedIds.remove(nodeId);
        }
      }),
    );
    return Column(
      children: <Widget>[
        Expanded(
          child: TaskMoveDropTarget(
            key: ValueKey<String>('event-list-drop-${widget.rootEventId}'),
            controller: controller,
            parentId: widget.rootEventId,
            child: children.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(18),
                    child: Align(
                      alignment: Alignment.topLeft,
                      child: Text(
                        '还没有子任务',
                        style: TextStyle(color: colors.faint, fontSize: 11),
                      ),
                    ),
                  )
                : Builder(
                    builder: (context) {
                      return KeyedSubtree(
                        key: treeViewportKey,
                        child: Listener(
                          onPointerSignal: _handleTreePointerSignal,
                          child: Scrollbar(
                            key: ValueKey<String>(
                              'event-tree-scrollbar-${widget.rootEventId}',
                            ),
                            controller: treeScrollController,
                            thumbVisibility: true,
                            interactive: true,
                            radius: const Radius.circular(4),
                            child: _EventTaskGroup(
                              key: ValueKey<String>(
                                'event-tree-scroll-${widget.rootEventId}',
                              ),
                              interaction: interaction,
                              parentId: widget.rootEventId,
                              depth: 0,
                              scrollController: treeScrollController,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ),
        _CardQuickAdd(
          controller: controller,
          parentId: widget.rootEventId,
          onCreated: highlightCreated,
        ),
      ],
    );
  }
}

class _EventTaskTreeInteraction {
  const _EventTaskTreeInteraction({
    required this.controller,
    required this.tree,
    required this._collapsedIds,
    required this._expandedBeyondPreviewIds,
    required this._highlightedId,
    required this._inlineDraftParentId,
    required this._inlineRenameNodeId,
    required this._inlineDraftBuilder,
    required this._inlineRenameBuilder,
    required this._onCreateChild,
    required this._onRename,
    required this._onDelete,
    required this._onAbandon,
    required this._onToggleExpanded,
  });

  final AppController controller;
  final NodeTree tree;
  final Set<String> _collapsedIds;
  final Set<String> _expandedBeyondPreviewIds;
  final String? _highlightedId;
  final String? _inlineDraftParentId;
  final String? _inlineRenameNodeId;
  final Widget Function(int depth) _inlineDraftBuilder;
  final Widget Function(TodoNode node) _inlineRenameBuilder;
  final ValueChanged<String> _onCreateChild;
  final ValueChanged<TodoNode> _onRename;
  final ValueChanged<TodoNode> _onDelete;
  final ValueChanged<TodoNode> _onAbandon;
  final void Function(String nodeId, int depth) _onToggleExpanded;

  bool isExpanded(String nodeId, int depth) =>
      !_collapsedIds.contains(nodeId) &&
      (depth < _maximumPreviewDepth ||
          _expandedBeyondPreviewIds.contains(nodeId));

  bool canExpand(TodoNode node) => tree.visibleChildrenOf(node.id).isNotEmpty;

  bool showsChildren(TodoNode node, int depth) =>
      isExpanded(node.id, depth) &&
      (tree.visibleChildrenOf(node.id).isNotEmpty || showsDraft(node.id));

  bool showsDraft(String parentId) => _inlineDraftParentId == parentId;

  bool isHighlighted(String nodeId) => _highlightedId == nodeId;

  bool isRenaming(String nodeId) => _inlineRenameNodeId == nodeId;

  Widget buildDraft(int depth) => _inlineDraftBuilder(depth);

  Widget buildRename(TodoNode node) => _inlineRenameBuilder(node);

  void createChild(String parentId) => _onCreateChild(parentId);

  void rename(TodoNode node) => _onRename(node);

  void delete(TodoNode node) => _onDelete(node);

  void abandon(TodoNode node) => _onAbandon(node);

  void toggleExpanded(String nodeId, int depth) =>
      _onToggleExpanded(nodeId, depth);
}

class _EventTaskGroup extends StatefulWidget {
  const _EventTaskGroup({
    required this.interaction,
    required this.parentId,
    required this.depth,
    this.scrollController,
    super.key,
  });

  final _EventTaskTreeInteraction interaction;
  final String parentId;
  final int depth;
  final ScrollController? scrollController;

  @override
  State<_EventTaskGroup> createState() => _EventTaskGroupState();
}

class _EventTaskGroupState extends State<_EventTaskGroup> {
  @override
  Widget build(BuildContext context) {
    final interaction = widget.interaction;
    final children = interaction.tree.visibleChildrenOf(widget.parentId);
    final showsInlineDraft = interaction.showsDraft(widget.parentId);
    final rootGroup = widget.scrollController != null;
    return ListView.builder(
      controller: widget.scrollController,
      shrinkWrap: !rootGroup,
      physics: rootGroup
          ? const ClampingScrollPhysics()
          : const NeverScrollableScrollPhysics(),
      padding: rootGroup
          ? const EdgeInsets.fromLTRB(10, 9, 16, 4)
          : EdgeInsets.zero,
      itemCount: children.length + (showsInlineDraft ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == children.length) {
          return KeyedSubtree(
            key: ValueKey<String>('event-inline-draft-${widget.parentId}'),
            child: interaction.buildDraft(widget.depth),
          );
        }
        final node = children[index];
        return _EventTreeBranch(
          key: ValueKey<String>('event-task-branch-${node.id}'),
          interaction: interaction,
          node: node,
          depth: widget.depth,
          onKeyboardReorder: (direction, toEdge) {
            final newIndex = toEdge
                ? (direction < 0 ? 0 : children.length - 1)
                : (index + direction).clamp(0, children.length - 1);
            _reorder(children, index, newIndex);
          },
        );
      },
    );
  }

  void _reorder(List<TodoNode> children, int oldIndex, int newIndex) {
    if (newIndex == oldIndex) return;
    final orderedIds = children.map((node) => node.id).toList();
    final movedId = orderedIds.removeAt(oldIndex);
    orderedIds.insert(newIndex.clamp(0, orderedIds.length), movedId);
    unawaited(
      widget.interaction.controller.reorderChildren(
        widget.parentId,
        orderedIds,
      ),
    );
  }
}

class _EventTreeBranch extends StatelessWidget {
  const _EventTreeBranch({
    required this.interaction,
    required this.node,
    required this.depth,
    required this.onKeyboardReorder,
    super.key,
  });

  final _EventTaskTreeInteraction interaction;
  final TodoNode node;
  final int depth;
  final void Function(int direction, bool toEdge) onKeyboardReorder;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: <Widget>[
      _EventTreeRow(
        interaction: interaction,
        node: node,
        depth: depth,
        onKeyboardReorder: onKeyboardReorder,
      ),
      if (interaction.showsChildren(node, depth))
        _EventTaskGroup(
          interaction: interaction,
          parentId: node.id,
          depth: depth + 1,
        ),
    ],
  );
}

class _EventTreeRow extends StatefulWidget {
  const _EventTreeRow({
    required this.interaction,
    required this.node,
    required this.depth,
    required this.onKeyboardReorder,
  });

  final _EventTaskTreeInteraction interaction;
  final TodoNode node;
  final int depth;
  final void Function(int direction, bool toEdge) onKeyboardReorder;

  @override
  State<_EventTreeRow> createState() => _EventTreeRowState();
}

class _EventTreeRowState extends State<_EventTreeRow> {
  final FocusNode focusNode = FocusNode(debugLabel: 'event-task-row');
  bool hovered = false;
  bool focused = false;

  @override
  void initState() {
    super.initState();
    if (widget.interaction.isHighlighted(widget.node.id)) {
      _revealAfterLayout();
    }
  }

  @override
  void didUpdateWidget(covariant _EventTreeRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.interaction.isHighlighted(oldWidget.node.id) &&
        widget.interaction.isHighlighted(widget.node.id)) {
      _revealAfterLayout();
    }
  }

  void _revealAfterLayout() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !widget.interaction.isHighlighted(widget.node.id)) {
        return;
      }
      final scrollable = Scrollable.maybeOf(context);
      final renderObject = context.findRenderObject();
      if (scrollable == null || renderObject == null) return;
      unawaited(
        scrollable.position.ensureVisible(
          renderObject,
          alignment: 0.5,
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 180),
          curve: Curves.easeOut,
        ),
      );
    });
  }

  @override
  void dispose() {
    focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final interaction = widget.interaction;
    final controller = interaction.controller;
    final node = widget.node;
    final tree = interaction.tree;
    final depth = widget.depth;
    final expanded = interaction.isExpanded(node.id, depth);
    final highlighted = interaction.isHighlighted(node.id);
    final renaming = interaction.isRenaming(node.id);
    final onToggleExpanded = interaction.canExpand(node)
        ? () => interaction.toggleExpanded(node.id, depth)
        : null;
    final children = tree.visibleChildrenOf(node.id);
    final isLeaf = tree.isLeaf(node.id);
    final hiddenDescendants = tree
        .descendantsOf(node.id)
        .where((descendant) => !descendant.isAbandoned)
        .length;
    final complete = tree.isComplete(node.id);
    final showActions = (hovered || focused) && !renaming;
    final deleteButtonStyle = ButtonStyle(
      foregroundColor: WidgetStateProperty.resolveWith(
        (states) =>
            states.contains(WidgetState.hovered) ? colors.danger : colors.muted,
      ),
      overlayColor: WidgetStateProperty.resolveWith(
        (states) =>
            states.contains(WidgetState.hovered) ? colors.dangerSoft : null,
      ),
    );
    final row = Focus(
      key: ValueKey<String>('event-row-focus-${node.id}'),
      focusNode: focusNode,
      onFocusChange: (value) => setState(() => focused = value),
      onKeyEvent: (_, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        if (event.logicalKey == LogicalKeyboardKey.f2 && !renaming) {
          interaction.rename(node);
          return KeyEventResult.handled;
        }
        if (renaming || !HardwareKeyboard.instance.isAltPressed) {
          return KeyEventResult.ignored;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
          widget.onKeyboardReorder(
            -1,
            HardwareKeyboard.instance.isShiftPressed,
          );
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
          widget.onKeyboardReorder(1, HardwareKeyboard.instance.isShiftPressed);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => hovered = true),
        onExit: (_) => setState(() => hovered = false),
        child: DecoratedBox(
          key: ValueKey<String>('event-row-surface-${node.id}'),
          decoration: BoxDecoration(
            color: renaming
                ? colors.accentSoft.withValues(alpha: 0.55)
                : highlighted
                ? colors.accentSoft
                : hovered
                ? colors.surfaceHover
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: focused
                ? Border.all(
                    color: Theme.of(
                      context,
                    ).colorScheme.primary.withValues(alpha: 0.45),
                  )
                : null,
          ),
          child: AnimatedOpacity(
            key: ValueKey<String>('event-task-drag-source-${node.id}'),
            opacity: 1,
            duration: const Duration(milliseconds: 90),
            curve: Curves.easeOut,
            child: GestureDetector(
              key: ValueKey<String>('event-row-${node.id}'),
              behavior: HitTestBehavior.opaque,
              onTap: renaming
                  ? null
                  : () {
                      focusNode.requestFocus();
                      controller.select(node.id);
                    },
              child: SizedBox(
                height: 36,
                child: Padding(
                  padding: EdgeInsets.only(left: depth * 20),
                  child: Row(
                    children: <Widget>[
                      SizedBox(
                        width: 18,
                        child: AnimatedOpacity(
                          opacity: renaming
                              ? 0.25
                              : hovered
                              ? 1
                              : 0.45,
                          duration: const Duration(milliseconds: 90),
                          child: IgnorePointer(
                            ignoring: renaming,
                            child: TaskMoveDragHandle(
                              key: ValueKey<String>(
                                'event-task-drag-${node.id}',
                              ),
                              node: node,
                              child: Tooltip(
                                message: '拖动调整位置或层级 · ⌥↑↓ 键盘排序',
                                child: MouseRegion(
                                  cursor: SystemMouseCursors.grab,
                                  child: Icon(
                                    Icons.drag_indicator,
                                    size: 16,
                                    color: colors.muted,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      SizedBox(
                        width: onToggleExpanded == null ? 8 : 18,
                        child: onToggleExpanded == null
                            ? null
                            : IconButton(
                                key: ValueKey<String>(
                                  'event-expand-${node.id}',
                                ),
                                tooltip: expanded ? '折叠' : '展开',
                                padding: EdgeInsets.zero,
                                visualDensity: VisualDensity.compact,
                                onPressed: renaming ? null : onToggleExpanded,
                                icon: Icon(
                                  expanded
                                      ? Icons.keyboard_arrow_down
                                      : Icons.keyboard_arrow_right,
                                  size: 15,
                                  color: colors.faint,
                                ),
                              ),
                      ),
                      InkResponse(
                        key: ValueKey<String>('event-complete-${node.id}'),
                        onTap: isLeaf && !renaming
                            ? () => controller.setTaskStatus(
                                node.id,
                                complete
                                    ? TodoNodeStatus.active
                                    : TodoNodeStatus.completed,
                              )
                            : null,
                        radius: 16,
                        child: Container(
                          width: isLeaf ? 15 : 7,
                          height: isLeaf ? 15 : 7,
                          decoration: BoxDecoration(
                            color: isLeaf && complete
                                ? colors.completion
                                : isLeaf
                                ? Colors.transparent
                                : AppTheme.accent,
                            shape: BoxShape.circle,
                            border: isLeaf && !complete
                                ? Border.all(color: colors.faint, width: 1.2)
                                : null,
                          ),
                          child: isLeaf && complete
                              ? const Icon(
                                  Icons.check,
                                  size: 10,
                                  color: Colors.white,
                                )
                              : null,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: renaming
                            ? interaction.buildRename(node)
                            : Align(
                                alignment: Alignment.centerLeft,
                                child: Tooltip(
                                  message: '双击重命名',
                                  waitDuration: const Duration(
                                    milliseconds: 700,
                                  ),
                                  child: MouseRegion(
                                    cursor: SystemMouseCursors.text,
                                    child: GestureDetector(
                                      behavior: HitTestBehavior.opaque,
                                      onDoubleTap: () =>
                                          interaction.rename(node),
                                      child: Text(
                                        key: ValueKey<String>(
                                          'event-row-title-${node.id}',
                                        ),
                                        node.title,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: complete ? colors.faint : null,
                                          fontSize: 12,
                                          fontWeight: isLeaf
                                              ? FontWeight.w500
                                              : FontWeight.w600,
                                          decoration: complete
                                              ? TextDecoration.lineThrough
                                              : null,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                      ),
                      if (node.deadline != null && !hovered && !renaming)
                        Text(
                          formatCompactDeadline(node.deadline!),
                          style: TextStyle(color: colors.faint, fontSize: 9),
                        ),
                      if (children.isNotEmpty &&
                          !expanded &&
                          !hovered &&
                          !renaming) ...<Widget>[
                        const SizedBox(width: 8),
                        Text(
                          '$hiddenDescendants 项',
                          key: ValueKey<String>(
                            'event-nested-count-${node.id}',
                          ),
                          style: TextStyle(color: colors.faint, fontSize: 9),
                        ),
                      ],
                      AnimatedOpacity(
                        key: ValueKey<String>('event-row-actions-${node.id}'),
                        opacity: showActions ? 1 : 0,
                        duration: const Duration(milliseconds: 120),
                        child: IgnorePointer(
                          ignoring: !showActions,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              IconButton(
                                key: ValueKey<String>(
                                  'event-abandon-task-${node.id}',
                                ),
                                tooltip: '放弃任务',
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints.tightFor(
                                  width: 28,
                                  height: 30,
                                ),
                                visualDensity: VisualDensity.compact,
                                mouseCursor: SystemMouseCursors.click,
                                onPressed: () => interaction.abandon(node),
                                icon: Icon(
                                  Icons.block_outlined,
                                  size: 16,
                                  color: colors.muted,
                                ),
                              ),
                              IconButton(
                                key: ValueKey<String>(
                                  'event-add-child-${node.id}',
                                ),
                                tooltip: '新建子任务',
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints.tightFor(
                                  width: 28,
                                  height: 30,
                                ),
                                visualDensity: VisualDensity.compact,
                                mouseCursor: SystemMouseCursors.click,
                                onPressed: () =>
                                    interaction.createChild(node.id),
                                icon: Icon(
                                  Icons.add,
                                  size: 16,
                                  color: colors.muted,
                                ),
                              ),
                              IconButton(
                                key: ValueKey<String>(
                                  'event-delete-task-${node.id}',
                                ),
                                tooltip: '删除任务',
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints.tightFor(
                                  width: 28,
                                  height: 30,
                                ),
                                visualDensity: VisualDensity.compact,
                                mouseCursor: SystemMouseCursors.click,
                                style: deleteButtonStyle,
                                onPressed: () => interaction.delete(node),
                                icon: const Icon(
                                  Icons.delete_outline,
                                  size: 16,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    return TaskMoveRowDropTarget(
      key: ValueKey<String>('event-task-drop-${node.id}'),
      controller: controller,
      target: node,
      child: row,
    );
  }
}

class _InlineTaskRenameField extends StatelessWidget {
  const _InlineTaskRenameField({
    required this.nodeId,
    required this.controller,
    required this.focusNode,
    required this.submitting,
    required this.failed,
    required this.onChanged,
    required this.fontWeight,
    required this.onSubmit,
    required this.onCancel,
  });

  final String nodeId;
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool submitting;
  final bool failed;
  final ValueChanged<String> onChanged;
  final FontWeight fontWeight;
  final VoidCallback onSubmit;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Focus(
      onKeyEvent: (_, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.escape) {
          onCancel();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Semantics(
        textField: true,
        label: '重命名任务',
        child: LayoutBuilder(
          builder: (context, constraints) {
            final showKeyboardHint = constraints.maxWidth >= 190;
            return Row(
              children: <Widget>[
                Expanded(
                  child: TextField(
                    key: ValueKey<String>('event-inline-rename-$nodeId'),
                    controller: controller,
                    focusNode: focusNode,
                    enabled: !submitting,
                    autofocus: true,
                    onChanged: onChanged,
                    onSubmitted: (_) => onSubmit(),
                    onTapOutside: (_) => focusNode.unfocus(),
                    textInputAction: TextInputAction.done,
                    style: TextStyle(fontSize: 12, fontWeight: fontWeight),
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      disabledBorder: InputBorder.none,
                      filled: false,
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ),
                if (submitting)
                  const Padding(
                    padding: EdgeInsets.only(right: 8),
                    child: SizedBox.square(
                      dimension: 12,
                      child: CircularProgressIndicator(strokeWidth: 1.5),
                    ),
                  )
                else if (failed)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Tooltip(
                      message: '保存失败，请重试',
                      child: Icon(
                        Icons.error_outline,
                        size: 15,
                        color: colors.danger,
                      ),
                    ),
                  )
                else if (showKeyboardHint)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Text(
                      '↵ 保存  ·  Esc 取消',
                      style: TextStyle(color: colors.faint, fontSize: 9),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _InlineTaskDraftRow extends StatelessWidget {
  const _InlineTaskDraftRow({
    required this.depth,
    required this.controller,
    required this.focusNode,
    required this.submitting,
    required this.onChanged,
    required this.onSubmit,
    required this.onCancel,
    required this.onRevealed,
    super.key,
  });

  final int depth;
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool submitting;
  final ValueChanged<String> onChanged;
  final VoidCallback onSubmit;
  final VoidCallback onCancel;
  final VoidCallback onRevealed;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final animationsDisabled = MediaQuery.disableAnimationsOf(context);
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: animationsDisabled
          ? Duration.zero
          : const Duration(milliseconds: 120),
      curve: Curves.easeOut,
      onEnd: onRevealed,
      builder: (context, value, child) => ClipRect(
        child: Align(
          alignment: Alignment.topCenter,
          heightFactor: value,
          child: Opacity(opacity: value, child: child),
        ),
      ),
      child: Focus(
        onKeyEvent: (_, event) {
          if (event is KeyDownEvent &&
              event.logicalKey == LogicalKeyboardKey.escape) {
            onCancel();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: Semantics(
          textField: true,
          label: '新建子任务',
          child: Container(
            key: const ValueKey<String>('event-inline-draft-surface'),
            height: 36,
            padding: EdgeInsets.only(left: depth * 20),
            decoration: BoxDecoration(
              color: colors.accentSoft.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(8),
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final showKeyboardHint =
                    constraints.maxWidth - depth * 20 >= 245;
                return Row(
                  children: <Widget>[
                    const SizedBox(width: 18),
                    const SizedBox(width: 8),
                    Container(
                      width: 15,
                      height: 15,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: colors.faint, width: 1.2),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: TextField(
                        key: const ValueKey<String>('event-inline-draft-input'),
                        controller: controller,
                        focusNode: focusNode,
                        enabled: !submitting,
                        autofocus: true,
                        onChanged: onChanged,
                        onSubmitted: (_) => onSubmit(),
                        onTapOutside: (_) => focusNode.unfocus(),
                        textInputAction: TextInputAction.done,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                        decoration: InputDecoration(
                          hintText: '输入子任务名称…',
                          hintStyle: TextStyle(
                            color: colors.faint,
                            fontSize: 12,
                          ),
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          disabledBorder: InputBorder.none,
                          filled: false,
                          isDense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    ),
                    if (submitting)
                      const Padding(
                        padding: EdgeInsets.only(right: 8),
                        child: SizedBox.square(
                          dimension: 12,
                          child: CircularProgressIndicator(strokeWidth: 1.5),
                        ),
                      )
                    else if (showKeyboardHint)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Text(
                          '↵ 创建  ·  Esc 取消',
                          style: TextStyle(color: colors.faint, fontSize: 9),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _CardQuickAdd extends StatefulWidget {
  const _CardQuickAdd({
    required this.controller,
    required this.parentId,
    required this.onCreated,
  });

  final AppController controller;
  final String parentId;
  final ValueChanged<String> onCreated;

  @override
  State<_CardQuickAdd> createState() => _CardQuickAddState();
}

class _CardQuickAddState extends State<_CardQuickAdd> {
  final TextEditingController textController = TextEditingController();
  late final FocusNode focusNode = FocusNode()..addListener(_handleFocusChange);
  bool expanded = false;

  void _handleFocusChange() {
    if (!focusNode.hasFocus && textController.text.trim().isEmpty && expanded) {
      setState(() => expanded = false);
    }
  }

  void open() {
    setState(() => expanded = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) focusNode.requestFocus();
    });
  }

  void close() {
    textController.clear();
    focusNode.unfocus();
    if (expanded) setState(() => expanded = false);
  }

  @override
  void dispose() {
    focusNode.removeListener(_handleFocusChange);
    focusNode.dispose();
    textController.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    final title = textController.text.trim();
    if (title.isEmpty) return;
    final result = await widget.controller.create(
      parentId: widget.parentId,
      title: title,
      selectCreated: false,
    );
    if (result case NodeWriteSuccess<TodoNode>(:final value)) {
      textController.clear();
      widget.onCreated(value.id);
    }
    if (mounted) focusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(11, 0, 11, 12),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 150),
        child: expanded
            ? Focus(
                onKeyEvent: (_, event) {
                  if (event is KeyDownEvent &&
                      event.logicalKey == LogicalKeyboardKey.escape) {
                    close();
                    return KeyEventResult.handled;
                  }
                  return KeyEventResult.ignored;
                },
                child: TextField(
                  key: ValueKey<String>('event-quick-add-${widget.parentId}'),
                  controller: textController,
                  focusNode: focusNode,
                  onSubmitted: (_) => submit(),
                  textInputAction: TextInputAction.done,
                  style: const TextStyle(fontSize: 11),
                  decoration: InputDecoration(
                    hintText: '添加子任务…',
                    prefixIcon: const Icon(Icons.add, size: 16),
                    suffixText: '↵',
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 10),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(9),
                      borderSide: BorderSide(color: colors.border),
                    ),
                  ),
                ),
              )
            : Align(
                key: const ValueKey<String>('quick-add-collapsed'),
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  key: ValueKey<String>(
                    'event-quick-add-trigger-${widget.parentId}',
                  ),
                  onPressed: open,
                  style: TextButton.styleFrom(
                    foregroundColor: colors.muted,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    visualDensity: VisualDensity.compact,
                  ),
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('添加任务', style: TextStyle(fontSize: 11)),
                ),
              ),
      ),
    );
  }
}
