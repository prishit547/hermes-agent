// Verifies the first-run welcome/permission-priming flow: it introduces the
// orb, advances to the permissions page, and reports completion.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_mobile/ui/core/atl_theme.dart';
import 'package:hermes_mobile/ui/features/onboarding/welcome_intro.dart';

void main() {
  testWidgets('walks from intro to permissions to completion', (tester) async {
    var done = false;
    await tester.pumpWidget(MaterialApp(
      theme: buildAtlTheme(Brightness.dark),
      home: WelcomeIntro(onDone: () => done = true),
    ));
    await tester.pump();

    // Page 1 — intro.
    expect(find.text('Meet Atlantic'), findsOneWidget);
    expect(find.text('Next'), findsOneWidget);

    // Advance to the permissions page (explicit pumps; the orb animates forever
    // so pumpAndSettle would never return).
    await tester.tap(find.text('Next'));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }

    expect(find.text('Enable the essentials'), findsOneWidget);
    expect(find.text('Microphone'), findsOneWidget);
    expect(find.text('Notifications'), findsOneWidget);

    // Finish without granting anything.
    expect(done, isFalse);
    await tester.tap(find.text('Get started'));
    await tester.pump();
    expect(done, isTrue);
  });
}
