// Which sources title search may query: defaults, round trips and storage shape.
import 'package:debrify/services/profiles/profile_preferences.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/source_search_preferences.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeLegacy();
    SharedPreferences.setMockInitialValues({});
  });
  tearDown(ProfileRuntime.debugReset);

  test('an untouched profile searches everything', () async {
    final choices = await SourceSearchPreferences.read();
    expect(choices, const SourceSearchChoices());
    expect(choices.iptv, isTrue);
    expect(choices.mediaServers, isTrue);
    expect(choices.excludedPlaylistIds, isEmpty);
    expect(choices.includesPlaylist('any'), isTrue);
  });

  test('choices round-trip and exclusions are stored sorted', () async {
    const choices = SourceSearchChoices(
      excludedPlaylistIds: {'b', 'a'},
      mediaServers: false,
    );
    await SourceSearchPreferences.write(choices);

    expect(await SourceSearchPreferences.read(), choices);
    final prefs = await ProfilePreferences.instance();
    expect(prefs.getStringList(SourceSearchPreferences.excludedKey), [
      'a',
      'b',
    ]);
    expect(prefs.getBool(SourceSearchPreferences.mediaServersKey), isFalse);
  });

  test('an empty exclusion set removes its key', () async {
    await SourceSearchPreferences.write(
      const SourceSearchChoices(excludedPlaylistIds: {'a'}),
    );
    await SourceSearchPreferences.write(const SourceSearchChoices());

    final prefs = await ProfilePreferences.instance();
    expect(prefs.getStringList(SourceSearchPreferences.excludedKey), isNull);
  });

  test('readOrDefault falls back to the defaults when storage fails', () async {
    ProfileRuntime.debugReset();
    expect(
      await SourceSearchPreferences.readOrDefault(),
      const SourceSearchChoices(),
    );
  });

  test('readOrDefault reads stored choices', () async {
    await SourceSearchPreferences.write(const SourceSearchChoices(iptv: false));
    expect(
      await SourceSearchPreferences.readOrDefault(),
      const SourceSearchChoices(iptv: false),
    );
  });

  test('IPTV off leaves every playlist out', () {
    const choices = SourceSearchChoices(iptv: false);
    expect(choices.includesPlaylist('a'), isFalse);
  });

  test('withPlaylist excludes and includes again', () {
    const base = SourceSearchChoices();
    final out = base.withPlaylist('a', included: false);
    expect(out.includesPlaylist('a'), isFalse);
    expect(out.includesPlaylist('b'), isTrue);
    expect(out.withPlaylist('a', included: true), base);
    expect(base.excludedPlaylistIds, isEmpty, reason: 'copies, never mutates');
  });

  test('copyWith keeps the exclusions and equality compares contents', () {
    const base = SourceSearchChoices(excludedPlaylistIds: {'x'});
    final changed = base.copyWith(iptv: false, mediaServers: false);
    expect(changed.iptv, isFalse);
    expect(changed.mediaServers, isFalse);
    expect(changed.excludedPlaylistIds, {'x'});
    expect(
      const SourceSearchChoices(excludedPlaylistIds: {'x', 'y'}),
      SourceSearchChoices(excludedPlaylistIds: {'y', 'x'}),
    );
    expect(
      const SourceSearchChoices(excludedPlaylistIds: {'x'}).hashCode,
      SourceSearchChoices(excludedPlaylistIds: {'x'}).hashCode,
    );
  });
}
