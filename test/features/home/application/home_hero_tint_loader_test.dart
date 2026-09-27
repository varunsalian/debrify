import 'dart:async';
import 'dart:ui';
import 'package:debrify/features/home/application/home_hero_tint_loader.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

StremioMeta item(String id, {String? poster = 'poster'}) =>
    StremioMeta(id: id, type: 'movie', name: id, poster: poster);
const red = Color(0xFFFF0000);
const blue = Color(0xFF0000FF);

void main() {
  test('missing posters, cached nulls and colors all wait the full 120ms', () {
    fakeAsync((clock) {
      var reads = 0;
      final values = <Color?>[];
      final loader = HomeHeroTintLoader(
        resolve: (poster) async {
          reads++;
          return poster == 'gray' ? null : red;
        },
        isOwnerCurrent: () => true,
      );
      void load(StremioMeta source) =>
          loader.load(source, isCurrent: () => true, publish: values.add);
      for (final source in [
        item('empty', poster: ''),
        item('null', poster: null),
        item('a'),
        item('a'),
        item('gray', poster: 'gray'),
        item('gray', poster: 'changed'),
      ]) {
        final count = values.length;
        load(source);
        clock.elapse(const Duration(milliseconds: 119));
        expect(values, hasLength(count));
        clock.elapse(const Duration(milliseconds: 1));
        expect(values, hasLength(count + 1));
      }
      expect(values, [null, null, red, red, null, null]);
      expect(reads, 2);
      // A now-missing poster clears even when the same title has a cached color.
      load(item('a', poster: null));
      clock.elapse(const Duration(milliseconds: 120));
      expect(values.last, isNull);
      expect(reads, 2);
      loader.dispose();
    });
  });

  test(
    'newer request wins and a stale extraction cannot populate title cache',
    () {
      fakeAsync((clock) {
        final old = Completer<Color?>();
        final values = <Color?>[];
        var reads = 0;
        final loader = HomeHeroTintLoader(
          resolve: (_) {
            reads++;
            return reads == 1 ? old.future : Future.value(blue);
          },
          isOwnerCurrent: () => true,
        );
        void load(String id) =>
            loader.load(item(id), isCurrent: () => true, publish: values.add);
        load('A');
        clock.elapse(const Duration(milliseconds: 120));
        load('B');
        clock.elapse(const Duration(milliseconds: 120));
        old.complete(red);
        clock.flushMicrotasks();
        expect(values, [blue]);
        load('A');
        clock.elapse(const Duration(milliseconds: 120));
        expect(reads, 3);
        expect(values, [blue, blue]);
        loader.dispose();
      });
    },
  );

  test(
    'title cache keeps the original 301-entry threshold and full-clear policy',
    () {
      fakeAsync((clock) {
        var reads = 0;
        final loader = HomeHeroTintLoader(
          resolve: (_) async {
            reads++;
            return red;
          },
          isOwnerCurrent: () => true,
        );
        void load(String id) {
          loader.load(item(id), isCurrent: () => true, publish: (_) {});
          clock.elapse(const Duration(milliseconds: 120));
        }

        for (var i = 0; i < 301; i++) {
          load('$i');
        }
        expect(reads, 301);
        load('0');
        expect(reads, 301);
        load('301');
        expect(reads, 302);
        load('0');
        expect(reads, 303);
        loader.dispose();
      });
    },
  );

  for (final retire in ['owner', 'unmount', 'dispose']) {
    test('$retire rejects a pending extraction', () {
      fakeAsync((clock) {
        var owner = true;
        var mounted = true;
        final pending = Completer<Color?>();
        final values = <Color?>[];
        final loader = HomeHeroTintLoader(
          resolve: (_) => pending.future,
          isOwnerCurrent: () => owner,
        );
        loader.load(item('A'), isCurrent: () => mounted, publish: values.add);
        clock.elapse(const Duration(milliseconds: 120));
        switch (retire) {
          case 'owner':
            owner = false;
          case 'unmount':
            mounted = false;
          case 'dispose':
            loader.dispose();
        }
        pending.complete(red);
        clock.flushMicrotasks();
        expect(values, isEmpty);
        loader.dispose();
      });
    });
  }

  test(
    'retiring before dwell prevents cacheless work and disposal prevents rescheduling',
    () {
      fakeAsync((clock) {
        var owner = true;
        final loader = HomeHeroTintLoader(
          resolve: (_) => throw StateError('retired request'),
          isOwnerCurrent: () => owner,
        );
        void load() => loader.load(
          item('A'),
          isCurrent: () => true,
          publish: (_) => fail('retired publication'),
        );
        load();
        owner = false;
        clock.elapse(const Duration(milliseconds: 120));
        owner = true;
        load();
        loader.dispose();
        load();
        expect(clock.nonPeriodicTimerCount, 0);
        clock.elapse(const Duration(seconds: 1));
      });
    },
  );
}
