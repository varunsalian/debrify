import 'package:debrify/models/metadata_preferences.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/services/metadata_preferences_service.dart';
import 'package:debrify/services/metadata_provider_service.dart';
import 'package:debrify/widgets/metadata_presentation_mixin.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'metadata_artwork_loading_test.dart'
    show CardProbe, ProbeState, Provider;

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await MetadataPreferencesService.save(
      MetadataPreferences(providers: {MetadataCategory.posters: 'tmdb'}),
    );
  });

  const original = StremioMeta(
    id: 'shared-cache',
    type: 'movie',
    name: 'Original',
  );
  const resolved = StremioMeta(
    id: 'shared-cache',
    type: 'movie',
    name: 'Resolved',
    poster: 'selected-art',
  );

  testWidgets(
    'resolved cache survives disposal and is shared across widget types',
    (tester) async {
      final provider = Provider(
        (_) async => const MetadataPresentation(resolved),
      );
      await tester.pumpWidget(MaterialApp(home: CardProbe(original, provider)));
      await tester.pumpAndSettle();
      expect(provider.calls, 1);
      expect(find.text('selected-art'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        MaterialApp(home: _OtherProbe(original, provider)),
      );
      await tester.pumpAndSettle();
      expect(provider.calls, 1);
      expect(find.text('selected-art'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'hero preloads feed other cards and policy changes invalidate the shared entry',
    (tester) async {
      final provider = Provider(
        (_) async => const MetadataPresentation(resolved),
      );
      await tester.pumpWidget(MaterialApp(home: CardProbe(original, provider)));
      await tester.pumpAndSettle();
      const target = StremioMeta(
        id: 'preloaded-shared-cache',
        type: 'movie',
        name: 'Next',
      );
      var warmed = 0;
      StremioMeta? warmedItem;
      final state = tester.state<ProbeState>(find.byType(CardProbe));
      final pending = state.preloadMetadata([target], (item, _) async {
        warmedItem = item;
        warmed++;
      });
      await tester.pumpAndSettle();
      await pending;
      expect(warmed, 1, reason: 'provider calls: ${provider.calls}');
      expect(warmedItem, same(resolved));
      expect(provider.calls, 2);
      await tester.pumpWidget(MaterialApp(home: _OtherProbe(target, provider)));
      await tester.pumpAndSettle();
      expect(provider.calls, 2);
      expect(find.text('selected-art'), findsOneWidget);
      await MetadataPreferencesService.save(
        MetadataPreferences(
          providers: {MetadataCategory.posters: 'tmdb'},
          language: 'fr-FR',
        ),
      );
      await tester.pumpAndSettle();
      expect(provider.calls, 3);
      expect(find.text('selected-art'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    },
  );
}

class _OtherProbe extends StatefulWidget {
  const _OtherProbe(this.item, this.provider);
  final StremioMeta item;
  final MetadataProviderService provider;
  @override
  State<_OtherProbe> createState() => _OtherProbeState();
}

class _OtherProbeState extends State<_OtherProbe>
    with MetadataPresentationMixin<_OtherProbe> {
  @override
  StremioMeta get originalMetadata => widget.item;
  @override
  MetadataProviderService get metadataProvider => widget.provider;
  @override
  Widget build(BuildContext context) => Text(
    metadataArtworkPending(MetadataCategory.posters)
        ? 'loading'
        : presentedMetadata!.poster ?? 'empty',
  );
}
