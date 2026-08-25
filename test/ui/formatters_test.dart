import 'package:best_todo_list/domain/deadline.dart';
import 'package:best_todo_list/ui/common/formatters.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('截止日期仅在主动设置时间后显示时间', () {
    final dateOnly = DateOnlyDeadline(year: 2026, month: 8, day: 19);
    final timed = TimedDeadline(DateTime(2026, 8, 19, 18));

    expect(formatDeadline(dateOnly), '8 月 19 日');
    expect(formatDeadline(timed), '8 月 19 日，18:00');
  });
}
