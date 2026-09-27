import 'dart:async';
import 'package:debrify/features/home/application/home_hero_live_preview.dart';
import 'package:debrify/features/home/data/home_hero_live_repository.dart';
import 'package:debrify/services/stremio_iptv_service.dart';
import 'package:flutter_test/flutter_test.dart';

List<StremioIptvCandidate> candidates(List<String> urls) => [
  for (final url in urls) StremioIptvCandidate(url: url, label: url),
];
Future<void> flush() => Future<void>.delayed(Duration.zero);

class _Fixture {
  bool mounted = true;
  bool owner = true;
  String? url;
  String? channel = 'addon:a';
  final events = <String>[];
  Future<List<StremioIptvCandidate>> Function(String) resolve = (_) async =>
      candidates(['a', 'b']);
  late final preview = HomeHeroLivePreview(
    repository: HomeHeroLiveRepository(
      isAddonChannel: (key) {
        events.add('classify:$key');
        return key.startsWith('addon:');
      },
      resolveCandidates: (key) {
        events.add('resolve:$key');
        return resolve(key);
      },
      invalidate: (key) => events.add('invalidate:$key'),
    ),
    isOwnerCurrent: () => owner,
  );
  void publish(String? value) {
    url = value;
    events.add('publish:$value');
  }

  void load(String key, {void Function()? prepare}) => preview.load(
    key,
    isCurrent: () => mounted,
    prepare: () {
      events.add('prepare');
      url = null;
      prepare?.call();
    },
    publish: publish,
  );
  void fail() => preview.playbackFailed(
    currentUrl: url,
    channelKey: () => channel,
    publish: publish,
  );
}

void main() {
  test(
    'plain URL publishes synchronously after preparation without resolving',
    () {
      final f = _Fixture();
      f.load('direct');
      expect(f.url, 'direct');
      expect(f.events, ['prepare', 'classify:direct', 'publish:direct']);
      f.fail();
      expect(f.events, hasLength(3));
      f.preview.dispose();
    },
  );

  test(
    'candidate order is retained and exhaustion invalidates before clearing URL',
    () async {
      final f = _Fixture();
      f.load('addon:a');
      expect(f.url, isNull);
      await flush();
      expect(f.url, 'a');
      f.fail();
      expect(f.url, 'b');
      f.fail();
      expect(f.url, isNull);
      expect(f.events.sublist(f.events.length - 2), [
        'invalidate:addon:a',
        'publish:null',
      ]);
      final count = f.events.length;
      f.fail();
      expect(f.events, hasLength(count));
      f.preview.dispose();
    },
  );

  test(
    'unknown current URL retires cache; missing channel skips invalidation',
    () async {
      for (final channel in ['addon:a', null]) {
        final f = _Fixture();
        f.channel = channel;
        f.load('addon:a');
        await flush();
        f.url = 'unknown';
        f.fail();
        expect(f.url, isNull);
        expect(
          f.events.where((event) => event.startsWith('invalidate:')),
          channel == null ? isEmpty : ['invalidate:addon:a'],
        );
        f.preview.dispose();
      }
    },
  );

  test('duplicate candidate URLs retain original indexOf behavior', () async {
    final f = _Fixture();
    f.resolve = (_) async => candidates(['a', 'a', 'b']);
    f.load('addon:a');
    await flush();
    f.fail();
    expect(f.url, 'a');
    f.fail();
    expect(f.url, 'a');
    expect(f.events.where((event) => event.startsWith('invalidate:')), isEmpty);
    f.preview.dispose();
  });

  test('empty resolution leaves prepared display unchanged', () async {
    final f = _Fixture();
    f.resolve = (_) async => [];
    f.load('addon:a');
    await flush();
    expect(f.url, isNull);
    expect(f.events, ['prepare', 'classify:addon:a', 'resolve:addon:a']);
    f.fail();
    expect(f.events, hasLength(3));
    f.preview.dispose();
  });

  test(
    'new channel rejects older completion and owns the fallback ladder',
    () async {
      final f = _Fixture();
      final old = Completer<List<StremioIptvCandidate>>();
      f.resolve = (key) => key == 'addon:old'
          ? old.future
          : Future.value(candidates(['new-a', 'new-b']));
      f.load('addon:old');
      f.load('addon:new');
      await flush();
      old.complete(candidates(['old-a', 'old-b']));
      await flush();
      expect(f.url, 'new-a');
      f.fail();
      expect(f.url, 'new-b');
      f.preview.dispose();
    },
  );

  for (final retire in ['invalidate', 'owner', 'unmount', 'dispose']) {
    test('$retire rejects an outstanding candidate result', () async {
      final f = _Fixture();
      final response = Completer<List<StremioIptvCandidate>>();
      f.resolve = (_) => response.future;
      f.load('addon:a');
      switch (retire) {
        case 'invalidate':
          f.preview.invalidateRequest();
        case 'owner':
          f.owner = false;
        case 'unmount':
          f.mounted = false;
        case 'dispose':
          f.preview.dispose();
      }
      response.complete(candidates(['late']));
      await flush();
      expect(f.url, isNull);
      expect(f.events.where((event) => event.startsWith('publish:')), isEmpty);
      f.preview.dispose();
    });
  }

  test(
    'request invalidation and candidate clearing preserve separate notification points',
    () async {
      final f = _Fixture();
      f.load('addon:a');
      await flush();
      f.preview.invalidateRequest();
      f.fail();
      expect(f.url, 'b');
      f.preview.clearCandidates();
      final before = f.events.length;
      f.fail();
      expect(f.events, hasLength(before));
      f.preview.dispose();
    },
  );

  test(
    'retired owner cannot invalidate another profile cache or start resolution',
    () async {
      final f = _Fixture();
      f.load('addon:a');
      await flush();
      f.url = 'b';
      f.owner = false;
      final before = f.events.length;
      f.fail();
      f.load('addon:new');
      expect(f.events, hasLength(before));
      f.preview.dispose();
    },
  );

  test(
    'synchronous retirement during preparation prevents direct publication',
    () {
      final f = _Fixture();
      f.load('direct', prepare: f.preview.invalidateRequest);
      expect(f.events, ['prepare']);
      expect(f.url, isNull);
      f.preview.dispose();
    },
  );
}
