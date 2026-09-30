import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wavepass_mobile/screens/wallet_screen.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({
      'hide_balance_preference': false,
    });
  });

  testWidgets('WalletScreen shows Bank Account Required prompt when cashout is tapped with no bank',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      const MaterialApp(
        home: WalletScreen(venueId: 'test-venue-no-bank'),
      ),
    );

    // Allow initial load to finish
    await tester.pumpAndSettle();

    // Verify wallet loaded
    expect(find.text('Venue Wallet'), findsOneWidget);
    expect(find.text('Cash Out'), findsOneWidget);

    // Tap Cash Out when no bank accounts are registered
    await tester.tap(find.text('Cash Out'));
    await tester.pumpAndSettle();

    // Verify helpful prompt dialog appears
    expect(find.text('Bank Account Required'), findsOneWidget);
    expect(
      find.textContaining('You do not have a registered settlement bank account yet'),
      findsOneWidget,
    );
    expect(find.text('Add Bank Account'), findsOneWidget);

    // Tapping 'Add Bank Account' in prompt dialog opens bank registration
    await tester.tap(find.text('Add Bank Account'));
    await tester.pumpAndSettle();

    expect(find.text('Add Payout Bank'), findsOneWidget);
  });

  testWidgets('Bank registration dialog validates 10-digit NUBAN, name, and bank code with inline feedback',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      const MaterialApp(
        home: WalletScreen(venueId: 'test-venue-validation'),
      ),
    );

    await tester.pumpAndSettle();

    // Tap 'Add Bank' button
    await tester.tap(find.text('Add Bank').first);
    await tester.pumpAndSettle();

    expect(find.text('Add Payout Bank'), findsOneWidget);

    // Tap Save with empty fields
    await tester.tap(find.text('Save Bank Account'));
    await tester.pumpAndSettle();

    // Verify inline error prompts
    expect(find.text('Account number is required.'), findsOneWidget);
    expect(find.text('Account holder name is required.'), findsOneWidget);

    // Enter invalid short account number (< 10 digits)
    final acctField = find.widgetWithText(TextField, 'Account Number');
    await tester.enterText(acctField, '12345');
    await tester.tap(find.text('Save Bank Account'));
    await tester.pumpAndSettle();

    expect(find.text('Account number must be exactly 10 digits.'), findsOneWidget);

    // Now enter valid 10-digit number but leave name empty
    await tester.enterText(acctField, '0123456789');
    await tester.tap(find.text('Save Bank Account'));
    await tester.pumpAndSettle();

    expect(find.text('Account number must be exactly 10 digits.'), findsNothing);
    expect(find.text('Account holder name is required.'), findsOneWidget);

    // Cancel dialog
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(find.text('Add Payout Bank'), findsNothing);
  });
}
