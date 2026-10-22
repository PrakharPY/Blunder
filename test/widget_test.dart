import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:blunder/main.dart';

void main() {
  testWidgets('opens the model and switches to its UV layout', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const BlunderApp());

    expect(find.text('File'), findsOneWidget);
    expect(find.text('Free view · 0 vertices selected'), findsOneWidget);

    await tester.tap(find.text('UVs'));
    await tester.pumpAndSettle();

    expect(find.text('Choose a texture, then drag UV corners over it'),
        findsOneWidget);
  });

  testWidgets('keyboard switches views and locks move to an axis',
      (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const BlunderApp());
    await tester.sendKeyEvent(LogicalKeyboardKey.numpad1);
    await tester.pumpAndSettle();
    expect(find.text('Front view · 0 vertices selected'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyM);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
    await tester.pumpAndSettle();
    expect(find.text('Front view · Move along Z · drag'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.numpad3);
    await tester.sendKeyEvent(LogicalKeyboardKey.numpad7);
    await tester.pumpAndSettle();
    expect(find.text('Top view · Move along Z · drag'), findsOneWidget);
  });

  testWidgets('rotation shortcut accepts an axis and angle before Enter',
      (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const BlunderApp());
    await tester.sendKeyEvent(LogicalKeyboardKey.keyR);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyY);
    await tester.pumpAndSettle();
    expect(find.text('Rotate Y: type degrees · Enter'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.digit9, character: '9');
    await tester.sendKeyEvent(LogicalKeyboardKey.digit0, character: '0');
    await tester.pumpAndSettle();
    expect(find.text('Rotate Y: 90 · Enter'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.textContaining('Rotate Y:'), findsNothing);
  });

  testWidgets('lists independently selectable meshes in the scene panel',
      (tester) async {
    tester.view.physicalSize = const Size(1100, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const BlunderApp());
    final firstMeshTile =
        find.ancestor(of: find.text('Mesh_1'), matching: find.byType(ListTile));
    expect(tester.widget<ListTile>(firstMeshTile).selected, isTrue);

    await tester.tap(find.byTooltip('Add mesh').last);
    await tester.pumpAndSettle();

    expect(find.text('Mesh_1'), findsOneWidget);
    expect(find.text('Mesh_2'), findsOneWidget);
    final secondMeshTile =
        find.ancestor(of: find.text('Mesh_2'), matching: find.byType(ListTile));
    expect(tester.widget<ListTile>(firstMeshTile).selected, isFalse);
    expect(tester.widget<ListTile>(secondMeshTile).selected, isTrue);

    await tester.tap(find.text('Mesh_1'));
    await tester.pumpAndSettle();
    expect(tester.widget<ListTile>(firstMeshTile).selected, isTrue);
    expect(tester.widget<ListTile>(secondMeshTile).selected, isFalse);
  });

  testWidgets('keeps Add vertex active for repeated viewport clicks',
      (tester) async {
    tester.view.physicalSize = const Size(1100, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const BlunderApp());
    await tester.tap(find.byTooltip('Add vertex'));
    await tester.pumpAndSettle();
    final viewport =
        tester.getRect(find.byKey(const ValueKey('modelViewport')));
    await tester.tapAt(viewport.center + const Offset(-30, 0));
    await tester.pumpAndSettle();
    await tester.tapAt(viewport.center + const Offset(30, 0));
    await tester.pumpAndSettle();

    expect(find.text('6 vertices · 1 faces'), findsOneWidget);
    expect(find.text('Tap the surface to place a vertex'), findsOneWidget);
  });

  testWidgets('has visible zoom controls and a dirty-scene prompt',
      (tester) async {
    tester.view.physicalSize = const Size(1100, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const BlunderApp());
    expect(find.text('100%'), findsOneWidget);
    expect(tester.getSize(find.byTooltip('Zoom in')).height, lessThan(28));
    await tester.tap(find.byTooltip('Zoom in'));
    await tester.pumpAndSettle();
    expect(find.text('125%'), findsOneWidget);
    expect(
      tester.widget<Text>(find.text('File')).style?.fontSize,
      lessThan(14),
    );

    await tester.tap(find.byTooltip('Add mesh').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('File menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('New scene'));
    await tester.pumpAndSettle();
    expect(find.text('Unsaved changes'), findsOneWidget);
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();
    expect(find.text('Mesh_2'), findsNothing);
  });

  testWidgets('provides independent view controls for four scene quadrants',
      (tester) async {
    tester.view.physicalSize = const Size(1100, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const BlunderApp());
    await tester.tap(find.byTooltip('Add menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(MenuItemButton, 'Scene'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('modelViewport')), findsOneWidget);
    expect(find.byKey(const ValueKey('modelViewport1')), findsOneWidget);

    await tester.tap(find.byTooltip('Add menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Scene: 4 views'));
    await tester.pumpAndSettle();

    for (var index = 0; index < 4; index++) {
      final key = index == 0 ? 'modelViewport' : 'modelViewport$index';
      expect(find.byKey(ValueKey(key)), findsOneWidget);
    }
    expect(find.byTooltip('Change view'), findsNWidgets(4));

    await tester.tap(find.byTooltip('Change view').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Back').last);
    await tester.pumpAndSettle();

    expect(find.text('Back'), findsOneWidget);
    expect(find.text('Free'), findsOneWidget);
    expect(find.text('Left'), findsOneWidget);
    expect(find.text('Top'), findsOneWidget);
  });

  testWidgets('Strip continuously adds connected triangle faces',
      (tester) async {
    tester.view.physicalSize = const Size(1100, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const BlunderApp());
    await tester.tap(find.byTooltip('Strip'));
    await tester.pumpAndSettle();
    final viewport =
        tester.getRect(find.byKey(const ValueKey('modelViewport')));
    for (final offset in const [
      Offset(-70, 30),
      Offset(0, 30),
      Offset(-35, -30),
      Offset(35, -30),
    ]) {
      await tester.tapAt(viewport.center + offset);
      await tester.pumpAndSettle();
    }

    expect(find.text('8 vertices · 3 faces'), findsOneWidget);
    expect(find.text('Strip: place next vertex to add a triangle'),
        findsOneWidget);
  });

  testWidgets('menu trigger toggles an open dropdown and remains visible',
      (tester) async {
    tester.view.physicalSize = const Size(900, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const BlunderApp());
    final fileMenu = find.byTooltip('File menu');
    await tester.tap(fileMenu);
    await tester.pumpAndSettle();
    expect(find.text('New scene'), findsOneWidget);

    await tester.tap(fileMenu);
    await tester.pumpAndSettle();
    expect(find.text('New scene'), findsNothing);
    expect(fileMenu, findsOneWidget);
  });

  testWidgets('scene panel collapses to a plus and can be restored',
      (tester) async {
    tester.view.physicalSize = const Size(1100, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const BlunderApp());
    final before = tester.getRect(find.byKey(const ValueKey('modelViewport')));
    await tester.tap(find.byTooltip('Hide scene panel'));
    await tester.pumpAndSettle();

    expect(find.text('Mesh_1'), findsNothing);
    expect(find.byTooltip('Show scene panel'), findsOneWidget);
    final collapsed =
        tester.getRect(find.byKey(const ValueKey('modelViewport')));
    expect(collapsed.width, greaterThan(before.width + 100));

    await tester.tap(find.byTooltip('Show scene panel'));
    await tester.pumpAndSettle();
    expect(find.text('Mesh_1'), findsOneWidget);
  });

  testWidgets('left Ctrl and left Shift wheel pan without zooming',
      (tester) async {
    tester.view.physicalSize = const Size(1100, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const BlunderApp());
    final viewport =
        tester.getRect(find.byKey(const ValueKey('modelViewport')));

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendEventToBinding(
      PointerScrollEvent(
        position: viewport.center,
        scrollDelta: const Offset(0, -60),
      ),
    );
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(find.text('100%'), findsOneWidget);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendEventToBinding(
      PointerScrollEvent(
        position: viewport.center,
        scrollDelta: const Offset(0, 60),
      ),
    );
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pumpAndSettle();
    expect(find.text('100%'), findsOneWidget);

    await tester.sendEventToBinding(
      PointerScrollEvent(
        position: viewport.center,
        scrollDelta: const Offset(0, -60),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('109%'), findsOneWidget);
  });
}
