import 'dart:async';

import 'package:flutter/cupertino.dart' show CupertinoSlidingSegmentedControl;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/app_controller.dart';
import '../../app/node_write_result.dart';
import '../../app/app_theme.dart';
import '../../domain/deadline.dart';
import '../../domain/node_tree.dart';
import '../../domain/todo_node.dart';
import '../common/create_node_dialog.dart';
import '../common/delete_node.dart';
import '../common/formatters.dart';
import 'event_board_layout.dart';
import 'event_board_reorder_session.dart';
import 'event_card_task_interaction.dart';
import 'today_focus_projection.dart';

class EventBoardView extends StatefulWidget {
  const EventBoardView({required this.controller, super.key});

  final AppController controller;

  static const double minimumCardWidth = EventBoardLayout.minimumCardWidth;
  static const double maximumCardWidth = EventBoardLayout.maximumCardWidth;
  static const double singleColumnMaximumWidth =
      EventBoardLayout.singleColumnMaximumWidth;
  static const double minimumCardHeight = EventBoardLayout.minimumCardHeight;
  static const double maximumCardHeight = EventBoardLayout.maximumCardHeight;
  static const double spacing = EventBoardLayout.spacing;
  static const int maximumColumns = EventBoardLayout.maximumColumns;
  static const int previewRowLimit = EventBoardLayout.previewRowLimit;

  @override
  State<EventBoardView> createState() => _EventBoardViewState();
}

class _EventBoardViewState extends State<EventBoardView> {
  final GlobalKey boardKey = GlobalKey();
  final GlobalKey scrollViewportKey = GlobalKey();
  final ScrollController boardScrollController = ScrollController();
  final FocusNode boardFocusNode = FocusNode(debugLabel: 'event-board');
  final EventBoardReorderSession reorderSession = EventBoardReorderSession();
  Timer? autoScrollTimer;
  Timer? responsiveReflowTimer;
  double autoScrollVelocity = 0;
  int? renderedColumns;
  bool animateResponsiveReflow = false;
  Offset? latestDragPosition;
  late EventBoardFilter selectedFilter;
  bool focusBoardBuilt = false;
  Object? allBoardCacheKey;
  Widget? allBoardCache;
  Object? focusBoardCacheKey;
  Widget? focusBoardCache;

  @override
  void initState() {
    super.initState();
    selectedFilter = widget.controller.eventBoardFilter;
    focusBoardBuilt = selectedFilter == EventBoardFilter.todayFocus;
  }

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
    final sourceTree = widget.controller.tree;
    final allRoots = sourceTree.visibleChildrenOf(null);
    final todayFocus = TodayFocusProjection.from(
      source: sourceTree,
      roots: allRoots,
      now: widget.controller.now,
    );
    final focusMode = selectedFilter == EventBoardFilter.todayFocus;
    final allRootsById = <String, TodoNode>{
      for (final root in allRoots) root.id: root,
    };
    final allRootIds = allRoots.map((root) => root.id).toList();
    final previewIds = reorderSession.orderedIds;
    final orderedAllIds =
        previewIds != null &&
            previewIds.length == allRootIds.length &&
            previewIds.every(allRootsById.containsKey)
        ? previewIds
        : allRootIds;
    final orderedAllRoots = orderedAllIds
        .map((id) => allRootsById[id]!)
        .toList();
    return Focus(
      focusNode: boardFocusNode,
      onKeyEvent: (_, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.escape &&
            reorderSession.active) {
          _cancelEventDrag();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: LayoutBuilder(
        builder: (context, constraints) {
          final maxHeight = constraints.hasBoundedHeight
              ? constraints.maxHeight
              : double.infinity;
          final allLayout = const EventBoardLayout().project(
            maxWidth: constraints.maxWidth,
            maxHeight: maxHeight,
            tree: sourceTree,
            roots: orderedAllRoots,
          );
          final focusLayout = const EventBoardLayout().project(
            maxWidth: constraints.maxWidth,
            maxHeight: maxHeight,
            tree: todayFocus.tree,
            roots: todayFocus.roots,
            includeNewEventCard: false,
          );
          final activeLayout = focusMode ? focusLayout : allLayout;
          _recordRenderedColumns(activeLayout.columns);
          final animationsDisabled = MediaQuery.disableAnimationsOf(context);
          final layoutAnimationDuration = animationsDisabled
              ? Duration.zero
              : reorderSession.active
              ? const Duration(milliseconds: 160)
              : animateResponsiveReflow
              ? const Duration(milliseconds: 140)
              : Duration.zero;
          final cacheKey = (
            sourceTree,
            orderedAllIds.join('\u0000'),
            allLayout.gridWidth,
            allLayout.totalHeight,
            allLayout.cardWidth,
            allLayout.columns,
            layoutAnimationDuration,
          );
          if (allBoardCacheKey != cacheKey || allBoardCache == null) {
            allBoardCacheKey = cacheKey;
            allBoardCache = _buildBoard(
              context: context,
              roots: orderedAllRoots,
              allRoots: allRoots,
              displayTree: sourceTree,
              layout: allLayout,
              animationDuration: layoutAnimationDuration,
              focusMode: false,
              todayFocus: todayFocus,
              includeNewEventCard: true,
              stackKey: boardKey,
            );
          }
          if (focusBoardBuilt) {
            final now = widget.controller.now;
            final focusCacheKey = (
              sourceTree,
              DateTime(now.year, now.month, now.day),
              todayFocus.roots
                  .map(
                    (root) => '${root.id}:${todayFocus.taskCountFor(root.id)}',
                  )
                  .join('\u0000'),
              focusLayout.gridWidth,
              focusLayout.totalHeight,
              focusLayout.cardWidth,
              focusLayout.columns,
              layoutAnimationDuration,
            );
            if (focusBoardCacheKey != focusCacheKey ||
                focusBoardCache == null) {
              focusBoardCacheKey = focusCacheKey;
              focusBoardCache = _buildBoard(
                context: context,
                roots: todayFocus.roots,
                allRoots: allRoots,
                displayTree: todayFocus.tree,
                layout: focusLayout,
                animationDuration: layoutAnimationDuration,
                focusMode: true,
                todayFocus: todayFocus,
                includeNewEventCard: false,
              );
            }
          }

          return KeyedSubtree(
            key: const ValueKey<String>('event-board-scroll'),
            child: SingleChildScrollView(
              key: scrollViewportKey,
              controller: boardScrollController,
              padding: activeLayout.padding,
              child: Align(
                alignment: Alignment.topCenter,
                child: SizedBox(
                  width: activeLayout.gridWidth,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      _EventBoardToolbar(
                        eventCount: focusMode
                            ? todayFocus.roots.length
                            : allRoots.length,
                        selected: selectedFilter,
                        todayEventCount: todayFocus.roots.length,
                        onSelected: _setFilter,
                      ),
                      const SizedBox(height: 16),
                      Visibility(
                        visible: !focusMode,
                        maintainState: true,
                        maintainAnimation: true,
                        child: allBoardCache!,
                      ),
                      if (focusBoardBuilt)
                        Visibility(
                          visible: focusMode,
                          maintainState: true,
                          maintainAnimation: true,
                          child: focusBoardCache!,
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

  void _setFilter(EventBoardFilter filter) {
    if (selectedFilter == filter) return;
    if (reorderSession.active) _cancelEventDrag();
    widget.controller.setEventBoardFilter(filter, notify: false);
    setState(() {
      selectedFilter = filter;
      if (filter == EventBoardFilter.todayFocus) focusBoardBuilt = true;
    });
    if (boardScrollController.hasClients) boardScrollController.jumpTo(0);
  }

  Widget _buildBoard({
    required BuildContext context,
    required List<TodoNode> roots,
    required List<TodoNode> allRoots,
    required NodeTree displayTree,
    required EventBoardLayoutProjection layout,
    required Duration animationDuration,
    required bool focusMode,
    required TodayFocusProjection todayFocus,
    required bool includeNewEventCard,
    Key? stackKey,
  }) {
    if (allRoots.isEmpty) {
      return _EmptyBoard(onCreate: () => _createEvent(context));
    }
    if (focusMode && roots.isEmpty) {
      return _TodayFocusEmpty(
        onShowAll: () => _setFilter(EventBoardFilter.all),
      );
    }
    final items = <TodoNode?>[...roots, if (includeNewEventCard) null];
    return SizedBox(
      key: const ValueKey<String>('event-board-wrap'),
      height: layout.totalHeight,
      child: RepaintBoundary(
        child: Stack(
          key: stackKey,
          children: <Widget>[
            for (var index = 0; index < items.length; index++)
              _buildPositionedItem(
                context: context,
                item: items[index],
                allRoots: allRoots,
                displayTree: displayTree,
                focusMode: focusMode,
                todayTaskCount: items[index] == null
                    ? 0
                    : todayFocus.taskCountFor(items[index]!.id),
                index: index,
                columns: layout.columns,
                width: layout.cardWidth,
                height: layout.heightAt(index),
                animationDuration: animationDuration,
                left: layout.leftAt(index),
                top: layout.topAt(index),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildPositionedItem({
    required BuildContext context,
    required TodoNode? item,
    required List<TodoNode> allRoots,
    required NodeTree displayTree,
    required bool focusMode,
    required int todayTaskCount,
    required int index,
    required int columns,
    required double width,
    required double height,
    required Duration animationDuration,
    required double left,
    required double top,
  }) {
    Widget buildEventCard({bool dropTargeted = false}) => _EventCard(
      controller: widget.controller,
      node: item!,
      tree: displayTree,
      now: widget.controller.now,
      color:
          _eventColors[allRoots.indexWhere((root) => root.id == item.id) %
              _eventColors.length],
      dropTargeted: dropTargeted,
      focusMode: focusMode,
      todayTaskCount: todayTaskCount,
      onDragStarted: () => _startDragging(item.id, allRoots),
      onDragUpdate: _updateEventAutoScroll,
      onDragEnd: _endDragging,
      onKeyboardReorder: (direction, toEdge) =>
          _keyboardReorderEvent(item.id, direction, toEdge, allRoots),
    );

    final child = item == null
        ? DragTarget<String>(
            onWillAcceptWithDetails: (_) => true,
            onMove: (_) => _previewAtEnd(),
            builder: (context, candidates, _) => _NewEventCard(
              onPressed: () => _createEvent(context),
              dropTargeted: candidates.isNotEmpty,
            ),
          )
        : focusMode
        ? buildEventCard()
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
            builder: (context, candidates, _) =>
                buildEventCard(dropTargeted: candidates.isNotEmpty),
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
      reorderSession.start(id, roots.map((root) => root.id).toList());
      latestDragPosition = null;
    });
  }

  void _previewAround(String targetId, {required bool after}) {
    if (reorderSession.previewAround(targetId, after: after)) {
      setState(() {});
    }
  }

  void _previewAtEnd() {
    if (reorderSession.previewAtEnd()) {
      setState(() {});
    }
  }

  void _endDragging(DraggableDetails details) {
    if (!reorderSession.active) return;
    final orderedIds = reorderSession.finish(
      droppedInside: _isInsideBoard(latestDragPosition),
    );
    if (orderedIds != null) {
      unawaited(widget.controller.reorderChildren(null, orderedIds));
    }
    _finishDragPresentation();
  }

  void _finishDragPresentation() {
    _stopEventAutoScroll();
    if (!mounted) return;
    setState(() {
      latestDragPosition = null;
    });
  }

  void _cancelEventDrag() {
    _stopEventAutoScroll();
    setState(() {
      reorderSession.cancel();
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
    final reordered = reorderSession.reorderFromKeyboard(
      id: id,
      direction: direction,
      toEdge: toEdge,
      orderedIds: orderedIds,
    );
    if (reordered != null) {
      unawaited(widget.controller.reorderChildren(null, reordered));
    }
  }

  Future<void> _createEvent(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (context) => CreateNodeDialog(
        showDefaultTodayDeadline: true,
        onSubmitWithDefaultTodayDeadline: (title, defaultTodayDeadline) async {
          final now = widget.controller.now;
          final result = await widget.controller.create(
            title: title,
            deadline: defaultTodayDeadline
                ? TimedDeadline(DateTime(now.year, now.month, now.day, 23))
                : null,
            selectCreated: false,
          );
          if (result is NodeWriteFailure) return '创建失败，请重试';
          widget.controller.showEventOverview();
          return null;
        },
      ),
    );
  }
}

class _EventBoardToolbar extends StatelessWidget {
  const _EventBoardToolbar({
    required this.eventCount,
    required this.selected,
    required this.todayEventCount,
    required this.onSelected,
  });

  final int eventCount;
  final EventBoardFilter selected;
  final int todayEventCount;
  final ValueChanged<EventBoardFilter> onSelected;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return SizedBox(
      key: const ValueKey<String>('event-board-toolbar'),
      height: 32,
      child: Row(
        children: <Widget>[
          const Text(
            '事件',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(width: 8),
          Text(
            '$eventCount 个事件',
            style: TextStyle(color: colors.faint, fontSize: 11),
          ),
          const Spacer(),
          Tooltip(
            message: '今日包含今天截止和已经逾期的未完成任务',
            child: SizedBox(
              key: const ValueKey<String>('event-board-filter'),
              width: 122,
              height: 32,
              child: MouseRegion(
                key: const ValueKey<String>('event-board-filter-cursor'),
                cursor: SystemMouseCursors.click,
                child: CupertinoSlidingSegmentedControl<EventBoardFilter>(
                  key: const ValueKey<String>('event-board-filter-control'),
                  groupValue: selected,
                  backgroundColor: const Color(0xFFECEDE9),
                  thumbColor: const Color(0xFFC9DED9),
                  padding: const EdgeInsets.all(2),
                  proportionalWidth: true,
                  onValueChanged: (value) {
                    if (value != null) onSelected(value);
                  },
                  children: <EventBoardFilter, Widget>{
                    EventBoardFilter.all: _EventBoardFilterLabel(
                      label: '全部',
                      selected: selected == EventBoardFilter.all,
                    ),
                    EventBoardFilter.todayFocus: _EventBoardFilterLabel(
                      label: '今日',
                      count: todayEventCount,
                      selected: selected == EventBoardFilter.todayFocus,
                    ),
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EventBoardFilterLabel extends StatelessWidget {
  const _EventBoardFilterLabel({
    required this.label,
    required this.selected,
    this.count,
  });

  final String label;
  final bool selected;
  final int? count;

  @override
  Widget build(BuildContext context) {
    const selectedForeground = Color(0xFF294D49);
    const mutedForeground = Color(0xFF666D67);
    final foreground = selected ? selectedForeground : mutedForeground;

    return Semantics(
      label: count == null ? label : '$label，$count 个事件',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 7),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              label,
              style: TextStyle(
                color: foreground,
                fontSize: 11,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
            if (count case final count?) ...<Widget>[
              const SizedBox(width: 3),
              Container(
                key: const ValueKey<String>('event-board-today-count'),
                height: 15,
                constraints: const BoxConstraints(minWidth: 15),
                padding: const EdgeInsets.symmetric(horizontal: 3),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selected
                      ? Colors.white.withValues(alpha: 0.62)
                      : Colors.black.withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    color: selected
                        ? selectedForeground
                        : const Color(0xFF626862),
                    fontSize: 8.5,
                    height: 1,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
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
    required this.focusMode,
    required this.todayTaskCount,
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
  final bool focusMode;
  final int todayTaskCount;
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
    final sourceTree = controller.tree;
    final now = widget.now;
    final color = widget.color;
    final dropTargeted = widget.dropTargeted;
    final colors = AppColors.of(context);
    final leaves = sourceTree.actionableLeafDescendantsOf(node.id);
    final completed = leaves.where((leaf) => leaf.completedAt != null).length;
    final abandoned = sourceTree
        .leafDescendantsOf(node.id)
        .where((leaf) => leaf.isAbandoned)
        .length;
    final progress = leaves.isEmpty ? 0.0 : completed / leaves.length;
    final children = sourceTree.childrenOf(node.id);
    Widget dragRegion() => Focus(
      focusNode: cardFocusNode,
      onKeyEvent: (_, event) {
        if (widget.focusMode ||
            event is! KeyDownEvent ||
            !HardwareKeyboard.instance.isAltPressed) {
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
          cursor: widget.focusMode
              ? SystemMouseCursors.basic
              : SystemMouseCursors.grab,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              if (!widget.focusMode) ...<Widget>[
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
              ],
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
                      widget.focusMode
                          ? '${widget.todayTaskCount} 项关注'
                          : children.isEmpty
                          ? '单项任务'
                          : '${children.length} 个直接子任务',
                      style: TextStyle(
                        color: widget.focusMode
                            ? AppTheme.accent
                            : colors.faint,
                        fontSize: 10,
                        fontWeight: widget.focusMode
                            ? FontWeight.w600
                            : FontWeight.normal,
                      ),
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
                            child: widget.focusMode
                                ? dragRegion()
                                : Draggable<String>(
                                    key: ValueKey<String>(
                                      'event-drag-region-${node.id}',
                                    ),
                                    data: node.id,
                                    rootOverlay: true,
                                    dragAnchorStrategy:
                                        pointerDragAnchorStrategy,
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
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.surface,
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
                                                  borderRadius:
                                                      BorderRadius.circular(3),
                                                ),
                                              ),
                                              const SizedBox(width: 10),
                                              Expanded(
                                                child: Text(
                                                  node.title,
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
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
                          if (!widget.focusMode)
                            MenuAnchor(
                              menuChildren: <Widget>[
                                MenuItemButton(
                                  onPressed: () =>
                                      _renameNode(context, controller, node),
                                  child: const Text('重命名'),
                                ),
                                MenuItemButton(
                                  onPressed: () =>
                                      _abandonTask(context, controller, node),
                                  leadingIcon: const Icon(
                                    Icons.block_outlined,
                                    size: 17,
                                  ),
                                  child: const Text('放弃任务'),
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
                            '$completed / ${leaves.length} 已完成'
                            '${abandoned == 0 ? '' : ' · $abandoned 已放弃'}',
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
                    displayTree: tree,
                    focusMode: widget.focusMode,
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

Future<void> _abandonTask(
  BuildContext context,
  AppController controller,
  TodoNode node,
) async {
  final result = await controller.setTaskStatus(
    node.id,
    TodoNodeStatus.abandoned,
  );
  if (!context.mounted || result is NodeWriteFailure) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: const Text('任务已放弃'),
      action: SnackBarAction(
        label: '撤销',
        onPressed: () =>
            controller.setTaskStatus(node.id, TodoNodeStatus.active),
      ),
    ),
  );
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

class _TodayFocusEmpty extends StatelessWidget {
  const _TodayFocusEmpty({required this.onShowAll});

  final VoidCallback onShowAll;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 420,
    child: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(Icons.task_alt, size: 44, color: AppColors.of(context).muted),
          const SizedBox(height: 14),
          const Text(
            '今天没有需要关注的任务',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(
            '今天截止和已经逾期的未完成任务都会显示在这里',
            style: TextStyle(color: AppColors.of(context).muted, fontSize: 12),
          ),
          const SizedBox(height: 18),
          OutlinedButton(onPressed: onShowAll, child: const Text('查看全部事件')),
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
  await showDialog<void>(
    context: context,
    builder: (context) => CreateNodeDialog(
      title: '重命名',
      initialTitle: node.title,
      fieldLabel: '名称',
      hintText: '输入新名称',
      confirmLabel: '保存',
      onSubmit: (title) async {
        final result = await controller.updateTitle(node.id, title);
        return result is NodeWriteFailure ? '保存失败，请重试' : null;
      },
    ),
  );
}
