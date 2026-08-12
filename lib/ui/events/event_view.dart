import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../../app/app_theme.dart';
import '../../domain/node_tree.dart';
import '../../domain/todo_node.dart';
import '../common/create_node_dialog.dart';
import '../common/deadline_dialog.dart';
import '../common/delete_confirmation_dialog.dart';
import '../common/formatters.dart';
import '../common/node_tile.dart';

class EventView extends StatelessWidget {
  const EventView({required this.controller, super.key});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final node = controller.selectedNode;
    if (node == null) return _EmptyEvents(controller: controller);
    final tree = controller.tree;
    final children = tree.childrenOf(node.id);

    return Column(
      children: <Widget>[
        _EventHeader(controller: controller, node: node, tree: tree),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(42, 0, 42, 48),
            children: <Widget>[
              const SizedBox(height: 26),
              _SectionHeader(label: '子任务', count: children.length),
              const SizedBox(height: 10),
              if (children.isEmpty)
                const _InlineEmpty(message: '把这件事拆成下一步行动')
              else
                ReorderableListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  buildDefaultDragHandles: false,
                  itemCount: children.length,
                  onReorderItem: (oldIndex, newIndex) {
                    final reordered = List<TodoNode>.of(children);
                    final moved = reordered.removeAt(oldIndex);
                    reordered.insert(newIndex, moved);
                    controller.reorderChildren(
                      node.id,
                      reordered.map((item) => item.id).toList(),
                    );
                  },
                  itemBuilder: (context, index) {
                    final child = children[index];
                    return Padding(
                      key: ValueKey<String>(child.id),
                      padding: const EdgeInsets.only(bottom: 7),
                      child: NodeTile(
                        node: child,
                        tree: tree,
                        onOpen: () => controller.select(child.id),
                        onToggleComplete: (value) =>
                            controller.setCompleted(child.id, value),
                        trailing: ReorderableDragStartListener(
                          index: index,
                          child: Tooltip(
                            message: '拖动排序',
                            child: MouseRegion(
                              cursor: SystemMouseCursors.grab,
                              child: Icon(
                                Icons.drag_indicator,
                                size: 17,
                                color: AppColors.of(context).muted,
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              const SizedBox(height: 2),
              _QuickAdd(controller: controller, parentId: node.id),
            ],
          ),
        ),
      ],
    );
  }
}

class _EventHeader extends StatelessWidget {
  const _EventHeader({
    required this.controller,
    required this.node,
    required this.tree,
  });

  final AppController controller;
  final TodoNode node;
  final NodeTree tree;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final isLeaf = tree.isLeaf(node.id);
    final complete = tree.isComplete(node.id);
    final leaves = tree.leafDescendantsOf(node.id);
    final completedCount = leaves
        .where((leaf) => leaf.completedAt != null)
        .length;
    final completedAt = tree.effectiveCompletedAt(node.id);
    final path = tree.pathFor(node.id);
    return Padding(
      padding: const EdgeInsets.fromLTRB(42, 32, 42, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Container(
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.primary,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          isLeaf ? '任务' : '事件',
                          style: TextStyle(
                            color: colors.muted,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 7),
                    _EditableTitle(
                      key: ValueKey<String>(node.id),
                      title: node.title,
                      onSaved: (value) =>
                          controller.updateTitle(node.id, value),
                    ),
                    const SizedBox(height: 7),
                    Text(
                      <String>['所有事件', ...path].join('  /  '),
                      style: TextStyle(color: colors.faint, fontSize: 12),
                    ),
                    const SizedBox(height: 9),
                    Wrap(
                      spacing: 16,
                      runSpacing: 6,
                      children: <Widget>[
                        _LifecycleDate(
                          icon: Icons.schedule_outlined,
                          label: '创建时间',
                          value: formatDate(node.createdAt),
                        ),
                        if (completedAt != null)
                          _LifecycleDate(
                            icon: Icons.check_circle_outline,
                            label: '完成时间',
                            value: formatDate(completedAt),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              if (isLeaf) ...<Widget>[
                OutlinedButton.icon(
                  key: const ValueKey<String>('detail-completion-toggle'),
                  onPressed: () => controller.setCompleted(node.id, !complete),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: complete
                        ? Theme.of(context).colorScheme.primary
                        : colors.muted,
                    backgroundColor: complete
                        ? colors.accentSoft
                        : Colors.transparent,
                    side: BorderSide(
                      color: complete
                          ? Theme.of(context).colorScheme.primary
                          : colors.border,
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 9,
                    ),
                    visualDensity: VisualDensity.compact,
                  ),
                  icon: Icon(
                    complete
                        ? Icons.check_circle
                        : Icons.radio_button_unchecked,
                    size: 16,
                  ),
                  label: Text(complete ? '已完成' : '标记完成'),
                ),
                const SizedBox(width: 8),
              ],
              PopupMenuButton<String>(
                tooltip: '更多操作',
                icon: Icon(Icons.more_horiz, size: 19, color: colors.muted),
                onSelected: (value) {
                  if (value == 'delete') {
                    _deleteSelected(context, controller, node.id);
                  }
                },
                itemBuilder: (context) => const <PopupMenuEntry<String>>[
                  PopupMenuItem(
                    value: 'delete',
                    child: ListTile(
                      leading: Icon(Icons.delete_outline),
                      title: Text('删除事件'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              border: Border.all(color: colors.border),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () => _editDeadline(context, controller, node),
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Row(
                        children: <Widget>[
                          Icon(
                            Icons.calendar_today_outlined,
                            color: Theme.of(context).colorScheme.primary,
                            size: 20,
                          ),
                          const SizedBox(width: 11),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                '截止时间',
                                style: TextStyle(
                                  color: colors.muted,
                                  fontSize: 10,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                formatDeadline(node.deadline),
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Container(width: 1, height: 36, color: colors.border),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(left: 20),
                    child: Row(
                      children: <Widget>[
                        SizedBox(
                          width: 38,
                          height: 38,
                          child: Stack(
                            fit: StackFit.expand,
                            children: <Widget>[
                              CircularProgressIndicator(
                                value: leaves.isEmpty
                                    ? 0
                                    : completedCount / leaves.length,
                                strokeWidth: 4,
                                backgroundColor: colors.border,
                              ),
                              Center(
                                child: Text(
                                  '$completedCount/${leaves.length}',
                                  style: const TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 11),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              '整体进度',
                              style: TextStyle(
                                color: colors.muted,
                                fontSize: 10,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              leaves.isEmpty
                                  ? '添加子任务后汇总'
                                  : completedCount == leaves.length
                                  ? '已全部完成'
                                  : '还差 ${leaves.length - completedCount} 项',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (_hasLateChild(node, tree)) ...<Widget>[
            const SizedBox(height: 9),
            Row(
              children: <Widget>[
                Icon(Icons.info_outline, size: 15, color: colors.muted),
                const SizedBox(width: 6),
                Text(
                  '有子任务的截止时间晚于当前事件',
                  style: TextStyle(color: colors.muted, fontSize: 11),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  bool _hasLateChild(TodoNode parent, NodeTree tree) =>
      parent.deadline != null &&
      tree
          .childrenOf(parent.id)
          .any(
            (child) =>
                child.deadline != null &&
                child.deadline!.isAfter(parent.deadline!),
          );
}

class _LifecycleDate extends StatelessWidget {
  const _LifecycleDate({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final color = AppColors.of(context).muted;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 5),
        Text('$label $value', style: TextStyle(color: color, fontSize: 11)),
      ],
    );
  }
}

class _EditableTitle extends StatefulWidget {
  const _EditableTitle({required this.title, required this.onSaved, super.key});
  final String title;
  final ValueChanged<String> onSaved;

  @override
  State<_EditableTitle> createState() => _EditableTitleState();
}

class _EditableTitleState extends State<_EditableTitle> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.title,
  );
  late final FocusNode _focusNode = FocusNode()
    ..addListener(_saveWhenFocusLeaves);

  void _saveWhenFocusLeaves() {
    if (!_focusNode.hasFocus && _controller.text.trim() != widget.title) {
      widget.onSaved(_controller.text);
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_saveWhenFocusLeaves);
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
    textField: true,
    label: '事件标题',
    child: TextField(
      controller: _controller,
      focusNode: _focusNode,
      maxLines: 1,
      onSubmitted: widget.onSaved,
      style: const TextStyle(
        fontSize: 30,
        height: 1.2,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.8,
      ),
      decoration: const InputDecoration(
        isDense: true,
        filled: false,
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: UnderlineInputBorder(),
      ),
    ),
  );
}

class _QuickAdd extends StatefulWidget {
  const _QuickAdd({required this.controller, required this.parentId});
  final AppController controller;
  final String parentId;

  @override
  State<_QuickAdd> createState() => _QuickAddState();
}

class _QuickAddState extends State<_QuickAdd> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  var _focused = false;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_handleFocusChanged);
  }

  void _handleFocusChanged() {
    if (_focused != _focusNode.hasFocus) {
      setState(() => _focused = _focusNode.hasFocus);
    }
  }

  Future<void> _submit(String value) async {
    if (value.trim().isEmpty) return;
    await widget.controller.create(
      parentId: widget.parentId,
      title: value,
      selectCreated: false,
    );
    if (mounted) _controller.clear();
  }

  @override
  void dispose() {
    _focusNode.removeListener(_handleFocusChanged);
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final radius = BorderRadius.circular(10);
    return CustomPaint(
      foregroundPainter: _focused
          ? null
          : _DashedRoundedBorderPainter(color: colors.border, borderRadius: 10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        height: 45,
        padding: const EdgeInsets.symmetric(horizontal: 13),
        decoration: BoxDecoration(
          color: _focused
              ? Theme.of(context).colorScheme.surface
              : Colors.transparent,
          border: _focused
              ? Border.all(color: Theme.of(context).colorScheme.primary)
              : null,
          borderRadius: radius,
        ),
        child: Row(
          children: <Widget>[
            Icon(
              Icons.add,
              size: 18,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: _controller,
                focusNode: _focusNode,
                onSubmitted: _submit,
                style: const TextStyle(fontSize: 12),
                decoration: InputDecoration(
                  isCollapsed: true,
                  filled: false,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  disabledBorder: InputBorder.none,
                  errorBorder: InputBorder.none,
                  focusedErrorBorder: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
                  hintText: '添加一个子任务…',
                  hintStyle: TextStyle(color: colors.muted),
                ),
              ),
            ),
            Container(
              constraints: const BoxConstraints(minWidth: 22),
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                border: Border.all(color: colors.border),
                borderRadius: BorderRadius.circular(5),
              ),
              child: Text(
                '↵',
                textAlign: TextAlign.center,
                style: TextStyle(color: colors.muted, fontSize: 10),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DashedRoundedBorderPainter extends CustomPainter {
  const _DashedRoundedBorderPainter({
    required this.color,
    required this.borderRadius,
  });

  final Color color;
  final double borderRadius;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          Offset.zero & size,
          Radius.circular(borderRadius),
        ),
      );
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        canvas.drawPath(metric.extractPath(distance, distance + 5), paint);
        distance += 9;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedRoundedBorderPainter oldDelegate) =>
      color != oldDelegate.color || borderRadius != oldDelegate.borderRadius;
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label, required this.count});
  final String label;
  final int count;

  @override
  Widget build(BuildContext context) => Row(
    children: <Widget>[
      Text(
        label,
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
      ),
      const SizedBox(width: 6),
      Text(
        '$count',
        style: TextStyle(fontSize: 11, color: AppColors.of(context).muted),
      ),
      const Spacer(),
      Icon(Icons.sort, size: 14, color: AppColors.of(context).faint),
      const SizedBox(width: 5),
      Text(
        '手动排序',
        style: TextStyle(fontSize: 11, color: AppColors.of(context).faint),
      ),
    ],
  );
}

class _InlineEmpty extends StatelessWidget {
  const _InlineEmpty({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(18),
    margin: const EdgeInsets.only(bottom: 8),
    decoration: BoxDecoration(
      border: Border.all(color: AppColors.of(context).border),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Text(
      message,
      textAlign: TextAlign.center,
      style: TextStyle(color: AppColors.of(context).muted, fontSize: 12),
    ),
  );
}

class _EmptyEvents extends StatelessWidget {
  const _EmptyEvents({required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(
          Icons.account_tree_outlined,
          size: 45,
          color: AppColors.of(context).muted,
        ),
        const SizedBox(height: 14),
        const Text(
          '从一件想完成的事开始',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 7),
        Text(
          '它可以是一项任务，也可以继续拆成事件树',
          style: TextStyle(color: AppColors.of(context).muted),
        ),
        const SizedBox(height: 18),
        FilledButton.icon(
          onPressed: () => _createRoot(context, controller),
          icon: const Icon(Icons.add),
          label: const Text('新建事件'),
        ),
      ],
    ),
  );
}

Future<void> _createRoot(BuildContext context, AppController controller) async {
  final title = await showDialog<String>(
    context: context,
    builder: (context) => const CreateNodeDialog(),
  );
  if (title != null && title.trim().isNotEmpty) {
    await controller.create(title: title);
  }
}

Future<void> _editDeadline(
  BuildContext context,
  AppController controller,
  TodoNode node,
) async {
  final result = await showDialog<DeadlineDialogResult>(
    context: context,
    builder: (context) => DeadlineDialog(initialValue: node.deadline),
  );
  if (!context.mounted || result == null) return;
  switch (result) {
    case SaveDeadline(:final value):
      await controller.updateDeadline(node.id, value);
    case ClearDeadline():
      await controller.updateDeadline(node.id, null);
  }
}

Future<void> _deleteSelected(
  BuildContext context,
  AppController controller,
  String nodeId,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => const DeleteConfirmationDialog(
      title: '删除这个事件？',
      message: '它的所有子任务也会一起删除。你可以在提示消失前撤销。',
    ),
  );
  if (confirmed != true || !context.mounted) return;
  await controller.delete(nodeId);
  if (!context.mounted || controller.error != null) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: const Text('事件已删除'),
      action: SnackBarAction(label: '撤销', onPressed: controller.undoDelete),
    ),
  );
}
