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

    expect(find.text('Blunder'), findsOneWidget);
    expect(find.text('Free view · 0/4 vertices selected'), findsOneWidget);

    await tester.tap(find.text('UVs'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Drag a corner to map'), findsOneWidget);
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
    expect(find.text('Front view · 0/4 vertices selected'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyM);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
    await tester.pumpAndSettle();
    expect(find.text('Front view · Move along Z · drag'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.numpad3);
    await tester.sendKeyEvent(LogicalKeyboardKey.numpad7);
    await tester.pumpAndSettle();
    expect(find.text('Top view · Move along Z · drag'), findsOneWidget);
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
}
