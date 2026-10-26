import 'package:flutter/material.dart';

import '../../domain/todo_node.dart';

Color eventColor(TodoNode node) {
  var seed = 2166136261;
  for (final unit in node.id.codeUnits) {
    seed = ((seed ^ unit) * 16777619) & 0xffffffff;
  }
  double next() {
    seed = (seed * 1664525 + 1013904223) & 0xffffffff;
    return seed / 4294967296;
  }

  final fallbackHue = next() * 360;
  return HSVColor.fromAHSV(
    1,
    node.eventHue ?? fallbackHue,
    0.40 + next() * 0.05,
    0.70 + next() * 0.05,
  ).toColor();
}
