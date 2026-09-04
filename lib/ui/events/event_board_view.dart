import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/app_controller.dart';
import '../../app/node_write_result.dart';
import '../../app/app_theme.dart';
import '../../domain/node_tree.dart';
import '../../domain/todo_node.dart';
import '../common/create_node_dialog.dart';
import '../common/delete_node.dart';
import '../common/formatters.dart';
import 'event_board_layout.dart';
import 'event_board_reorder_session.dart';
import 'event_card_task_interaction.dart';

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
    final roots = widget.controller.tree.visibleChildrenOf(null);
    final rootsById = <String, TodoNode>{
      for (final root in roots) root.id: root,
    };
    final rootIds = roots.map((root) => root.id).toList();
    final previewIds = reorderSession.orderedIds;
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
            reorderSession.active) {
          _cancelEventDrag();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: LayoutBuilder(
        builder: (context, constraints) {
          final layout = const EventBoardLayout().project(
            maxWidth: constraints.maxWidth,
            maxHeight: constraints.hasBoundedHeight
                ? constraints.maxHeight
                : double.infinity,
            tree: widget.controller.tree,
            roots: orderedRoots,
          );
          _recordRenderedColumns(layout.columns);
          final animationsDisabled = MediaQuery.disableAnimationsOf(context);
          final layoutAnimationDuration = animationsDisabled
              ? Duration.zero
              : reorderSession.active
              ? const Duration(milliseconds: 160)
              : animateResponsiveReflow
              ? const Duration(milliseconds: 140)
              : Duration.zero;
          final items = <TodoNode?>[...orderedRoots, null];

          return KeyedSubtree(
            key: const ValueKey<String>('event-board-scroll'),
            child: SingleChildScrollView(
              key: scrollViewportKey,
              controller: boardScrollController,
              padding: layout.padding,
              child: roots.isEmpty
                  ? _EmptyBoard(onCreate: () => _createEvent(context))
                  : Align(
                      alignment: Alignment.topCenter,
                      child: SizedBox(
                        key: const ValueKey<String>('event-board-wrap'),
                        width: layout.gridWidth,
                        height: layout.totalHeight,
                        child: Stack(
                          key: boardKey,
                          children: <Widget>[
                            for (var index = 0; index < items.length; index++)
                              _buildPositionedItem(
                                context: context,
                                item: items[index],
                                allRoots: roots,
                                index: index,
                                columns: layout.columns,
                                width: layout.cardWidth,
                                height: layout.heightAt(index),
                                animationDuration: layoutAnimationDuration,
                                left: layout.leftAt(index),
                                top: layout.topAt(index),
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
        onSubmit: (title) async {
          final result = await widget.controller.create(
            title: title,
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
    final leaves = tree.actionableLeafDescendantsOf(node.id);
    final completed = leaves.where((leaf) => leaf.completedAt != null).length;
    final abandoned = tree
        .leafDescendantsOf(node.id)
        .where((leaf) => leaf.isAbandoned)
        .length;
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
