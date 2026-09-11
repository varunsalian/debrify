import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart' as mk;
import 'package:debrify/screens/video_player/services/subtitle_track_utils.dart';

void main() {
  const english = mk.SubtitleTrack('1', 'English', 'eng');
  const spanish = mk.SubtitleTrack('2', 'Spanish', 'es');
  const untagged = mk.SubtitleTrack('3', null, null);
  const addon = mk.SubtitleTrack(
    '4',
    'English addon',
    'en',
    external: true,
    externalFilename: '/tmp/stremio_sub_test.srt',
  );

  test('keeps mpv selected embedded language ahead of English', () {
    expect(
      subtitleWithoutLanguagePreference([english, spanish], selectedId: '2'),
      spanish,
    );
  });

  test('auto placeholder falls back to real English track', () {
    expect(
      subtitleWithoutLanguagePreference([
        mk.SubtitleTrack.auto(),
        mk.SubtitleTrack.no(),
        spanish,
        english,
      ], selectedId: 'auto'),
      english,
    );
  });

  test('untagged embedded subtitles beat addon fallback', () {
    expect(
      subtitleWithoutLanguagePreference([addon, untagged], selectedId: 'no'),
      untagged,
    );
  });

  test('selected app-managed addon is not mistaken for embedded', () {
    expect(
      subtitleWithoutLanguagePreference([addon, english], selectedId: '4'),
      english,
    );
  });

  test('no real embedded tracks permits addon fallback', () {
    expect(
      subtitleWithoutLanguagePreference([
        mk.SubtitleTrack.auto(),
        mk.SubtitleTrack.no(),
        addon,
      ], selectedId: 'auto'),
      isNull,
    );
  });

  test('selected local sidecar is preserved', () {
    const sidecar = mk.SubtitleTrack(
      '5',
      'Local',
      'es',
      external: true,
      externalFilename: '/movies/title.es.srt',
    );
    expect(
      subtitleWithoutLanguagePreference([english, sidecar], selectedId: '5'),
      sidecar,
    );
  });

  test('bitmap track retains native rendering requirement', () {
    const bitmap = mk.SubtitleTrack('6', null, null, image: true);
    final selected = subtitleWithoutLanguagePreference([
      bitmap,
    ], selectedId: '6');
    expect(requiresNativeSubtitleRendering(selected!), isTrue);
  });
}
