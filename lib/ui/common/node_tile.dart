import 'package:flutter/material.dart';

import '../../app/app_theme.dart';
import '../../domain/node_tree.dart';
import '../../domain/todo_node.dart';
import 'formatters.dart';

class NodeTile extends StatelessWidget {
  const NodeTile({
    required this.node,
    required this.tree,
    required this.onOpen,
    required this.onToggleComplete,
    this.path,
    this.trailing,
    super.key,
  });

  final TodoNode node;
  final NodeTree tree;
  final VoidCallback onOpen;
  final ValueChanged<bool> onToggleComplete;
  final String? path;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final isEvent = !tree.isLeaf(node.id);
    final complete = tree.isComplete(node.id);
    final leaves = tree.leafDescendantsOf(node.id);
    final completedCount = leaves
        .where((leaf) => leaf.completedAt != null)
        .length;
    final overdue = isOverdue(node.deadline, DateTime.now()) && !complete;
    final surfaceColor = isEvent
        ? Color.alphaBlend(
            colors.accentSoft.withValues(alpha: 0.45),
            Theme.of(context).colorScheme.surface,
          )
        : Theme.of(context).colorScheme.surface;

    return Semantics(
      button: true,
      label: isEvent ? '事件：${node.title}' : '任务：${node.title}',
      child: Container(
        constraints: const BoxConstraints(minHeight: 62),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: colors.border),
        ),
        child: Stack(
          children: <Widget>[
            Material(
              color: surfaceColor,
              child: InkWell(
                onTap: onOpen,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  child: Row(
                    children: <Widget>[
                      if (isEvent)
                        Icon(
                          Icons.account_tree_outlined,
                          size: 20,
                          color: Theme.of(context).colorScheme.primary,
                        )
                      else
                        Semantics(
                          label: complete ? '取消完成' : '标记完成',
                          child: Checkbox(
                            value: complete,
                            onChanged: (value) =>
                                onToggleComplete(value ?? false),
                            shape: const CircleBorder(),
                            visualDensity: VisualDensity.compact,
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
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                decoration: complete
                                    ? TextDecoration.lineThrough
                                    : null,
                                color: complete
                                    ? colors.muted
                                    : Theme.of(context).colorScheme.onSurface,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Wrap(
                              spacing: 10,
                              runSpacing: 3,
                              children: <Widget>[
                                if (node.deadline != null)
                                  Text(
                                    formatDeadline(node.deadline),
                                    style: TextStyle(
                                      color: overdue
                                          ? colors.danger
                                          : Theme.of(
                                              context,
                                            ).colorScheme.primary,
                                      fontSize: 11,
                                      fontWeight: overdue
                                          ? FontWeight.w600
                                          : FontWeight.normal,
                                    ),
                                  ),
                                if (isEvent)
                                  Text(
                                    '$completedCount / ${leaves.length} 已完成',
                                    style: TextStyle(
                                      color: colors.muted,
                                      fontSize: 11,
                                    ),
                                  ),
                                if (path != null && path!.isNotEmpty)
                                  Text(
                                    path!,
                                    style: TextStyle(
                                      color: colors.muted,
                                      fontSize: 11,
                                    ),
                                  ),
                              ],
                            ),
                            if (isEvent) ...<Widget>[
                              const SizedBox(height: 7),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(2),
                                child: LinearProgressIndicator(
                                  value: leaves.isEmpty
                                      ? 0
                                      : completedCount / leaves.length,
                                  minHeight: 3,
                                  backgroundColor: colors.border,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      if (trailing != null)
                        trailing!
                      else
                        Icon(
                          Icons.chevron_right,
                          size: 18,
                          color: colors.muted,
                        ),
                    ],
                  ),
                ),
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
    );
  }
}
