import 'dart:async';
import 'package:debrify/features/discover/application/discover_layout_dependencies.dart';
import 'package:debrify/features/discover/application/discover_source_dependencies.dart';
import 'package:debrify/features/discover/data/discover_layout_preferences.dart';
import 'package:debrify/features/discover/data/discover_source_repository.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/screens/search_screen.dart';
import 'package:debrify/services/main_page_bridge.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/stremio_service.dart';
import 'package:debrify/widgets/see_all/discover_detail_rail.dart';
import 'package:debrify/widgets/see_all/discover_trailer_stage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../theme/golden_harness.dart' show disableRuntimeFonts;

void main() {
  testWidgets(
    'Discover uses scoped warm layout and resets preview before refresh',
    (tester) async {
      disableRuntimeFonts();
      ProfileRuntime.debugReset();
      ProfileRuntime.initializeLegacy();
      SharedPreferences.setMockInitialValues({'stremio_addons_v1': '[]'});
      StremioService.instance.invalidateCache();
      tester.view.physicalSize = const Size(1200, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.reset();
        ProfileRuntime.debugReset();
      });
      final reads = <Completer<String>>[];
      final remembered = <String>[];
      DiscoverTrailerStage? outgoing;
      Future<void> drive(FutureOr<void> Function() action) async {
        await tester.runAsync(
          () => http.runWithClient(() async {
            await action();
            await Future<void>.delayed(const Duration(milliseconds: 100));
          }, () => MockClient((_) async => http.Response('{}', 404))),
        );
        await tester.pump(const Duration(milliseconds: 300));
      }

      await drive(
        () => tester.pumpWidget(
          ProviderScope(
            overrides: [
              discoverSourceRepositoryProvider.overrideWith(
                (ref, session) => DiscoverSourceRepository(
                  readDefault: () async => 'cw',
                  readLast: () async => 'cw',
                  readAddons: () async => [],
                  writeLast: (_, _) async {},
                ),
              ),
              discoverLayoutPreferencesProvider.overrideWith(
                (ref, session) => DiscoverLayoutPreferences(
                  readCached: () => 'grid',
                  readSaved: (_) {
                    if (outgoing case final stage?) {
                      expect(stage.loading.value, isFalse);
                      expect(stage.meta.value, isNull);
                      expect(stage.showing!.value, isFalse);
                      expect(stage.takeover!.value, 0);
                    }
                    final result = Completer<String>();
                    reads.add(result);
                    return result.future;
                  },
                  remember: remembered.add,
                ),
              ),
            ],
            child: const MaterialApp(
              home: SearchScreen(discoverMode: true, isTelevision: true),
            ),
          ),
        ),
      );
      expect(reads, hasLength(1));
      expect(tester.getSize(find.byType(DiscoverDetailRail)).width, 450);
      outgoing = tester.widget<DiscoverTrailerStage>(
        find.byType(DiscoverTrailerStage),
      );
      outgoing.loading.value = true;
      (outgoing.meta as ValueNotifier<StremioMeta?>).value = const StremioMeta(
        id: 'a',
        type: 'movie',
        name: 'A',
      );
      outgoing.showing!.value = true;
      outgoing.takeover!.value = .5;
      MainPageBridge.discoverLayoutChanged!();
      expect(reads, hasLength(2));
      await drive(() => reads.last.complete('stage'));
      expect(
        tester
            .widget<DiscoverDetailRail>(find.byType(DiscoverDetailRail))
            .layout,
        DiscoverDetailLayout.stage,
      );
      await drive(() => reads.first.complete('grid'));
      expect(
        tester
            .widget<DiscoverDetailRail>(find.byType(DiscoverDetailRail))
            .layout,
        DiscoverDetailLayout.stage,
      );
      expect(remembered, ['stage']);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 5));
      expect(tester.takeException(), isNull);
    },
  );
}
