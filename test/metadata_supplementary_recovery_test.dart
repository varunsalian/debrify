import 'package:debrify/models/metadata_preferences.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/services/metadata_preferences_service.dart';
import 'package:debrify/services/metadata_provider_service.dart';
import 'package:debrify/services/tmdb_metadata_repository.dart';
import 'package:debrify/widgets/metadata_presentation_mixin.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SupplementaryRepository extends TmdbMetadataRepository {
  bool fail = true;
  int supplementaryReads = 0;
  @override
  Future<Map<String, dynamic>> get(
    String path, [
    Map<String, String> query = const {},
    bool Function()? isRelevant,
  ]) async {
    if (query.containsKey('append_to_response')) {
      return {
        'title': 'Translated title',
        'original_language': 'fr',
        'images': {
          'posters': [
            {'iso_639_1': null, 'file_path': '/neutral.jpg'},
          ],
        },
      };
    }
    supplementaryReads++;
    if (fail) throw StateError('temporary secondary failure');
    return path.endsWith('/images')
        ? {
            'posters': [
              {'iso_639_1': 'fr', 'file_path': '/preferred.jpg'},
            ],
          }
        : {'overview': 'English synopsis'};
  }
}

const original = StremioMeta(
  id: 'tmdb:1',
  type: 'movie',
  name: 'Catalog',
  description: 'Catalog synopsis',
);
final artworkPrefs = MetadataPreferences(
  providers: {MetadataCategory.posters: 'tmdb'},
  artworkLanguage: 'original',
);

class CardProbe extends StatefulWidget {
  final MetadataProviderService provider;
  const CardProbe(this.provider, {super.key});
  @override
  State<CardProbe> createState() => CardProbeState();
}

class CardProbeState extends State<CardProbe>
    with MetadataPresentationMixin<CardProbe> {
  @override
  StremioMeta get originalMetadata => original;
  @override
  MetadataProviderService get metadataProvider => widget.provider;
  @override
  Widget build(BuildContext context) =>
      Text(presentedMetadata!.poster ?? 'loading');
}

void main() {
  test(
    'partial original-language artwork stays usable but retryable',
    () async {
      final repository = SupplementaryRepository();
      final service = MetadataProviderService(tmdb: repository);
      final partial = await service.present(
        original,
        preferences: artworkPrefs,
      );
      expect(partial.item.poster, endsWith('/neutral.jpg'));
      expect(partial.unavailable, isEmpty);
      expect(partial.retryable, true);
      repository.fail = false;
      final recovered = await service.present(
        original,
        preferences: artworkPrefs,
      );
      expect(recovered.item.poster, endsWith('/preferred.jpg'));
      expect(recovered.retryable, false);
    },
  );
  test(
    'English fallback failures also preserve usable fields and allow retry',
    () async {
      final repository = SupplementaryRepository();
      final service = MetadataProviderService(tmdb: repository);
      final prefs = MetadataPreferences(
        providers: {MetadataCategory.information: 'tmdb'},
        language: 'fr-FR',
        fallback: true,
      );
      final partial = await service.present(original, preferences: prefs);
      expect(partial.item.name, 'Translated title');
      expect(partial.item.description, 'Catalog synopsis');
      expect(partial.retryable, true);
      repository.fail = false;
      final recovered = await service.present(original, preferences: prefs);
      expect(recovered.item.description, 'English synopsis');
      expect(recovered.retryable, false);
    },
  );
  for (final remount in [false, true]) {
    testWidgets(
      'partial artwork recovers and caches only success remount=$remount',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        await MetadataPreferencesService.save(artworkPrefs);
        final repository = SupplementaryRepository();
        final service = MetadataProviderService(tmdb: repository);
        Widget card() => MaterialApp(home: CardProbe(service));
        await tester.pumpWidget(card());
        await tester.pumpAndSettle();
        expect(find.textContaining('/neutral.jpg'), findsOneWidget);
        repository.fail = false;
        if (remount) {
          await tester.pumpWidget(const SizedBox());
          await tester.pumpWidget(card());
        } else {
          await tester.pump(const Duration(seconds: 2));
        }
        await tester.pumpAndSettle();
        expect(find.textContaining('/preferred.jpg'), findsOneWidget);
        expect(repository.supplementaryReads, 2);
        await tester.pumpWidget(const SizedBox());
        await tester.pumpWidget(card());
        await tester.pumpAndSettle();
        expect(find.textContaining('/preferred.jpg'), findsOneWidget);
        expect(repository.supplementaryReads, 2);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
