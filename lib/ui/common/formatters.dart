import '../../domain/deadline.dart';

String formatDeadline(Deadline? value) {
  if (value == null) return '未设置截止日期';
  return switch (value) {
    DateOnlyDeadline(:final month, :final day) => '$month 月 $day 日',
    TimedDeadline(:final localTime) =>
      '${localTime.month} 月 ${localTime.day} 日，'
          '${_two(localTime.hour)}:${_two(localTime.minute)}',
  };
}

String formatTime(DateTime value) {
  final local = value.toLocal();
  return '${_two(local.hour)}:${_two(local.minute)}';
}

String formatDate(DateTime value) {
  final local = value.toLocal();
  return '${local.year}/${_two(local.month)}/${_two(local.day)}';
}

String formatCompactDeadline(Deadline value) =>
    '${value.calendarDate.month}/${value.calendarDate.day}';

bool isToday(DateTime? value, DateTime now) =>
    value != null &&
    value.toLocal().year == now.year &&
    value.toLocal().month == now.month &&
    value.toLocal().day == now.day;

String _two(int value) => value.toString().padLeft(2, '0');
