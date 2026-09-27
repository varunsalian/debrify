import 'package:debrify/features/discover/presentation/discover_preview.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/models/youtube_resolved_streams.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

const title = StremioMeta(id: 'a', type: 'movie', name: 'A');
const video = YoutubeResolvedStreams(playUrl: 'fixture-video');

void activate(DiscoverPreview preview) {
  preview.streams.value = video;
  preview.meta.value = title;
  preview.shown.value = title;
  preview.volume.value = 42;
  preview.loading.value = true;
  preview.showing.value = true;
  preview.theater.value = true;
  preview.takeover.value = .6;
}

List<String> record(DiscoverPreview preview) {
  final events = <String>[];
  preview.streams.addListener(() => events.add('streams'));
  preview.meta.addListener(() => events.add('meta'));
  preview.loading.addListener(() => events.add('loading'));
  preview.showing.addListener(() => events.add('showing'));
  preview.theater.addListener(() => events.add('theater'));
  preview.takeover.addListener(() => events.add('takeover'));
  return events;
}

void main() {
  test(
    'observation waits for change; activity restores controls and restarts dwell',
    () {
      fakeAsync((clock) {
        final preview = DiscoverPreview(isCurrent: () => true);
        preview.showing.value = true;
        preview.observePlayback();
        preview.observePlayback();
        clock.elapse(const Duration(seconds: 6));
        expect(preview.theater.value, isFalse);
        preview.showing.value = false;
        preview.showing.value = true;
        expect(clock.nonPeriodicTimerCount, 1);
        clock.elapse(const Duration(milliseconds: 4999));
        expect(preview.theater.value, isFalse);
        clock.elapse(const Duration(milliseconds: 1));
        expect(preview.theater.value, isTrue);
        preview.onActivity();
        expect(preview.theater.value, isFalse);
        clock.elapse(const Duration(seconds: 4));
        preview.onActivity();
        clock.elapse(const Duration(milliseconds: 4999));
        expect(preview.theater.value, isFalse);
        clock.elapse(const Duration(milliseconds: 1));
        expect(preview.theater.value, isTrue);
        preview.dispose();
      });
    },
  );

  test('dwell rejects retired views and stopped playback', () {
    fakeAsync((clock) {
      var current = true;
      final preview = DiscoverPreview(isCurrent: () => current);
      preview.observePlayback();
      preview.showing.value = true;
      current = false;
      clock.elapse(const Duration(seconds: 5));
      expect(preview.theater.value, isFalse);
      current = true;
      preview.onActivity();
      clock.elapse(const Duration(seconds: 4));
      preview.showing.value = false;
      clock.elapse(const Duration(seconds: 2));
      expect(preview.theater.value, isFalse);
      expect(clock.nonPeriodicTimerCount, 0);
      preview.dispose();
    });
  });

  test(
    'playback reset retains artwork and volume with original notification order',
    () {
      fakeAsync((clock) {
        final preview = DiscoverPreview(isCurrent: () => true);
        preview.observePlayback();
        activate(preview);
        final events = record(preview);
        preview.resetPlayback();
        // Showing's original internal listener restores theater synchronously.
        expect(events, [
          'streams',
          'meta',
          'loading',
          'theater',
          'showing',
          'takeover',
        ]);
        expect(preview.streams.value, isNull);
        expect(preview.meta.value, isNull);
        expect(preview.loading.value, isFalse);
        expect(preview.showing.value, isFalse);
        expect(preview.theater.value, isFalse);
        expect(preview.takeover.value, 0);
        expect(preview.shown.value, same(title));
        expect(preview.volume.value, 42);
        expect(clock.nonPeriodicTimerCount, 0);
        preview.dispose();
      });
    },
  );

  test('compact reset clears only stage effects in their original order', () {
    fakeAsync((clock) {
      final preview = DiscoverPreview(isCurrent: () => true);
      preview.observePlayback();
      expect(preview.needsCompactReset, isFalse);
      activate(preview);
      expect(preview.needsCompactReset, isTrue);
      final events = record(preview);
      preview.clearCompactEffects();
      expect(events, ['takeover', 'theater', 'showing']);
      expect(preview.needsCompactReset, isFalse);
      expect(preview.streams.value, same(video));
      expect(preview.meta.value, same(title));
      expect(preview.shown.value, same(title));
      expect(preview.volume.value, 42);
      expect(preview.loading.value, isTrue);
      expect(clock.nonPeriodicTimerCount, 0);
      preview.dispose();
    });
  });

  test(
    'stop detaches playback and dispose rejects retained activity callbacks',
    () {
      fakeAsync((clock) {
        final preview = DiscoverPreview(isCurrent: () => true);
        preview.observePlayback();
        preview.showing.value = true;
        preview.stopObservingPlayback();
        preview.showing.value = false;
        preview.showing.value = true;
        clock.elapse(const Duration(seconds: 6));
        expect(preview.theater.value, isFalse);
        preview.observePlayback();
        preview.onActivity();
        final activity = preview.onActivity;
        preview.dispose();
        activity();
        preview.observePlayback();
        preview.resetPlayback();
        preview.clearCompactEffects();
        preview.dispose();
        clock.elapse(const Duration(seconds: 6));
        expect(clock.nonPeriodicTimerCount, 0);
      });
    },
  );

  test(
    'independent views keep their own feed and dwell through other disposal',
    () {
      fakeAsync((clock) {
        final first = DiscoverPreview(isCurrent: () => true);
        final second = DiscoverPreview(isCurrent: () => true);
        first.observePlayback();
        second.observePlayback();
        first.showing.value = true;
        second.showing.value = true;
        second.streams.value = video;
        expect(first.streams.value, isNull);
        first.dispose();
        clock.elapse(const Duration(seconds: 5));
        expect(second.theater.value, isTrue);
        expect(second.streams.value, same(video));
        second.dispose();
      });
    },
  );
}
