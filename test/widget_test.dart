import 'dart:ui' show Size;

import 'package:blunder/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('opens the model and switches to its UV layout', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const BlunderApp());

    expect(find.text('Blunder'), findsOneWidget);
    expect(find.text('0/4 vertices selected'), findsOneWidget);

    await tester.tap(find.text('UVs'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Drag a corner to map'), findsOneWidget);
  });
}
