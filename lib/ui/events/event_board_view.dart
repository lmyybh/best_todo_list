import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/app_controller.dart';
import '../../app/app_theme.dart';
import '../../domain/node_tree.dart';
import '../../domain/todo_node.dart';
import '../common/create_node_dialog.dart';
import '../common/delete_confirmation_dialog.dart';
import '../common/formatters.dart';

class EventBoardView extends StatefulWidget {
  const EventBoardView({required this.controller, super.key});

  final AppController controller;

  static const double minimumCardWidth = 300;
  static const double maximumCardWidth = 420;
  static const double singleColumnMaximumWidth = 680;
  static const double minimumCardHeight = 280;
  static const double maximumCardHeight = 500;
  static const int maximumColumns = 4;
  static const int previewRowLimit = 5;
  static const int maximumPreviewDepth = 2;
  static const double spacing = 16;

  @override
  State<EventBoardView> createState() => _EventBoardViewState();
}

class _EventBoardViewState extends State<EventBoardView> {
  final GlobalKey boardKey = GlobalKey();
  final GlobalKey scrollViewportKey = GlobalKey();
  final ScrollController boardScrollController = ScrollController();
  final FocusNode boardFocusNode = FocusNode(debugLabel: 'event-board');
  Timer? autoScrollTimer;
  Timer? responsiveReflowTimer;
  double autoScrollVelocity = 0;
  int? renderedColumns;
  bool animateResponsiveReflow = false;
  String? draggedEventId;
  List<String>? previewRootIds;
  List<String>? dragStartRootIds;
  Offset? latestDragPosition;
  bool dragCanceled = false;

  @override
  void dispose() {
    autoScrollTimer?.cancel();
    responsiveReflowTimer?.cancel();
    boardScrollController.dispose();
    boardFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final roots = widget.controller.tree.childrenOf(null);
    final rootsById = <String, TodoNode>{
      for (final root in roots) root.id: root,
    };
    final rootIds = roots.map((root) => root.id).toList();
    final previewIds = previewRootIds;
    final orderedIds =
        previewIds != null &&
            previewIds.length == rootIds.length &&
            previewIds.every(rootsById.containsKey)
        ? previewIds
        : rootIds;
    final orderedRoots = orderedIds.map((id) => rootsById[id]!).toList();
    return Focus(
      focusNode: boardFocusNode,
      onKeyEvent: (_, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.escape &&
            draggedEventId != null) {
          _cancelEventDrag();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: LayoutBuilder(
        builder: (context, constraints) {
          final panelPadding = constraints.maxWidth < 640
              ? const EdgeInsets.fromLTRB(16, 16, 16, 24)
              : constraints.maxWidth < 1200
              ? const EdgeInsets.fromLTRB(20, 20, 20, 28)
              : const EdgeInsets.fromLTRB(24, 24, 24, 32);
          final availableWidth =
              (constraints.maxWidth - panelPadding.horizontal)
                  .clamp(0, double.infinity)
                  .toDouble();
          final columns =
              ((availableWidth + EventBoardView.spacing) /
                      (EventBoardView.minimumCardWidth +
                          EventBoardView.spacing))
                  .floor()
                  .clamp(1, EventBoardView.maximumColumns);
          _recordRenderedColumns(columns);
          final animationsDisabled = MediaQuery.disableAnimationsOf(context);
          final layoutAnimationDuration = animationsDisabled
              ? Duration.zero
              : draggedEventId != null
              ? const Duration(milliseconds: 160)
              : animateResponsiveReflow
              ? const Duration(milliseconds: 140)
              : Duration.zero;
          final maximumWidthForColumns = columns == 1
              ? EventBoardView.singleColumnMaximumWidth
              : EventBoardView.maximumCardWidth * columns +
                    EventBoardView.spacing * (columns - 1);
          final gridWidth = availableWidth
              .clamp(0, maximumWidthForColumns)
              .toDouble();
          final resolvedWidth =
              (gridWidth - EventBoardView.spacing * (columns - 1)) / columns;
          final viewportHeight = constraints.hasBoundedHeight
              ? constraints.maxHeight
              : 800.0;
          final minimumCardHeight = (viewportHeight * 0.36)
              .clamp(EventBoardView.minimumCardHeight, 340)
              .toDouble();
          final maximumCardHeight = (viewportHeight * 0.55)
              .clamp(360, EventBoardView.maximumCardHeight)
              .toDouble();

          final items = <TodoNode?>[...orderedRoots, null];
          final rowHeights = <double>[];
          for (var start = 0; start < items.length; start += columns) {
            final row = items.sublist(
              start,
              (start + columns).clamp(0, items.length),
            );
            rowHeights.add(
              row.whereType<TodoNode>().fold<double>(
                minimumCardHeight,
                (height, node) =>
                    height >
                        _preferredCardHeight(
                          widget.controller.tree,
                          node,
                          minimumHeight: minimumCardHeight,
                          maximumHeight: maximumCardHeight,
                        )
                    ? height
                    : _preferredCardHeight(
                        widget.controller.tree,
                        node,
                        minimumHeight: minimumCardHeight,
                        maximumHeight: maximumCardHeight,
                      ),
              ),
            );
          }
          final rowOffsets = <double>[];
          var totalHeight = 0.0;
          for (final height in rowHeights) {
            rowOffsets.add(totalHeight);
            totalHeight += height + EventBoardView.spacing;
          }
          if (rowHeights.isNotEmpty) totalHeight -= EventBoardView.spacing;

          return KeyedSubtree(
            key: const ValueKey<String>('event-board-scroll'),
            child: SingleChildScrollView(
              key: scrollViewportKey,
              controller: boardScrollController,
              padding: panelPadding,
              child: roots.isEmpty
                  ? _EmptyBoard(onCreate: () => _createEvent(context))
                  : Align(
                      alignment: Alignment.topCenter,
                      child: SizedBox(
                        key: const ValueKey<String>('event-board-wrap'),
                        width: gridWidth,
                        height: totalHeight,
                        child: Stack(
                          key: boardKey,
                          children: <Widget>[
                            for (var index = 0; index < items.length; index++)
                              _buildPositionedItem(
                                context: context,
                                item: items[index],
                                allRoots: roots,
                                index: index,
                                columns: columns,
                                width: resolvedWidth,
                                height: rowHeights[index ~/ columns],
                                animationDuration: layoutAnimationDuration,
                                left:
                                    (index % columns) *
                                    (resolvedWidth + EventBoardView.spacing),
                                top: rowOffsets[index ~/ columns],
                              ),
                          ],
                        ),
                      ),
                    ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildPositionedItem({
    required BuildContext context,
    required TodoNode? item,
    required List<TodoNode> allRoots,
    required int index,
    required int columns,
    required double width,
    required double height,
    required Duration animationDuration,
    required double left,
    required double top,
  }) {
    final child = item == null
        ? DragTarget<String>(
            onWillAcceptWithDetails: (_) => true,
            onMove: (_) => _previewAtEnd(),
            builder: (context, candidates, _) => _NewEventCard(
              onPressed: () => _createEvent(context),
              dropTargeted: candidates.isNotEmpty,
            ),
          )
        : DragTarget<String>(
            onWillAcceptWithDetails: (details) {
              if (details.data == item.id) return false;
              _previewAround(item.id, after: false);
              return true;
            },
            onMove: (details) {
              final renderObject =
                  boardKey.currentContext?.findRenderObject() as RenderBox?;
              if (renderObject == null) return;
              final local = renderObject.globalToLocal(details.offset);
              final after = columns == 1
                  ? local.dy > top + height / 2
                  : local.dx > left + width / 2;
              _previewAround(item.id, after: after);
            },
            builder: (context, candidates, _) => _EventCard(
              controller: widget.controller,
              node: item,
              tree: widget.controller.tree,
              now: widget.controller.now,
              color:
                  _eventColors[allRoots.indexWhere(
                        (root) => root.id == item.id,
                      ) %
                      _eventColors.length],
              dropTargeted: candidates.isNotEmpty,
              onDragStarted: () => _startDragging(item.id, allRoots),
              onDragUpdate: _updateEventAutoScroll,
              onDragEnd: _endDragging,
              onKeyboardReorder: (direction, toEdge) =>
                  _keyboardReorderEvent(item.id, direction, toEdge, allRoots),
            ),
          );

    return AnimatedPositioned(
      key: ValueKey<String>('event-layout-${item?.id ?? 'new'}'),
      duration: animationDuration,
      curve: Curves.easeOutCubic,
      left: left,
      top: top,
      width: width,
      height: height,
      child: KeyedSubtree(
        key: item == null
            ? const ValueKey<String>('new-event-card')
            : ValueKey<String>('event-card-${item.id}'),
        child: child,
      ),
    );
  }

  void _recordRenderedColumns(int columns) {
    if (renderedColumns == columns) return;
    if (renderedColumns != null) {
      animateResponsiveReflow = true;
      responsiveReflowTimer?.cancel();
      responsiveReflowTimer = Timer(const Duration(milliseconds: 140), () {
        if (mounted) setState(() => animateResponsiveReflow = false);
      });
    }
    renderedColumns = columns;
  }

  void _startDragging(String id, List<TodoNode> roots) {
    boardFocusNode.requestFocus();
    setState(() {
      draggedEventId = id;
      dragStartRootIds = roots.map((root) => root.id).toList();
      previewRootIds = List<String>.of(dragStartRootIds!);
      latestDragPosition = null;
      dragCanceled = false;
    });
  }

  void _previewAround(String targetId, {required bool after}) {
    final draggedId = draggedEventId;
    final current = previewRootIds;
    if (draggedId == null || current == null || draggedId == targetId) return;
    final next = List<String>.of(current)..remove(draggedId);
    final targetIndex = next.indexOf(targetId);
    if (targetIndex < 0) return;
    next.insert(targetIndex + (after ? 1 : 0), draggedId);
    if (!listEquals(next, current)) setState(() => previewRootIds = next);
  }

  void _previewAtEnd() {
    final draggedId = draggedEventId;
    final current = previewRootIds;
    if (draggedId == null || current == null) return;
    final next = List<String>.of(current)
      ..remove(draggedId)
      ..add(draggedId);
    if (!listEquals(next, current)) setState(() => previewRootIds = next);
  }

  void _commitPreviewOrder() {
    final orderedIds = previewRootIds;
    if (!dragCanceled && orderedIds != null) {
      unawaited(widget.controller.reorderChildren(null, orderedIds));
    }
    _clearDragging();
  }

  void _endDragging(DraggableDetails details) {
    if (draggedEventId == null) return;
    final previewChanged =
        previewRootIds != null &&
        dragStartRootIds != null &&
        !listEquals(previewRootIds, dragStartRootIds);
    if (!dragCanceled && previewChanged && _isInsideBoard(latestDragPosition)) {
      _commitPreviewOrder();
    } else {
      _clearDragging();
    }
  }

  void _clearDragging() {
    _stopEventAutoScroll();
    if (!mounted) return;
    setState(() {
      draggedEventId = null;
      previewRootIds = null;
      dragStartRootIds = null;
      latestDragPosition = null;
      dragCanceled = false;
    });
  }

  void _cancelEventDrag() {
    _stopEventAutoScroll();
    setState(() {
      dragCanceled = true;
      previewRootIds = dragStartRootIds == null
          ? null
          : List<String>.of(dragStartRootIds!);
    });
  }

  void _updateEventAutoScroll(DragUpdateDetails details) {
    latestDragPosition = details.globalPosition;
    final renderObject =
        scrollViewportKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderObject == null || !boardScrollController.hasClients) return;
    final local = renderObject.globalToLocal(details.globalPosition);
    const edge = 72.0;
    if (local.dy < edge) {
      autoScrollVelocity = -((edge - local.dy) / edge * 12)
          .clamp(2, 12)
          .toDouble();
    } else if (local.dy > renderObject.size.height - edge) {
      autoScrollVelocity =
          ((local.dy - (renderObject.size.height - edge)) / edge * 12).clamp(
            2,
            12,
          );
    } else {
      _stopEventAutoScroll();
      return;
    }
    autoScrollTimer ??= Timer.periodic(const Duration(milliseconds: 16), (_) {
      if (!boardScrollController.hasClients) return;
      final position = boardScrollController.position;
      final next = (position.pixels + autoScrollVelocity).clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      );
      boardScrollController.jumpTo(next);
    });
  }

  bool _isInsideBoard(Offset? globalPosition) {
    if (globalPosition == null) return false;
    final renderObject =
        scrollViewportKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderObject == null) return false;
    final local = renderObject.globalToLocal(globalPosition);
    return (Offset.zero & renderObject.size).contains(local);
  }

  void _stopEventAutoScroll() {
    autoScrollTimer?.cancel();
    autoScrollTimer = null;
    autoScrollVelocity = 0;
  }

  void _keyboardReorderEvent(
    String id,
    int direction,
    bool toEdge,
    List<TodoNode> roots,
  ) {
    final orderedIds = roots.map((root) => root.id).toList();
    final oldIndex = orderedIds.indexOf(id);
    if (oldIndex < 0) return;
    final newIndex = toEdge
        ? (direction < 0 ? 0 : orderedIds.length - 1)
        : (oldIndex + direction).clamp(0, orderedIds.length - 1);
    if (newIndex == oldIndex) return;
    orderedIds
      ..removeAt(oldIndex)
      ..insert(newIndex, id);
    unawaited(widget.controller.reorderChildren(null, orderedIds));
  }

  Future<void> _createEvent(BuildContext context) async {
    final title = await showDialog<String>(
      context: context,
      builder: (context) => const CreateNodeDialog(),
    );
    if (title == null || title.trim().isEmpty) return;
    await widget.controller.create(title: title, selectCreated: false);
    widget.controller.showEventOverview();
  }
}

double _preferredCardHeight(
  NodeTree tree,
  TodoNode node, {
  required double minimumHeight,
  required double maximumHeight,
}) {
  final visibleRows = tree
      .descendantsOf(node.id)
      .length
      .clamp(0, EventBoardView.previewRowLimit);
  final hidden = tree.descendantsOf(node.id).length > visibleRows;
  return (225 + visibleRows * 36 + (hidden ? 28 : 0))
      .clamp(minimumHeight, maximumHeight)
      .toDouble();
}

const _eventColors = <Color>[
  Color(0xFFC97967),
  Color(0xFF8D7E9F),
  Color(0xFFB58A43),
  Color(0xFF718D72),
  Color(0xFF568B8A),
  Color(0xFF7784A5),
];

class _EventCard extends StatefulWidget {
  const _EventCard({
    required this.controller,
    required this.node,
    required this.tree,
    required this.now,
    required this.color,
    required this.dropTargeted,
    required this.onDragStarted,
    required this.onDragUpdate,
    required this.onDragEnd,
    required this.onKeyboardReorder,
  });

  final AppController controller;
  final TodoNode node;
  final NodeTree tree;
  final DateTime now;
  final Color color;
  final bool dropTargeted;
  final VoidCallback onDragStarted;
  final ValueChanged<DragUpdateDetails> onDragUpdate;
  final ValueChanged<DraggableDetails> onDragEnd;
  final void Function(int direction, bool toEdge) onKeyboardReorder;

  @override
  State<_EventCard> createState() => _EventCardState();
}

class _EventCardState extends State<_EventCard> {
  final Set<String> collapsedIds = <String>{};
  final Set<String> expandedBeyondPreviewIds = <String>{};
  final ScrollController treeScrollController = ScrollController();
  final FocusNode cardFocusNode = FocusNode(debugLabel: 'event-card');
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
  bool cardHovered = false;
  bool cardDragging = false;
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
    cardFocusNode.dispose();
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
    await _deleteNode(context, widget.controller, node);
  }

  void highlightCreated(String nodeId) {
    highlightTimer?.cancel();
    setState(() => highlightedId = nodeId);
    highlightTimer = Timer(const Duration(milliseconds: 900), () {
      if (mounted) setState(() => highlightedId = null);
    });
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final node = widget.node;
    final tree = widget.tree;
    final now = widget.now;
    final color = widget.color;
    final dropTargeted = widget.dropTargeted;
    final colors = AppColors.of(context);
    final leaves = tree.leafDescendantsOf(node.id);
    final completed = leaves.where((leaf) => leaf.completedAt != null).length;
    final progress = leaves.isEmpty ? 0.0 : completed / leaves.length;
    final children = tree.childrenOf(node.id);
    Widget dragRegion() => Focus(
      focusNode: cardFocusNode,
      onKeyEvent: (_, event) {
        if (event is! KeyDownEvent || !HardwareKeyboard.instance.isAltPressed) {
          return KeyEventResult.ignored;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowLeft ||
            event.logicalKey == LogicalKeyboardKey.arrowUp) {
          widget.onKeyboardReorder(
            -1,
            HardwareKeyboard.instance.isShiftPressed,
          );
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowRight ||
            event.logicalKey == LogicalKeyboardKey.arrowDown) {
          widget.onKeyboardReorder(1, HardwareKeyboard.instance.isShiftPressed);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Listener(
        onPointerDown: (_) => cardFocusNode.requestFocus(),
        child: MouseRegion(
          cursor: SystemMouseCursors.grab,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              SizedBox(
                key: ValueKey<String>('event-drag-${node.id}'),
                width: 22,
                height: 24,
                child: AnimatedOpacity(
                  opacity: cardHovered || cardDragging ? 1 : 0.55,
                  duration: const Duration(milliseconds: 100),
                  child: Tooltip(
                    message: '拖动排序 · ⌥↑↓ 键盘移动',
                    child: Icon(
                      Icons.drag_indicator,
                      size: 18,
                      color: colors.muted,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 7),
              Container(
                width: 10,
                height: 10,
                margin: const EdgeInsets.only(top: 4),
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    InkWell(
                      key: ValueKey<String>('event-title-${node.id}'),
                      mouseCursor: SystemMouseCursors.click,
                      onTap: () => controller.select(node.id),
                      child: Text(
                        node.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 16,
                          height: 1.25,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      children.isEmpty ? '单项任务' : '${children.length} 个直接子任务',
                      style: TextStyle(color: colors.faint, fontSize: 10),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    return MouseRegion(
      onEnter: (_) => setState(() => cardHovered = true),
      onExit: (_) => setState(() => cardHovered = false),
      child: AnimatedContainer(
        key: ValueKey<String>('event-card-surface-${node.id}'),
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(13),
          boxShadow: dropTargeted
              ? <BoxShadow>[
                  BoxShadow(
                    color: Theme.of(
                      context,
                    ).colorScheme.primary.withValues(alpha: 0.22),
                    blurRadius: 20,
                    spreadRadius: 1,
                  ),
                ]
              : cardHovered
              ? <BoxShadow>[
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 16,
                    offset: const Offset(0, 5),
                  ),
                ]
              : const <BoxShadow>[],
        ),
        child: AnimatedOpacity(
          key: ValueKey<String>('event-drag-source-${node.id}'),
          opacity: cardDragging ? 0.16 : 1,
          duration: const Duration(milliseconds: 100),
          curve: Curves.easeOut,
          child: Material(
            color: Theme.of(context).colorScheme.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(13),
              side: BorderSide(
                color: dropTargeted
                    ? Theme.of(context).colorScheme.primary
                    : cardHovered
                    ? color.withValues(alpha: 0.72)
                    : colors.border,
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(17, 16, 17, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Expanded(
                            child: Draggable<String>(
                              key: ValueKey<String>(
                                'event-drag-region-${node.id}',
                              ),
                              data: node.id,
                              rootOverlay: true,
                              dragAnchorStrategy: pointerDragAnchorStrategy,
                              onDragStarted: () {
                                setState(() => cardDragging = true);
                                widget.onDragStarted();
                              },
                              onDragUpdate: widget.onDragUpdate,
                              onDragEnd: (details) {
                                if (mounted) {
                                  setState(() => cardDragging = false);
                                }
                                widget.onDragEnd(details);
                              },
                              feedback: Material(
                                color: Theme.of(context).colorScheme.surface,
                                elevation: 12,
                                shadowColor: Colors.black26,
                                borderRadius: BorderRadius.circular(13),
                                child: SizedBox(
                                  width: 280,
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 13,
                                    ),
                                    child: Row(
                                      children: <Widget>[
                                        Icon(
                                          Icons.drag_indicator,
                                          size: 18,
                                          color: colors.muted,
                                        ),
                                        const SizedBox(width: 8),
                                        Container(
                                          width: 9,
                                          height: 9,
                                          decoration: BoxDecoration(
                                            color: color,
                                            borderRadius: BorderRadius.circular(
                                              3,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Text(
                                            node.title,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              childWhenDragging: dragRegion(),
                              child: dragRegion(),
                            ),
                          ),
                          MenuAnchor(
                            menuChildren: <Widget>[
                              MenuItemButton(
                                onPressed: () =>
                                    _renameNode(context, controller, node),
                                child: const Text('重命名'),
                              ),
                              MenuItemButton(
                                onPressed: () =>
                                    _deleteNode(context, controller, node),
                                child: const Text('删除'),
                              ),
                            ],
                            builder: (context, menu, _) => IconButton(
                              key: ValueKey<String>('event-menu-${node.id}'),
                              tooltip: '任务操作',
                              onPressed: menu.open,
                              visualDensity: VisualDensity.compact,
                              icon: Icon(
                                Icons.more_horiz,
                                size: 17,
                                color: colors.muted,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: <Widget>[
                          Text(
                            '$completed / ${leaves.length} 已完成',
                            style: TextStyle(color: colors.muted, fontSize: 10),
                          ),
                          const Spacer(),
                          _DeadlineLabel(node: node, now: now),
                        ],
                      ),
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: LinearProgressIndicator(
                          value: progress,
                          minHeight: 3,
                          color: color,
                          backgroundColor: colors.borderSoft,
                        ),
                      ),
                    ],
                  ),
                ),
                Divider(height: 1, color: colors.borderSoft),
                Expanded(
                  child: children.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.all(18),
                          child: Align(
                            alignment: Alignment.topLeft,
                            child: Text(
                              '还没有子任务',
                              style: TextStyle(
                                color: colors.faint,
                                fontSize: 11,
                              ),
                            ),
                          ),
                        )
                      : Builder(
                          builder: (context) {
                            return KeyedSubtree(
                              key: treeViewportKey,
                              child: Scrollbar(
                                key: ValueKey<String>(
                                  'event-tree-scrollbar-${node.id}',
                                ),
                                controller: treeScrollController,
                                thumbVisibility: true,
                                interactive: true,
                                radius: const Radius.circular(4),
                                child: _EventTaskGroup(
                                  key: ValueKey<String>(
                                    'event-tree-scroll-${node.id}',
                                  ),
                                  controller: controller,
                                  tree: tree,
                                  parentId: node.id,
                                  depth: 0,
                                  collapsedIds: collapsedIds,
                                  expandedBeyondPreviewIds:
                                      expandedBeyondPreviewIds,
                                  highlightedId: highlightedId,
                                  inlineDraftParentId: inlineDraftParentId,
                                  inlineRenameNodeId: inlineRenameNodeId,
                                  scrollController: treeScrollController,
                                  inlineDraftBuilder: (depth) =>
                                      _InlineTaskDraftRow(
                                        key: inlineDraftKey,
                                        depth: depth,
                                        controller: inlineDraftController,
                                        focusNode: inlineDraftFocusNode,
                                        submitting: inlineDraftSubmitting,
                                        onSubmit: _finishInlineDraft,
                                        onCancel: _closeInlineDraft,
                                      ),
                                  inlineRenameBuilder: (node) =>
                                      _InlineTaskRenameField(
                                        nodeId: node.id,
                                        controller: inlineRenameController,
                                        focusNode: inlineRenameFocusNode,
                                        submitting: inlineRenameSubmitting,
                                        failed: inlineRenameFailed,
                                        fontWeight:
                                            tree.childrenOf(node.id).isEmpty
                                            ? FontWeight.w500
                                            : FontWeight.w600,
                                        onSubmit: _finishInlineRename,
                                        onCancel: _closeInlineRename,
                                      ),
                                  onCreateChild: (parentId) =>
                                      unawaited(_openInlineDraft(parentId)),
                                  onRename: (task) =>
                                      unawaited(_openInlineRename(task)),
                                  onDelete: (task) =>
                                      unawaited(_deleteTaskNode(task)),
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
                  parentId: node.id,
                  onCreated: highlightCreated,
                ),
              ],
            ),
          ),
        ),
      ),
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
              (widget.depth < EventBoardView.maximumPreviewDepth ||
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
          (depth < EventBoardView.maximumPreviewDepth ||
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
    super.key,
  });

  final int depth;
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool submitting;
  final VoidCallback onSubmit;
  final VoidCallback onCancel;

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

class _DeadlineLabel extends StatelessWidget {
  const _DeadlineLabel({required this.node, required this.now});

  final TodoNode node;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    if (node.deadline == null) return const SizedBox.shrink();
    final overdue = isOverdue(
      node.deadline,
      now,
      hasTime: node.hasDeadlineTime,
    );
    return Text(
      overdue ? '已逾期' : formatCompactDate(node.deadline!),
      style: TextStyle(
        color: overdue ? AppColors.of(context).danger : AppTheme.accent,
        fontSize: 10,
        fontWeight: overdue ? FontWeight.w700 : FontWeight.w500,
      ),
    );
  }
}

class _NewEventCard extends StatelessWidget {
  const _NewEventCard({required this.onPressed, this.dropTargeted = false});

  final VoidCallback onPressed;
  final bool dropTargeted;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return OutlinedButton(
      key: const ValueKey<String>('event-new-card'),
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: colors.muted,
        enabledMouseCursor: SystemMouseCursors.click,
        backgroundColor: dropTargeted
            ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.06)
            : null,
        side: BorderSide(
          color: dropTargeted
              ? Theme.of(context).colorScheme.primary
              : colors.border,
          width: dropTargeted ? 2 : 1,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
      ),
      child: const Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(Icons.add_circle_outline, size: 34),
          SizedBox(height: 10),
          Text('新建事件', style: TextStyle(fontWeight: FontWeight.w600)),
          SizedBox(height: 5),
          Text('添加一个并排的事件块', style: TextStyle(fontSize: 10)),
        ],
      ),
    );
  }
}

class _EmptyBoard extends StatelessWidget {
  const _EmptyBoard({required this.onCreate});

  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 520,
    child: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(
            Icons.dashboard_customize_outlined,
            size: 46,
            color: AppColors.of(context).muted,
          ),
          const SizedBox(height: 14),
          const Text(
            '从一件想完成的事开始',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(
            '每个事件会成为一个独立的任务块',
            style: TextStyle(color: AppColors.of(context).muted, fontSize: 12),
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: onCreate,
            icon: const Icon(Icons.add, size: 17),
            label: const Text('新建事件'),
          ),
        ],
      ),
    ),
  );
}

Future<void> _renameNode(
  BuildContext context,
  AppController controller,
  TodoNode node,
) async {
  final title = await showDialog<String>(
    context: context,
    builder: (context) => CreateNodeDialog(
      title: '重命名',
      initialTitle: node.title,
      fieldLabel: '名称',
      hintText: '输入新名称',
      confirmLabel: '保存',
    ),
  );
  if (title != null && title.trim().isNotEmpty) {
    await controller.updateTitle(node.id, title);
  }
}

Future<void> _deleteNode(
  BuildContext context,
  AppController controller,
  TodoNode node,
) async {
  final hasChildren = controller.tree.childrenOf(node.id).isNotEmpty;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => DeleteConfirmationDialog(
      title: hasChildren ? '删除这个事件？' : '删除这个任务？',
      message: hasChildren ? '它的所有子任务也会一起删除。' : '删除后可以在提示消失前撤销。',
    ),
  );
  if (confirmed != true || !context.mounted) return;
  await controller.delete(node.id);
  controller.showEventOverview();
}
