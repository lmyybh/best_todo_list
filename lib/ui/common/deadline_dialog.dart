import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/app_theme.dart';

sealed class DeadlineDialogResult {
  const DeadlineDialogResult();
}

class SaveDeadline extends DeadlineDialogResult {
  const SaveDeadline(this.value, {required this.hasTime});

  final DateTime value;
  final bool hasTime;
}

class ClearDeadline extends DeadlineDialogResult {
  const ClearDeadline();
}

Future<DeadlineDialogResult?> showDeadlinePicker({
  required BuildContext context,
  required BuildContext anchorContext,
  DateTime? initialValue,
  bool initialHasTime = false,
  DateTime? now,
}) {
  final anchor = anchorContext.findRenderObject()! as RenderBox;
  final overlay =
      Navigator.of(context).overlay!.context.findRenderObject()! as RenderBox;
  final anchorRect =
      anchor.localToGlobal(Offset.zero, ancestor: overlay) & anchor.size;
  final screen = overlay.size;
  const desiredWidth = 468.0;
  const desiredHeight = 348.0;
  const margin = 12.0;
  final width = screen.width < desiredWidth + margin * 2
      ? screen.width - margin * 2
      : desiredWidth;
  final height = screen.height < desiredHeight + margin * 2
      ? screen.height - margin * 2
      : desiredHeight;
  final left = anchorRect.left.clamp(margin, screen.width - width - margin);
  final roomBelow = screen.height - anchorRect.bottom - margin;
  final top = roomBelow >= height
      ? anchorRect.bottom + 6
      : anchorRect.top >= height + margin
      ? anchorRect.top - height - 6
      : margin;

  return showGeneralDialog<DeadlineDialogResult>(
    context: context,
    barrierDismissible: true,
    barrierLabel: '关闭截止日期设置',
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 150),
    pageBuilder: (context, _, _) => Stack(
      children: <Widget>[
        Positioned(
          left: left,
          top: top,
          width: width,
          height: height,
          child: DeadlineDialog(
            initialValue: initialValue,
            initialHasTime: initialHasTime,
            now: now,
          ),
        ),
      ],
    ),
    transitionBuilder: (context, animation, _, child) => FadeTransition(
      opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
      child: child,
    ),
  );
}

class DeadlineDialog extends StatefulWidget {
  const DeadlineDialog({
    this.initialValue,
    this.initialHasTime = false,
    this.now,
    super.key,
  });

  final DateTime? initialValue;
  final bool initialHasTime;
  final DateTime? now;

  @override
  State<DeadlineDialog> createState() => _DeadlineDialogState();
}

class _DeadlineDialogState extends State<DeadlineDialog> {
  final _formKey = GlobalKey<FormState>();
  late DateTime _date;
  late DateTime _visibleMonth;
  late final TextEditingController _timeController;

  @override
  void initState() {
    super.initState();
    final now = widget.now ?? DateTime.now();
    final initial = widget.initialValue?.toLocal() ?? now;
    _date = DateTime(initial.year, initial.month, initial.day);
    _visibleMonth = DateTime(initial.year, initial.month);
    _timeController = TextEditingController(
      text: _formatTime(
        widget.initialValue != null && widget.initialHasTime
            ? initial.hour
            : 21,
        widget.initialValue != null && widget.initialHasTime
            ? initial.minute
            : 0,
      ),
    );
  }

  @override
  void dispose() {
    _timeController.dispose();
    super.dispose();
  }

  DateTime get _now => widget.now ?? DateTime.now();

  void _useDate(DateTime value) {
    setState(() {
      _date = DateTime(value.year, value.month, value.day);
      _visibleMonth = DateTime(value.year, value.month);
    });
  }

  void _shiftMonth(int offset) {
    setState(() {
      _visibleMonth = DateTime(
        _visibleMonth.year,
        _visibleMonth.month + offset,
      );
    });
  }

  void _moveDate(int days) => _useDate(_date.add(Duration(days: days)));

  void _adjustTime(int minuteDelta) {
    final match = RegExp(
      r'^([01]\d|2[0-3]):[0-5]\d$',
    ).firstMatch(_timeController.text);
    if (match == null) return;
    final value = DateTime(
      2000,
      1,
      1,
      int.parse(match.group(1)!),
      int.parse(match.group(0)!.substring(3)),
    ).add(Duration(minutes: minuteDelta));
    _timeController.value = TextEditingValue(
      text: _formatTime(value.hour, value.minute),
      selection: const TextSelection.collapsed(offset: 5),
    );
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    final parts = _timeController.text.split(':');
    Navigator.pop(
      context,
      SaveDeadline(
        DateTime(
          _date.year,
          _date.month,
          _date.day,
          int.parse(parts[0]),
          int.parse(parts[1]),
        ),
        hasTime: true,
      ),
    );
  }

  DateTime _thisSunday() {
    final start = DateTime(_now.year, _now.month, _now.day);
    return start.add(Duration(days: DateTime.sunday - start.weekday));
  }

  DateTime _nextMonday() {
    final start = DateTime(_now.year, _now.month, _now.day);
    return start
        .subtract(Duration(days: start.weekday - 1))
        .add(const Duration(days: 7));
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Focus(
      onKeyEvent: (_, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.escape) {
          Navigator.pop(context);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Material(
        color: Theme.of(context).colorScheme.surface,
        elevation: 14,
        shadowColor: Colors.black.withValues(alpha: 0.12),
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: colors.borderSoft),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                const Text(
                  '设置截止日期',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  height: 240,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      SizedBox(
                        width: 112,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: <Widget>[
                            Padding(
                              padding: const EdgeInsets.fromLTRB(7, 6, 7, 5),
                              child: Text(
                                '快捷日期',
                                style: TextStyle(
                                  color: colors.muted,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                            _QuickDateRow(
                              label: '今天',
                              date: DateTime(_now.year, _now.month, _now.day),
                              selectedDate: _date,
                              onPressed: _useDate,
                            ),
                            _QuickDateRow(
                              label: '明天',
                              date: DateTime(
                                _now.year,
                                _now.month,
                                _now.day + 1,
                              ),
                              selectedDate: _date,
                              onPressed: _useDate,
                            ),
                            if (_now.weekday != DateTime.sunday)
                              _QuickDateRow(
                                label: '本周日',
                                date: _thisSunday(),
                                selectedDate: _date,
                                onPressed: _useDate,
                              ),
                            _QuickDateRow(
                              label: '下周一',
                              date: _nextMonday(),
                              selectedDate: _date,
                              onPressed: _useDate,
                            ),
                          ],
                        ),
                      ),
                      Container(
                        width: 1,
                        margin: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 14,
                        ),
                        color: colors.borderSoft.withValues(alpha: 0.7),
                      ),
                      Expanded(
                        child: _CompactCalendar(
                          key: const ValueKey<String>('deadline-calendar'),
                          selectedDate: _date,
                          visibleMonth: _visibleMonth,
                          today: _now,
                          onDateSelected: _useDate,
                          onPreviousMonth: () => _shiftMonth(-1),
                          onNextMonth: () => _shiftMonth(1),
                          onMoveDate: _moveDate,
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Divider(
                    height: 1,
                    color: colors.borderSoft.withValues(alpha: 0.7),
                  ),
                ),
                const SizedBox(height: 9),
                Row(
                  children: <Widget>[
                    Icon(Icons.event_outlined, size: 15, color: colors.muted),
                    const SizedBox(width: 6),
                    Text(
                      _formatDateWithWeekday(_date),
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (widget.initialValue != null) ...<Widget>[
                      const SizedBox(width: 3),
                      TextButton(
                        key: const ValueKey<String>('deadline-clear'),
                        onPressed: () =>
                            Navigator.pop(context, const ClearDeadline()),
                        style: TextButton.styleFrom(
                          foregroundColor: colors.muted,
                          minimumSize: const Size(0, 30),
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          visualDensity: VisualDensity.compact,
                        ),
                        child: const Text('移除', style: TextStyle(fontSize: 11)),
                      ),
                    ],
                    const Spacer(),
                    _DeadlineTimeField(
                      controller: _timeController,
                      onAdjust: _adjustTime,
                      onSubmitted: _save,
                    ),
                    const SizedBox(width: 7),
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      style: TextButton.styleFrom(
                        foregroundColor: colors.muted,
                        minimumSize: const Size(50, 30),
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        visualDensity: VisualDensity.compact,
                      ),
                      child: const Text('取消', style: TextStyle(fontSize: 12)),
                    ),
                    const SizedBox(width: 3),
                    FilledButton(
                      key: const ValueKey<String>('deadline-save'),
                      onPressed: _save,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(64, 30),
                        padding: const EdgeInsets.symmetric(horizontal: 15),
                        visualDensity: VisualDensity.compact,
                      ),
                      child: const Text('保存', style: TextStyle(fontSize: 12)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _QuickDateRow extends StatelessWidget {
  const _QuickDateRow({
    required this.label,
    required this.date,
    required this.selectedDate,
    required this.onPressed,
  });

  final String label;
  final DateTime date;
  final DateTime selectedDate;
  final ValueChanged<DateTime> onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final selected = _sameDate(date, selectedDate);
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: InkWell(
        mouseCursor: SystemMouseCursors.click,
        borderRadius: BorderRadius.circular(6),
        onTap: () => onPressed(date),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          decoration: BoxDecoration(
            color: selected
                ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.05)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            children: <Widget>[
              SizedBox(
                width: 16,
                child: selected
                    ? Icon(
                        Icons.check_rounded,
                        size: 14,
                        color: Theme.of(context).colorScheme.primary,
                      )
                    : const SizedBox.shrink(),
              ),
              const SizedBox(width: 2),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: selected ? FontWeight.w500 : FontWeight.w400,
                  ),
                ),
              ),
              Text(
                '${date.month}/${date.day}',
                style: TextStyle(color: colors.muted, fontSize: 9),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CompactCalendar extends StatelessWidget {
  const _CompactCalendar({
    required this.selectedDate,
    required this.visibleMonth,
    required this.today,
    required this.onDateSelected,
    required this.onPreviousMonth,
    required this.onNextMonth,
    required this.onMoveDate,
    super.key,
  });

  final DateTime selectedDate;
  final DateTime visibleMonth;
  final DateTime today;
  final ValueChanged<DateTime> onDateSelected;
  final VoidCallback onPreviousMonth;
  final VoidCallback onNextMonth;
  final ValueChanged<int> onMoveDate;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    const weekdays = <String>['一', '二', '三', '四', '五', '六', '日'];
    final weekdayColor = Color.lerp(colors.faint, colors.muted, 0.45)!;
    final firstDay = DateTime(visibleMonth.year, visibleMonth.month);
    final leadingDays = firstDay.weekday - 1;
    final daysInMonth = DateTime(
      visibleMonth.year,
      visibleMonth.month + 1,
      0,
    ).day;
    return Focus(
      autofocus: true,
      onKeyEvent: (_, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
          onMoveDate(-1);
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
          onMoveDate(1);
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
          onMoveDate(-7);
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
          onMoveDate(7);
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.pageUp) {
          onPreviousMonth();
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.pageDown) {
          onNextMonth();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Column(
        children: <Widget>[
          SizedBox(
            height: 32,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                _MonthButton(
                  tooltip: '上个月',
                  icon: Icons.chevron_left,
                  onPressed: onPreviousMonth,
                ),
                SizedBox(
                  width: 92,
                  child: Text(
                    '${visibleMonth.year}年${visibleMonth.month}月',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                _MonthButton(
                  tooltip: '下个月',
                  icon: Icons.chevron_right,
                  onPressed: onNextMonth,
                ),
              ],
            ),
          ),
          const SizedBox(height: 5),
          Row(
            children: <Widget>[
              for (final weekday in weekdays)
                Expanded(
                  child: Text(
                    weekday,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: weekdayColor,
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 5),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 150),
              child: GridView.builder(
                key: ValueKey<String>(
                  '${visibleMonth.year}-${visibleMonth.month}',
                ),
                padding: EdgeInsets.zero,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 7,
                  childAspectRatio: 1.43,
                ),
                itemCount: 42,
                itemBuilder: (context, index) {
                  final day = index - leadingDays + 1;
                  if (day < 1 || day > daysInMonth) {
                    return const SizedBox.shrink();
                  }
                  final date = DateTime(
                    visibleMonth.year,
                    visibleMonth.month,
                    day,
                  );
                  return _CalendarDay(
                    date: date,
                    selected: _sameDate(date, selectedDate),
                    today: _sameDate(date, today),
                    onPressed: () => onDateSelected(date),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MonthButton extends StatelessWidget {
  const _MonthButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: tooltip,
    mouseCursor: SystemMouseCursors.click,
    onPressed: onPressed,
    padding: EdgeInsets.zero,
    constraints: const BoxConstraints.tightFor(width: 28, height: 28),
    visualDensity: VisualDensity.compact,
    icon: Icon(icon, size: 17, color: AppColors.of(context).muted),
  );
}

class _CalendarDay extends StatelessWidget {
  const _CalendarDay({
    required this.date,
    required this.selected,
    required this.today,
    required this.onPressed,
  });

  final DateTime date;
  final bool selected;
  final bool today;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Center(
      child: Semantics(
        button: true,
        selected: selected,
        label: '${date.year}年${date.month}月${date.day}日',
        child: SizedBox(
          width: 28,
          height: 28,
          child: Material(
            color: selected ? primary : Colors.transparent,
            shape: CircleBorder(
              side: today && !selected
                  ? BorderSide(color: primary)
                  : BorderSide.none,
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              mouseCursor: SystemMouseCursors.click,
              customBorder: const CircleBorder(),
              hoverColor: primary.withValues(alpha: 0.08),
              onTap: onPressed,
              child: Center(
                child: Text(
                  '${date.day}',
                  style: TextStyle(
                    color: selected ? Colors.white : null,
                    fontSize: 12,
                    fontWeight: selected || today
                        ? FontWeight.w600
                        : FontWeight.w400,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DeadlineTimeField extends StatefulWidget {
  const _DeadlineTimeField({
    required this.controller,
    required this.onAdjust,
    required this.onSubmitted,
  });

  final TextEditingController controller;
  final ValueChanged<int> onAdjust;
  final VoidCallback onSubmitted;

  @override
  State<_DeadlineTimeField> createState() => _DeadlineTimeFieldState();
}

class _DeadlineTimeFieldState extends State<_DeadlineTimeField> {
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode()..addListener(_handleFocusChanged);
  }

  @override
  void dispose() {
    _focusNode
      ..removeListener(_handleFocusChanged)
      ..dispose();
    super.dispose();
  }

  void _handleFocusChanged() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final primary = Theme.of(context).colorScheme.primary;
    return Container(
      width: 86,
      height: 28,
      decoration: BoxDecoration(
        border: Border.all(
          color: _focusNode.hasFocus ? primary : colors.borderSoft,
          width: _focusNode.hasFocus ? 1.5 : 1,
        ),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Row(
        children: <Widget>[
          const SizedBox(width: 7),
          Icon(Icons.schedule_outlined, size: 13, color: colors.muted),
          const SizedBox(width: 2),
          Expanded(
            child: Focus(
              onKeyEvent: (_, event) {
                if (event is! KeyDownEvent) return KeyEventResult.ignored;
                if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
                  widget.onAdjust(15);
                  return KeyEventResult.handled;
                }
                if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
                  widget.onAdjust(-15);
                  return KeyEventResult.handled;
                }
                return KeyEventResult.ignored;
              },
              child: TextFormField(
                key: const ValueKey<String>('deadline-time-field'),
                controller: widget.controller,
                focusNode: _focusNode,
                textAlign: TextAlign.center,
                inputFormatters: <TextInputFormatter>[
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9:]')),
                  LengthLimitingTextInputFormatter(5),
                ],
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
                decoration: const InputDecoration(
                  hintText: '21:00',
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  errorBorder: InputBorder.none,
                  focusedErrorBorder: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.only(right: 6, bottom: 2),
                  errorStyle: TextStyle(fontSize: 0, height: 0),
                ),
                validator: (value) {
                  if (value == null ||
                      !RegExp(r'^([01]\d|2[0-3]):[0-5]\d$').hasMatch(value)) {
                    return '请输入 HH:mm';
                  }
                  return null;
                },
                onFieldSubmitted: (_) => widget.onSubmitted(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _formatTime(int hour, int minute) =>
    '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';

String _formatDateWithWeekday(DateTime date) {
  const weekdays = <String>['一', '二', '三', '四', '五', '六', '日'];
  return '${date.month}月${date.day}日 · 周${weekdays[date.weekday - 1]}';
}

bool _sameDate(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;
