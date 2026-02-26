import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gozen_planlama/main.dart';

void main() {
  testWidgets('App boots', (WidgetTester tester) async {
    await tester.pumpWidget(const GozenApp());
    await tester.pumpAndSettle();

    expect(find.text('Gozen Planlama'), findsOneWidget);
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
