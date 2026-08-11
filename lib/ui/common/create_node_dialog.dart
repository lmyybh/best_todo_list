import 'package:flutter/material.dart';

class CreateNodeDialog extends StatefulWidget {
  const CreateNodeDialog({this.title = '新建事件', super.key});

  final String title;

  @override
  State<CreateNodeDialog> createState() => _CreateNodeDialogState();
}

class _CreateNodeDialogState extends State<CreateNodeDialog> {
  final TextEditingController _controller = TextEditingController();

  void _submit() => Navigator.pop(context, _controller.text);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog.adaptive(
    title: Text(widget.title),
    content: TextField(
      controller: _controller,
      autofocus: true,
      decoration: const InputDecoration(labelText: '标题'),
      onSubmitted: (_) => _submit(),
    ),
    actions: <Widget>[
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(onPressed: _submit, child: const Text('创建')),
    ],
  );
}
