import 'package:flutter/material.dart';

import '../../app/app_theme.dart';

class DeleteConfirmationDialog extends StatelessWidget {
  const DeleteConfirmationDialog({
    required this.title,
    required this.message,
    super.key,
  });

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final deleteForeground =
        ThemeData.estimateBrightnessForColor(colors.danger) == Brightness.dark
        ? Colors.white
        : Colors.black;
    return AlertDialog(
      backgroundColor: Theme.of(context).colorScheme.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      contentPadding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
      actionsPadding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      title: Text(
        title,
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
      ),
      content: SizedBox(
        width: 320,
        child: Text(
          message,
          style: TextStyle(color: colors.muted, fontSize: 13, height: 1.5),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('取消'),
        ),
        FilledButton(
          key: const ValueKey<String>('confirm-delete-button'),
          style: FilledButton.styleFrom(
            backgroundColor: colors.danger,
            foregroundColor: deleteForeground,
          ),
          onPressed: () => Navigator.pop(context, true),
          child: const Text('删除'),
        ),
      ],
    );
  }
}
