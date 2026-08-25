sealed class Deadline implements Comparable<Deadline> {
  const Deadline();

  static Deadline? fromStorage({String? date, int? instantMilliseconds}) {
    if (date != null && instantMilliseconds != null) {
      throw const FormatException('截止期限的日期与时间点不能同时存在');
    }
    if (date != null) {
      final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(date);
      if (match == null) throw FormatException('无效的日期期限：$date');
      return DateOnlyDeadline(
        year: int.parse(match.group(1)!),
        month: int.parse(match.group(2)!),
        day: int.parse(match.group(3)!),
      );
    }
    if (instantMilliseconds != null) {
      return TimedDeadline(
        DateTime.fromMillisecondsSinceEpoch(instantMilliseconds, isUtc: true),
      );
    }
    return null;
  }

  DateTime get calendarDate;

  DateTime get effectiveAt;

  DeadlineStorage get storage;

  bool isOverdue(DateTime now) => !effectiveAt.isAfter(now);

  @override
  int compareTo(Deadline other) => effectiveAt.compareTo(other.effectiveAt);
}

final class DateOnlyDeadline extends Deadline {
  factory DateOnlyDeadline({
    required int year,
    required int month,
    required int day,
  }) {
    final value = DateTime(year, month, day);
    if (value.year != year || value.month != month || value.day != day) {
      throw FormatException('无效的日期期限：$year-$month-$day');
    }
    return DateOnlyDeadline._(year: year, month: month, day: day);
  }

  const DateOnlyDeadline._({
    required this.year,
    required this.month,
    required this.day,
  });

  final int year;
  final int month;
  final int day;

  @override
  DateTime get calendarDate => DateTime(year, month, day);

  @override
  DateTime get effectiveAt => DateTime(year, month, day + 1);

  @override
  DeadlineStorage get storage => DeadlineStorage(
    date:
        '${year.toString().padLeft(4, '0')}-'
        '${month.toString().padLeft(2, '0')}-'
        '${day.toString().padLeft(2, '0')}',
  );
}

final class TimedDeadline extends Deadline {
  TimedDeadline(DateTime value) : instant = _startOfMinute(value.toUtc());

  final DateTime instant;

  DateTime get localTime => instant.toLocal();

  @override
  DateTime get calendarDate =>
      DateTime(localTime.year, localTime.month, localTime.day);

  @override
  DateTime get effectiveAt => localTime;

  @override
  DeadlineStorage get storage =>
      DeadlineStorage(instantMilliseconds: instant.millisecondsSinceEpoch);

  @override
  bool isOverdue(DateTime now) {
    final nowInstant = now.toUtc();
    return instant.isBefore(nowInstant) &&
        instant != _startOfMinute(nowInstant);
  }

  static DateTime _startOfMinute(DateTime value) => DateTime.utc(
    value.year,
    value.month,
    value.day,
    value.hour,
    value.minute,
  );
}

class DeadlineStorage {
  const DeadlineStorage({this.date, this.instantMilliseconds});

  final String? date;
  final int? instantMilliseconds;
}
