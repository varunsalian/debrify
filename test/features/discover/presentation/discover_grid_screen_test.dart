import 'package:debrify/features/discover/application/discover_card_settings_dependencies.dart';
import 'package:debrify/services/main_page_bridge.dart';
import 'package:debrify/widgets/see_all/discover_card_settings_scope.dart';
import 'package:debrify/widgets/see_all/discover_browsing_input.dart';
import 'dart:async';
import 'package:debrify/features/discover/application/discover_source_dependencies.dart';
import 'package:debrify/features/discover/data/discover_source_repository.dart';
import 'package:debrify/features/discover/presentation/discover_stage_veils.dart';
import 'package:debrify/screens/search_screen.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/stremio_service.dart';
import 'package:debrify/services/storage_service.dart';
import 'package:debrify/widgets/see_all/discover_detail_rail.dart';
import 'package:debrify/widgets/see_all/discover_trailer_stage.dart';
import 'package:debrify/widgets/see_all/stremio_dropdown.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../theme/golden_harness.dart' show disableRuntimeFonts;

void main() {
  for (final layout in ['grid', 'stage']) {
    testWidgets(
      'Discover $layout resize clears stage effects without refetching sources',
      (tester) async {
        disableRuntimeFonts();
        ProfileRuntime.debugReset();
        ProfileRuntime.initializeLegacy();
        SharedPreferences.setMockInitialValues({
          'discover_layout': layout,
          'stremio_addons_v1': '[]',
        });
        StorageService.discoverLayoutCached = layout;
        StremioService.instance.invalidateCache();
        tester.view.physicalSize = const Size(1200, 700);
        tester.view.devicePixelRatio = 1;
        addTearDown(() {
          tester.view.reset();
          ProfileRuntime.debugReset();
          StorageService.discoverLayoutCached = 'stage';
        });
        var cardSettings = (
          showTypeTags: false,
          showRatings: true,
          showTitles: false,
        );
        var preferenceReads = 0;
        var addonReads = 0;
        final writes = <String>[];
        Future<void> drive(FutureOr<void> Function() action) async {
          await tester.runAsync(
            () => http.runWithClient(() async {
              await action();
              await Future<void>.delayed(const Duration(milliseconds: 150));
            }, () => MockClient((_) async => http.Response('{}', 404))),
          );
          await tester.pump(const Duration(milliseconds: 300));
        }

        await drive(
          () => tester.pumpWidget(
            ProviderScope(
              overrides: [
                discoverCardSettingsReaderProvider.overrideWith(
                  (ref, session) =>
                      () => cardSettings,
                ),
                discoverSourceRepositoryProvider.overrideWith(
                  (ref, session) => DiscoverSourceRepository(
                    readDefault: () async {
                      preferenceReads++;
                      return 'cw';
                    },
                    readLast: () async => 'cw',
                    readAddons: () async {
                      addonReads++;
                      return [];
                    },
                    writeLast: (value, current) async {
                      if (current()) writes.add(value);
                    },
                  ),
                ),
              ],
              child: const MaterialApp(
                home: SearchScreen(discoverMode: true, isTelevision: true),
              ),
            ),
          ),
        );
        expect(find.byType(DiscoverDetailRail), findsOneWidget);
        if (layout == 'grid') {
          expect(tester.getSize(find.byType(DiscoverDetailRail)).width, 450);
        } else {
          final identity = tester.widget<DiscoverDetailRail>(
            find.byType(DiscoverDetailRail),
          );
          expect(identity.layout, DiscoverDetailLayout.stage);
          expect(identity.stageMaxWidth, 560);
          expect(identity.stageBudget, 352);
          expect(identity.settleDelay, const Duration(milliseconds: 260));
        }
        DiscoverCardSettingsScope settings() =>
            tester.widget<DiscoverCardSettingsScope>(
              find.byType(DiscoverCardSettingsScope),
            );
        expect(settings().showTypeTags, isFalse);
        expect(settings().showRatings, isTrue);
        expect(settings().showTitles, isFalse);
        cardSettings = (
          showTypeTags: true,
          showRatings: false,
          showTitles: true,
        );
        MainPageBridge.discoverCardSettingsChanged!();
        await tester.pump();
        expect(settings().showTypeTags, isTrue);
        expect(settings().showRatings, isFalse);
        expect(settings().showTitles, isTrue);
        final stage = tester.widget<DiscoverTrailerStage>(
          find.byType(DiscoverTrailerStage),
        );
        final veils = tester.widget<DiscoverStageVeils>(
          find.byType(DiscoverStageVeils),
        );
        stage.showing!.value = true;
        await tester.pump(const Duration(milliseconds: 4999));
        expect(veils.theater.value, isFalse);
        await tester.pump(const Duration(milliseconds: 1));
        expect(veils.theater.value, isTrue);
        tester
            .widget<DiscoverBrowsingInput>(find.byType(DiscoverBrowsingInput))
            .onActivity();
        expect(veils.theater.value, isFalse);
        await tester.pump(const Duration(milliseconds: 4999));
        expect(veils.theater.value, isFalse);
        await tester.pump(const Duration(milliseconds: 1));
        expect(veils.theater.value, isTrue);
        stage.takeover!.value = .5;
        (veils.theater as ValueNotifier<bool>).value = true;
        await tester.pump();
        tester.view.physicalSize = const Size(700, 600);
        await drive(() => tester.pump());
        await tester.pump();
        expect(find.byType(DiscoverTrailerStage), findsNothing);
        expect(find.byType(DiscoverDetailRail), findsNothing);
        expect(stage.showing!.value, isFalse);
        expect(stage.takeover!.value, 0);
        expect(veils.theater.value, isFalse);
        tester.view.physicalSize = const Size(1200, 700);
        await drive(() => tester.pump());
        expect(find.byType(DiscoverDetailRail), findsOneWidget);
        final selector = tester.widget<StremioDropdown<String>>(
          find.byWidgetPredicate(
            (widget) =>
                widget is StremioDropdown<String> && widget.label == 'Source',
          ),
        );
        expect(selector.value, 'cw');
        expect(preferenceReads, 1);
        expect(addonReads, 1);
        expect(writes, ['cw']);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 5));
        expect(tester.takeException(), isNull);
      },
    );
  }
}
