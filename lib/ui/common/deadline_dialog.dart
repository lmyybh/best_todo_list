import 'package:flutter/material.dart';

import '../../app/app_theme.dart';

sealed class DeadlineDialogResult {
  const DeadlineDialogResult();
}

class SaveDeadline extends DeadlineDialogResult {
  const SaveDeadline(this.value);
  final DateTime value;
}

class ClearDeadline extends DeadlineDialogResult {
  const ClearDeadline();
}

class DeadlineDialog extends StatefulWidget {
  const DeadlineDialog({this.initialValue, this.now, super.key});

  final DateTime? initialValue;
  final DateTime? now;

  @override
  State<DeadlineDialog> createState() => _DeadlineDialogState();
}

class _DeadlineDialogState extends State<DeadlineDialog> {
  late DateTime _date;
  late int _hour;
  late int _minute;

  @override
  void initState() {
    super.initState();
    final now = widget.now ?? DateTime.now();
    final initial =
        widget.initialValue?.toLocal() ?? now.add(const Duration(days: 1));
    _date = DateTime(initial.year, initial.month, initial.day);
    _hour = initial.hour;
    _minute = initial.minute;
  }

  void _useDate(DateTime value) {
    setState(() => _date = DateTime(value.year, value.month, value.day));
  }

  void _save() => Navigator.pop(
    context,
    SaveDeadline(DateTime(_date.year, _date.month, _date.day, _hour, _minute)),
  );

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final now = widget.now ?? DateTime.now();
    return AlertDialog(
      backgroundColor: Theme.of(context).colorScheme.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      actionsPadding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      title: const Text(
        '设置截止时间',
        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
      ),
      content: SizedBox(
        width: 360,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Row(
                children: <Widget>[
                  ActionChip(
                    label: const Text('今天'),
                    onPressed: () => _useDate(now),
                  ),
                  const SizedBox(width: 8),
                  ActionChip(
                    label: const Text('明天'),
                    onPressed: () => _useDate(now.add(const Duration(days: 1))),
                  ),
                  const Spacer(),
                  Text(
                    '${_date.year}/${_date.month.toString().padLeft(2, '0')}/${_date.day.toString().padLeft(2, '0')}',
                    style: TextStyle(color: colors.muted, fontSize: 12),
                  ),
                ],
              ),
              CalendarDatePicker(
                initialDate: _date,
                firstDate: DateTime(2000),
                lastDate: DateTime(2100),
                onDateChanged: _useDate,
              ),
              const SizedBox(height: 4),
              Row(
                children: <Widget>[
                  const Icon(Icons.schedule_outlined, size: 18),
                  const SizedBox(width: 10),
                  const Text('时间'),
                  const Spacer(),
                  DropdownButton<int>(
                    key: const ValueKey<String>('deadline-hour'),
                    value: _hour,
                    items: <DropdownMenuItem<int>>[
                      for (var hour = 0; hour < 24; hour++)
                        DropdownMenuItem(
                          value: hour,
                          child: Text(hour.toString().padLeft(2, '0')),
                        ),
                    ],
                    onChanged: (value) =>
                        setState(() => _hour = value ?? _hour),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8),
                    child: Text(':'),
                  ),
                  DropdownButton<int>(
                    key: const ValueKey<String>('deadline-minute'),
                    value: _minute,
                    items: <DropdownMenuItem<int>>[
                      for (var minute = 0; minute < 60; minute++)
                        DropdownMenuItem(
                          value: minute,
                          child: Text(minute.toString().padLeft(2, '0')),
                        ),
                    ],
                    onChanged: (value) =>
                        setState(() => _minute = value ?? _minute),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: <Widget>[
        if (widget.initialValue != null)
          TextButton(
            onPressed: () => Navigator.pop(context, const ClearDeadline()),
            child: Text('清除', style: TextStyle(color: colors.danger)),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(onPressed: _save, child: const Text('保存')),
      ],
    );
  }
}
