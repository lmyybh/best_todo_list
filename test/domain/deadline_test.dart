import 'package:best_todo_list/domain/deadline.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('日期期限在指定日结束后才逾期', () {
    final deadline = DateOnlyDeadline(year: 2026, month: 8, day: 19);

    expect(deadline.calendarDate, DateTime(2026, 8, 19));
    expect(deadline.effectiveAt, DateTime(2026, 8, 20));
    expect(deadline.isOverdue(DateTime(2026, 8, 19, 23, 59)), isFalse);
    expect(deadline.isOverdue(DateTime(2026, 8, 20)), isTrue);
  });

  test('定时期限表示真实时间点并归一化到整分钟', () {
    final localTime = DateTime(2026, 8, 19, 18, 30, 45, 123);
    final deadline = TimedDeadline(localTime);

    expect(deadline.instant, DateTime(2026, 8, 19, 18, 30).toUtc());
    expect(deadline.calendarDate, DateTime(2026, 8, 19));
    expect(deadline.effectiveAt, DateTime(2026, 8, 19, 18, 30));
    expect(deadline.isOverdue(DateTime(2026, 8, 19, 18, 30, 59)), isFalse);
    expect(deadline.isOverdue(DateTime(2026, 8, 19, 18, 31)), isTrue);
  });

  test('日期期限以时区无关的日历日往返持久化 seam', () {
    final deadline = DateOnlyDeadline(year: 2026, month: 8, day: 9);

    expect(deadline.storage.date, '2026-08-09');
    expect(deadline.storage.instantMilliseconds, isNull);

    final restored = Deadline.fromStorage(date: '2026-08-09');
    expect(restored, isA<DateOnlyDeadline>());
    expect(restored!.calendarDate, DateTime(2026, 8, 9));
  });

  test('截止期限按有效截止点比较', () {
    final dateOnly = DateOnlyDeadline(year: 2026, month: 8, day: 19);
    final timed = TimedDeadline(DateTime(2026, 8, 19, 18));

    expect(dateOnly.compareTo(timed), greaterThan(0));
    expect(timed.compareTo(dateOnly), lessThan(0));
  });

  test('定时期限以 UTC 时间点往返持久化 seam', () {
    final instant = DateTime.utc(2026, 8, 19, 10, 30);
    final deadline = TimedDeadline(instant);

    final restored = Deadline.fromStorage(
      instantMilliseconds: deadline.storage.instantMilliseconds,
    );

    expect(restored, isA<TimedDeadline>());
    expect((restored! as TimedDeadline).instant, instant);
  });

  test('持久化数据同时包含两种期限时明确失败', () {
    expect(
      () => Deadline.fromStorage(
        date: '2026-08-19',
        instantMilliseconds: DateTime.utc(2026, 8, 19).millisecondsSinceEpoch,
      ),
      throwsFormatException,
    );
  });

  test('持久化数据包含无效日期时明确失败', () {
    expect(
      () => Deadline.fromStorage(date: '2026-02-30'),
      throwsFormatException,
    );
  });
}
