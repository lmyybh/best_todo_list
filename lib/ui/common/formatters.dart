String formatDeadline(DateTime? value, {bool hasTime = true}) {
  if (value == null) return '未设置截止日期';
  final local = value.toLocal();
  if (!hasTime) return '${local.month} 月 ${local.day} 日';
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

String formatCompactDate(DateTime value) {
  final local = value.toLocal();
  return '${local.month}/${local.day}';
}

bool isOverdue(DateTime? deadline, DateTime now, {bool hasTime = true}) {
  if (deadline == null) return false;
  final local = deadline.toLocal();
  if (!hasTime) {
    return DateTime(local.year, local.month, local.day + 1).isBefore(now) ||
        DateTime(local.year, local.month, local.day + 1).isAtSameMomentAs(now);
  }
  return local.isBefore(now) && !_sameMinute(local, now);
}

DateTime effectiveDeadline(DateTime deadline, {required bool hasTime}) {
  final local = deadline.toLocal();
  if (hasTime) return local;
  return DateTime(local.year, local.month, local.day + 1);
}

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
