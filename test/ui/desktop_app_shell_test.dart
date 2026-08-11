import 'package:best_todo_list/ui/adaptive/desktop_app_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('桌面外壳根据窗口宽度约束侧栏尺寸', (tester) async {
    double? sidebarWidth;
    addTearDown(() => tester.binding.setSurfaceSize(null));

    Future<void> pumpShell(double width) async {
      await tester.binding.setSurfaceSize(Size(width, 600));
      await tester.pumpWidget(
        MaterialApp(
          home: DesktopAppShell(
            sidebarBuilder: (context, width) {
              sidebarWidth = width;
              return SizedBox(width: width);
            },
            body: const SizedBox.expand(),
          ),
        ),
      );
    }

    await pumpShell(800);
    expect(sidebarWidth, 220);

    await pumpShell(1000);
    expect(sidebarWidth, 240);

    await pumpShell(1400);
    expect(sidebarWidth, 258);
  });
}
