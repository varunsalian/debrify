import 'package:debrify/features/discover/models/discover_card_settings.dart';
import 'package:debrify/features/discover/presentation/discover_content.dart';
import 'package:debrify/features/discover/presentation/discover_preview.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/widgets/see_all/discover_card_settings_scope.dart';
import 'package:debrify/widgets/see_all/discover_detail_rail.dart';
import 'package:debrify/widgets/see_all/discover_trailer_stage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../../theme/golden_harness.dart' show disableRuntimeFonts;

void main() {
  for (final scenario in [
    (size: const Size(719, 600), stage: false, preview: false),
    (size: const Size(900, 419), stage: false, preview: false),
    (size: const Size(720, 420), stage: false, preview: true),
    (size: const Size(720, 420), stage: true, preview: true),
  ]) {
    testWidgets(
      'canvas threshold $scenario preserves panel settings and reset timing',
      (tester) async {
        disableRuntimeFonts();
        tester.view.physicalSize = scenario.size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final preview = DiscoverPreview(isCurrent: () => true);
        final focused = ValueNotifier<StremioMeta?>(null);
        if (!scenario.preview) {
          preview.takeover.value = .5;
          preview.showing.value = true;
          preview.theater.value = true;
          preview.loading.value = true;
          preview.volume.value = .3;
        }
        double? takeoverDuringBuild;
        DiscoverCardSettingsScope? settings;
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => buildDiscoverContent(
                context,
                sourcePanel: Builder(
                  builder: (context) {
                    takeoverDuringBuild = preview.takeover.value;
                    settings = DiscoverCardSettingsScope.maybeOf(context);
                    return const Center(child: Text('Source panel'));
                  },
                ),
                cardSettings: (
                  showTypeTags: false,
                  showRatings: true,
                  showTitles: false,
                ),
                showPreview: true,
                stage: scenario.stage,
                focused: focused,
                preview: preview,
                isCurrent: () => true,
                loadingIndicator: (_) => const SizedBox(),
                ambientIndicator: (_) => const SizedBox(),
              ),
            ),
          ),
        );
        expect(find.text('Source panel'), findsOneWidget);
        expect(settings!.showTypeTags, isFalse);
        expect(settings!.showRatings, isTrue);
        expect(settings!.showTitles, isFalse);
        expect(
          find.byType(DiscoverTrailerStage),
          scenario.preview ? findsOneWidget : findsNothing,
        );
        if (scenario.preview) {
          final rail = tester.widget<DiscoverDetailRail>(
            find.byType(DiscoverDetailRail),
          );
          expect(
            rail.layout,
            scenario.stage
                ? DiscoverDetailLayout.stage
                : DiscoverDetailLayout.rail,
          );
        } else {
          expect(takeoverDuringBuild, .5);
          expect(preview.takeover.value, 0);
          expect(preview.showing.value, isFalse);
          expect(preview.theater.value, isFalse);
          expect(preview.loading.value, isTrue);
          expect(preview.volume.value, .3);
        }
        await tester.pumpWidget(const SizedBox());
        preview.dispose();
        focused.dispose();
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final bypass in [true, false]) {
    testWidgets(
      bypass
          ? 'flat source bypass does not reset borrowed preview'
          : 'retired host rejects a scheduled compact reset',
      (tester) async {
        tester.view.physicalSize = const Size(700, 400);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        var current = true;
        final preview = DiscoverPreview(isCurrent: () => current);
        final focused = ValueNotifier<StremioMeta?>(null);
        preview.takeover.value = .5;
        preview.showing.value = true;
        preview.theater.value = true;
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => buildDiscoverContent(
                context,
                sourcePanel: Builder(
                  builder: (_) {
                    if (!bypass) current = false;
                    return const Text('Flat panel');
                  },
                ),
                cardSettings: defaultDiscoverCardSettings,
                showPreview: !bypass,
                stage: true,
                focused: focused,
                preview: preview,
                isCurrent: () => current,
                loadingIndicator: (_) => const SizedBox(),
                ambientIndicator: (_) => const SizedBox(),
              ),
            ),
          ),
        );
        expect(find.byType(DiscoverTrailerStage), findsNothing);
        expect(find.text('Flat panel'), findsOneWidget);
        expect(preview.takeover.value, .5);
        expect(preview.showing.value, isTrue);
        expect(preview.theater.value, isTrue);
        await tester.pumpWidget(const SizedBox());
        preview.takeover.value =
            .2; // The composition never owns these signals.
        expect(preview.takeover.value, .2);
        preview.dispose();
        focused.dispose();
        expect(tester.takeException(), isNull);
      },
    );
  }
}
