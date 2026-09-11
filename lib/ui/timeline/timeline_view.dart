import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/app_controller.dart';
import '../../app/app_theme.dart';
import '../../domain/timeline.dart';
import '../../domain/todo_node.dart';
import '../common/formatters.dart';

class TimelineView extends StatelessWidget {
  const TimelineView({required this.controller, super.key});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final projection = controller.timelineProjection;
    final overdue = projection.overdue;
    final regular = projection.regular;
    final completed = projection.completed;
    final abandoned = projection.abandoned;
    final treeEntries = <TimelineTreeEntry>[
      ...projection.overdueTree,
      ...projection.regularTree,
    ];
    final expandableEntries = treeEntries
        .where(
          (entry) =>
              entry.entry.isEvent &&
              entry.matchingCount > (entry.isContext ? 0 : 1),
        )
        .toList();
    final allExpanded =
        expandableEntries.isNotEmpty &&
        expandableEntries.every(
          (entry) => controller.isTimelineExpanded(
            entry.entry.node.id,
            isRoot: entry.depth == 0,
          ),
        );

    return Focus(
      autofocus: true,
      onKeyEvent: (_, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
          controller.moveTimelineSelection(-1);
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
          controller.moveTimelineSelection(1);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 880),
          child: Column(
            children: <Widget>[
              _DateNavigator(controller: controller, projection: projection),
              _TimelineContext(
                projection: projection,
                hasHierarchy: expandableEntries.isNotEmpty,
                allExpanded: allExpanded,
                onToggleAll: () => allExpanded
                    ? controller.collapseTimelineTrees(treeEntries)
                    : controller.expandTimelineTrees(treeEntries),
              ),
              Expanded(
                child:
                    overdue.isEmpty &&
                        regular.isEmpty &&
                        completed.isEmpty &&
                        abandoned.isEmpty
                    ? const _TimelineEmpty()
                    : ListView(
                        key: const ValueKey<String>('timeline-task-list'),
                        padding: const EdgeInsets.fromLTRB(30, 8, 30, 48),
                        children: <Widget>[
                          if (overdue.isNotEmpty) ...<Widget>[
                            _TimelineSection(
                              title: '已逾期',
                              count: overdue.length,
                              danger: true,
                            ),
                            const SizedBox(height: 10),
                            _TimelineTreeList(
                              controller: controller,
                              entries: projection.overdueTree,
                            ),
                          ],
                          if (regular.isNotEmpty ||
                              projection.laterSelected) ...<Widget>[
                            if (overdue.isNotEmpty) const SizedBox(height: 20),
                            _TimelineSection(
                              title: projection.laterSelected
                                  ? '更晚'
                                  : _relativeDateLabel(
                                      projection.selectedDate,
                                      projection.now,
                                    ),
                              count: regular.length,
                            ),
                            const SizedBox(height: 10),
                            _TimelineTreeList(
                              controller: controller,
                              entries: projection.regularTree,
                            ),
                          ] else if (overdue.isEmpty)
                            _TimelineOpenEmpty(completed: completed.isNotEmpty),
                          if (completed.isNotEmpty) ...<Widget>[
                            const SizedBox(height: 20),
                            _TimelineSection(
                              title: '已完成',
                              count: completed.length,
                            ),
                            const SizedBox(height: 10),
                            _TimelineActivityList(
                              controller: controller,
                              entries: completed,
                              kind: _ActivityKind.completed,
                            ),
                          ],
                          if (abandoned.isNotEmpty) ...<Widget>[
                            const SizedBox(height: 20),
                            _TimelineSection(
                              title: '已放弃',
                              count: abandoned.length,
                            ),
                            const SizedBox(height: 10),
                            _TimelineActivityList(
                              controller: controller,
                              entries: abandoned,
                              kind: _ActivityKind.abandoned,
                            ),
                          ],
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DateNavigator extends StatelessWidget {
  const _DateNavigator({required this.controller, required this.projection});

  final AppController controller;
  final TimelineProjection projection;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final start = projection.windowStart;
    return Padding(
      padding: const EdgeInsets.fromLTRB(30, 24, 30, 0),
      child: Column(
        children: <Widget>[
          SizedBox(
            height: 42,
            child: Row(
              children: <Widget>[
                Text(
                  '${start.year} 年 ${start.month} 月',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 9),
                Text(
                  '第 ${_isoWeek(start)} 周',
                  style: TextStyle(color: colors.muted, fontSize: 11),
                ),
                const Spacer(),
                _NavigatorButton(
                  key: const ValueKey<String>('timeline-previous-week'),
                  tooltip: '上一周',
                  icon: Icons.chevron_left,
                  onPressed: () => controller.shiftTimelineWindow(-1),
                ),
                TextButton(
                  key: const ValueKey<String>('timeline-today'),
                  onPressed: controller.resetTimelineToToday,
                  child: const Text('回到今天', style: TextStyle(fontSize: 11)),
                ),
                _NavigatorButton(
                  key: const ValueKey<String>('timeline-next-week'),
                  tooltip: '下一周',
                  icon: Icons.chevron_right,
                  onPressed: () => controller.shiftTimelineWindow(1),
                ),
              ],
            ),
          ),
          Container(
            height: 70,
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: colors.borderSoft)),
            ),
            child: Row(
              children: <Widget>[
                for (final date in projection.dates)
                  Expanded(
                    child: _DateButton(
                      date: date,
                      now: projection.now,
                      openCount: projection.countFor(date),
                      completedCount: projection.completedCountFor(date),
                      selected:
                          !projection.laterSelected &&
                          _sameDate(date, projection.selectedDate),
                      onPressed: () => controller.selectTimelineDate(date),
                    ),
                  ),
                Expanded(
                  child: _LaterButton(
                    selected: projection.laterSelected,
                    count: projection.laterCount,
                    onPressed: controller.selectTimelineLater,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DateButton extends StatelessWidget {
  const _DateButton({
    required this.date,
    required this.now,
    required this.openCount,
    required this.completedCount,
    required this.selected,
    required this.onPressed,
  });

  final DateTime date;
  final DateTime now;
  final int openCount;
  final int completedCount;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => _DateSurface(
    selected: selected,
    onPressed: onPressed,
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        Text(
          _relativeDateLabel(date, now),
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 2),
        Text(
          '${date.day}',
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
        ),
        Text(
          completedCount == 0
              ? openCount == 0
                    ? '无待办'
                    : '$openCount 待办'
              : '$openCount待办 · $completedCount完成',
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.fade,
          style: TextStyle(color: AppColors.of(context).muted, fontSize: 12),
        ),
      ],
    ),
  );
}

class _LaterButton extends StatelessWidget {
  const _LaterButton({
    required this.selected,
    required this.count,
    required this.onPressed,
  });

  final bool selected;
  final int count;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => _DateSurface(
    key: const ValueKey<String>('timeline-later'),
    selected: selected,
    onPressed: onPressed,
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        const Text(
          '更晚',
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 4),
        const Icon(Icons.calendar_month_outlined, size: 15),
        const SizedBox(height: 3),
        Text(
          '$count 待办',
          style: TextStyle(color: AppColors.of(context).muted, fontSize: 10),
        ),
      ],
    ),
  );
}

class _DateSurface extends StatelessWidget {
  const _DateSurface({
    required this.selected,
    required this.onPressed,
    required this.child,
    super.key,
  });

  final bool selected;
  final VoidCallback onPressed;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Semantics(
      selected: selected,
      button: true,
      child: InkWell(
        onTap: onPressed,
        mouseCursor: SystemMouseCursors.click,
        hoverColor: colors.surfaceHover,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: selected
                ? colors.accentSoft.withValues(alpha: 0.55)
                : Colors.transparent,
            border: selected
                ? const Border(
                    bottom: BorderSide(color: AppTheme.accent, width: 2),
                  )
                : null,
          ),
          child: DefaultTextStyle.merge(
            style: TextStyle(color: selected ? AppTheme.accent : colors.muted),
            child: Center(child: child),
          ),
        ),
      ),
    );
  }
}

class _TimelineContext extends StatelessWidget {
  const _TimelineContext({
    required this.projection,
    required this.hasHierarchy,
    required this.allExpanded,
    required this.onToggleAll,
  });

  final TimelineProjection projection;
  final bool hasHierarchy;
  final bool allExpanded;
  final VoidCallback onToggleAll;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(30, 14, 30, 8),
    child: Row(
      children: <Widget>[
        Text(
          projection.laterSelected
              ? '更晚的任务'
              : '${projection.selectedDate.month} 月 ${projection.selectedDate.day} 日',
          style: TextStyle(color: AppColors.of(context).muted, fontSize: 10),
        ),
        const Spacer(),
        if (hasHierarchy)
          TextButton.icon(
            key: const ValueKey<String>('timeline-toggle-all'),
            onPressed: onToggleAll,
            icon: Icon(
              allExpanded ? Icons.unfold_less : Icons.unfold_more,
              size: 15,
            ),
            label: Text(allExpanded ? '折叠全部' : '展开全部'),
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              textStyle: const TextStyle(fontSize: 11),
            ),
          ),
      ],
    ),
  );
}

class _NavigatorButton extends StatelessWidget {
  const _NavigatorButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    super.key,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: tooltip,
    onPressed: onPressed,
    visualDensity: VisualDensity.compact,
    icon: Icon(icon, size: 16),
  );
}

enum _ActivityKind { completed, abandoned }

class _TimelineActivityList extends StatelessWidget {
  const _TimelineActivityList({
    required this.controller,
    required this.entries,
    required this.kind,
  });

  final AppController controller;
  final List<TimelineEntry> entries;
  final _ActivityKind kind;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Material(
      color: Theme.of(context).colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: colors.borderSoft),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: <Widget>[
          for (var index = 0; index < entries.length; index++) ...<Widget>[
            if (index > 0)
              Divider(
                height: 1,
                indent: 14,
                endIndent: 14,
                color: colors.borderSoft,
              ),
            _TimelineActivityRow(
              controller: controller,
              entry: entries[index],
              kind: kind,
            ),
          ],
        ],
      ),
    );
  }
}

class _TimelineActivityRow extends StatefulWidget {
  const _TimelineActivityRow({
    required this.controller,
    required this.entry,
    required this.kind,
  });

  final AppController controller;
  final TimelineEntry entry;
  final _ActivityKind kind;

  @override
  State<_TimelineActivityRow> createState() => _TimelineActivityRowState();
}

class _TimelineActivityRowState extends State<_TimelineActivityRow> {
  var _hovered = false;

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final entry = widget.entry;
    final node = entry.node;
    final completed = widget.kind == _ActivityKind.completed;
    final occurredAt = completed ? entry.completedAt! : node.abandonedAt!;
    final colors = AppColors.of(context);
    final path = entry.path.length > 1
        ? entry.path.sublist(0, entry.path.length - 1).join(' / ')
        : '顶层事件';

    void openNode() {
      controller.select(node.id);
      controller.setView(AppView.events);
    }

    return Semantics(
      key: ValueKey<String>('timeline-activity-${node.id}'),
      button: true,
      label: '${completed ? '已完成' : '已放弃'}：${node.title}',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: Material(
          color: _hovered ? colors.surfaceHover : Colors.transparent,
          animationDuration: const Duration(milliseconds: 150),
          child: InkWell(
            onTap: openNode,
            hoverColor: Colors.transparent,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 52),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 7, 14, 7),
                child: Row(
                  children: <Widget>[
                    if (completed)
                      IconButton(
                        tooltip: '取消完成',
                        onPressed: () => controller.setTaskStatus(
                          node.id,
                          TodoNodeStatus.active,
                        ),
                        visualDensity: VisualDensity.compact,
                        constraints: const BoxConstraints.tightFor(
                          width: 24,
                          height: 24,
                        ),
                        padding: EdgeInsets.zero,
                        icon: Icon(
                          Icons.check_circle,
                          size: 18,
                          color: colors.completion,
                        ),
                      )
                    else
                      IconButton(
                        tooltip: '取消放弃',
                        onPressed: () => controller.setTaskStatus(
                          node.id,
                          TodoNodeStatus.active,
                        ),
                        visualDensity: VisualDensity.compact,
                        constraints: const BoxConstraints.tightFor(
                          width: 24,
                          height: 24,
                        ),
                        padding: EdgeInsets.zero,
                        icon: Icon(
                          Icons.block_outlined,
                          size: 18,
                          color: colors.muted,
                        ),
                      ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Text(
                            node.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: completed
                                  ? Theme.of(context).colorScheme.onSurface
                                  : colors.muted,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              decoration: completed
                                  ? null
                                  : TextDecoration.lineThrough,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            path,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: colors.muted, fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text(
                          '${formatTime(occurredAt)} ${completed ? '完成' : '放弃'}',
                          style: TextStyle(
                            color: completed ? colors.completion : colors.muted,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (node.deadline != null) ...<Widget>[
                          const SizedBox(height: 2),
                          Text(
                            '原定 ${formatDeadline(node.deadline)}',
                            style: TextStyle(color: colors.muted, fontSize: 10),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TimelineTreeList extends StatelessWidget {
  const _TimelineTreeList({required this.controller, required this.entries});

  final AppController controller;
  final List<TimelineTreeEntry> entries;

  bool _isVisible(TimelineTreeEntry entry) {
    for (var index = 0; index < entry.ancestorIds.length; index++) {
      if (!controller.isTimelineExpanded(
        entry.ancestorIds[index],
        isRoot: index == 0,
      )) {
        return false;
      }
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final groups = <List<TimelineTreeEntry>>[];
    for (final entry in entries) {
      if (entry.depth == 0 || groups.isEmpty) {
        groups.add(<TimelineTreeEntry>[]);
      }
      groups.last.add(entry);
    }

    return AnimatedSize(
      duration: const Duration(milliseconds: 180),
      alignment: Alignment.topCenter,
      curve: Curves.easeOutCubic,
      child: Column(
        children: <Widget>[
          for (final group in groups)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _TimelineTreeGroup(
                controller: controller,
                entries: group.where(_isVisible).toList(),
              ),
            ),
        ],
      ),
    );
  }
}

class _TimelineTreeGroup extends StatelessWidget {
  const _TimelineTreeGroup({required this.controller, required this.entries});

  final AppController controller;
  final List<TimelineTreeEntry> entries;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Material(
      color: Theme.of(context).colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: colors.borderSoft),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: <Widget>[
          for (var index = 0; index < entries.length; index++) ...<Widget>[
            if (index > 0)
              Divider(
                height: 1,
                indent: 14,
                endIndent: 14,
                color: colors.borderSoft,
              ),
            _TimelineTreeRow(controller: controller, treeEntry: entries[index]),
          ],
        ],
      ),
    );
  }
}

class _TimelineTreeRow extends StatefulWidget {
  const _TimelineTreeRow({required this.controller, required this.treeEntry});

  final AppController controller;
  final TimelineTreeEntry treeEntry;

  @override
  State<_TimelineTreeRow> createState() => _TimelineTreeRowState();
}

class _TimelineTreeRowState extends State<_TimelineTreeRow> {
  var _hovered = false;

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final treeEntry = widget.treeEntry;
    final entry = treeEntry.entry;
    final node = entry.node;
    final colors = AppColors.of(context);
    final tree = controller.tree;
    final isEvent = entry.isEvent;
    final complete = entry.isComplete;
    final abandoned = node.isAbandoned;
    final leaves = isEvent
        ? tree.actionableLeafDescendantsOf(node.id)
        : const <TodoNode>[];
    final completedCount = leaves
        .where((leaf) => leaf.completedAt != null)
        .length;
    final hasShownChildren =
        isEvent && treeEntry.matchingCount > (treeEntry.isContext ? 0 : 1);
    final expanded =
        hasShownChildren &&
        controller.isTimelineExpanded(node.id, isRoot: treeEntry.depth == 0);
    final overdue =
        (node.deadline?.isOverdue(controller.now) ?? false) && !complete;
    final visualDepth = treeEntry.depth > 5 ? 5 : treeEntry.depth;
    final rowColor = _hovered
        ? colors.surfaceHover
        : isEvent
        ? colors.accentSoft.withValues(alpha: 0.3)
        : Colors.transparent;

    void openNode() {
      controller.select(node.id);
      controller.setView(AppView.events);
    }

    return Focus(
      onKeyEvent: (_, event) {
        if (event is! KeyDownEvent || !hasShownChildren) {
          return KeyEventResult.ignored;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowRight && !expanded ||
            event.logicalKey == LogicalKeyboardKey.arrowLeft && expanded) {
          controller.toggleTimelineExpanded(
            node.id,
            isRoot: treeEntry.depth == 0,
          );
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Semantics(
        key: ValueKey<String>('timeline-row-${node.id}'),
        button: true,
        label: '${isEvent ? '事件' : '任务'}：${node.title}',
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: Material(
            color: rowColor,
            animationDuration: const Duration(milliseconds: 150),
            child: InkWell(
              onTap: openNode,
              hoverColor: Colors.transparent,
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: isEvent ? 50 : 44),
                child: Stack(
                  children: <Widget>[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(10, 6, 12, 6),
                      child: Row(
                        children: <Widget>[
                          if (visualDepth > 0)
                            CustomPaint(
                              size: Size(visualDepth * 18.0, 32),
                              painter: _TreeLinesPainter(
                                depth: visualDepth,
                                color: colors.border,
                              ),
                            ),
                          if (isEvent && hasShownChildren)
                            IconButton(
                              key: ValueKey<String>(
                                'timeline-expand-${node.id}',
                              ),
                              tooltip: expanded ? '折叠子任务' : '展开子任务',
                              onPressed: () =>
                                  controller.toggleTimelineExpanded(
                                    node.id,
                                    isRoot: treeEntry.depth == 0,
                                  ),
                              icon: Icon(
                                expanded
                                    ? Icons.keyboard_arrow_down
                                    : Icons.keyboard_arrow_right,
                                size: 18,
                              ),
                              visualDensity: VisualDensity.compact,
                              constraints: const BoxConstraints.tightFor(
                                width: 28,
                                height: 28,
                              ),
                              padding: EdgeInsets.zero,
                            )
                          else
                            const SizedBox(width: 28),
                          if (abandoned)
                            IconButton(
                              tooltip: '取消放弃',
                              onPressed: () => controller.setTaskStatus(
                                node.id,
                                TodoNodeStatus.active,
                              ),
                              visualDensity: VisualDensity.compact,
                              constraints: const BoxConstraints.tightFor(
                                width: 28,
                                height: 28,
                              ),
                              padding: EdgeInsets.zero,
                              icon: Icon(
                                Icons.block_outlined,
                                size: 18,
                                color: colors.muted,
                              ),
                            )
                          else if (isEvent)
                            const SizedBox(width: 28)
                          else
                            SizedBox(
                              width: 28,
                              height: 28,
                              child: Checkbox.adaptive(
                                value: complete,
                                onChanged: (value) => controller.setTaskStatus(
                                  node.id,
                                  value ?? false
                                      ? TodoNodeStatus.completed
                                      : TodoNodeStatus.active,
                                ),
                                shape: const CircleBorder(),
                                visualDensity: VisualDensity.compact,
                              ),
                            ),
                          const SizedBox(width: 9),
                          Expanded(
                            child: Tooltip(
                              message: entry.path.join(' / '),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: <Widget>[
                                  Text(
                                    node.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: isEvent
                                          ? FontWeight.w600
                                          : FontWeight.w500,
                                      decoration: complete || abandoned
                                          ? TextDecoration.lineThrough
                                          : null,
                                      color: complete || abandoned
                                          ? colors.muted
                                          : Theme.of(
                                              context,
                                            ).colorScheme.onSurface,
                                    ),
                                  ),
                                  if (isEvent) ...<Widget>[
                                    const SizedBox(height: 2),
                                    Text(
                                      '${treeEntry.matchingCount} 项相关 · '
                                      '$completedCount/${leaves.length} 已完成'
                                      '${treeEntry.depth > 5 ? ' · 第 ${treeEntry.depth + 1} 层' : ''}',
                                      style: TextStyle(
                                        color: colors.muted,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                          if (node.deadline != null) ...<Widget>[
                            const SizedBox(width: 12),
                            Text(
                              formatDeadline(node.deadline),
                              style: TextStyle(
                                color: overdue
                                    ? colors.danger
                                    : Theme.of(context).colorScheme.primary,
                                fontSize: 11,
                                fontWeight: overdue
                                    ? FontWeight.w600
                                    : FontWeight.normal,
                              ),
                            ),
                          ],
                          const SizedBox(width: 4),
                          AnimatedOpacity(
                            duration: const Duration(milliseconds: 150),
                            opacity: _hovered ? 1 : 0,
                            child: Icon(
                              Icons.chevron_right,
                              size: 16,
                              color: colors.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (overdue)
                      Positioned(
                        left: 0,
                        top: 0,
                        bottom: 0,
                        width: 3,
                        child: ColoredBox(color: colors.danger),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TreeLinesPainter extends CustomPainter {
  const _TreeLinesPainter({required this.depth, required this.color});

  final int depth;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    for (var level = 0; level < depth; level++) {
      final x = level * 18.0 + 9;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    final branchX = (depth - 1) * 18.0 + 9;
    canvas.drawLine(
      Offset(branchX, size.height / 2),
      Offset(size.width, size.height / 2),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _TreeLinesPainter oldDelegate) =>
      oldDelegate.depth != depth || oldDelegate.color != color;
}

class _TimelineSection extends StatelessWidget {
  const _TimelineSection({
    required this.title,
    required this.count,
    this.danger = false,
  });
  final String title;
  final int count;
  final bool danger;

  @override
  Widget build(BuildContext context) => Row(
    children: <Widget>[
      Text(
        title,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: danger ? AppColors.of(context).danger : null,
        ),
      ),
      const SizedBox(width: 6),
      Text(
        '$count',
        style: TextStyle(fontSize: 11, color: AppColors.of(context).muted),
      ),
    ],
  );
}

class _TimelineOpenEmpty extends StatelessWidget {
  const _TimelineOpenEmpty({required this.completed});

  final bool completed;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Semantics(
      key: const ValueKey<String>('timeline-open-empty'),
      label: completed ? '今天的待办已全部完成' : '这一天没有待办',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          color: completed
              ? colors.accentSoft.withValues(alpha: 0.42)
              : Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: colors.borderSoft),
        ),
        child: Row(
          children: <Widget>[
            Icon(
              completed ? Icons.check_circle_outline : Icons.event_available,
              size: 18,
              color: completed ? colors.completion : colors.muted,
            ),
            const SizedBox(width: 9),
            Text(
              completed ? '今天的待办已全部完成' : '这一天没有待办',
              style: TextStyle(
                color: completed ? colors.completion : colors.muted,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TimelineEmpty extends StatelessWidget {
  const _TimelineEmpty();

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(
          Icons.event_available_outlined,
          size: 44,
          color: AppColors.of(context).muted,
        ),
        const SizedBox(height: 13),
        const Text(
          '这一天没有待办',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 6),
        Text(
          '给自己留一点空白也很好',
          style: TextStyle(color: AppColors.of(context).muted, fontSize: 12),
        ),
      ],
    ),
  );
}

String _relativeDateLabel(DateTime date, DateTime now) {
  final start = DateTime(now.year, now.month, now.day);
  final difference = DateTime(
    date.year,
    date.month,
    date.day,
  ).difference(start).inDays;
  if (difference == 0) return '今天';
  if (difference == 1) return '明天';
  return '周${const <int, String>{1: '一', 2: '二', 3: '三', 4: '四', 5: '五', 6: '六', 7: '日'}[date.weekday]}';
}

bool _sameDate(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

int _isoWeek(DateTime date) {
  final thursday = date.add(Duration(days: 4 - date.weekday));
  final firstThursday = DateTime(thursday.year, 1, 4);
  return 1 +
      thursday
              .difference(
                firstThursday.subtract(
                  Duration(days: firstThursday.weekday - 4),
                ),
              )
              .inDays ~/
          7;
}
