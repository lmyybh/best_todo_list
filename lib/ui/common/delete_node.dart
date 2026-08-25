import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../../app/node_write_result.dart';
import '../../domain/todo_node.dart';
import 'delete_confirmation_dialog.dart';

Future<void> confirmDeleteNode(
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
  final result = await controller.delete(node.id);
  if (result is NodeWriteSuccess) controller.showEventOverview();
}
