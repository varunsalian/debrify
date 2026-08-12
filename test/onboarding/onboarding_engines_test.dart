import 'package:debrify/services/engine/remote_engine_manager.dart';
import 'package:debrify/widgets/onboarding/onboarding_focus.dart';
import 'package:debrify/widgets/onboarding/onboarding_models.dart';
import 'package:debrify/widgets/onboarding/steps/engines_step.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'onboarding_test_harness.dart';

void main() {
  test('metadata catalogue parses optional descriptions', () async {
    final client = MockClient((request) async {
      return http.Response('''
version: "1"
engines:
  - name: Alpha
    path: torrents/alpha.yaml
    description: Finds carefully curated releases.
  - name: Beta
    path: torrents/beta.yaml
''', 200);
    });
    final manager = RemoteEngineManager(client: client);
    final engines = await manager.fetchAvailableEngines();
    expect(engines, hasLength(2));
    expect(engines.first.description, 'Finds carefully curated releases.');
    expect(engines.last.description, isNull);
    manager.dispose();
  });

  for (final count in <int>[3, 11]) {
    testWidgets(
      '$count manifest engines render dynamically and name-only safely',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(960, 540));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final focus = OnboardFocusController();
        addTearDown(focus.dispose);
        final engines = List<RemoteEngineInfo>.generate(
          count,
          (index) => RemoteEngineInfo(
            id: 'engine_$index',
            fileName: 'engine_$index.yaml',
            displayName: 'Engine $index',
            description: index == 0 ? 'A useful description.' : null,
          ),
        );
        await tester.pumpWidget(
          onboardingApp(
            EnginesStep(
              layout: OnboardLayout.stage,
              focusController: focus,
              engines: engines,
              selected: engines.map((engine) => engine.id).toSet(),
              loading: false,
              importing: false,
              onToggle: (_) {},
              onTurnAllOff: () {},
              onContinue: () {},
              onSkip: () {},
              onRetry: () {},
            ),
          ),
        );
        expect(find.text('A useful description.'), findsOneWidget);
        expect(find.text('Engine ${count - 1}'), findsOneWidget);
        expect(find.text('8'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
