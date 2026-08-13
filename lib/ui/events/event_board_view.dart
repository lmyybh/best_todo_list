import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../../app/app_theme.dart';
import '../../domain/node_tree.dart';
import '../../domain/todo_node.dart';
import '../common/create_node_dialog.dart';
import '../common/delete_confirmation_dialog.dart';
import '../common/formatters.dart';

class EventBoardView extends StatelessWidget {
  const EventBoardView({required this.controller, super.key});

  final AppController controller;

  static const double cardWidth = 352;
  static const double minimumCardWidth = 300;
  static const double spacing = 16;

  @override
  Widget build(BuildContext context) {
    final roots = controller.tree.childrenOf(null);
    return LayoutBuilder(
      builder: (context, constraints) {
        final horizontalPadding = constraints.maxWidth < 760 ? 18.0 : 22.0;
        final availableWidth = constraints.maxWidth - horizontalPadding * 2;
        final columns = ((availableWidth + spacing) / (cardWidth + spacing))
            .floor()
            .clamp(1, 4);
        final resolvedWidth =
            ((availableWidth - spacing * (columns - 1)) / columns)
                .clamp(minimumCardWidth, cardWidth)
                .toDouble();

        return SingleChildScrollView(
          key: const ValueKey<String>('event-board-scroll'),
          padding: EdgeInsets.fromLTRB(
            horizontalPadding,
            18,
            horizontalPadding,
            28,
          ),
          child: roots.isEmpty
              ? _EmptyBoard(onCreate: () => _createEvent(context))
              : Align(
                  alignment: Alignment.topLeft,
                  child: Wrap(
                    key: const ValueKey<String>('event-board-wrap'),
                    spacing: spacing,
                    runSpacing: spacing,
                    children: <Widget>[
                      for (var index = 0; index < roots.length; index++)
                        SizedBox(
                          key: ValueKey<String>(
                            'event-card-${roots[index].id}',
                          ),
                          width: resolvedWidth,
                          child: _EventCard(
                            controller: controller,
                            node: roots[index],
                            tree: controller.tree,
                            now: controller.now,
                            color: _eventColors[index % _eventColors.length],
                          ),
                        ),
                      SizedBox(
                        key: const ValueKey<String>('new-event-card'),
                        width: resolvedWidth,
                        child: _NewEventCard(
                          onPressed: () => _createEvent(context),
                        ),
                      ),
                    ],
                  ),
                ),
        );
      },
    );
  }

  Future<void> _createEvent(BuildContext context) async {
    final title = await showDialog<String>(
      context: context,
      builder: (context) => const CreateNodeDialog(),
    );
    if (title == null || title.trim().isEmpty) return;
    await controller.create(title: title, selectCreated: false);
    controller.showEventOverview();
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

class _EventCard extends StatelessWidget {
  const _EventCard({
    required this.controller,
    required this.node,
    required this.tree,
    required this.now,
    required this.color,
  });

  final AppController controller;
  final TodoNode node;
  final NodeTree tree;
  final DateTime now;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final leaves = tree.leafDescendantsOf(node.id);
    final completed = leaves.where((leaf) => leaf.completedAt != null).length;
    final progress = leaves.isEmpty ? 0.0 : completed / leaves.length;
    final children = tree.childrenOf(node.id);
    return Material(
      color: Theme.of(context).colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(13),
        side: BorderSide(color: colors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(17, 16, 17, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
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
                            children.isEmpty
                                ? '单项任务'
                                : '${children.length} 个直接子任务',
                            style: TextStyle(color: colors.faint, fontSize: 10),
                          ),
                        ],
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
                        tooltip: '更多操作',
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
          if (children.isEmpty)
            Padding(
              padding: const EdgeInsets.all(18),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '还没有子任务',
                  style: TextStyle(color: colors.faint, fontSize: 11),
                ),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 9, 10, 11),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  for (final child in children)
                    _EventTreeRow(
                      controller: controller,
                      node: child,
                      tree: tree,
                      depth: 0,
                    ),
                ],
              ),
            ),
          _CardQuickAdd(controller: controller, parentId: node.id),
        ],
      ),
    );
  }
}

class _EventTreeRow extends StatefulWidget {
  const _EventTreeRow({
    required this.controller,
    required this.node,
    required this.tree,
    required this.depth,
  });

  final AppController controller;
  final TodoNode node;
  final NodeTree tree;
  final int depth;

  @override
  State<_EventTreeRow> createState() => _EventTreeRowState();
}

class _EventTreeRowState extends State<_EventTreeRow> {
  bool expanded = true;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final children = widget.tree.childrenOf(widget.node.id);
    final complete = widget.tree.isComplete(widget.node.id);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Material(
          key: ValueKey<String>('event-row-surface-${widget.node.id}'),
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            key: ValueKey<String>('event-row-${widget.node.id}'),
            mouseCursor: SystemMouseCursors.click,
            hoverColor: colors.surfaceHover,
            onTap: () => widget.controller.select(widget.node.id),
            child: SizedBox(
              height: 36,
              child: Padding(
                padding: EdgeInsets.only(left: widget.depth * 20),
                child: Row(
                  children: <Widget>[
                    SizedBox(
                      width: 22,
                      child: children.isEmpty
                          ? null
                          : IconButton(
                              key: ValueKey<String>(
                                'event-expand-${widget.node.id}',
                              ),
                              tooltip: expanded ? '折叠' : '展开',
                              padding: EdgeInsets.zero,
                              visualDensity: VisualDensity.compact,
                              onPressed: () =>
                                  setState(() => expanded = !expanded),
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
                      key: ValueKey<String>('event-complete-${widget.node.id}'),
                      onTap: children.isEmpty
                          ? () => widget.controller.setCompleted(
                              widget.node.id,
                              !complete,
                            )
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
                      child: Text(
                        widget.node.title,
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
                    if (widget.node.deadline != null)
                      Text(
                        formatCompactDate(widget.node.deadline!),
                        style: TextStyle(color: colors.faint, fontSize: 9),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (expanded)
          for (final child in children)
            _EventTreeRow(
              controller: widget.controller,
              node: child,
              tree: widget.tree,
              depth: widget.depth + 1,
            ),
      ],
    );
  }
}

class _CardQuickAdd extends StatefulWidget {
  const _CardQuickAdd({required this.controller, required this.parentId});

  final AppController controller;
  final String parentId;

  @override
  State<_CardQuickAdd> createState() => _CardQuickAddState();
}

class _CardQuickAddState extends State<_CardQuickAdd> {
  final TextEditingController textController = TextEditingController();

  @override
  void dispose() {
    textController.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    final title = textController.text.trim();
    if (title.isEmpty) return;
    await widget.controller.create(
      parentId: widget.parentId,
      title: title,
      selectCreated: false,
    );
    textController.clear();
    widget.controller.showEventOverview();
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(11, 0, 11, 12),
      child: TextField(
        key: ValueKey<String>('event-quick-add-${widget.parentId}'),
        controller: textController,
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
  const _NewEventCard({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return SizedBox(
      height: 180,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: colors.muted,
          side: BorderSide(color: colors.border),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(13),
          ),
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
