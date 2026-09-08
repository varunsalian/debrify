import 'dart:async';
import 'package:debrify/models/metadata_preferences.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/services/metadata_preferences_service.dart';
import 'package:debrify/services/metadata_provider_service.dart';
import 'package:debrify/widgets/metadata_presentation_mixin.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class Provider extends MetadataProviderService {
  int calls = 0;
  final Future<MetadataPresentation> Function(int) respond;
  Provider(this.respond);
  @override
  Future<MetadataPresentation> present(
    StremioMeta item, {
    MetadataPreferences? preferences,
    bool Function()? isRelevant,
  }) => respond(++calls);
}

class CardProbe extends StatefulWidget {
  final StremioMeta item;
  final Provider provider;
  const CardProbe(this.item, this.provider, {super.key});
  @override
  State<CardProbe> createState() => ProbeState();
}

class ProbeState extends State<CardProbe>
    with MetadataPresentationMixin<CardProbe> {
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

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await MetadataPreferencesService.save(
      MetadataPreferences(providers: {MetadataCategory.posters: 'tmdb'}),
    );
  });
  const original = StremioMeta(
    id: 'test-loading',
    type: 'movie',
    name: 'A',
    poster: 'addon',
  );
  const selected = StremioMeta(
    id: 'test-loading',
    type: 'movie',
    name: 'A',
    poster: 'tmdb',
  );
  testWidgets(
    'selected posters never flash original art; remount reuses resolved art',
    (tester) async {
      final ready = Completer<MetadataPresentation>();
      final provider = Provider((_) => ready.future);
      await tester.pumpWidget(MaterialApp(home: CardProbe(original, provider)));
      await tester.pump();
      expect(find.text('addon'), findsNothing);
      expect(find.text('loading'), findsOneWidget);
      ready.complete(const MetadataPresentation(selected));
      await tester.pump();
      await tester.pump();
      expect(find.text('tmdb'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(MaterialApp(home: CardProbe(original, provider)));
      await tester.pump();
      expect(find.text('tmdb'), findsOneWidget);
      expect(provider.calls, 1);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'mounted metadata failure retries and recovers without scrolling',
    (tester) async {
      final provider = Provider(
        (n) async => n == 1
            ? const MetadataPresentation(
                StremioMeta(id: 'test-loading', type: 'movie', name: 'A'),
                retryable: true,
              )
            : const MetadataPresentation(selected),
      );
      await tester.pumpWidget(MaterialApp(home: CardProbe(original, provider)));
      await tester.pump();
      expect(find.text('empty'), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
      await tester.pump();
      expect(find.text('tmdb'), findsOneWidget);
      expect(provider.calls, 2);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('unmapped artwork does not keep retrying', (tester) async {
    final provider = Provider(
      (_) async => const MetadataPresentation(
        StremioMeta(id: 'test-loading', type: 'movie', name: 'A'),
        unavailable: {MetadataCategory.posters},
      ),
    );
    await tester.pumpWidget(MaterialApp(home: CardProbe(original, provider)));
    await tester.pump(const Duration(seconds: 20));
    expect(provider.calls, 1);
    await tester.pumpWidget(const SizedBox());
  });
}
