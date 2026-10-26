import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../../app/node_write_result.dart';
import '../../app/node_persistence_workspace.dart';
import '../../domain/todo_node.dart';
import '../common/formatters.dart';

class CalendarCreateTaskDialog extends StatefulWidget {
  const CalendarCreateTaskDialog({
    required this.controller,
    required this.start,
    required this.end,
    super.key,
  });

  final AppController controller;
  final DateTime start;
  final DateTime end;

  @override
  State<CalendarCreateTaskDialog> createState() =>
      _CalendarCreateTaskDialogState();
}

class _CalendarCreateTaskDialogState extends State<CalendarCreateTaskDialog> {
  final _form = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _eventText = TextEditingController();
  String? _eventId;
  bool _saving = false;
  String? _error;
  String? _eventError;

  Map<String, String> get _events => {
    for (final node in widget.controller.tree.childrenOf(null))
      if (!node.isDeleted && !node.isAbandoned && !node.isEventArchived)
        node.id: node.title,
  };

  Future<void> _submit() async {
    if (_saving || !_form.currentState!.validate()) return;
    final eventName = _eventText.text.trim();
    if (eventName.isEmpty) {
      setState(() => _eventError = '请选择或输入所属事件');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final result = await widget.controller.createScheduledTask(
      title: _title.text.trim(),
      eventName: eventName,
      eventId: _events[_eventId] == eventName ? _eventId : null,
      start: widget.start,
      end: widget.end,
    );
    if (!mounted) return;
    if (result is NodeWriteSuccess<TodoNode>) {
      Navigator.pop(context);
    } else {
      setState(() {
        _saving = false;
        _error =
            result is NodeWriteFailure<TodoNode> &&
                result.error is NodeRuleException
            ? result.error.toString()
            : '创建失败，请重试';
      });
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _eventText.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final events = _events;
    String date(DateTime value) => formatDate(value).replaceAll('/', '.');
    final endLabel =
        DateUtils.isSameDay(widget.start.toLocal(), widget.end.toLocal())
        ? formatTime(widget.end)
        : '${date(widget.end)} ${formatTime(widget.end)}';
    return PopScope(
      canPop: !_saving,
      child: AlertDialog(
        key: const ValueKey('calendar-create-task-dialog'),
        backgroundColor: Theme.of(context).colorScheme.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
        contentPadding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
        actionsPadding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        title: const Text(
          '新建任务',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
        content: SizedBox(
          width: 400,
          child: SingleChildScrollView(
            child: Form(
              key: _form,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '任务时间：${date(widget.start)} ${formatTime(widget.start)} — $endLabel',
                    key: const ValueKey('calendar-create-time'),
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    key: const ValueKey('calendar-create-title'),
                    controller: _title,
                    autofocus: true,
                    enabled: !_saving,
                    decoration: const InputDecoration(
                      labelText: '任务名称',
                      hintText: '输入任务名称',
                    ),
                    validator: (value) => value == null || value.trim().isEmpty
                        ? '任务名称不能为空'
                        : null,
                    onChanged: (_) => setState(() {}),
                    onFieldSubmitted: (_) => _submit(),
                  ),
                  const SizedBox(height: 16),
                  DropdownMenu<String>(
                    key: const ValueKey('calendar-create-event'),
                    controller: _eventText,
                    initialSelection: _eventId,
                    width: 400,
                    menuHeight: 240,
                    enabled: !_saving,
                    enableFilter: true,
                    requestFocusOnTap: true,
                    label: const Text('所属事件（必填）'),
                    hintText: '选择已有事件，或输入新事件名称',
                    errorText: _eventError,
                    dropdownMenuEntries: [
                      for (final entry in events.entries)
                        DropdownMenuEntry(value: entry.key, label: entry.value),
                    ],
                    onSelected: (value) {
                      if (value == null) return;
                      setState(() {
                        _eventId = value;
                        _eventError = null;
                      });
                    },
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '事件不存在时，将与任务一起创建。',
                    style: TextStyle(
                      fontSize: 11,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        _error!,
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _saving ? null : () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            key: const ValueKey('calendar-create-confirm'),
            onPressed: _saving || _title.text.trim().isEmpty ? null : _submit,
            child: Text(_saving ? '创建中…' : '创建'),
          ),
        ],
      ),
    );
  }
}
