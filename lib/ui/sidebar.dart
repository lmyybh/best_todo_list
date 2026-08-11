import 'package:flutter/material.dart';

import '../app/app_controller.dart';
import '../app/app_theme.dart';
import '../domain/node_tree.dart';
import '../domain/timeline.dart';
import '../domain/todo_node.dart';
import 'common/create_node_dialog.dart';

class AppSidebar extends StatelessWidget {
  const AppSidebar({required this.controller, super.key});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Container(
      width: 258,
      decoration: BoxDecoration(
        border: Border(right: BorderSide(color: colors.border)),
      ),
      child: Material(
        color: colors.sidebar,
        child: Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 16, 14, 18),
              child: SegmentedButton<AppView>(
                segments: const <ButtonSegment<AppView>>[
                  ButtonSegment(
                    value: AppView.events,
                    icon: Icon(Icons.account_tree_outlined, size: 17),
                    label: Text('事件'),
                  ),
                  ButtonSegment(
                    value: AppView.timeline,
                    icon: Icon(Icons.timeline_outlined, size: 17),
                    label: Text('时间线'),
                  ),
                ],
                selected: <AppView>{controller.view},
                onSelectionChanged: (selection) =>
                    controller.setView(selection.first),
                showSelectedIcon: false,
                style: const ButtonStyle(visualDensity: VisualDensity.compact),
              ),
            ),
            Expanded(
              child: controller.view == AppView.events
                  ? _EventNavigation(controller: controller)
                  : _TimelineNavigation(controller: controller),
            ),
            Divider(height: 1, color: colors.border),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(
                children: <Widget>[
                  const Expanded(
                    child: Text(
                      '枝序',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: '切换主题（系统 / 浅色 / 深色）',
                    onPressed: controller.cycleTheme,
                    icon: Icon(switch (controller.themeMode) {
                      ThemeMode.system => Icons.brightness_auto_outlined,
                      ThemeMode.light => Icons.light_mode_outlined,
                      ThemeMode.dark => Icons.dark_mode_outlined,
                    }, size: 18),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EventNavigation extends StatelessWidget {
  const _EventNavigation({required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final roots = controller.tree.childrenOf(null);
    return Column(
      children: <Widget>[
        DragTarget<String>(
          onAcceptWithDetails: (details) =>
              controller.move(nodeId: details.data),
          builder: (context, candidates, rejected) => Container(
            margin: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: candidates.isNotEmpty
                  ? Theme.of(
                      context,
                    ).colorScheme.primary.withValues(alpha: 0.12)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
            ),
            padding: const EdgeInsets.fromLTRB(10, 0, 2, 6),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    candidates.isNotEmpty ? '移到顶层' : '我的事件',
                    style: TextStyle(
                      color: AppColors.of(context).muted,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: '新建顶层事件',
                  onPressed: () => _showCreateDialog(context, controller),
                  icon: const Icon(Icons.add, size: 18),
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: roots.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      '还没有事件\n点击上方 + 开始',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: AppColors.of(context).muted,
                        height: 1.6,
                      ),
                    ),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  children: <Widget>[
                    for (final node in roots)
                      _TreeNode(
                        controller: controller,
                        tree: controller.tree,
                        node: node,
                        depth: 0,
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

class _TreeNode extends StatelessWidget {
  const _TreeNode({
    required this.controller,
    required this.tree,
    required this.node,
    required this.depth,
  });
  final AppController controller;
  final NodeTree tree;
  final TodoNode node;
  final int depth;

  @override
  Widget build(BuildContext context) {
    final children = tree.childrenOf(node.id);
    final hasChildren = children.isNotEmpty;
    final expanded = controller.expandedIds.contains(node.id);
    final selected = controller.selectedId == node.id;
    final tile = DragTarget<String>(
      onWillAcceptWithDetails: (details) => details.data != node.id,
      onAcceptWithDetails: (details) =>
          controller.move(nodeId: details.data, newParentId: node.id),
      builder: (context, candidates, rejected) => Material(
        color: candidates.isNotEmpty
            ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.12)
            : selected
            ? AppColors.of(context).accentSoft
            : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: ListTile(
          dense: true,
          minTileHeight: 36,
          contentPadding: EdgeInsets.only(left: 6 + depth * 16, right: 8),
          leading: SizedBox(
            width: 20,
            child: hasChildren
                ? IconButton(
                    padding: EdgeInsets.zero,
                    tooltip: expanded ? '折叠' : '展开',
                    onPressed: () => controller.toggleExpanded(node.id),
                    icon: Icon(
                      expanded ? Icons.expand_more : Icons.chevron_right,
                      size: 17,
                    ),
                  )
                : Icon(
                    Icons.circle_outlined,
                    size: 7,
                    color: AppColors.of(context).muted,
                  ),
          ),
          title: Text(
            node.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
          trailing: hasChildren
              ? Text(
                  '${tree.leafDescendantsOf(node.id).where((leaf) => leaf.completedAt == null).length}',
                  style: TextStyle(
                    fontSize: 10,
                    color: AppColors.of(context).muted,
                  ),
                )
              : null,
          onTap: () => controller.select(node.id),
        ),
      ),
    );

    return Column(
      children: <Widget>[
        Draggable<String>(
          data: node.id,
          rootOverlay: true,
          feedback: Material(
            elevation: 8,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              child: Text(node.title),
            ),
          ),
          childWhenDragging: Opacity(opacity: 0.4, child: tile),
          child: tile,
        ),
        if (expanded)
          for (final child in children)
            _TreeNode(
              controller: controller,
              tree: tree,
              node: child,
              depth: depth + 1,
            ),
      ],
    );
  }
}

class _TimelineNavigation extends StatelessWidget {
  const _TimelineNavigation({required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    const labels = <TimelineGroup, String>{
      TimelineGroup.today: '今天',
      TimelineGroup.tomorrow: '明天',
      TimelineGroup.thisWeek: '本周',
      TimelineGroup.other: '其他',
    };
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 2, 10, 8),
          child: Text(
            '时间范围',
            style: TextStyle(
              color: AppColors.of(context).muted,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        for (final group in TimelineGroup.values)
          ListTile(
            dense: true,
            minTileHeight: 38,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            selected: controller.timelineGroup == group,
            selectedTileColor: AppColors.of(context).accentSoft,
            title: Text(labels[group]!, style: const TextStyle(fontSize: 13)),
            onTap: () => controller.setTimelineGroup(group),
          ),
      ],
    );
  }
}

Future<void> _showCreateDialog(
  BuildContext context,
  AppController controller,
) async {
  final title = await showDialog<String>(
    context: context,
    builder: (context) => const CreateNodeDialog(),
  );
  if (title != null && title.trim().isNotEmpty) {
    await controller.create(title: title);
  }
}
