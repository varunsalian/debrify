import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../lib/widgets/playback_startup_view.dart';

void main() {
  for (final size in <Size>[
    Size(320, 568),
    Size(390, 844),
    Size(568, 320),
    Size(740, 360),
    Size(1024, 768),
    Size(800, 600),
    Size(1440, 900),
    Size(1920, 1080),
  ]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('$size text scale $scale', (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(
                size: size,
                textScaler: TextScaler.linear(scale),
                padding: const EdgeInsets.only(top: 24, bottom: 24),
                disableAnimations: true,
              ),
              child: PlaybackStartupView(
                title: 'The Lord of the Rings: The Fellowship of the Ring',
                episode: 'Season 12 · Episode 24',
                details: 'Trying 2 of 5',
                retrying: true,
                onBack: () {},
              ),
            ),
          ),
        );
        await tester.pump(const Duration(seconds: 1));
        expect(tester.takeException(), isNull);
        expect(
          find.byKey(const ValueKey('startup-source-back')).hitTestable(),
          findsOneWidget,
        );
        expect(find.text('Playback details').hitTestable(), findsOneWidget);
        await tester.ensureVisible(
          find.text(
            'The previous source couldn’t start. Trying an alternative.',
          ),
        );
        await tester.pump();
        expect(
          find
              .text(
                'The previous source couldn’t start. Trying an alternative.',
              )
              .hitTestable(),
          findsOneWidget,
        );
        await tester.tap(find.text('Playback details'));
        await tester.pump(const Duration(seconds: 1));
        expect(find.text('Trying 2 of 5'), findsOneWidget);
        expect(find.text('Close').hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
