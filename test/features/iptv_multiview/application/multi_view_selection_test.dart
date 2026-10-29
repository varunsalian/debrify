// Multi-view selection: adding, removing, the sound tile, the per-platform
// tile limit, the grid shape and profile isolation.
import 'package:debrify/features/iptv_multiview/application/multi_view_selection_notifier.dart';
import 'package:debrify/features/iptv_multiview/models/multi_view_selection.dart';
import 'package:debrify/models/iptv_playlist.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

IptvChannel _ch(String id) =>
    IptvChannel(name: 'Channel $id', url: 'https://tv.test/$id.ts');

void main() {
  late Object? owner;
  late ProviderContainer container;
  MultiViewSelectionNotifier notifier() =>
      container.read(multiViewSelectionProvider.notifier);
  MultiViewSelection state() => container.read(multiViewSelectionProvider);
  List<String> names() => [
    for (final c in notifier().current().channels) c.name,
  ];

  setUp(() {
    owner = 'profile-a';
    container = ProviderContainer(
      overrides: [
        multiViewOwnerProvider.overrideWithValue(() => owner),
        multiViewMaxTilesProvider.overrideWithValue(3),
      ],
    );
    addTearDown(container.dispose);
  });

  test('starts empty', () {
    expect(state().isEmpty, isTrue);
    expect(state().audioIndex, 0);
  });

  test('adds in order, refuses duplicates by url and stops when full', () {
    expect(notifier().add(_ch('1')), MultiViewAddResult.added);
    expect(
      notifier().add(IptvChannel(name: 'Renamed', url: 'https://tv.test/1.ts')),
      MultiViewAddResult.duplicate,
    );
    expect(notifier().add(_ch('2')), MultiViewAddResult.added);
    expect(notifier().add(_ch('3')), MultiViewAddResult.added);
    expect(notifier().add(_ch('4')), MultiViewAddResult.full);
    expect(names(), ['Channel 1', 'Channel 2', 'Channel 3']);
    expect(notifier().contains(_ch('2')), isTrue);
    expect(notifier().contains(_ch('4')), isFalse);
    expect(() => state().channels.add(_ch('5')), throwsUnsupportedError);
  });

  test('the sound follows its tile when an earlier tile leaves', () {
    for (final id in ['1', '2', '3']) {
      notifier().add(_ch(id));
    }
    notifier().setAudio(2);
    notifier().remove(0);
    expect(names(), ['Channel 2', 'Channel 3']);
    expect(state().audioIndex, 1);
  });

  test('removing the sound tile moves the sound to the first tile', () {
    for (final id in ['1', '2', '3']) {
      notifier().add(_ch(id));
    }
    notifier().setAudio(1);
    notifier().remove(1);
    expect(state().audioIndex, 0);
    notifier().remove(7);
    notifier().setAudio(9);
    expect(names(), ['Channel 1', 'Channel 3']);
    expect(state().audioIndex, 0);
  });

  test('clear empties the selection', () {
    notifier().add(_ch('1'));
    notifier().clear();
    expect(state().isEmpty, isTrue);
  });

  test('another profile never sees or extends this selection', () {
    notifier().add(_ch('1'));
    notifier().add(_ch('2'));
    owner = 'profile-b';
    expect(notifier().current().isEmpty, isTrue);
    expect(notifier().add(_ch('3')), MultiViewAddResult.added);
    expect(names(), ['Channel 3']);
    expect(state().owner, 'profile-b');
  });

  test('tile limits per platform', () {
    expect(multiViewMaxTiles(MultiViewPlatform.androidTv), 4);
    expect(multiViewMaxTiles(MultiViewPlatform.android), 4);
    expect(multiViewMaxTiles(MultiViewPlatform.desktop), 4);
    expect(multiViewMaxTiles(MultiViewPlatform.ios), 2);
    expect(multiViewMaxTiles(MultiViewPlatform.tvos), 0);
  });

  test('grid shapes', () {
    expect(multiViewGrid(0), (rows: 0, cols: 0));
    expect(multiViewGrid(1), (rows: 1, cols: 1));
    expect(multiViewGrid(2), (rows: 1, cols: 2));
    expect(multiViewGrid(3), (rows: 2, cols: 2));
    expect(multiViewGrid(4), (rows: 2, cols: 2));
  });
}
