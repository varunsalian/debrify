import 'dart:async';
import 'package:debrify/features/home/application/home_board_providers.dart';
import 'package:debrify/models/metadata_preferences.dart';
import 'package:debrify/models/metadata_presentation.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/services/metadata_preferences_service.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../home_progressive_pagination_test.dart' show HomeFixture, page;
import '../../theme/golden_harness.dart' show disableRuntimeFonts;
import 'fixtures/card_metadata_fixture.dart';

MetadataPresentation approved(StremioMeta item, String plot) =>
    MetadataPresentation(
      StremioMeta(
        id: item.id,
        type: item.type,
        name: item.name,
        description: plot,
        runtime: '123 min',
      ),
    );

void main() {
  setUp(disableRuntimeFonts);
  for (final moveFocus in [false, true]) {
    testWidgets(
      'hero uses scoped metadata and rejects stale plot (move=$moveFocus)',
      (tester) async {
        final data = CardMetadataFake();
        data.preferences = () async => MetadataPreferences(
          providers: {MetadataCategory.information: 'tmdb'},
          fallback: false,
        );
        data.respond = (item) async => approved(item, 'Approved ${item.name}');
        final home = HomeFixture(tester, fastCount: 2);
        home.slow.complete(page('Slow'));
        await home.mount(
          wrap: (child) => ProviderScope(
            overrides: [
              homeCardMetadataRepositoryProvider.overrideWith(
                (ref, epoch) => data.repository(epoch),
              ),
            ],
            child: child,
          ),
        );
        await home.settle();
        final origin = await home.focusFast();
        await home.settle();
        expect(find.text('Approved Fast 0'), findsOneWidget);
        final requests = List.of(home.requests);
        final pending = Completer<MetadataPresentation>();
        StremioMeta? requested;
        data.respond = (item) {
          if (item.name == 'Fast 0') {
            requested = item;
            return pending.future;
          }
          return Future.value(approved(item, 'Current ${item.name}'));
        };
        await home.drive(() => MetadataPreferencesService.revision.value++);
        await home.settle();
        expect(requested, isNotNull);
        expect(find.text('Approved Fast 0'), findsNothing);
        if (moveFocus) {
          Focus.of(tester.element(find.text('Fast 1').last)).requestFocus();
          await home.pump(const Duration(milliseconds: 300));
          await home.settle();
          expect(find.text('Current Fast 1'), findsOneWidget);
        }
        await home.drive(
          () => pending.complete(approved(requested!, 'Late Fast 0')),
        );
        await home.settle();
        expect(
          find.text('Late Fast 0'),
          moveFocus ? findsNothing : findsOneWidget,
        );
        if (!moveFocus) expect(origin.hasFocus, isTrue);
        expect(home.requests, requests);
        expect(tester.takeException(), isNull);
        await home.dispose();
      },
    );
  }
}
