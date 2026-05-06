import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bottle_knockdown_app/main.dart';

void main() {
  testWidgets('App boots to placeholder home screen', (WidgetTester tester) async {
    await tester.pumpWidget(const BottleKnockdownApp());
    await tester.pumpAndSettle();

    expect(find.text('Bottle Knockdown Detector'), findsOneWidget);
    expect(find.text('Phase 1 scaffold ready'), findsOneWidget);
    expect(find.byIcon(Icons.local_drink_rounded), findsOneWidget);
  });
}
