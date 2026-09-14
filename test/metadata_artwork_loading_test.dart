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
  final bool hero;
  const CardProbe(this.item, this.provider, {super.key, this.hero = false});
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
  Widget build(BuildContext context) => widget.hero
      ? Column(
          children: [
            Text(heroPresentation!.background ?? 'no-art'),
            Text(heroPresentation!.description ?? 'no-plot'),
          ],
        )
      : Text(
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
  testWidgets('hero retry recovers and becomes reusable', (tester) async {
    final provider = Provider((n) async => MetadataPresentation(selected, retryable: n == 2));
    await tester.pumpWidget(MaterialApp(home: CardProbe(original, provider)));
    await tester.pump();
    const next = StremioMeta(id: 'recover-preload', type: 'movie', name: 'Hero');
    final state = tester.state<ProbeState>(find.byType(CardProbe));
    final preload = state.preloadMetadata(const [next], (_, _) async {});
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    await preload;
    expect(provider.calls, 3);
    await tester.pumpWidget(MaterialApp(home: CardProbe(next, provider)));
    await tester.pump();
    expect(provider.calls, 3);
    expect(find.text('tmdb'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('disposing cancels a delayed hero retry', (tester) async {
    final provider = Provider((n) async => MetadataPresentation(selected, retryable: n > 1));
    await tester.pumpWidget(MaterialApp(home: CardProbe(original, provider)));
    await tester.pump();
    final state = tester.state<ProbeState>(find.byType(CardProbe));
    final preload = state.preloadMetadata(const [
      StremioMeta(id: 'cancel-retry', type: 'movie', name: 'Hero')], (_, _) async {});
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    await preload;
    expect(provider.calls, 2);
  });

  testWidgets('failed hero preloads retry twice then stop', (tester) async {
    final provider = Provider((n) async => n == 1
        ? const MetadataPresentation(selected)
        : const MetadataPresentation(selected, retryable: true));
    await tester.pumpWidget(MaterialApp(home: CardProbe(original, provider)));
    await tester.pump();
    final state = tester.state<ProbeState>(find.byType(CardProbe));
    final preload = state.preloadMetadata(const [
      StremioMeta(id: 'retry-preload', type: 'movie', name: 'Hero')], (_, _) async {});
    await tester.pump();
    expect(provider.calls, 2);
    await tester.pump(const Duration(seconds: 2));
    expect(provider.calls, 3);
    await tester.pump(const Duration(seconds: 4));
    await preload;
    expect(provider.calls, 4);
    await tester.pump(const Duration(seconds: 20));
    expect(provider.calls, 4);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('entire hero reel preloads with bounded concurrency and navigation reuse', (tester) async {
    final pending = <Completer<MetadataPresentation>>[];
    final provider = Provider((n) {
      if (n == 1) return Future.value(const MetadataPresentation(selected));
      final ready = Completer<MetadataPresentation>();
      pending.add(ready);
      return ready.future;
    });
    await tester.pumpWidget(MaterialApp(home: CardProbe(original, provider)));
    await tester.pump();
    final state = tester.state<ProbeState>(find.byType(CardProbe));
    final heroes = List.generate(8, (i) => StremioMeta(id: 'preload-$i', type: 'movie', name: 'Hero'));
    var warmed = 0;
    final loading = state.preloadMetadata(heroes, (_, _) async { warmed++; });
    await tester.pump();
    expect(pending.length, 2);
    for (var i = 0; i < heroes.length; i++) {
      pending[i].complete(const MetadataPresentation(selected));
      await tester.pump();
      expect(pending.length - i - 1, lessThanOrEqualTo(2));
    }
    await loading;
    expect(warmed, heroes.length);
    expect(provider.calls, heroes.length + 1);
    await tester.pumpWidget(MaterialApp(home: CardProbe(heroes.last, provider)));
    await tester.pump();
    expect(find.text('tmdb'), findsOneWidget);
    expect(provider.calls, heroes.length + 1);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('disposed hero preload does not publish or start further work', (tester) async {
    final ready = Completer<MetadataPresentation>();
    final provider = Provider((n) => n == 1
        ? Future.value(const MetadataPresentation(selected)) : ready.future);
    await tester.pumpWidget(MaterialApp(home: CardProbe(original, provider)));
    await tester.pump();
    final state = tester.state<ProbeState>(find.byType(CardProbe));
    var warmed = 0;
    final loading = state.preloadMetadata(List.generate(5, (i) =>
      StremioMeta(id: 'disposed-$i', type: 'movie', name: 'Hero')), (_, _) async { warmed++; });
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    ready.complete(const MetadataPresentation(selected));
    await tester.pump();
    await loading;
    expect(warmed, 0);
    expect(provider.calls, 3);
  });

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
  testWidgets(
    'hero hides original fields while loading and retains resolved art across retry failure',
    (tester) async {
      await MetadataPreferencesService.save(
        MetadataPreferences(
          providers: {
            MetadataCategory.backgrounds: 'tmdb',
            MetadataCategory.information: 'tmdb',
          },
        ),
      );
      const catalog = StremioMeta(
        id: 'hero-retry',
        type: 'movie',
        name: 'Hero',
        background: 'addon-art',
        description: 'addon-plot',
      );
      const selected = StremioMeta(
        id: 'hero-retry',
        type: 'movie',
        name: 'Hero',
        background: 'tmdb-art',
        description: 'tmdb-plot',
      );
      final first = Completer<MetadataPresentation>();
      final provider = Provider((attempt) async {
        if (attempt == 1) return first.future;
        if (attempt == 2) {
          return const MetadataPresentation(
            StremioMeta(id: 'hero-retry', type: 'movie', name: 'Hero'),
            retryable: true,
          );
        }
        return const MetadataPresentation(selected);
      });
      await tester.pumpWidget(
        MaterialApp(home: CardProbe(catalog, provider, hero: true)),
      );
      await tester.pump();
      expect(find.text('addon-art'), findsNothing);
      expect(find.text('addon-plot'), findsNothing);
      first.complete(const MetadataPresentation(selected, retryable: true));
      await tester.pump();
      await tester.pump();
      expect(find.text('tmdb-art'), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
      await tester.pump();
      expect(provider.calls, 2);
      expect(find.text('tmdb-art'), findsOneWidget);
      expect(find.text('tmdb-plot'), findsOneWidget);
      await tester.pump(const Duration(seconds: 4));
      await tester.pump();
      expect(provider.calls, 3);
      expect(find.text('tmdb-art'), findsOneWidget);
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
