import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../../app/app_theme.dart';
import '../../domain/timeline.dart';
import '../common/formatters.dart';
import '../common/node_tile.dart';

class TimelineView extends StatelessWidget {
  const TimelineView({required this.controller, super.key});

  final AppController controller;

  static const labels = <TimelineGroup, String>{
    TimelineGroup.today: '今天',
    TimelineGroup.tomorrow: '明天',
    TimelineGroup.thisWeek: '本周',
    TimelineGroup.other: '其他',
  };

  @override
  Widget build(BuildContext context) {
    final entries = controller.timelineEntries;
    final now = controller.now;
    final overdue = controller.timelineGroup == TimelineGroup.today
        ? entries
              .where(
                (entry) =>
                    isOverdue(entry.node.deadline, now) && !entry.isComplete,
              )
              .toList()
        : const <TimelineEntry>[];
    final regular = overdue.isEmpty
        ? entries
        : entries.where((entry) => !overdue.contains(entry)).toList();

    return Column(
      children: <Widget>[
        Container(
          padding: const EdgeInsets.fromLTRB(42, 32, 42, 24),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: AppColors.of(context).border),
            ),
          ),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      '${now.year} 年 ${now.month} 月 ${now.day} 日',
                      style: TextStyle(
                        color: AppColors.of(context).muted,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 7),
                    Text(
                      labels[controller.timelineGroup]!,
                      style: const TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.8,
                      ),
                    ),
                    const SizedBox(height: 7),
                    Text(
                      _subtitle(controller.timelineGroup),
                      style: TextStyle(
                        color: AppColors.of(context).muted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Semantics(
                label: '显示已完成任务',
                child: Row(
                  children: <Widget>[
                    Switch.adaptive(
                      value: controller.showCompleted,
                      onChanged: controller.setShowCompleted,
                    ),
                    const Text('显示已完成', style: TextStyle(fontSize: 12)),
                  ],
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: entries.isEmpty
              ? _TimelineEmpty(group: controller.timelineGroup)
              : ListView(
                  padding: const EdgeInsets.fromLTRB(42, 28, 42, 48),
                  children: <Widget>[
                    if (overdue.isNotEmpty) ...<Widget>[
                      _TimelineSection(
                        title: '已逾期',
                        count: overdue.length,
                        danger: true,
                      ),
                      const SizedBox(height: 10),
                      ...overdue.map(
                        (entry) => _Entry(controller: controller, entry: entry),
                      ),
                      const SizedBox(height: 20),
                    ],
                    _TimelineSection(
                      title: labels[controller.timelineGroup]!,
                      count: regular.length,
                    ),
                    const SizedBox(height: 10),
                    ...regular.map(
                      (entry) => _Entry(controller: controller, entry: entry),
                    ),
                  ],
                ),
        ),
      ],
    );
  }

  String _subtitle(TimelineGroup group) => switch (group) {
    TimelineGroup.today => '把注意力留给眼前的事',
    TimelineGroup.tomorrow => '提前看一眼下一步',
    TimelineGroup.thisWeek => '周一到周日的全部安排',
    TimelineGroup.other => '逾期、远期和未设置时间的任务',
  };
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
  const _TimelineEmpty({required this.group});
  final TimelineGroup group;

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
        Text(
          '${TimelineView.labels[group]}没有待办',
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
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
