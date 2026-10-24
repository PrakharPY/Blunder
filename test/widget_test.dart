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

    expect(
      find.text(
        'Face 1 · 0 UVs · B: box select · S: move · E: stretch · M: mirror · '
        'choose a texture',
      ),
      findsOneWidget,
    );
    expect(find.text('Smart UV remap'), findsOneWidget);
    expect(find.text('Add texture'), findsOneWidget);
  });

  testWidgets('selects, moves, stretches, and mirrors UV points by shortcut',
      (tester) async {
    tester.view.physicalSize = const Size(1100, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const BlunderApp());
    await tester.tap(find.text('UV layout'));
    await tester.pumpAndSettle();

    final canvasRect =
        tester.getRect(find.byKey(const ValueKey('uvEditorCanvas')));
    final uvScale = canvasRect.shortestSide * 0.72;
    final uvOrigin = canvasRect.center - Offset(uvScale / 2, uvScale / 2);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
    await tester.pumpAndSettle();
    expect(
      find.text('UV box select · drag a box around UV corners'),
      findsOneWidget,
    );
    await tester.dragFrom(
      uvOrigin + const Offset(2, 2),
      Offset(uvScale - 4, uvScale - 4),
    );
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Face 1 · 4 UVs · B: box select · S: move · E: stretch · M: mirror · '
        'choose a texture',
      ),
      findsOneWidget,
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
    await tester.pumpAndSettle();
    expect(
      find.text('UV move · drag selected UVs · Enter confirms · Esc cancels'),
      findsOneWidget,
    );
    await tester.dragFrom(canvasRect.center, const Offset(20, -12));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.keyE);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyX);
    await tester.pumpAndSettle();
    expect(
      find.text('UV stretch X · drag to scale · Enter confirms · Esc cancels'),
      findsOneWidget,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.textContaining('UV stretch'), findsNothing);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyM);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyY);
    await tester.pumpAndSettle();
    expect(
      find.text('UV mirrored on Y · Enter confirms · Esc cancels'),
      findsOneWidget,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
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
    final firstMeshTile = find.ancestor(
      of: find.textContaining('Mesh_1'),
      matching: find.byType(ListTile),
    );
    expect(tester.widget<ListTile>(firstMeshTile).selected, isTrue);

    await tester.tap(find.byTooltip('Add mesh').last);
    await tester.pumpAndSettle();

    expect(find.textContaining('Mesh_1'), findsOneWidget);
    expect(find.textContaining('Mesh_2'), findsOneWidget);
    final secondMeshTile = find.ancestor(
      of: find.textContaining('Mesh_2'),
      matching: find.byType(ListTile),
    );
    expect(tester.widget<ListTile>(firstMeshTile).selected, isFalse);
    expect(tester.widget<ListTile>(secondMeshTile).selected, isTrue);

    await tester.tap(find.textContaining('Mesh_1'));
    await tester.pumpAndSettle();
    expect(tester.widget<ListTile>(firstMeshTile).selected, isTrue);
    expect(tester.widget<ListTile>(secondMeshTile).selected, isFalse);
  });

  testWidgets('mesh long-press menu renames and copies a mesh', (tester) async {
    tester.view.physicalSize = const Size(1100, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const BlunderApp());
    await tester.longPress(find.textContaining('Mesh_1'));
    await tester.pumpAndSettle();
    expect(find.text('Rename mesh'), findsOneWidget);
    await tester.tap(find.text('Rename mesh'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'Ground');
    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Ground'), findsOneWidget);

    await tester.longPress(find.textContaining('Ground').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create copy'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Ground_copy'), findsOneWidget);

    await tester.tap(find.textContaining('Ground_copy'));
    await tester.pumpAndSettle();
    await tester.longPress(find.textContaining('Ground').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete mesh'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Ground ·'), findsNothing);
    final remainingTile = find.ancestor(
      of: find.textContaining('Ground_copy'),
      matching: find.byType(ListTile),
    );
    expect(tester.widget<ListTile>(remainingTile).selected, isTrue);
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

    expect(find.textContaining('6 vertices · 1 face'), findsOneWidget);
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
    await tester.tap(find.text('New Scene'));
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

  testWidgets('closes viewport panes and keeps one viewport open',
      (tester) async {
    tester.view.physicalSize = const Size(1100, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const BlunderApp());
    await tester.tap(find.byTooltip('Add menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Scene: 4 views'));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Close this viewport'), findsNWidgets(4));
    await tester.tap(find.byTooltip('Close this viewport').first);
    await tester.pumpAndSettle();
    expect(find.byTooltip('Close this viewport'), findsNWidgets(3));

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(find.byTooltip('Close this viewport'), findsNWidgets(4));

    for (var count = 4; count > 1; count--) {
      await tester.tap(find.byTooltip('Close this viewport').first);
      await tester.pumpAndSettle();
    }
    expect(find.byTooltip('Close this viewport'), findsNothing);
    expect(find.byKey(const ValueKey('modelViewport')), findsOneWidget);
  });

  testWidgets('A toggles selection, Delete removes vertices, and undo restores',
      (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const BlunderApp());
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    await tester.pumpAndSettle();
    expect(find.text('Free view · 4 vertices selected'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    await tester.pumpAndSettle();
    expect(find.text('Free view · 0 vertices selected'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    await tester.sendKeyEvent(LogicalKeyboardKey.delete);
    await tester.pumpAndSettle();
    expect(find.text('Free view · 0 vertices selected'), findsOneWidget);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(find.text('Free view · 4 vertices selected'), findsOneWidget);
  });

  testWidgets('B box-selects vertices in the model viewport', (tester) async {
    tester.view.physicalSize = const Size(1100, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const BlunderApp());
    final viewport =
        tester.getRect(find.byKey(const ValueKey('modelViewport')));
    await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
    await tester.dragFrom(
      viewport.topLeft + const Offset(2, 2),
      viewport.bottomRight - viewport.topLeft - const Offset(4, 4),
    );
    await tester.pumpAndSettle();
    expect(find.text('Free view · 4 vertices selected'), findsOneWidget);
  });

  testWidgets('S accepts a typed proportional scale and undo is available',
      (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const BlunderApp());
    await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit1, character: '1');
    await tester.sendKeyEvent(LogicalKeyboardKey.period, character: '.');
    await tester.sendKeyEvent(LogicalKeyboardKey.digit2, character: '2');
    await tester.sendKeyEvent(LogicalKeyboardKey.digit5, character: '5');
    await tester.pumpAndSettle();
    expect(
        find.text('Scale 1.25 · Enter confirms · Esc cancels'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.byTooltip('Undo (Ctrl+Z)'), findsOneWidget);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
  });

  testWidgets('axis toolbar constrains move and Mesh menu duplicates selection',
      (tester) async {
    tester.view.physicalSize = const Size(1100, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const BlunderApp());
    await tester.tap(find.text('Y').first);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Move on Y (M)'));
    await tester.pumpAndSettle();
    expect(find.text('Free view · Move along Y · drag'), findsOneWidget);

    await tester.tap(find.byTooltip('Mesh menu'));
    await tester.pumpAndSettle();
    expect(find.text('Duplicate selection  (Shift+D)'), findsOneWidget);
    await tester.tap(find.text('Duplicate selection  (Shift+D)'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Move on Y (M)'), findsOneWidget);
    expect(find.byTooltip('More editing tools'), findsNothing);
  });

  testWidgets('Help menu opens shortcut list and About credits',
      (tester) async {
    tester.view.physicalSize = const Size(1100, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const BlunderApp());
    await tester.tap(find.byTooltip('Help menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Shortcut Keys'));
    await tester.pumpAndSettle();
    expect(find.text('Shortcut Keys'), findsOneWidget);
    expect(find.textContaining('Select all vertices/faces'), findsOneWidget);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Help menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('About Blunder'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Blunder v1.05'), findsOneWidget);
    expect(find.textContaining('Prakhar Kumar Yadav'), findsOneWidget);
    expect(find.textContaining('GitHub Copilot'), findsOneWidget);
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

    expect(find.textContaining('8 vertices · 3 faces'), findsOneWidget);
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
    expect(find.text('New Scene'), findsOneWidget);
    expect(find.text('Open'), findsOneWidget);
    expect(find.text('Save'), findsOneWidget);
    expect(find.text('Save As'), findsOneWidget);
    expect(find.text('Export'), findsOneWidget);
    expect(find.text('Exit'), findsOneWidget);
    expect(find.text('Import .obj…'), findsOneWidget);
    expect(find.text('Import .obj…'), findsOneWidget);

    await tester.tap(fileMenu);
    await tester.pumpAndSettle();
    expect(find.text('New Scene'), findsNothing);
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

    expect(find.textContaining('Mesh_1'), findsNothing);
    expect(find.byTooltip('Show scene panel'), findsOneWidget);
    final collapsed =
        tester.getRect(find.byKey(const ValueKey('modelViewport')));
    expect(collapsed.width, greaterThan(before.width + 100));

    await tester.tap(find.byTooltip('Show scene panel'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Mesh_1'), findsOneWidget);
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
