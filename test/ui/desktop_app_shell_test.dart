import 'package:best_todo_list/ui/adaptive/desktop_app_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('桌面外壳始终使用 54 像素窄导航栏', (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));

    Future<void> pumpShell(double width) async {
      await tester.binding.setSurfaceSize(Size(width, 600));
      await tester.pumpWidget(
        MaterialApp(
          home: DesktopAppShell(
            navigation: const ColoredBox(
              key: ValueKey<String>('test-navigation'),
              color: Colors.red,
            ),
            body: const SizedBox.expand(),
          ),
        ),
      );
    }

    await pumpShell(800);
    expect(
      tester
          .getSize(find.byKey(const ValueKey<String>('test-navigation')))
          .width,
      DesktopAppShell.navigationWidth,
    );

    await pumpShell(1000);
    expect(
      tester
          .getSize(find.byKey(const ValueKey<String>('test-navigation')))
          .width,
      DesktopAppShell.navigationWidth,
    );

    await pumpShell(1400);
    expect(
      tester
          .getSize(find.byKey(const ValueKey<String>('test-navigation')))
          .width,
      DesktopAppShell.navigationWidth,
    );
  });
}
