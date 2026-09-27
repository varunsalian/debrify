import 'dart:async';
import 'package:debrify/features/home/application/home_card_metadata_dependencies.dart';
import 'package:debrify/features/home/presentation/home_card_metadata_view.dart';
import 'package:debrify/models/metadata_preferences.dart';
import 'package:debrify/models/metadata_presentation.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/services/metadata_preferences_service.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../fixtures/card_metadata_fixture.dart';

void main() {
  setUp(() {
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeLegacy();
    SharedPreferences.setMockInitialValues({});
  });
  tearDown(ProfileRuntime.debugReset);

  testWidgets(
    'same-title refresh retains approved artwork; recycled tiles clear it immediately',
    (tester) async {
      final data = CardMetadataFake();
      final host = _Host(data);
      await tester.pumpWidget(host.build(cardSource));
      await tester.pumpAndSettle();
      expect(find.text('approved-art'), findsOneWidget);
      await tester.pumpWidget(host.build(cardSource));
      await tester.pump();
      expect(data.requests, hasLength(1));
      final pending = Completer<MetadataPresentation>();
      data.respond = (_) => pending.future;
      final updated = StremioMeta(
        id: cardSource.id,
        type: cardSource.type,
        name: 'Updated',
      );
      await tester.pumpWidget(host.build(updated));
      expect(find.text('approved-art'), findsOneWidget);
      expect(find.text('loading'), findsNothing);
      await tester.pump();
      expect(data.requests, hasLength(2));
      const other = StremioMeta(id: 'other', type: 'movie', name: 'Other');
      data.respond = (_) async => const MetadataPresentation(other);
      await tester.pumpWidget(host.build(other));
      expect(find.text('approved-art'), findsNothing);
      pending.complete(const MetadataPresentation(approvedCard));
      await tester.pumpAndSettle();
      expect(find.text('Other'), findsOneWidget);
      expect(data.cache.peek(updated), isNull);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'current-provider refresh replaces retained metadata with the new catalog object',
    (tester) async {
      final data = CardMetadataFake();
      final host = _Host(data);
      await tester.pumpWidget(host.build(cardSource));
      await tester.pumpAndSettle();
      final pending = Completer<MetadataPresentation>();
      data.preferences = () async => MetadataPreferences();
      data.respond = (_) => pending.future;
      final updated = StremioMeta(
        id: cardSource.id,
        type: cardSource.type,
        name: 'Updated',
        poster: 'new-catalog-art',
      );
      await tester.pumpWidget(host.build(updated));
      expect(find.text('approved-art'), findsOneWidget);
      pending.complete(MetadataPresentation(updated));
      await tester.pumpAndSettle();
      expect(find.text('new-catalog-art'), findsOneWidget);
      expect(find.text('approved-art'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'policy revision clears old artwork while its replacement is pending',
    (tester) async {
      final data = CardMetadataFake();
      final host = _Host(data);
      await tester.pumpWidget(host.build(cardSource));
      await tester.pumpAndSettle();
      final pending = Completer<MetadataPresentation>();
      data.respond = (_) => pending.future;
      MetadataPreferencesService.revision.value++;
      await tester.pump();
      expect(find.text('approved-art'), findsNothing);
      expect(find.text('loading'), findsOneWidget);
      expect(data.requests, hasLength(2));
      pending.complete(const MetadataPresentation(approvedCard));
      await tester.pumpAndSettle();
      expect(find.text('approved-art'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'a simultaneous policy and same-title update cannot retain old artwork',
    (tester) async {
      final data = CardMetadataFake();
      final host = _Host(data);
      await tester.pumpWidget(host.build(cardSource));
      await tester.pumpAndSettle();
      final pending = Completer<MetadataPresentation>();
      data.respond = (_) => pending.future;
      MetadataPreferencesService.revision.value++;
      final updated = StremioMeta(
        id: cardSource.id,
        type: cardSource.type,
        name: 'Updated',
      );
      await tester.pumpWidget(host.build(updated));
      expect(find.text('approved-art'), findsNothing);
      expect(find.text('loading'), findsOneWidget);
      await tester.pump();
      expect(data.requests.last.item, same(updated));
      pending.complete(const MetadataPresentation(approvedCard));
      await tester.pumpAndSettle();
      expect(find.text('approved-art'), findsOneWidget);
      expect(data.cache.peek(cardSource), isNull);
      expect(data.cache.peek(updated)?.value.item, same(approvedCard));
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'outgoing cards retire on profile change and a new keyed card can load',
    (tester) async {
      final data = CardMetadataFake();
      final pending = Completer<MetadataPresentation>();
      data.respond = (_) => pending.future;
      final host = _Host(data);
      await tester.pumpWidget(host.build(cardSource));
      await tester.pump();
      expect(data.requests, hasLength(1));
      ProfileRuntime.promoteLegacyToCommitted(
        ProfileScope(profileId: 'incoming', dataGeneration: 1, sessionEpoch: 1),
      );
      await tester.pump();
      await tester.pump();
      pending.complete(const MetadataPresentation(approvedCard));
      await tester.pumpAndSettle();
      expect(data.preferenceReads, 1);
      expect(data.cache.peek(cardSource), isNull);
      expect(find.text('approved-art'), findsNothing);
      data.respond = (_) async => const MetadataPresentation(approvedCard);
      await tester.pumpWidget(
        host.build(cardSource, key: const ValueKey('incoming')),
      );
      await tester.pumpAndSettle();
      expect(data.preferenceReads, 2);
      expect(find.text('approved-art'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('covered routes accept metadata once and reveal it on return', (
    tester,
  ) async {
    final data = CardMetadataFake();
    final pending = Completer<MetadataPresentation>();
    data.respond = (_) => pending.future;
    final host = _Host(data);
    await tester.pumpWidget(host.build(cardSource));
    await tester.pump();
    unawaited(
      host.navigator.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('Covered')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    pending.complete(const MetadataPresentation(approvedCard));
    await tester.pumpAndSettle();
    expect(data.requests, hasLength(1));
    host.navigator.currentState!.pop();
    await tester.pumpAndSettle();
    expect(find.text('approved-art'), findsOneWidget);
    expect(data.preferenceReads, 1);
    expect(data.requests, hasLength(1));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'unmount cancels retries and policy subscriptions without clearing shared results',
    (tester) async {
      final data = CardMetadataFake();
      var retry = true;
      data.respond = (_) async =>
          MetadataPresentation(approvedCard, retryable: retry);
      final host = _Host(data);
      await tester.pumpWidget(host.build(cardSource));
      await tester.pump();
      expect(data.requests, hasLength(1));
      await tester.pumpWidget(const SizedBox());
      MetadataPreferencesService.revision.value++;
      await tester.pump(const Duration(seconds: 10));
      expect(data.requests, hasLength(1));
      retry = false;
      await tester.pumpWidget(host.build(cardSource));
      await tester.pumpAndSettle();
      expect(data.requests, hasLength(2));
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(host.build(cardSource));
      await tester.pumpAndSettle();
      expect(data.requests, hasLength(2));
      expect(find.text('approved-art'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    },
  );
}

class _Host {
  _Host(CardMetadataFake data)
    : overrides = [
        homeCardMetadataRepositoryProvider.overrideWith(
          (ref, epoch) => data.repository(epoch),
        ),
      ];
  final List<Override> overrides;
  final navigator = GlobalKey<NavigatorState>();
  Widget build(StremioMeta original, {Key key = const ValueKey('card')}) =>
      ProviderScope(
        overrides: overrides,
        child: MaterialApp(
          navigatorKey: navigator,
          home: HomeCardMetadataView(
            key: key,
            original: original,
            builder: (_, state) => Column(
              children: [
                Text(
                  state.artworkPending(MetadataCategory.posters)
                      ? 'loading'
                      : state.presented.poster ?? 'empty',
                ),
                Text(state.presented.name),
              ],
            ),
          ),
        ),
      );
}
