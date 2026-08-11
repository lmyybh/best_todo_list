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
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: SizedBox(
      width: 360,
      child: TextField(
        controller: _controller,
        autofocus: true,
        decoration: const InputDecoration(labelText: '标题', hintText: '输入事件名称'),
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _submit(),
      ),
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
