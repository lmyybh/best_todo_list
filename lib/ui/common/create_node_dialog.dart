import 'dart:async';

import 'package:flutter/material.dart';

class CreateNodeDialog extends StatefulWidget {
  const CreateNodeDialog({
    this.title = '新建事件',
    this.initialTitle = '',
    this.fieldLabel = '标题',
    this.hintText = '输入事件名称',
    this.confirmLabel = '创建',
    this.onSubmit,
    super.key,
  });

  final String title;
  final String initialTitle;
  final String fieldLabel;
  final String hintText;
  final String confirmLabel;
  final Future<String?> Function(String value)? onSubmit;

  @override
  State<CreateNodeDialog> createState() => _CreateNodeDialogState();
}

class _CreateNodeDialogState extends State<CreateNodeDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialTitle,
  );
  bool _submitting = false;
  String? _submitError;

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

  Future<void> _submit() async {
    if (_submitting) return;
    if (!_formKey.currentState!.validate()) return;
    final value = _controller.text.trim();
    final submit = widget.onSubmit;
    if (submit == null) {
      Navigator.pop(context, value);
      return;
    }
    setState(() {
      _submitting = true;
      _submitError = null;
    });
    final error = await submit(value);
    if (!mounted) return;
    if (error == null) {
      Navigator.pop(context);
    } else {
      setState(() {
        _submitting = false;
        _submitError = error;
      });
    }
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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            TextFormField(
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
              onFieldSubmitted: (_) => unawaited(_submit()),
            ),
            if (_submitError != null) ...<Widget>[
              const SizedBox(height: 6),
              Text(
                _submitError!,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                  fontSize: 12,
                ),
              ),
            ],
          ],
        ),
      ),
    ),
    actions: <Widget>[
      TextButton(
        onPressed: _submitting ? null : () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(
        key: const ValueKey<String>('node-title-confirm-button'),
        onPressed: _controller.text.trim().isEmpty || _submitting
            ? null
            : _submit,
        child: Text(_submitting ? '保存中…' : widget.confirmLabel),
      ),
    ],
  );
}
