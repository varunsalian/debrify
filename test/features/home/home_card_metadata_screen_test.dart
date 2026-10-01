import 'package:debrify/features/home/application/home_board_providers.dart';
import 'package:debrify/models/metadata_preferences.dart';
import 'package:debrify/models/metadata_presentation.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/services/metadata_preferences_service.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../home_progressive_pagination_test.dart' show HomeFixture;
import 'fixtures/card_metadata_fixture.dart';

void main() {
  testWidgets(
    'real catalog cards render injected metadata and retain focus without catalog reload',
    (tester) async {
      final data = CardMetadataFake();
      data.respond = (item) async => MetadataPresentation(item);
      final home = HomeFixture(tester);
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
      final node = await home.focusFast();
      final requests = List.of(home.requests);
      data.respond = (item) async => MetadataPresentation(
        StremioMeta(
          id: item.id,
          type: item.type,
          name: 'Resolved ${item.name}',
        ),
      );
      await home.drive(
        () => MetadataPreferencesService.save(
          MetadataPreferences(
            providers: {
              MetadataCategory.information: 'tmdb',
              MetadataCategory.posters: 'tmdb',
            },
          ),
        ),
      );
      await home.settle();
      final card = find
          .byWidgetPredicate(
            (widget) =>
                widget.runtimeType.toString() == 'HomeCatalogCard' &&
                (widget as dynamic).item.name == 'Fast 0',
          )
          .first;
      final title = find.descendant(
        of: card,
        matching: find.text('Resolved Fast 0'),
      );
      expect(title, findsWidgets);
      expect(Focus.of(tester.element(title.last)), same(node));
      expect(node.hasFocus, isTrue);
      expect(home.requests, requests);
      expect(tester.takeException(), isNull);
      await home.dispose();
    },
  );
}
