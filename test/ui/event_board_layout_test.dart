import 'package:best_todo_list/domain/node_tree.dart';
import 'package:best_todo_list/domain/todo_node.dart';
import 'package:best_todo_list/ui/events/event_board_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('桌面视口投影为三列等高事件行', () {
    final roots = <TodoNode>[
      _node('first', 1000),
      _node('second', 2000),
      _node('third', 3000),
    ];

    final projection = const EventBoardLayout().project(
      maxWidth: 1000,
      maxHeight: 800,
      tree: NodeTree(roots),
      roots: roots,
    );

    expect(projection.padding, const EdgeInsets.fromLTRB(20, 20, 20, 28));
    expect(projection.columns, 3);
    expect(projection.gridWidth, 960);
    expect(projection.cardWidth, closeTo(309.333, 0.001));
    expect(projection.heightAt(0), 288);
    expect(projection.heightAt(3), 288);
    expect(projection.topAt(0), 0);
    expect(projection.topAt(3), 304);
    expect(projection.totalHeight, 592);
  });

  test('窄视口限制为单列并保留隐藏任务高度', () {
    final root = _node('root', 1000);
    final nodes = <TodoNode>[
      root,
      for (var index = 0; index < 6; index++)
        _node('child-$index', (index + 1) * 1000, parentId: root.id),
    ];

    final projection = const EventBoardLayout().project(
      maxWidth: 600,
      maxHeight: double.infinity,
      tree: NodeTree(nodes),
      roots: <TodoNode>[root],
    );

    expect(projection.padding, const EdgeInsets.fromLTRB(16, 16, 16, 24));
    expect(projection.columns, 1);
    expect(projection.gridWidth, 568);
    expect(projection.cardWidth, 568);
    expect(projection.heightAt(0), 433);
    expect(projection.heightAt(1), 288);
    expect(projection.topAt(0), 0);
    expect(projection.topAt(1), 449);
    expect(projection.totalHeight, 737);
  });
}

TodoNode _node(String id, int order, {String? parentId}) => TodoNode(
  id: id,
  parentId: parentId,
  title: id,
  createdAt: _now,
  updatedAt: _now,
  manualOrder: order,
);

final _now = DateTime.utc(2026, 8, 26, 9);
