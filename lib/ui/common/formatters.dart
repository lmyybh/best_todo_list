String formatDeadline(DateTime? value) {
  if (value == null) return '未设置截止时间';
  final local = value.toLocal();
  return '${local.month} 月 ${local.day} 日，${_two(local.hour)}:${_two(local.minute)}';
}

String formatTime(DateTime value) {
  final local = value.toLocal();
  return '${_two(local.hour)}:${_two(local.minute)}';
}

String formatDate(DateTime value) {
  final local = value.toLocal();
  return '${local.year}/${_two(local.month)}/${_two(local.day)}';
}

bool isOverdue(DateTime? deadline, DateTime now) =>
    deadline != null &&
    deadline.toLocal().isBefore(now) &&
    !_sameMinute(deadline.toLocal(), now);

bool isToday(DateTime? value, DateTime now) =>
    value != null &&
    value.toLocal().year == now.year &&
    value.toLocal().month == now.month &&
    value.toLocal().day == now.day;

String _two(int value) => value.toString().padLeft(2, '0');

bool _sameMinute(DateTime a, DateTime b) =>
    a.year == b.year &&
    a.month == b.month &&
    a.day == b.day &&
    a.hour == b.hour &&
    a.minute == b.minute;
