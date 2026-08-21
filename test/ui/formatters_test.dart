import 'package:best_todo_list/ui/common/formatters.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('仅日期的截止时间在当天结束后才算逾期', () {
    final deadline = DateTime(2026, 8, 19);

    expect(
      isOverdue(deadline, DateTime(2026, 8, 19, 23, 59), hasTime: false),
      isFalse,
    );
    expect(isOverdue(deadline, DateTime(2026, 8, 20), hasTime: false), isTrue);
  });

  test('截止日期仅在主动设置时间后显示时间', () {
    final deadline = DateTime(2026, 8, 19, 18);

    expect(formatDeadline(deadline, hasTime: false), '8 月 19 日');
    expect(formatDeadline(deadline), '8 月 19 日，18:00');
  });
}
