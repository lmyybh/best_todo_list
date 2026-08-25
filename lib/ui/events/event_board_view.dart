import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/app_controller.dart';
import '../../app/app_theme.dart';
import '../../domain/node_tree.dart';
import '../../domain/todo_node.dart';
import '../common/create_node_dialog.dart';
import '../common/delete_node.dart';
import '../common/formatters.dart';
import 'event_card_task_interaction.dart';

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
  final FocusNode cardFocusNode = FocusNode(debugLabel: 'event-card');
  bool cardHovered = false;
  bool cardDragging = false;

  @override
  void dispose() {
    cardFocusNode.dispose();
    super.dispose();
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
                                onPressed: () => confirmDeleteNode(
                                  context,
                                  controller,
                                  node,
                                ),
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
                  child: EventCardTaskInteraction(
                    controller: controller,
                    rootEventId: node.id,
                  ),
                ),
              ],
            ),
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
    final overdue = node.deadline?.isOverdue(now) ?? false;
    return Text(
      overdue ? '已逾期' : formatCompactDeadline(node.deadline!),
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
