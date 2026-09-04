import 'package:flutter/widgets.dart';

import '../../domain/node_tree.dart';
import '../../domain/todo_node.dart';

class EventBoardLayout {
  const EventBoardLayout();

  static const double spacing = 16;
  static const double minimumCardWidth = 300;
  static const double maximumCardWidth = 420;
  static const double singleColumnMaximumWidth = 680;
  static const double minimumCardHeight = 280;
  static const double maximumCardHeight = 500;
  static const int maximumColumns = 4;
  static const int previewRowLimit = 5;

  EventBoardLayoutProjection project({
    required double maxWidth,
    required double maxHeight,
    required NodeTree tree,
    required List<TodoNode> roots,
  }) {
    final padding = maxWidth < 640
        ? const EdgeInsets.fromLTRB(16, 16, 16, 24)
        : maxWidth < 1200
        ? const EdgeInsets.fromLTRB(20, 20, 20, 28)
        : const EdgeInsets.fromLTRB(24, 24, 24, 32);
    final availableWidth = (maxWidth - padding.horizontal)
        .clamp(0, double.infinity)
        .toDouble();
    final columns = ((availableWidth + spacing) / (minimumCardWidth + spacing))
        .floor()
        .clamp(1, maximumColumns);
    final maximumWidthForColumns = columns == 1
        ? singleColumnMaximumWidth
        : maximumCardWidth * columns + spacing * (columns - 1);
    final gridWidth = availableWidth
        .clamp(0, maximumWidthForColumns)
        .toDouble();
    final cardWidth = (gridWidth - spacing * (columns - 1)) / columns;
    final viewportHeight = maxHeight.isFinite ? maxHeight : 800.0;
    final minimumCardHeight = (viewportHeight * 0.36)
        .clamp(EventBoardLayout.minimumCardHeight, 340)
        .toDouble();
    final maximumCardHeight = (viewportHeight * 0.55)
        .clamp(360, EventBoardLayout.maximumCardHeight)
        .toDouble();

    final preferredHeights = <double>[
      for (final root in roots)
        _preferredCardHeight(
          tree,
          root,
          minimumHeight: minimumCardHeight,
          maximumHeight: maximumCardHeight,
        ),
      minimumCardHeight,
    ];
    final rowHeights = <double>[];
    for (var start = 0; start < preferredHeights.length; start += columns) {
      final end = (start + columns).clamp(0, preferredHeights.length);
      rowHeights.add(
        preferredHeights
            .sublist(start, end)
            .reduce((height, next) => height > next ? height : next),
      );
    }
    final rowOffsets = <double>[];
    var totalHeight = 0.0;
    for (final height in rowHeights) {
      rowOffsets.add(totalHeight);
      totalHeight += height + spacing;
    }
    if (rowHeights.isNotEmpty) totalHeight -= spacing;

    return EventBoardLayoutProjection._(
      padding: padding,
      columns: columns,
      gridWidth: gridWidth,
      cardWidth: cardWidth,
      rowHeights: List<double>.unmodifiable(rowHeights),
      rowOffsets: List<double>.unmodifiable(rowOffsets),
      totalHeight: totalHeight,
    );
  }

  double _preferredCardHeight(
    NodeTree tree,
    TodoNode node, {
    required double minimumHeight,
    required double maximumHeight,
  }) {
    final descendantCount = tree.visibleDescendantsOf(node.id).length;
    final visibleRows = descendantCount.clamp(0, previewRowLimit);
    final hidden = descendantCount > visibleRows;
    return (225 + visibleRows * 36 + (hidden ? 28 : 0))
        .clamp(minimumHeight, maximumHeight)
        .toDouble();
  }
}

class EventBoardLayoutProjection {
  const EventBoardLayoutProjection._({
    required this.padding,
    required this.columns,
    required this.gridWidth,
    required this.cardWidth,
    required this._rowHeights,
    required this._rowOffsets,
    required this.totalHeight,
  });

  final EdgeInsets padding;
  final int columns;
  final double gridWidth;
  final double cardWidth;
  final List<double> _rowHeights;
  final List<double> _rowOffsets;
  final double totalHeight;

  double heightAt(int index) => _rowHeights[index ~/ columns];

  double leftAt(int index) =>
      (index % columns) * (cardWidth + EventBoardLayout.spacing);

  double topAt(int index) => _rowOffsets[index ~/ columns];
}
