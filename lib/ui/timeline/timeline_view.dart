import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/app_controller.dart';
import '../../app/app_theme.dart';
import '../../domain/timeline.dart';
import '../common/formatters.dart';
import '../common/node_tile.dart';

class TimelineView extends StatelessWidget {
  const TimelineView({required this.controller, super.key});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final entries = controller.selectedDateEntries;
    final completed = controller.selectedDateCompletedEntries;
    final overdue =
        !controller.timelineLaterSelected &&
            _sameDate(controller.selectedTimelineDate, controller.now)
        ? entries
              .where(
                (entry) =>
                    isOverdue(
                      entry.node.deadline,
                      controller.now,
                      hasTime: entry.node.hasDeadlineTime,
                    ) &&
                    !entry.isComplete,
              )
              .toList()
        : const <TimelineEntry>[];
    final regular = overdue.isEmpty
        ? entries
        : entries.where((entry) => !overdue.contains(entry)).toList();

    return Focus(
      autofocus: true,
      onKeyEvent: (_, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
          _moveSelection(-1);
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
          _moveSelection(1);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 880),
          child: Column(
            children: <Widget>[
              _DateNavigator(controller: controller),
              _TimelineContext(controller: controller),
              Expanded(
                child: entries.isEmpty && completed.isEmpty
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
                            ...overdue.map(
                              (entry) =>
                                  _Entry(controller: controller, entry: entry),
                            ),
                            const SizedBox(height: 20),
                          ],
                          _TimelineSection(
                            title: controller.timelineLaterSelected
                                ? '更晚'
                                : _relativeDateLabel(
                                    controller.selectedTimelineDate,
                                    controller.now,
                                  ),
                            count: regular.length,
                          ),
                          const SizedBox(height: 10),
                          ...regular.map(
                            (entry) =>
                                _Entry(controller: controller, entry: entry),
                          ),
                          if (completed.isNotEmpty) ...<Widget>[
                            const SizedBox(height: 20),
                            _TimelineSection(
                              title: '已完成',
                              count: completed.length,
                            ),
                            const SizedBox(height: 10),
                            ...completed.map(
                              (entry) =>
                                  _Entry(controller: controller, entry: entry),
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

  void _moveSelection(int direction) {
    final dates = controller.timelineDates;
    if (controller.timelineLaterSelected) {
      if (direction < 0) controller.selectTimelineDate(dates.last);
      return;
    }
    final currentIndex = dates.indexWhere(
      (date) => _sameDate(date, controller.selectedTimelineDate),
    );
    if (currentIndex < 0) return;
    final next = currentIndex + direction;
    if (next < 0) {
      controller.shiftTimelineWindow(-1);
    } else if (next >= dates.length) {
      controller.selectTimelineLater();
    } else {
      controller.selectTimelineDate(dates[next]);
    }
  }
}

class _DateNavigator extends StatelessWidget {
  const _DateNavigator({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final start = controller.timelineWindowStart;
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
                  style: TextStyle(color: colors.faint, fontSize: 9),
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
                  child: const Text('回到今天', style: TextStyle(fontSize: 10)),
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
                for (final date in controller.timelineDates)
                  Expanded(
                    child: _DateButton(
                      date: date,
                      now: controller.now,
                      count: controller.timelineCount(date),
                      selected:
                          !controller.timelineLaterSelected &&
                          _sameDate(date, controller.selectedTimelineDate),
                      onPressed: () => controller.selectTimelineDate(date),
                    ),
                  ),
                Expanded(
                  child: _LaterButton(
                    selected: controller.timelineLaterSelected,
                    count: TimelineQuery(controller.now)
                        .laterEntries(
                          controller.tree,
                          controller.timelineDates.last,
                        )
                        .length,
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
    required this.count,
    required this.selected,
    required this.onPressed,
  });

  final DateTime date;
  final DateTime now;
  final int count;
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
          style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 2),
        Text(
          '${date.day}',
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
        ),
        Text(
          count == 0 ? '无任务' : '$count 项',
          style: TextStyle(color: AppColors.of(context).faint, fontSize: 8),
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
          style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 4),
        const Icon(Icons.calendar_month_outlined, size: 15),
        const SizedBox(height: 3),
        Text(
          '$count 项',
          style: TextStyle(color: AppColors.of(context).faint, fontSize: 8),
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
  const _TimelineContext({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(30, 14, 30, 8),
    child: Align(
      alignment: Alignment.centerLeft,
      child: Text(
        controller.timelineLaterSelected
            ? '更晚的任务'
            : '${controller.selectedTimelineDate.month} 月 ${controller.selectedTimelineDate.day} 日',
        style: TextStyle(color: AppColors.of(context).muted, fontSize: 10),
      ),
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

class _Entry extends StatelessWidget {
  const _Entry({required this.controller, required this.entry});
  final AppController controller;
  final TimelineEntry entry;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 7),
    child: Opacity(
      opacity: entry.isComplete ? 0.65 : 1,
      child: NodeTile(
        node: entry.node,
        tree: controller.tree,
        now: controller.now,
        path: entry.path.length > 1
            ? entry.path.sublist(0, entry.path.length - 1).join(' / ')
            : '顶层事件',
        onOpen: () {
          controller.select(entry.node.id);
          controller.setView(AppView.events);
        },
        onToggleComplete: (value) =>
            controller.setCompleted(entry.node.id, value),
      ),
    ),
  );
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
