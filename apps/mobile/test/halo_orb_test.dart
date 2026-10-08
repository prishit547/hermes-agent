// Verifies the Halo orb renders in every pipeline state, reacts to an
// amplitude signal, animates across state transitions, and degrades to a
// static form under reduced motion — all without throwing.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_mobile/ui/core/atl_theme.dart';
import 'package:hermes_mobile/ui/core/halo_orb.dart';

Widget _host(Widget child, {bool reduceMotion = false}) {
  return MaterialApp(
    theme: buildAtlTheme(Brightness.dark),
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: reduceMotion),
      child: Scaffold(body: Center(child: child)),
    ),
  );
}

void main() {
  testWidgets('renders in every HaloState without error', (tester) async {
    for (final state in HaloState.values) {
      await tester.pumpWidget(_host(HaloOrb(state: state, size: 120)));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(HaloOrb), findsOneWidget);
      expect(tester.takeException(), isNull, reason: 'state=$state');
    }
  });

  testWidgets('consumes a live amplitude signal while listening',
      (tester) async {
    final level = ValueNotifier<double>(0);
    addTearDown(level.dispose);

    await tester.pumpWidget(
      _host(HaloOrb(state: HaloState.listening, size: 160, amplitude: level)),
    );
    await tester.pump(const Duration(milliseconds: 50));

    // Drive the amplitude up and let the internal smoothing advance a few
    // frames; the orb must keep rendering cleanly the whole time.
    level.value = 0.9;
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 33));
    }
    expect(tester.takeException(), isNull);
    expect(find.byType(HaloOrb), findsOneWidget);
  });

  testWidgets('crossfades across state transitions', (tester) async {
    await tester.pumpWidget(_host(const HaloOrb(state: HaloState.idle)));
    await tester.pump();

    for (final next in [
      HaloState.listening,
      HaloState.thinking,
      HaloState.speaking,
      HaloState.error,
      HaloState.idle,
    ]) {
      await tester.pumpWidget(_host(HaloOrb(state: next)));
      await tester.pump(const Duration(milliseconds: 130)); // mid-crossfade
      await tester.pump(const Duration(milliseconds: 200)); // settle
      expect(tester.takeException(), isNull, reason: 'transition to $next');
    }
  });

  testWidgets('degrades to a static orb under reduced motion', (tester) async {
    await tester.pumpWidget(
      _host(const HaloOrb(state: HaloState.listening), reduceMotion: true),
    );
    await tester.pump(const Duration(milliseconds: 100));
    // With animations disabled the widget still mounts and paints.
    expect(find.byType(HaloOrb), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
