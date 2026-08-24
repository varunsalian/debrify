import 'package:flutter_test/flutter_test.dart';
import 'package:debrify/screens/video_player/services/subtitle_settings_service.dart';

void main() {
  test('outline is a full 8-point ring on one circle', () {
    final shadows = SubtitleStyle.options[SubtitleStyle.defaultIndex].shadows!;
    expect(shadows, hasLength(8));
    // The cardinal directions are what the old 4-diagonal hack left uncovered
    // (notched glyph tops/sides read as a broken outline).
    final offsets = shadows.map((s) => s.offset).toList();
    expect(offsets, contains(const Offset(0, -1.5)));
    expect(offsets, contains(const Offset(0, 1.5)));
    expect(offsets, contains(const Offset(-1.5, 0)));
    expect(offsets, contains(const Offset(1.5, 0)));
    for (final shadow in shadows) {
      expect(shadow.offset.distance, closeTo(1.5, 0.01));
      expect(shadow.blurRadius, 0);
    }
  });

  test('edge ring scales with the drawn size, previews included', () {
    const data = SubtitleSettingsData(
      sizeIndex: 6, // Giant, 90px
      styleIndex: SubtitleStyle.defaultIndex, // Outline
      colorIndex: SubtitleColor.defaultIndex,
      bgIndex: SubtitleBackground.defaultIndex,
    );
    for (final shadow in data.buildTextStyle().shadows!) {
      expect(shadow.offset.distance, closeTo(1.5 * 90 / 42, 0.05));
    }
    // A preview drawing at half of Medium gets a proportionally halved ring.
    for (final shadow in data.buildTextStyle(fontSizePx: 21).shadows!) {
      expect(shadow.offset.distance, closeTo(0.75, 0.03));
    }
  });
}
