import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/app_controller.dart';
import '../../app/app_theme.dart';
import '../../domain/node_tree.dart';
import '../../domain/todo_node.dart';
import '../common/delete_node.dart';
import '../common/formatters.dart';

const int _maximumPreviewDepth = 2;

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
  late final FocusNode inlineDraftFocusNode = FocusNode(
    debugLabel: 'event-inline-task-draft',
  )..addListener(_handleInlineDraftFocusChange);
  late final FocusNode inlineRenameFocusNode = FocusNode(
    debugLabel: 'event-inline-task-rename',
  )..addListener(_handleInlineRenameFocusChange);
  Timer? highlightTimer;
  String? highlightedId;
  String? inlineDraftParentId;
  String? inlineRenameNodeId;
  String? inlineRenameOriginalTitle;
  bool inlineDraftSubmitting = false;
  bool inlineRenameSubmitting = false;
  bool inlineRenameFailed = false;

  @override
  void dispose() {
    highlightTimer?.cancel();
    inlineDraftFocusNode.removeListener(_handleInlineDraftFocusChange);
    inlineDraftFocusNode.dispose();
    inlineDraftController.dispose();
    inlineRenameFocusNode.removeListener(_handleInlineRenameFocusChange);
    inlineRenameFocusNode.dispose();
    inlineRenameController.dispose();
    treeScrollController.dispose();
    super.dispose();
  }

  void _handleInlineDraftFocusChange() {
    if (inlineDraftFocusNode.hasFocus ||
        inlineDraftParentId == null ||
        inlineDraftSubmitting) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted &&
          !inlineDraftFocusNode.hasFocus &&
          inlineDraftParentId != null &&
          !inlineDraftSubmitting) {
        unawaited(_finishInlineDraft());
      }
    });
  }

  Future<void> _openInlineDraft(String parentId) async {
    if (inlineDraftParentId == parentId) {
      inlineDraftFocusNode.requestFocus();
      return;
    }
    if (inlineRenameNodeId != null) await _finishInlineRename();
    if (inlineRenameNodeId != null || !mounted) return;
    if (inlineDraftParentId != null) await _finishInlineDraft();
    if (!mounted) return;
    inlineDraftController.clear();
    setState(() {
      inlineDraftParentId = parentId;
      collapsedIds.remove(parentId);
      expandedBeyondPreviewIds.add(parentId);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || inlineDraftParentId != parentId) return;
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
      if (mounted && inlineDraftParentId != null) _revealInlineDraft();
    });
  }

  Future<void> _finishInlineDraft() async {
    final parentId = inlineDraftParentId;
    if (parentId == null || inlineDraftSubmitting) return;
    final title = inlineDraftController.text.trim();
    if (title.isEmpty) {
      _closeInlineDraft();
      return;
    }
    setState(() => inlineDraftSubmitting = true);
    final created = await widget.controller.create(
      parentId: parentId,
      title: title,
      selectCreated: false,
    );
    if (!mounted) return;
    if (created == null) {
      setState(() => inlineDraftSubmitting = false);
      inlineDraftFocusNode.requestFocus();
      return;
    }
    highlightCreated(created.id);
    _closeInlineDraft();
  }

  void _closeInlineDraft() {
    if (inlineDraftParentId == null) return;
    inlineDraftController.clear();
    setState(() {
      inlineDraftParentId = null;
      inlineDraftSubmitting = false;
    });
    inlineDraftFocusNode.unfocus();
  }

  void _handleInlineRenameFocusChange() {
    if (inlineRenameFocusNode.hasFocus ||
        inlineRenameNodeId == null ||
        inlineRenameSubmitting) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted &&
          !inlineRenameFocusNode.hasFocus &&
          inlineRenameNodeId != null &&
          !inlineRenameSubmitting) {
        unawaited(_finishInlineRename());
      }
    });
  }

  Future<void> _openInlineRename(TodoNode node) async {
    if (inlineRenameNodeId == node.id) {
      inlineRenameFocusNode.requestFocus();
      return;
    }
    if (inlineDraftParentId != null) await _finishInlineDraft();
    if (inlineDraftParentId != null || !mounted) return;
    if (inlineRenameNodeId != null) await _finishInlineRename();
    if (inlineRenameNodeId != null || !mounted) return;
    inlineRenameController.text = node.title;
    inlineRenameController.selection = TextSelection(
      baseOffset: 0,
      extentOffset: node.title.length,
    );
    setState(() {
      inlineRenameNodeId = node.id;
      inlineRenameOriginalTitle = node.title;
      inlineRenameFailed = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && inlineRenameNodeId == node.id) {
        inlineRenameFocusNode.requestFocus();
      }
    });
  }

  Future<void> _finishInlineRename() async {
    final nodeId = inlineRenameNodeId;
    final originalTitle = inlineRenameOriginalTitle;
    if (nodeId == null || originalTitle == null || inlineRenameSubmitting) {
      return;
    }
    final title = inlineRenameController.text.trim();
    if (title.isEmpty || title == originalTitle) {
      _closeInlineRename();
      return;
    }
    setState(() {
      inlineRenameSubmitting = true;
      inlineRenameFailed = false;
    });
    await widget.controller.updateTitle(nodeId, title);
    if (!mounted) return;
    if (widget.controller.error != null) {
      setState(() {
        inlineRenameSubmitting = false;
        inlineRenameFailed = true;
      });
      inlineRenameFocusNode.requestFocus();
      return;
    }
    _closeInlineRename();
  }

  void _closeInlineRename() {
    if (inlineRenameNodeId == null) return;
    inlineRenameController.clear();
    setState(() {
      inlineRenameNodeId = null;
      inlineRenameOriginalTitle = null;
      inlineRenameSubmitting = false;
      inlineRenameFailed = false;
    });
    inlineRenameFocusNode.unfocus();
  }

  Future<void> _deleteTaskNode(TodoNode node) async {
    if (inlineDraftParentId != null) await _finishInlineDraft();
    if (inlineDraftParentId != null || !mounted) return;
    if (inlineRenameNodeId != null) await _finishInlineRename();
    if (inlineRenameNodeId != null || !mounted) return;
    await confirmDeleteNode(context, widget.controller, node);
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
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final tree = controller.tree;
    final children = tree.childrenOf(widget.rootEventId);
    final colors = AppColors.of(context);
    return Column(
      children: <Widget>[
        Expanded(
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
                          controller: controller,
                          tree: tree,
                          parentId: widget.rootEventId,
                          depth: 0,
                          collapsedIds: collapsedIds,
                          expandedBeyondPreviewIds: expandedBeyondPreviewIds,
                          highlightedId: highlightedId,
                          inlineDraftParentId: inlineDraftParentId,
                          inlineRenameNodeId: inlineRenameNodeId,
                          scrollController: treeScrollController,
                          inlineDraftBuilder: (depth) => _InlineTaskDraftRow(
                            key: inlineDraftKey,
                            depth: depth,
                            controller: inlineDraftController,
                            focusNode: inlineDraftFocusNode,
                            submitting: inlineDraftSubmitting,
                            onSubmit: _finishInlineDraft,
                            onCancel: _closeInlineDraft,
                            onRevealed: _revealInlineDraftAfterLayout,
                          ),
                          inlineRenameBuilder: (node) => _InlineTaskRenameField(
                            nodeId: node.id,
                            controller: inlineRenameController,
                            focusNode: inlineRenameFocusNode,
                            submitting: inlineRenameSubmitting,
                            failed: inlineRenameFailed,
                            fontWeight: tree.childrenOf(node.id).isEmpty
                                ? FontWeight.w500
                                : FontWeight.w600,
                            onSubmit: _finishInlineRename,
                            onCancel: _closeInlineRename,
                          ),
                          onCreateChild: (parentId) =>
                              unawaited(_openInlineDraft(parentId)),
                          onRename: (task) =>
                              unawaited(_openInlineRename(task)),
                          onDelete: (task) => unawaited(_deleteTaskNode(task)),
                          onToggleExpanded: (nodeId) => setState(() {
                            if (!collapsedIds.add(nodeId)) {
                              collapsedIds.remove(nodeId);
                            }
                          }),
                        ),
                      ),
                    );
                  },
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

class _EventTaskGroup extends StatefulWidget {
  const _EventTaskGroup({
    required this.controller,
    required this.tree,
    required this.parentId,
    required this.depth,
    required this.collapsedIds,
    required this.expandedBeyondPreviewIds,
    required this.highlightedId,
    required this.inlineDraftParentId,
    required this.inlineRenameNodeId,
    required this.inlineDraftBuilder,
    required this.inlineRenameBuilder,
    required this.onCreateChild,
    required this.onRename,
    required this.onDelete,
    required this.onToggleExpanded,
    this.scrollController,
    super.key,
  });

  final AppController controller;
  final NodeTree tree;
  final String parentId;
  final int depth;
  final Set<String> collapsedIds;
  final Set<String> expandedBeyondPreviewIds;
  final String? highlightedId;
  final String? inlineDraftParentId;
  final String? inlineRenameNodeId;
  final Widget Function(int depth) inlineDraftBuilder;
  final Widget Function(TodoNode node) inlineRenameBuilder;
  final ValueChanged<String> onCreateChild;
  final ValueChanged<TodoNode> onRename;
  final ValueChanged<TodoNode> onDelete;
  final ValueChanged<String> onToggleExpanded;
  final ScrollController? scrollController;

  @override
  State<_EventTaskGroup> createState() => _EventTaskGroupState();
}

class _EventTaskGroupState extends State<_EventTaskGroup> {
  final GlobalKey<ReorderableListState> listKey =
      GlobalKey<ReorderableListState>();
  final FocusNode focusNode = FocusNode(debugLabel: 'event-task-group');
  String? draggingId;

  @override
  void dispose() {
    focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final children = widget.tree.childrenOf(widget.parentId);
    final showsInlineDraft = widget.inlineDraftParentId == widget.parentId;
    final rootGroup = widget.scrollController != null;
    return Focus(
      focusNode: focusNode,
      onKeyEvent: (_, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.escape &&
            draggingId != null) {
          listKey.currentState?.cancelReorder();
          setState(() => draggingId = null);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: ReorderableList(
        key: listKey,
        controller: widget.scrollController,
        shrinkWrap: !rootGroup,
        physics: rootGroup
            ? const ClampingScrollPhysics()
            : const NeverScrollableScrollPhysics(),
        padding: rootGroup
            ? const EdgeInsets.fromLTRB(10, 9, 16, 4)
            : EdgeInsets.zero,
        autoScrollerVelocityScalar: 34,
        itemCount: children.length + (showsInlineDraft ? 1 : 0),
        onReorderStart: (index) {
          focusNode.requestFocus();
          setState(() => draggingId = children[index].id);
        },
        onReorderEnd: (_) => setState(() => draggingId = null),
        onReorderItem: (oldIndex, newIndex) =>
            _reorder(children, oldIndex, newIndex),
        proxyDecorator: (child, index, animation) => AnimatedBuilder(
          animation: animation,
          builder: (context, _) => Material(
            color: Theme.of(context).colorScheme.surface,
            elevation: 4 + animation.value * 8,
            shadowColor: Colors.black26,
            borderRadius: BorderRadius.circular(9),
            clipBehavior: Clip.antiAlias,
            child: child,
          ),
        ),
        itemBuilder: (context, index) {
          if (index == children.length) {
            return KeyedSubtree(
              key: ValueKey<String>('event-inline-draft-${widget.parentId}'),
              child: widget.inlineDraftBuilder(widget.depth),
            );
          }
          final node = children[index];
          final expanded = !widget.collapsedIds.contains(node.id);
          final canExpand =
              !widget.tree.isLeaf(node.id) &&
              (widget.depth < _maximumPreviewDepth ||
                  widget.expandedBeyondPreviewIds.contains(node.id));
          return _EventTreeBranch(
            key: ValueKey<String>('event-task-branch-${node.id}'),
            controller: widget.controller,
            node: node,
            tree: widget.tree,
            depth: widget.depth,
            reorderIndex: index,
            expanded: expanded,
            dragging: draggingId == node.id,
            highlighted: widget.highlightedId == node.id,
            renaming: widget.inlineRenameNodeId == node.id,
            onToggleExpanded: canExpand
                ? () => widget.onToggleExpanded(node.id)
                : null,
            onKeyboardReorder: (direction, toEdge) {
              final newIndex = toEdge
                  ? (direction < 0 ? 0 : children.length - 1)
                  : (index + direction).clamp(0, children.length - 1);
              _reorder(children, index, newIndex);
            },
            collapsedIds: widget.collapsedIds,
            expandedBeyondPreviewIds: widget.expandedBeyondPreviewIds,
            highlightedId: widget.highlightedId,
            inlineDraftParentId: widget.inlineDraftParentId,
            inlineRenameNodeId: widget.inlineRenameNodeId,
            inlineDraftBuilder: widget.inlineDraftBuilder,
            inlineRenameBuilder: widget.inlineRenameBuilder,
            onCreateChild: widget.onCreateChild,
            onRename: widget.onRename,
            onDelete: widget.onDelete,
            onToggleChildExpanded: widget.onToggleExpanded,
          );
        },
      ),
    );
  }

  void _reorder(List<TodoNode> children, int oldIndex, int newIndex) {
    if (newIndex == oldIndex) return;
    final orderedIds = children.map((node) => node.id).toList();
    final movedId = orderedIds.removeAt(oldIndex);
    orderedIds.insert(newIndex.clamp(0, orderedIds.length), movedId);
    unawaited(widget.controller.reorderChildren(widget.parentId, orderedIds));
  }
}

class _EventTreeBranch extends StatelessWidget {
  const _EventTreeBranch({
    required this.controller,
    required this.node,
    required this.tree,
    required this.depth,
    required this.reorderIndex,
    required this.expanded,
    required this.dragging,
    required this.highlighted,
    required this.renaming,
    required this.onToggleExpanded,
    required this.onKeyboardReorder,
    required this.collapsedIds,
    required this.expandedBeyondPreviewIds,
    required this.highlightedId,
    required this.inlineDraftParentId,
    required this.inlineRenameNodeId,
    required this.inlineDraftBuilder,
    required this.inlineRenameBuilder,
    required this.onCreateChild,
    required this.onRename,
    required this.onDelete,
    required this.onToggleChildExpanded,
    super.key,
  });

  final AppController controller;
  final TodoNode node;
  final NodeTree tree;
  final int depth;
  final int reorderIndex;
  final bool expanded;
  final bool dragging;
  final bool highlighted;
  final bool renaming;
  final VoidCallback? onToggleExpanded;
  final void Function(int direction, bool toEdge) onKeyboardReorder;
  final Set<String> collapsedIds;
  final Set<String> expandedBeyondPreviewIds;
  final String? highlightedId;
  final String? inlineDraftParentId;
  final String? inlineRenameNodeId;
  final Widget Function(int depth) inlineDraftBuilder;
  final Widget Function(TodoNode node) inlineRenameBuilder;
  final ValueChanged<String> onCreateChild;
  final ValueChanged<TodoNode> onRename;
  final ValueChanged<TodoNode> onDelete;
  final ValueChanged<String> onToggleChildExpanded;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: <Widget>[
      _EventTreeRow(
        controller: controller,
        node: node,
        tree: tree,
        depth: depth,
        reorderIndex: reorderIndex,
        expanded: expanded,
        dragging: dragging,
        highlighted: highlighted,
        renaming: renaming,
        onToggleExpanded: onToggleExpanded,
        onKeyboardReorder: onKeyboardReorder,
        onCreateChild: () => onCreateChild(node.id),
        renameField: inlineRenameBuilder(node),
        onRename: () => onRename(node),
        onDelete: () => onDelete(node),
      ),
      if (expanded &&
          (depth < _maximumPreviewDepth ||
              expandedBeyondPreviewIds.contains(node.id)) &&
          (tree.childrenOf(node.id).isNotEmpty ||
              inlineDraftParentId == node.id))
        _EventTaskGroup(
          controller: controller,
          tree: tree,
          parentId: node.id,
          depth: depth + 1,
          collapsedIds: collapsedIds,
          expandedBeyondPreviewIds: expandedBeyondPreviewIds,
          highlightedId: highlightedId,
          inlineDraftParentId: inlineDraftParentId,
          inlineRenameNodeId: inlineRenameNodeId,
          inlineDraftBuilder: inlineDraftBuilder,
          inlineRenameBuilder: inlineRenameBuilder,
          onCreateChild: onCreateChild,
          onRename: onRename,
          onDelete: onDelete,
          onToggleExpanded: onToggleChildExpanded,
        ),
    ],
  );
}

class _EventTreeRow extends StatefulWidget {
  const _EventTreeRow({
    required this.controller,
    required this.node,
    required this.tree,
    required this.depth,
    required this.reorderIndex,
    required this.expanded,
    required this.dragging,
    required this.highlighted,
    required this.renaming,
    required this.onToggleExpanded,
    required this.onKeyboardReorder,
    required this.onCreateChild,
    required this.renameField,
    required this.onRename,
    required this.onDelete,
  });

  final AppController controller;
  final TodoNode node;
  final NodeTree tree;
  final int depth;
  final int reorderIndex;
  final bool expanded;
  final bool dragging;
  final bool highlighted;
  final bool renaming;
  final VoidCallback? onToggleExpanded;
  final void Function(int direction, bool toEdge) onKeyboardReorder;
  final VoidCallback onCreateChild;
  final Widget renameField;
  final VoidCallback onRename;
  final VoidCallback onDelete;

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
    if (widget.highlighted) _revealAfterLayout();
  }

  @override
  void didUpdateWidget(covariant _EventTreeRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.highlighted && widget.highlighted) {
      _revealAfterLayout();
    }
  }

  void _revealAfterLayout() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !widget.highlighted) return;
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
    final controller = widget.controller;
    final node = widget.node;
    final tree = widget.tree;
    final depth = widget.depth;
    final expanded = widget.expanded;
    final highlighted = widget.highlighted;
    final onToggleExpanded = widget.onToggleExpanded;
    final children = tree.childrenOf(node.id);
    final hiddenDescendants = tree.descendantsOf(node.id).length;
    final complete = tree.isComplete(node.id);
    final showActions = (hovered || focused) && !widget.renaming;
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
    return Focus(
      key: ValueKey<String>('event-row-focus-${node.id}'),
      focusNode: focusNode,
      onFocusChange: (value) => setState(() => focused = value),
      onKeyEvent: (_, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        if (event.logicalKey == LogicalKeyboardKey.f2 && !widget.renaming) {
          widget.onRename();
          return KeyEventResult.handled;
        }
        if (widget.renaming || !HardwareKeyboard.instance.isAltPressed) {
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
            color: widget.renaming
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
            opacity: widget.dragging ? 0.24 : 1,
            duration: const Duration(milliseconds: 90),
            curve: Curves.easeOut,
            child: GestureDetector(
              key: ValueKey<String>('event-row-${node.id}'),
              behavior: HitTestBehavior.opaque,
              onTap: widget.renaming
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
                          opacity: widget.renaming
                              ? 0.25
                              : hovered || widget.dragging
                              ? 1
                              : 0.45,
                          duration: const Duration(milliseconds: 90),
                          child: IgnorePointer(
                            ignoring: widget.renaming,
                            child: ReorderableDragStartListener(
                              index: widget.reorderIndex,
                              key: ValueKey<String>(
                                'event-task-drag-${node.id}',
                              ),
                              child: Tooltip(
                                message: '拖动同级排序 · ⌥↑↓ 键盘移动',
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
                                onPressed: widget.renaming
                                    ? null
                                    : onToggleExpanded,
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
                        onTap: children.isEmpty && !widget.renaming
                            ? () => controller.setCompleted(node.id, !complete)
                            : null,
                        radius: 16,
                        child: Container(
                          width: children.isEmpty ? 15 : 7,
                          height: children.isEmpty ? 15 : 7,
                          decoration: BoxDecoration(
                            color: children.isEmpty && complete
                                ? colors.completion
                                : children.isEmpty
                                ? Colors.transparent
                                : AppTheme.accent,
                            shape: BoxShape.circle,
                            border: children.isEmpty && !complete
                                ? Border.all(color: colors.faint, width: 1.2)
                                : null,
                          ),
                          child: children.isEmpty && complete
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
                        child: widget.renaming
                            ? widget.renameField
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
                                      onDoubleTap: widget.onRename,
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
                                          fontWeight: children.isEmpty
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
                      if (node.deadline != null && !hovered && !widget.renaming)
                        Text(
                          formatCompactDate(node.deadline!),
                          style: TextStyle(color: colors.faint, fontSize: 9),
                        ),
                      if (children.isNotEmpty &&
                          onToggleExpanded == null &&
                          !hovered &&
                          !widget.renaming) ...<Widget>[
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
                                onPressed: widget.onCreateChild,
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
                                onPressed: widget.onDelete,
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
  }
}

class _InlineTaskRenameField extends StatelessWidget {
  const _InlineTaskRenameField({
    required this.nodeId,
    required this.controller,
    required this.focusNode,
    required this.submitting,
    required this.failed,
    required this.fontWeight,
    required this.onSubmit,
    required this.onCancel,
  });

  final String nodeId;
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool submitting;
  final bool failed;
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
    required this.onSubmit,
    required this.onCancel,
    required this.onRevealed,
    super.key,
  });

  final int depth;
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool submitting;
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
    final created = await widget.controller.create(
      parentId: widget.parentId,
      title: title,
      selectCreated: false,
    );
    textController.clear();
    if (created != null) widget.onCreated(created.id);
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
