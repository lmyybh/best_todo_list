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

  static const double cardWidth = 352;
  static const double minimumCardWidth = 300;
  static const double minimumCardHeight = 300;
  static const double maximumCardHeight = 430;
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
  double autoScrollVelocity = 0;
  String? draggedEventId;
  List<String>? previewRootIds;
  List<String>? dragStartRootIds;
  bool dragCanceled = false;

  @override
  void dispose() {
    autoScrollTimer?.cancel();
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
          final horizontalPadding = constraints.maxWidth < 760 ? 18.0 : 22.0;
          final availableWidth = constraints.maxWidth - horizontalPadding * 2;
          final columns =
              ((availableWidth + EventBoardView.spacing) /
                      (EventBoardView.cardWidth + EventBoardView.spacing))
                  .floor()
                  .clamp(1, 4);
          final resolvedWidth =
              ((availableWidth - EventBoardView.spacing * (columns - 1)) /
                      columns)
                  .clamp(
                    EventBoardView.minimumCardWidth,
                    EventBoardView.cardWidth,
                  )
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
                EventBoardView.minimumCardHeight,
                (height, node) =>
                    height > _preferredCardHeight(widget.controller.tree, node)
                    ? height
                    : _preferredCardHeight(widget.controller.tree, node),
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
              padding: EdgeInsets.fromLTRB(
                horizontalPadding,
                18,
                horizontalPadding,
                28,
              ),
              child: roots.isEmpty
                  ? _EmptyBoard(onCreate: () => _createEvent(context))
                  : SizedBox(
                      key: const ValueKey<String>('event-board-wrap'),
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
                              left:
                                  (index % columns) *
                                  (resolvedWidth + EventBoardView.spacing),
                              top: rowOffsets[index ~/ columns],
                            ),
                        ],
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
    required double left,
    required double top,
  }) {
    final child = item == null
        ? DragTarget<String>(
            onWillAcceptWithDetails: (_) => true,
            onMove: (_) => _previewAtEnd(),
            onAcceptWithDetails: (_) => _commitPreviewOrder(),
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
            onAcceptWithDetails: (_) => _commitPreviewOrder(),
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
      duration: const Duration(milliseconds: 160),
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

  void _startDragging(String id, List<TodoNode> roots) {
    boardFocusNode.requestFocus();
    setState(() {
      draggedEventId = id;
      dragStartRootIds = roots.map((root) => root.id).toList();
      previewRootIds = List<String>.of(dragStartRootIds!);
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
    if (!details.wasAccepted) _clearDragging();
  }

  void _clearDragging() {
    _stopEventAutoScroll();
    if (!mounted) return;
    setState(() {
      draggedEventId = null;
      previewRootIds = null;
      dragStartRootIds = null;
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

double _preferredCardHeight(NodeTree tree, TodoNode node) {
  final visibleRows = tree
      .descendantsOf(node.id)
      .length
      .clamp(0, EventBoardView.previewRowLimit);
  final hidden = tree.descendantsOf(node.id).length > visibleRows;
  return (225 + visibleRows * 36 + (hidden ? 28 : 0))
      .clamp(EventBoardView.minimumCardHeight, EventBoardView.maximumCardHeight)
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
  final ScrollController treeScrollController = ScrollController();
  final FocusNode cardFocusNode = FocusNode(debugLabel: 'event-card');
  Timer? highlightTimer;
  String? highlightedId;
  bool cardHovered = false;
  bool cardDragging = false;

  @override
  void dispose() {
    highlightTimer?.cancel();
    treeScrollController.dispose();
    cardFocusNode.dispose();
    super.dispose();
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
                          _DeadlineLabel(deadline: node.deadline, now: now),
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
                            return Scrollbar(
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
                                highlightedId: highlightedId,
                                scrollController: treeScrollController,
                                onToggleExpanded: (nodeId) => setState(() {
                                  if (!collapsedIds.add(nodeId)) {
                                    collapsedIds.remove(nodeId);
                                  }
                                }),
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
    required this.highlightedId,
    required this.onToggleExpanded,
    this.scrollController,
    super.key,
  });

  final AppController controller;
  final NodeTree tree;
  final String parentId;
  final int depth;
  final Set<String> collapsedIds;
  final String? highlightedId;
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
        itemCount: children.length,
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
          final node = children[index];
          final expanded = !widget.collapsedIds.contains(node.id);
          final canExpand =
              !widget.tree.isLeaf(node.id) &&
              widget.depth < EventBoardView.maximumPreviewDepth;
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
            highlightedId: widget.highlightedId,
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
    orderedIds.insert(newIndex, movedId);
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
    required this.onToggleExpanded,
    required this.onKeyboardReorder,
    required this.collapsedIds,
    required this.highlightedId,
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
  final VoidCallback? onToggleExpanded;
  final void Function(int direction, bool toEdge) onKeyboardReorder;
  final Set<String> collapsedIds;
  final String? highlightedId;
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
        onToggleExpanded: onToggleExpanded,
        onKeyboardReorder: onKeyboardReorder,
      ),
      if (expanded &&
          depth < EventBoardView.maximumPreviewDepth &&
          tree.childrenOf(node.id).isNotEmpty)
        _EventTaskGroup(
          controller: controller,
          tree: tree,
          parentId: node.id,
          depth: depth + 1,
          collapsedIds: collapsedIds,
          highlightedId: highlightedId,
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
    required this.onToggleExpanded,
    required this.onKeyboardReorder,
  });

  final AppController controller;
  final TodoNode node;
  final NodeTree tree;
  final int depth;
  final int reorderIndex;
  final bool expanded;
  final bool dragging;
  final bool highlighted;
  final VoidCallback? onToggleExpanded;
  final void Function(int direction, bool toEdge) onKeyboardReorder;

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
    return Focus(
      focusNode: focusNode,
      onFocusChange: (value) => setState(() => focused = value),
      onKeyEvent: (_, event) {
        if (event is! KeyDownEvent || !HardwareKeyboard.instance.isAltPressed) {
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
            color: highlighted
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
              onTap: () {
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
                        width: 20,
                        child: AnimatedOpacity(
                          opacity: hovered || widget.dragging ? 1 : 0.45,
                          duration: const Duration(milliseconds: 90),
                          child: ReorderableDragStartListener(
                            index: widget.reorderIndex,
                            key: ValueKey<String>('event-task-drag-${node.id}'),
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
                      SizedBox(
                        width: 22,
                        child: onToggleExpanded == null
                            ? null
                            : IconButton(
                                key: ValueKey<String>(
                                  'event-expand-${node.id}',
                                ),
                                tooltip: expanded ? '折叠' : '展开',
                                padding: EdgeInsets.zero,
                                visualDensity: VisualDensity.compact,
                                onPressed: onToggleExpanded,
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
                        onTap: children.isEmpty
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
                      const SizedBox(width: 8),
                      Expanded(
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            key: ValueKey<String>('event-row-title-${node.id}'),
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
                      if (node.deadline != null && !hovered)
                        Text(
                          formatCompactDate(node.deadline!),
                          style: TextStyle(color: colors.faint, fontSize: 9),
                        ),
                      if (children.isNotEmpty &&
                          onToggleExpanded == null &&
                          !hovered) ...<Widget>[
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
                        opacity: hovered ? 1 : 0,
                        duration: const Duration(milliseconds: 120),
                        child: IgnorePointer(
                          ignoring: !hovered,
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
                                onPressed: () =>
                                    _createChildNode(context, controller, node),
                                icon: Icon(
                                  Icons.add,
                                  size: 16,
                                  color: colors.muted,
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
                                  key: ValueKey<String>(
                                    'event-row-menu-${node.id}',
                                  ),
                                  tooltip: '任务操作',
                                  padding: EdgeInsets.zero,
                                  visualDensity: VisualDensity.compact,
                                  onPressed: menu.open,
                                  icon: Icon(
                                    Icons.more_horiz,
                                    size: 16,
                                    color: colors.muted,
                                  ),
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
  const _DeadlineLabel({required this.deadline, required this.now});

  final DateTime? deadline;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    if (deadline == null) return const SizedBox.shrink();
    final overdue = isOverdue(deadline, now);
    return Text(
      overdue ? '已逾期' : formatCompactDate(deadline!),
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
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: colors.muted,
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

Future<void> _createChildNode(
  BuildContext context,
  AppController controller,
  TodoNode parent,
) async {
  final title = await showDialog<String>(
    context: context,
    builder: (context) => const CreateNodeDialog(
      title: '新建子任务',
      fieldLabel: '任务名称',
      hintText: '输入子任务名称',
    ),
  );
  if (title == null || title.trim().isEmpty) return;
  await controller.create(
    parentId: parent.id,
    title: title,
    selectCreated: false,
  );
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
