import 'package:debrify/utils/platform_util.dart';
import 'package:debrify/widgets/detail/detail_episode_cells.dart';
import 'package:debrify/widgets/detail/theme/detail_theme.dart';
import 'package:debrify/widgets/detail/theme/detail_themes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('focused episode hint follows live detail-theme colors', (
    tester,
  ) async {
    PlatformUtil.debugSetAndroidTvCached(true);
    addTearDown(() => PlatformUtil.debugSetAndroidTvCached(null));
    final node = FocusNode();
    addTearDown(node.dispose);
    for (final theme in [DetailThemes.phosphor, DetailThemes.broadsheet]) {
      await tester.pumpWidget(
        MaterialApp(
          home: DetailThemeScope(
            theme: theme,
            child: Scaffold(
              body: DetailHoldHint(
                child: DetailEpisodeInteraction(
                  focusNode: node,
                  gesture: DetailOptionsGesture.holdOk,
                  onPlay: () {},
                  onOptions: () {},
                  builder: (_, focused) =>
                      const SizedBox(width: 100, height: 100),
                ),
              ),
            ),
          ),
        ),
      );
      node.requestFocus();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      final label = find.text('Long press for more actions');
      expect(label, findsOneWidget);
      expect(tester.widget<Text>(label).style!.color, theme.tx);
      expect(
        tester.widget<Icon>(find.byIcon(Icons.more_horiz_rounded)).color,
        theme.tx,
      );
      final pill = tester.widget<Container>(
        find.ancestor(of: label, matching: find.byType(Container)).first,
      );
      final decoration = pill.decoration! as BoxDecoration;
      expect((decoration.border! as Border).top.color, theme.hair);
      expect(decoration.color, theme.ground.withValues(alpha: 0.92));
      // Artwork can be bright or dark behind the translucent hint. The active
      // theme must keep its small text readable over either extreme.
      for (final artwork in [Colors.black, Colors.white]) {
        final background = Color.alphaBlend(decoration.color!, artwork);
        final ink = Color.alphaBlend(theme.tx, background).computeLuminance();
        final ground = background.computeLuminance();
        final contrast = ink > ground
            ? (ink + 0.05) / (ground + 0.05)
            : (ground + 0.05) / (ink + 0.05);
        expect(contrast, greaterThanOrEqualTo(4.5));
      }
      final opacity = tester.widget<AnimatedOpacity>(
        find.ancestor(of: label, matching: find.byType(AnimatedOpacity)).first,
      );
      expect(opacity.opacity, 1);
      expect(tester.takeException(), isNull);
    }
    await tester.pumpWidget(const SizedBox());
  });
}
