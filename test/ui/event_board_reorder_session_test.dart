import 'package:best_todo_list/ui/events/event_board_reorder_session.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('拖动预览只在面板内结束时提交', () {
    final session = EventBoardReorderSession();

    session.start('third', <String>['first', 'second', 'third']);
    session.previewAround('first', after: false);

    expect(session.orderedIds, <String>['third', 'first', 'second']);
    expect(session.finish(droppedInside: true), <String>[
      'third',
      'first',
      'second',
    ]);
    expect(session.active, isFalse);
  });

  test('重复拖到同一位置不产生新的预览状态', () {
    final session = EventBoardReorderSession();
    session.start('third', <String>['first', 'second', 'third']);

    expect(session.previewAround('first', after: false), isTrue);
    expect(session.previewAround('first', after: false), isFalse);
    expect(session.previewAtEnd(), isTrue);
    expect(session.previewAtEnd(), isFalse);
  });

  test('拖动在面板外结束不提交预览顺序', () {
    final session = EventBoardReorderSession();
    session.start('third', <String>['first', 'second', 'third']);
    session.previewAround('first', after: false);

    expect(session.finish(droppedInside: false), isNull);
    expect(session.active, isFalse);
  });

  test('Esc 取消恢复原预览并阻止提交', () {
    final session = EventBoardReorderSession();
    session.start('first', <String>['first', 'second', 'third']);
    session.previewAtEnd();

    session.cancel();

    expect(session.orderedIds, <String>['first', 'second', 'third']);
    expect(session.finish(droppedInside: true), isNull);
    expect(session.active, isFalse);
  });

  test('键盘排序支持单步和移到边缘', () {
    final session = EventBoardReorderSession();
    const ids = <String>['first', 'second', 'third'];

    expect(
      session.reorderFromKeyboard(
        id: 'second',
        direction: -1,
        toEdge: false,
        orderedIds: ids,
      ),
      <String>['second', 'first', 'third'],
    );
    expect(
      session.reorderFromKeyboard(
        id: 'first',
        direction: 1,
        toEdge: true,
        orderedIds: ids,
      ),
      <String>['second', 'third', 'first'],
    );
  });
}
