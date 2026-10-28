import 'dart:async';
import 'package:debrify/features/home/application/home_hero_providers.dart';
import 'package:debrify/features/home/data/home_hero_live_repository.dart';
import 'package:debrify/features/home/presentation/spotlight_iptv_card_preview.dart';
import 'package:debrify/models/iptv_playlist.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_scope.dart';
import 'package:debrify/services/stremio_iptv_service.dart';
import 'package:debrify/widgets/hero_trailer_backdrop.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _Fixture {
  final requests = <String>[];
  final invalidations = <String>[];
  final replies = <Completer<List<StremioIptvCandidate>>>[];
  late final repository = HomeHeroLiveRepository(
    isAddonChannel: (key) => key.startsWith('addon:'),
    resolveCandidates: (key) {
      requests.add(key);
      final reply = Completer<List<StremioIptvCandidate>>();
      replies.add(reply);
      return reply.future;
    },
    invalidate: invalidations.add,
  );
  Widget host(IptvChannel channel, {double volume = 42}) => ProviderScope(
    overrides: [homeHeroLiveRepositoryProvider.overrideWithValue(repository)],
    child: MaterialApp(
      home: SpotlightIptvCardPreview(channel: channel, ambientVolume: volume),
    ),
  );
  void complete(int index, List<String> urls) => replies[index].complete([
    for (final url in urls) StremioIptvCandidate(url: url, label: url),
  ]);
}

IptvChannel channel(String key, {String type = 'live'}) => IptvChannel(
  name: key,
  url: key,
  contentType: type,
  httpHeaders: const {'Referer': 'fixture'},
);
HeroTrailerBackdrop backdrop(WidgetTester tester) =>
    tester.widget(find.byType(HeroTrailerBackdrop));

void main() {
  setUp(() {
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeLegacy();
  });
  tearDown(ProfileRuntime.debugReset);

  testWidgets('a retired card handed a new channel drops the previous stream', (
    tester,
  ) async {
    final f = _Fixture();
    final first = channel('https://fixture.invalid/first');
    await tester.pumpWidget(f.host(first));
    expect(backdrop(tester).videoUrl, first.url);
    ProfileRuntime.promoteLegacyToCommitted(
      ProfileScope(profileId: 'incoming', dataGeneration: 1, sessionEpoch: 1),
    );
    await tester.pumpWidget(f.host(channel('addon:second')));
    await tester.pump();
    expect(find.byType(HeroTrailerBackdrop), findsNothing);
    expect(f.requests, isEmpty);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'direct preview retains audio, headers, delay and element across volume updates',
    (tester) async {
      final f = _Fixture();
      final selected = channel('https://fixture.invalid/direct');
      await tester.pumpWidget(f.host(selected));
      final original = tester.element(find.byType(HeroTrailerBackdrop));
      expect(backdrop(tester).videoUrl, selected.url);
      expect(backdrop(tester).live, isTrue);
      expect(backdrop(tester).httpHeaders, selected.playbackHeaders);
      expect(backdrop(tester).startDelay, const Duration(milliseconds: 300));
      expect(backdrop(tester).firstFrameTimeout, isNull);
      expect(backdrop(tester).ambientVolume, 42);
      await tester.pumpWidget(f.host(selected, volume: 17));
      expect(tester.element(find.byType(HeroTrailerBackdrop)), same(original));
      expect(backdrop(tester).ambientVolume, 17);
      expect(f.requests, isEmpty);
      backdrop(tester).onPlaybackFailed!();
      await tester.pump();
      expect(backdrop(tester).videoUrl, selected.url);
      expect(f.invalidations, isEmpty);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'ordered fallback replaces the player and exhaustion invalidates the channel',
    (tester) async {
      final f = _Fixture();
      final selected = channel('addon:a');
      await tester.pumpWidget(f.host(selected));
      expect(f.requests, ['addon:a']);
      expect(find.byType(HeroTrailerBackdrop), findsNothing);
      f.complete(0, ['https://fixture.invalid/a', 'https://fixture.invalid/b']);
      await tester.pump();
      final first = tester.element(find.byType(HeroTrailerBackdrop));
      expect(backdrop(tester).firstFrameTimeout, const Duration(seconds: 12));
      expect(backdrop(tester).httpHeaders, selected.playbackHeaders);
      backdrop(tester).onPlaybackFailed!();
      await tester.pump();
      expect(backdrop(tester).videoUrl, 'https://fixture.invalid/b');
      expect(
        tester.element(find.byType(HeroTrailerBackdrop)),
        isNot(same(first)),
      );
      backdrop(tester).onPlaybackFailed!();
      await tester.pump();
      expect(find.byType(HeroTrailerBackdrop), findsNothing);
      expect(f.invalidations, ['addon:a']);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'channel object replacement rejects old work; series never resolves',
    (tester) async {
      final f = _Fixture();
      final first = channel('addon:a');
      await tester.pumpWidget(f.host(first));
      await tester.pumpWidget(f.host(first, volume: 12));
      expect(f.requests, ['addon:a']);
      await tester.pumpWidget(f.host(channel('addon:a')));
      expect(f.requests, ['addon:a', 'addon:a']);
      f.complete(1, ['https://fixture.invalid/current']);
      await tester.pump();
      f.complete(0, ['https://fixture.invalid/old']);
      await tester.pump();
      expect(backdrop(tester).videoUrl, 'https://fixture.invalid/current');
      await tester.pumpWidget(f.host(channel('addon:series', type: 'series')));
      expect(f.requests, hasLength(2));
      expect(find.byType(HeroTrailerBackdrop), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final retire in ['dispose', 'profile']) {
    testWidgets('$retire rejects pending card results', (tester) async {
      final f = _Fixture();
      await tester.pumpWidget(f.host(channel('addon:a')));
      if (retire == 'dispose') {
        await tester.pumpWidget(const SizedBox());
      } else {
        ProfileRuntime.promoteLegacyToCommitted(
          ProfileScope(
            profileId: 'incoming',
            dataGeneration: 1,
            sessionEpoch: 1,
          ),
        );
      }
      f.complete(0, ['https://fixture.invalid/late']);
      await tester.pump();
      expect(find.byType(HeroTrailerBackdrop), findsNothing);
      if (retire == 'profile') {
        await tester.pumpWidget(f.host(channel('addon:new')));
        expect(f.requests, ['addon:a']);
      }
      expect(f.invalidations, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
