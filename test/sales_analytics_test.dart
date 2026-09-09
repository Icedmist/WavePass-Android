import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavepass_mobile/screens/home_dashboard_screen.dart';

void main() {
  testWidgets('HomeDashboardScreen displays earnings card and opens sales analytics sheet', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      const MaterialApp(
        home: HomeDashboardScreen(),
      ),
    );

    await tester.pump();

    expect(find.text("TODAY'S WI-FI EARNINGS"), findsOneWidget);
    expect(find.text("Breakdown"), findsOneWidget);

    await tester.tap(find.text("Breakdown"));
    await tester.pumpAndSettle();

    expect(find.text("Sales Analytics"), findsOneWidget);
    expect(find.text("Revenue and voucher performance breakdown"), findsOneWidget);

    expect(find.text("Today"), findsOneWidget);
    expect(find.text("Last 7 Days"), findsOneWidget);
    expect(find.text("This Month"), findsOneWidget);

    expect(find.text("TOTAL REVENUE"), findsOneWidget);
    expect(find.text("PASSES SOLD"), findsOneWidget);
    expect(find.text("AVG TICKET"), findsOneWidget);

    expect(find.text("PLAN DISTRIBUTION"), findsOneWidget);

    await tester.tap(find.text("Last 7 Days"));
    await tester.pumpAndSettle();

    expect(find.text("Sales Analytics"), findsOneWidget);

    await tester.tap(find.text("This Month"));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pumpAndSettle();

    expect(find.text("Sales Analytics"), findsNothing);
    expect(find.text("TODAY'S WI-FI EARNINGS"), findsOneWidget);
  });
}
