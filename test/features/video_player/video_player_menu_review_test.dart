import 'package:debrify/screens/video_player/widgets/player_menu_panel.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/identify_title_driver.dart';
import 'support/player_actions.dart';

void main() {
  testWidgets(
    'p13 quick menu keys plain filename by the manually identified episode',
    (t) async {
      final d = IdentifyTitleDriver(t);
      await d.setupIdentity();
      d.metas = [
        IdentifyTitleDriver.identityMeta('Chosen series', type: 'series'),
      ];
      try {
        // Launch.Title.2024.mkv has no parsed season or episode. The real
        // identity dialog supplies them, independently of launch coordinates.
        await d.mountIdentity();
        final pending = d.start(await d.menu());
        await d.found('Chosen series');
        await t.tap(find.text('Chosen series'));
        await d.episode('3', '4');
        final result = await d.f.finish(t, pending);
        expect(result?.episode, 4);
        expect(d.subtitlePaths, ['/subtitles/series/tt1200002:3:4.json']);
        d.panel.onClose();
        await d.f.advance(t, const Duration(milliseconds: 350));
        playerControls(t).onSpeed();
        await d.f.until(
          t,
          () => find.byType(PlayerMenuPanel).evaluate().isNotEmpty,
        );
        expect(d.panel.initialSection, PlayerMenuSection.speed);
        expect(d.panel.contentImdbId, 'tt1200002');
        expect(d.panel.contentSeason, 3);
        expect(d.panel.contentEpisode, 4);
        expect(
          d.panel.cachedAddonSlots,
          hasLength(1),
          reason: 'The quick menu must reuse the manual episode cache key',
        );
        expect(d.subtitlePaths, hasLength(1));
        expect(d.errors, isEmpty);
      } finally {
        await d.close();
      }
    },
  );
}
