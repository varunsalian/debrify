import 'package:flutter/material.dart';

import 'package:debrify/screens/settings/widgets/settings_widgets.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:debrify/widgets/cloud/cloud_segmented_tabs.dart';
import 'package:debrify/widgets/desktop_sidebar_nav.dart';

/// REAL widgets from each themed family, composed with fixture data.
///
/// Exists because the boundary demo did not: it renders synthetic containers,
/// so every golden could pass while a shipped screen was black-on-black under
/// a light theme — which is exactly what a review found after three waves.
/// These are the actual `SettingsTile`, `CloudSegmentedTabs`,
/// `DesktopSidebarNav` and so on, so a token that reads badly here reads badly
/// in the app.
///
/// Deliberately limited to widgets constructible from plain props. Screens
/// that need services, a database or platform channels are out of reach for a
/// widget test; the gap they leave is recorded in the rollout plan rather than
/// papered over with a mock that proves nothing.
/// Marks the gallery's own band captions so the contrast audit skips them.
const Key kGalleryLabelKey = Key('gallery-band-label');

class SurfaceGallery extends StatelessWidget {
  const SurfaceGallery({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    return Scaffold(
      backgroundColor: app.shell.ink,
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Band(
              label: 'settings',
              background: app.settings.bg,
              child: Column(
                children: [
                  const SettingsPageHeader(
                    icon: Icons.tune_rounded,
                    title: 'Playback',
                    subtitle: 'How videos start and what plays them',
                  ),
                  const SizedBox(height: 12),
                  SettingsSection(
                    title: 'General',
                    children: [
                      SettingsTile(
                        icon: Icons.play_circle_outline_rounded,
                        title: 'External player',
                        subtitle: 'Choose what opens a stream',
                        onTap: () async {},
                      ),
                      SettingsTile(
                        icon: Icons.delete_outline_rounded,
                        title: 'Clear downloads',
                        subtitle: 'Remove every finished file',
                        destructive: true,
                        onTap: () async {},
                      ),
                    ],
                  ),
                ],
              ),
            ),
            _Band(
              label: 'cloud',
              background: app.cloud.bg,
              child: CloudSegmentedTabs<int>(
                segments: const [
                  CloudSegment(0, 'Torrents', Icons.download_rounded),
                  CloudSegment(1, 'Files', Icons.folder_rounded),
                ],
                selected: 0,
                onSelected: (_) {},
              ),
            ),
            _Band(
              label: 'cloud · dialog',
              background: app.cloud.dialogSurface,
              child: Builder(
                builder: (context) => Text(
                  'Add a link',
                  // Inherited ink — the exact shape that broke: the surface
                  // was pinned dark while this followed the theme.
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ),
            _Band(
              label: 'sheet',
              background: app.sheetSurface,
              child: Builder(
                builder: (context) => Text(
                  'Remove from Continue Watching',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            ),
            _Band(
              label: 'nav · sheet',
              background: app.shell.navSheetBg,
              child: Builder(
                builder: (context) => Text(
                  'Edit Navigation',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ),
            _Band(
              label: 'home · poster placeholder',
              background: app.home.posterPlaceholder,
              child: Text(
                'A Title With No Artwork',
                style: TextStyle(color: app.core.tx, fontSize: 13),
              ),
            ),
            _Band(
              label: 'home · action sheet',
              background: app.home.sheetBg,
              child: Builder(
                builder: (context) => Text(
                  'Play in external player',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            ),
            _Band(
              label: 'seeAll · list',
              background: app.seeAll.listBg,
              child: Builder(
                builder: (context) => Text(
                  'No lists to show',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            ),
            _Band(
              label: 'seeAll · card',
              background: app.seeAll.card,
              child: Text(
                'Cinemeta',
                style: TextStyle(color: app.core.tx, fontSize: 14),
              ),
            ),
            _Band(
              label: 'calendar · row',
              background: app.calendar.row,
              child: Text(
                'S02 · E04 — The Long Night',
                style: TextStyle(color: app.fade(app.core.tx, 0.68)),
              ),
            ),
            _Band(
              label: 'calendar · time chips',
              background: app.calendar.row,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Modelled as the screen actually paints it: the tone is
                  // text on a 14%-tint chip of ITSELF, over the row — not
                  // bare on the card. Getting this wrong would audit a
                  // composite the app never draws.
                  for (final tone in app.calendar.accentPalette)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: ColoredBox(
                        color: Color.alphaBlend(
                          tone.withValues(alpha: 0.14),
                          app.calendar.row,
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(3),
                          child: Text('20:00',
                              style: TextStyle(color: tone, fontSize: 10)),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            // Ink ON a filled accent swatch — the `inkOn` role.
            _Band(
              label: 'on-accent',
              background: app.settings.accent,
              child: Text(
                'Save',
                style: TextStyle(
                  color: app.inkOn(app.settings.accent),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            // Dark glass over artwork — ink must NOT follow page text.
            _Band(
              label: 'on-glass',
              background: const Color(0xFF000000),
              child: Text('S02E04', style: TextStyle(color: app.onGlass)),
            ),
            SizedBox(
              height: 220,
              child: Row(
                children: [
                  DesktopSidebarNav(
                    currentIndex: 1,
                    entries: const [
                      DesktopNavEntry(Icons.home_rounded, 'Home', 'Main'),
                      DesktopNavEntry(Icons.explore_rounded, 'Discover', 'Main'),
                      DesktopNavEntry(Icons.settings_rounded, 'Settings', 'Setup'),
                    ],
                    onTap: (_) {},
                  ),
                  Expanded(
                    child: ColoredBox(
                      color: app.shell.ink,
                      child: Center(
                        child: Text('content',
                            style: TextStyle(color: app.core.tx)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One labelled strip: a real token background with real content on it.
///
/// The label rides OUTSIDE the coloured area so it can never be mistaken for
/// content under audit.
class _Band extends StatelessWidget {
  final String label;
  final Color background;
  final Widget child;

  const _Band({
    required this.label,
    required this.background,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ExcludeSemantics(
            child: SizedBox(
              height: 12,
              child: Text(
                label,
                // Keyed so the contrast audit can skip it: this caption is
                // test scaffolding sitting on the page ground, not app
                // content, and auditing it just reports on the harness.
                key: kGalleryLabelKey,
                style: const TextStyle(fontSize: 8, color: Color(0xFF808080)),
              ),
            ),
          ),
          ColoredBox(
            color: background,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: child,
            ),
          ),
        ],
      ),
    );
  }
}
