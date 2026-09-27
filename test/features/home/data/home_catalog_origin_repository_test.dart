import 'dart:async';

import 'package:debrify/features/home/data/home_catalog_origin_repository.dart';
import 'package:debrify/features/home/models/home_catalog_origin.dart';
import 'package:debrify/models/custom_series_identity.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:flutter_test/flutter_test.dart';

StremioAddon addon(String id, {String base = 'https://fixture.invalid'}) =>
    StremioAddon(
      id: id,
      name: id,
      baseUrl: base,
      manifestUrl: '$base/manifest.json',
      addedAt: DateTime.utc(2026),
    );
const item = StremioMeta(id: 'tt123', type: 'series', name: 'Title');

class OriginHarness {
  final native = addon('builtin', base: '');
  final fallback = addon('fallback');
  final restored = addon('restored');
  final calls = <String>[];
  bool current = true, ownerCurrent = true;
  bool Function()? writeGuard;
  Future<StremioMeta> Function(StremioMeta) classify = (value) async => value;
  Future<StremioAddon?> Function(String)? origin;
  late final repository = HomeCatalogOriginRepository(
    nativeAddon: native,
    isOwnerCurrent: () => ownerCurrent,
    scopeProgress: (value, source, guard) {
      calls.add('classify:${source.id}');
      writeGuard = guard;
      return classify(value);
    },
    readCustomOrigin: (id) {
      calls.add('origin:$id');
      return origin?.call(id) ?? Future.value(restored);
    },
  );
  Future<HomeCatalogOrigin> run([StremioMeta value = item]) =>
      repository.prepare(value, fallback, isCurrent: () => current);
}

void main() {
  test(
    'ordinary classified item retains fallback addon and exact item',
    () async {
      final h = OriginHarness();
      final result = await h.run();
      expect(result.status, HomeCatalogOriginStatus.ready);
      expect(result.item, same(item));
      expect(result.addon, same(h.fallback));
      expect(h.calls, ['classify:fallback']);
    },
  );

  test(
    'native fallback applies only without IMDb or configured item source',
    () async {
      for (final value in [
        const StremioMeta(id: 'tmdb:123', type: 'series', name: 'Native'),
        StremioMeta(
          id: 'tmdb:123',
          type: 'series',
          name: 'Native',
          sourceAddon: addon('empty', base: ''),
        ),
      ]) {
        final h = OriginHarness();
        expect((await h.run(value)).addon, same(h.native));
        expect(h.calls, ['classify:builtin']);
      }
      for (final value in [
        const StremioMeta(
          id: 'tmdb:123',
          imdbId: 'tt123',
          type: 'series',
          name: 'Matched',
        ),
        StremioMeta(
          id: 'tmdb:123',
          type: 'series',
          name: 'Configured',
          sourceAddon: addon('configured'),
        ),
      ]) {
        final h = OriginHarness();
        expect((await h.run(value)).addon, same(h.fallback));
        expect(h.calls, ['classify:fallback']);
      }
    },
  );

  test(
    'newly classified custom progress resolves origin and attaches that configuration',
    () async {
      final h = OriginHarness();
      final scoped = item.withCustomSeriesIdentity(h.fallback);
      h.classify = (_) async => scoped;
      final result = await h.run();
      expect(result.status, HomeCatalogOriginStatus.ready);
      expect(result.addon, same(h.restored));
      expect(result.item.sourceAddon, same(h.restored));
      expect(result.item.imdbId, scoped.imdbId);
      expect(h.calls, ['classify:fallback', 'origin:${scoped.imdbId}']);
    },
  );

  test(
    'missing custom configuration retains classified item for history UI',
    () async {
      final h = OriginHarness();
      final scoped = item.withCustomSeriesIdentity(h.fallback);
      h.classify = (_) async => scoped;
      h.origin = (_) async => null;
      final result = await h.run();
      expect(result.status, HomeCatalogOriginStatus.unavailable);
      expect(result.item, same(scoped));
      expect(result.addon, isNull);
    },
  );

  test(
    'malformed custom prefix uses the original parse-versus-prefix behavior',
    () async {
      final h = OriginHarness();
      const malformed = StremioMeta(
        id: 'custom',
        imdbId: 'custom-series:broken',
        type: 'series',
        name: 'Malformed',
      );
      expect(CustomSeriesIdentity.parse(malformed.imdbId), isNull);
      final result = await h.run(malformed);
      expect(h.calls, ['classify:fallback']);
      expect(result.addon, same(h.fallback));
      expect(result.item.sourceAddon, same(h.fallback));
    },
  );

  test('only classification StateError becomes unverified', () async {
    final h = OriginHarness()
      ..classify = (_) async => throw StateError('unverified');
    expect((await h.run()).status, HomeCatalogOriginStatus.unverified);
    final error = FormatException('other failure');
    h.classify = (_) async => throw error;
    await expectLater(h.run(), throwsA(same(error)));
    final scope = item.withCustomSeriesIdentity(h.fallback);
    h.classify = (_) async => scope;
    final originError = StateError('addon lookup failed');
    h.origin = (_) async => throw originError;
    await expectLater(h.run(), throwsA(same(originError)));
  });

  for (final owner in [false, true]) {
    test(
      '${owner ? 'owner' : 'view'} retirement stops classification continuation and future work',
      () async {
        final wait = Completer<StremioMeta>();
        final h = OriginHarness()..classify = (_) => wait.future;
        final pending = h.run();
        expect(h.writeGuard!(), isTrue);
        if (owner) {
          h.ownerCurrent = false;
        } else {
          h.current = false;
        }
        expect(h.writeGuard!(), isFalse);
        wait.complete(item.withCustomSeriesIdentity(h.fallback));
        expect((await pending).status, HomeCatalogOriginStatus.retired);
        expect((await h.run()).status, HomeCatalogOriginStatus.retired);
        expect(h.calls, ['classify:fallback']);
      },
    );
  }

  test('retirement during origin lookup suppresses a ready result', () async {
    final h = OriginHarness();
    final wait = Completer<StremioAddon?>();
    h.classify = (_) async => item.withCustomSeriesIdentity(h.fallback);
    h.origin = (_) => wait.future;
    final pending = h.run();
    await pumpEventQueue();
    h.current = false;
    wait.complete(h.restored);
    expect((await pending).status, HomeCatalogOriginStatus.retired);
  });

  test(
    'retired classification failure is silent instead of unverified',
    () async {
      final wait = Completer<StremioMeta>();
      final h = OriginHarness()..classify = (_) => wait.future;
      final pending = h.run();
      h.current = false;
      wait.completeError(StateError('network'));
      expect((await pending).status, HomeCatalogOriginStatus.retired);
    },
  );
}
