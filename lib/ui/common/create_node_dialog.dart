import 'package:flutter/material.dart';

class CreateNodeDialog extends StatefulWidget {
  const CreateNodeDialog({
    this.title = '新建事件',
    this.initialTitle = '',
    this.fieldLabel = '标题',
    this.hintText = '输入事件名称',
    this.confirmLabel = '创建',
    super.key,
  });

  final String title;
  final String initialTitle;
  final String fieldLabel;
  final String hintText;
  final String confirmLabel;

  @override
  State<CreateNodeDialog> createState() => _CreateNodeDialogState();
}

class _CreateNodeDialogState extends State<CreateNodeDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialTitle,
  );

  @override
  void initState() {
    super.initState();
    if (_controller.text.isNotEmpty) {
      _controller.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _controller.text.length,
      );
    }
    _controller.addListener(_handleTextChanged);
  }

  void _handleTextChanged() => setState(() {});

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.pop(context, _controller.text.trim());
  }

  @override
  void dispose() {
    _controller.removeListener(_handleTextChanged);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    backgroundColor: Theme.of(context).colorScheme.surface,
    surfaceTintColor: Colors.transparent,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
    contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
    actionsPadding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
    title: Text(
      widget.title,
      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
    ),
    content: SizedBox(
      width: 320,
      child: Form(
        key: _formKey,
        child: TextFormField(
          controller: _controller,
          autofocus: true,
          decoration: InputDecoration(
            labelText: widget.fieldLabel,
            hintText: widget.hintText,
          ),
          validator: (value) => value == null || value.trim().isEmpty
              ? '${widget.fieldLabel}不能为空'
              : null,
          textInputAction: TextInputAction.done,
          onFieldSubmitted: (_) => _submit(),
        ),
      ),
    ),
    actions: <Widget>[
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(
        key: const ValueKey<String>('node-title-confirm-button'),
        onPressed: _controller.text.trim().isEmpty ? null : _submit,
        child: Text(widget.confirmLabel),
      ),
    ],
  );
}
