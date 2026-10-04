import 'dart:io';
import 'dart:convert';

import 'package:debrify/screens/settings/iptv_settings_two_pane.dart';
import 'package:debrify/services/live_recording_service.dart';
import 'package:debrify/services/storage/startup_iptv_storage.dart';
import 'package:debrify/utils/platform_util.dart';
import 'package:debrify/widgets/tv_text_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../support/iptv_settings_fixture.dart';

void main() {
  testWidgets(
    'committed profile original fixture mounts and reads isolated owners',
    (tester) async {
      await iptvSettingsCase(tester, (f) async {
        await f.mount(tester);
        expect(f.member('loading'), isFalse);
        expect(f.member('recordingSectionVisible'), isTrue);
        expect(f.member('engineToggleVisible'), isFalse);
        expect(f.member('batteryExempt'), isNull);
        expect(f.catalogPaths.values.single, contains(f.ownerId));
        expect(f.requests, isEmpty);
        expect(tester.takeException(), isNull);
      });
    },
  );

  for (final size in [
    const Size(899, 800),
    const Size(900, 800),
    const Size(1200, 400),
  ]) {
    testWidgets('layout mounts from available space $size', (tester) async {
      await iptvSettingsCase(tester, (f) async {
        await f.mount(tester, size: size);
        final wide = size.width >= 900 && size.height > 420;
        expect(f.member('twoPaneActive'), wide);
        expect(
          find.byType(IptvSettingsTwoPane),
          wide ? findsOneWidget : findsNothing,
        );
        expect(f.member('phoneSection'), 'hub');
        expect(
          tester
              .widget<PopScope>(find.byWidgetPredicate((w) => w is PopScope))
              .canPop,
          isTrue,
        );
      });
    });
  }

  testWidgets(
    'widening synchronously resets section then rebuilds title and PopScope',
    (tester) async {
      await iptvSettingsCase(tester, (f) async {
        await f.mount(tester, size: const Size(800, 1000));
        await f.tap(tester, find.text('Sources'));
        await tester.pump();
        expect(f.member('phoneSection'), 'sources');
        expect(
          tester
              .widget<PopScope>(find.byWidgetPredicate((w) => w is PopScope))
              .canPop,
          isFalse,
        );
        final controller = f.member('tabController');
        final key = f.member('twoPaneKey');
        tester.view.physicalSize = const Size(1200, 800);
        await tester.pump();
        expect(f.member('phoneSection'), 'hub');
        expect(f.member('twoPaneActive'), isTrue);
        // Layout runs after the title and PopScope were built this frame.
        expect(
          tester
              .widget<PopScope>(find.byWidgetPredicate((w) => w is PopScope))
              .canPop,
          isFalse,
        );
        expect(
          find.descendant(
            of: find.byType(AppBar),
            matching: find.text('Sources'),
          ),
          findsOneWidget,
        );
        await tester.pump();
        expect(
          tester
              .widget<PopScope>(find.byWidgetPredicate((w) => w is PopScope))
              .canPop,
          isTrue,
        );
        expect(
          find.descendant(
            of: find.byType(AppBar),
            matching: find.text('IPTV Playlists'),
          ),
          findsOneWidget,
        );
        expect(identical(controller, f.member('tabController')), isTrue);
        expect(identical(key, f.member('twoPaneKey')), isTrue);
      });
    },
  );

  for (final entry in <String, String>{
    'Sources': 'sources',
    'Channel lists': 'lists',
    'Category order': 'categoryOrder',
    'Hidden categories': 'hidden',
    'Startup': 'startup',
    'Channel preview': 'channelPreview',
    'Continue watching': 'continueWatching',
    'Recording': 'recording',
  }.entries) {
    testWidgets(
      'phone hub ${entry.key} enters section and Back returns to hub',
      (tester) async {
        await iptvSettingsCase(tester, (f) async {
          await f.mount(tester, size: const Size(800, 1000));
          await tester.scrollUntilVisible(find.text(entry.key), 150);
          await tester.ensureVisible(find.text(entry.key));
          await tester.pump();
          await f.tap(tester, find.text(entry.key));
          await tester.pump();
          expect(f.member('phoneSection'), entry.value);
          expect(
            tester
                .widget<PopScope>(find.byWidgetPredicate((w) => w is PopScope))
                .canPop,
            isFalse,
          );
          await f.navigatorKey.currentState!.maybePop();
          await tester.pump();
          expect(f.member('phoneSection'), 'hub');
          expect(
            tester
                .widget<PopScope>(find.byWidgetPredicate((w) => w is PopScope))
                .canPop,
            isTrue,
          );
        }, sources: [iptvFixtureSource('z9')]);
      },
    );
  }

  for (final wide in [false, true]) {
    testWidgets(
      'openAddSource seeds actual add layout and retains controller/key $wide',
      (tester) async {
        await iptvSettingsCase(tester, (f) async {
          await f.mount(
            tester,
            size: wide ? const Size(1200, 800) : const Size(800, 1000),
            add: true,
          );
          expect(f.member('phoneSection'), wide ? 'hub' : 'sources');
          expect(
            find.widgetWithText(TvTextField, 'Playlist Name'),
            findsOneWidget,
          );
          final controller = f.member('tabController') as TabController;
          final key = f.member('twoPaneKey');
          controller.index = 2;
          await tester.pump();
          tester.view.physicalSize = wide
              ? const Size(800, 1000)
              : const Size(1200, 800);
          await tester.pump();
          await tester.pump();
          expect(identical(controller, f.member('tabController')), isTrue);
          expect(identical(key, f.member('twoPaneKey')), isTrue);
          expect(controller.index, 2);
        });
      },
    );
  }

  testWidgets(
    'wide back DOWN resolves the current key State at callback time',
    (tester) async {
      await iptvSettingsCase(tester, (f) async {
        await f.mount(tester);
        final key =
            f.member('twoPaneKey') as GlobalKey<IptvSettingsTwoPaneState>;
        final first = key.currentState;
        final back = f.member('backButtonFocusNode') as FocusNode;
        tester.view.physicalSize = const Size(800, 1000);
        await tester.pump();
        expect(key.currentState, isNull);
        tester.view.physicalSize = const Size(1200, 800);
        await tester.pump();
        expect(key.currentState, isNot(same(first)));
        back.requestFocus();
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pump();
        expect(FocusManager.instance.primaryFocus, isNot(same(back)));
        expect(FocusManager.instance.primaryFocus?.context, isNotNull);
      });
    },
  );

  for (final wide in [false, true]) {
    for (final add in [false, true]) {
      testWidgets('TV entry lands on attached destination wide=$wide add=$add', (
        tester,
      ) async {
        await iptvSettingsCase(tester, (f) async {
          PlatformUtil.debugSetAndroidTvCached(true);
          await f.mount(
            tester,
            size: wide ? const Size(1200, 800) : const Size(800, 1000),
            add: add,
          );
          // Explicitly manufacture the frame for the unchanged post-frame handoff.
          tester.binding.scheduleFrame();
          await tester.pump();
          final primary = FocusManager.instance.primaryFocus;
          expect(primary, isNotNull);
          expect(primary, isNot(isA<FocusScopeNode>()));
          expect(primary!.context, isNotNull);
          if (!wide) {
            expect(
              primary,
              same(f.member(add ? 'urlTabFocusNode' : 'hubSourcesFocusNode')),
            );
          }
          if (wide && add) expect(primary, same(f.member('urlTabFocusNode')));
        });
      });
    }
  }

  testWidgets('URL field arrows and tab keys keep explicit attached chains', (
    tester,
  ) async {
    await iptvSettingsCase(tester, (f) async {
      PlatformUtil.debugSetAndroidTvCached(true);
      await f.mount(tester, size: const Size(800, 1000), add: true);
      final fields = tester
          .widgetList<TvTextField>(find.byType(TvTextField))
          .toList();
      final name = fields.singleWhere(
        (field) => field.controller == f.member('nameController'),
      );
      final url = fields.singleWhere(
        (field) => field.controller == f.member('urlController'),
      );
      final epg = fields.singleWhere(
        (field) => field.controller == f.member('epgUrlController'),
      );
      name.onDownArrow!();
      await tester.pump();
      expect(
        FocusManager.instance.primaryFocus,
        same(f.member('urlInputFocusNode')),
      );
      url.onDownArrow!();
      await tester.pump();
      expect(
        FocusManager.instance.primaryFocus,
        same(f.member('epgUrlInputFocusNode')),
      );
      epg.onDownArrow!();
      await tester.pump();
      expect(
        FocusManager.instance.primaryFocus,
        same(f.member('addButtonFocusNode')),
      );
      (f.member('urlTabFocusNode') as FocusNode).requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(
        FocusManager.instance.primaryFocus,
        same(f.member('fileTabFocusNode')),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect((f.member('tabController') as TabController).index, 1);
      // The first transition lazily mounts the new page. A selected-tab
      // DOWN must manufacture a frame even when animateTo early-returns.
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      await tester.pump();
      expect(
        FocusManager.instance.primaryFocus,
        same(f.member('importFileButtonFocusNode')),
      );
      (f.member('xcTabFocusNode') as FocusNode).requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      await tester.pump();
      expect((f.member('tabController') as TabController).index, 2);
      expect(
        FocusManager.instance.primaryFocus,
        same(f.member('xcNameFocusNode')),
      );
      expect(
        tester
            .widgetList<ExcludeFocus>(find.byType(ExcludeFocus))
            .where((w) => w.excluding)
            .length,
        greaterThanOrEqualTo(2),
      );
    });
  });

  testWidgets(
    'resume recheck clears flag and uses actual non-Android recording result',
    (tester) async {
      await iptvSettingsCase(tester, (f) async {
        await f.mount(tester);
        await f.action(
          tester,
          () => f.member('requestBatteryExemption')() as Future<void>,
        );
        expect(f.member('recheckBatteryOnResume'), isTrue);
        f.member('lifecycle')(AppLifecycleState.paused);
        expect(f.member('recheckBatteryOnResume'), isTrue);
        f.member('lifecycle')(AppLifecycleState.resumed);
        expect(f.member('recheckBatteryOnResume'), isFalse);
        await f.frames(tester);
        expect(f.member('batteryExempt'), isFalse);
        expect(
          await LiveRecordingService.isIgnoringBatteryOptimizations(),
          isFalse,
        );
      });
    },
  );

  testWidgets('unmount while loadSettings is in flight publishes nothing', (
    tester,
  ) async {
    await iptvSettingsCase(tester, (f) async {
      await f.mount(tester, wait: false);
      final original = f.state;
      await tester.pumpWidget(const SizedBox.shrink());
      await f.frames(tester);
      expect(original.mounted, isFalse);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('desktop recording rows retain count and hide Android controls', (
    tester,
  ) async {
    await iptvSettingsCase(tester, (f) async {
      await f.mount(tester, size: const Size(800, 1000));
      f.member('enterPhoneSection')('recording');
      await tester.pump();
      expect(find.text('Background recording engine'), findsNothing);
      expect(find.textContaining('Battery optimization'), findsNothing);
      expect(find.text('Recordings'), findsOneWidget);
      expect(find.text('Simultaneous recordings (2)'), findsOneWidget);
      expect(f.member('scheduledCount'), 0);
      expect(f.member('maxConcurrent'), 2);
    });
  });

  testWidgets('startup labels preserve numbers and profile defaults', (
    tester,
  ) async {
    await iptvSettingsCase(tester, (f) async {
      await tester.runAsync(
        () => StartupIptvStorage.setStartupIptvChannel(
          'https://fixture.invalid/a.ts',
          name: 'Café',
          channelNumber: 42,
        ),
      );
      await f.mount(tester);
      expect(f.member('startupChannelLabel'), 'CH 42  ·  Café');
      expect(f.member('lastLiveChannelLabel'), 'unknown');
      expect(f.member('startupMode'), StartupIptvStorage.startupIptvModeLast);
      expect(f.member('appearanceVisible'), isTrue);
    });
  });

  for (final key in [
    LogicalKeyboardKey.enter,
    LogicalKeyboardKey.select,
    LogicalKeyboardKey.escape,
    LogicalKeyboardKey.goBack,
    LogicalKeyboardKey.browserBack,
  ]) {
    testWidgets(
      'TV AppBar back key ${key.keyLabel} returns narrow section to hub',
      (tester) async {
        await iptvSettingsCase(tester, (f) async {
          PlatformUtil.debugSetAndroidTvCached(true);
          await f.mount(tester, size: const Size(800, 1000));
          f.member('enterPhoneSection')('startup');
          await tester.pump();
          (f.member('backButtonFocusNode') as FocusNode).requestFocus();
          await tester.pump();
          if (key == LogicalKeyboardKey.browserBack ||
              key == LogicalKeyboardKey.goBack) {
            final node = f.member('backButtonFocusNode') as FocusNode;
            final input = tester.widget<Focus>(
              find.byWidgetPredicate((w) => w is Focus && w.focusNode == node),
            );
            expect(
              input.onKeyEvent!(
                node,
                KeyDownEvent(
                  physicalKey: PhysicalKeyboardKey.escape,
                  logicalKey: key,
                  timeStamp: Duration.zero,
                ),
              ),
              KeyEventResult.handled,
            );
          } else {
            await tester.sendKeyEvent(key);
          }
          await tester.pump();
          await tester.pump();
          expect(f.member('phoneSection'), 'hub');
          expect(find.widgetWithText(AppBar, 'IPTV Playlists'), findsOneWidget);
        });
      },
    );
  }
  for (final edit in [false, true]) {
    testWidgets(
      'TV ${edit ? 'edit' : 'import name'} dialog autofocus keeps the valid confirm button choice',
      (tester) async {
        await iptvSettingsCase(tester, (f) async {
          PlatformUtil.debugSetAndroidTvCached(true);
          await f.mount(tester, add: true);
          late Future<void> work;
          if (!edit) {
            f.picker.file(
              'input.m3u',
              Uint8List.fromList(utf8.encode(iptvFixtureM3u)),
            );
          }
          await tester.runAsync(() async {
            work = edit
                ? f.member('editPlaylist')(f.playlists.first) as Future<void>
                : f.member('importFromFile')() as Future<void>;
            f.outstanding.add(work);
          });
          await f.until(
            tester,
            () => find.byType(Dialog).evaluate().isNotEmpty,
          );
          await f.frames(tester);
          final label = edit ? 'Save' : 'Import';
          final focused = FocusManager.instance.primaryFocus!;
          expect((focused.context!.widget as Focus).autofocus, isTrue);
          expect(
            find.descendant(
              of: find.byWidget(focused.context!.widget),
              matching: find.text(label),
            ),
            findsOneWidget,
          );
          expect(FocusManager.instance.primaryFocus?.context, isNotNull);
          await f.tap(tester, find.text('Cancel'));
          await f.frames(tester);
          await tester.runAsync(() => work);
          expect(f.playlists.single.name, 'Source z9');
        }, sources: [iptvFixtureSource('z9')]);
      },
    );
  }
  for (final view in [
    'narrow_hub',
    'narrow_startup',
    'wide_two_pane',
    'edit_dialog',
  ]) {
    testWidgets('reachable pixel golden $view', (tester) async {
      final golden = File(
        'test/goldens/iptv_settings/${Platform.isLinux ? 'linux' : 'macos'}/$view.png',
      );
      const capture = bool.fromEnvironment(
        'IPTV_SETTINGS_CAPTURE_ORIGINAL_LINUX',
      );
      const strict = bool.fromEnvironment(
        'IPTV_SETTINGS_REQUIRE_ORIGINAL_LINUX',
      );
      if (Platform.isLinux && !capture && !strict && !golden.existsSync()) {
        // Authorized only before the separately verified Linux originals commit.
        debugPrint('Pending original IPTV settings Linux golden: $view');
        return;
      }
      if (Platform.isLinux && !capture) expect(golden.existsSync(), isTrue);
      await iptvSettingsCase(tester, (f) async {
        await f.mount(
          tester,
          size: view == 'narrow_hub' || view == 'narrow_startup'
              ? const Size(400, 800)
              : const Size(1200, 800),
        );
        if (view == 'narrow_startup') {
          f.member('enterPhoneSection')('startup');
          await tester.pump();
        }
        if (view == 'edit_dialog') {
          await tester.runAsync(() async {
            final work =
                f.member('editPlaylist')(f.playlists.first) as Future<void>;
            f.outstanding.add(work);
          });
          await f.frames(tester);
          expect(find.byType(Dialog), findsOneWidget);
        }
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pump();
        expect(f.requests, isEmpty);
        expect(tester.takeException(), isNull);
        try {
          await expectLater(
            find.byKey(const ValueKey('iptv-settings-canvas')),
            matchesGoldenFile(
              '../../../../goldens/iptv_settings/${Platform.isLinux ? 'linux' : 'macos'}/$view.png',
            ),
          );
        } finally {
          if (view == 'edit_dialog') {
            await f.tap(tester, find.text('Cancel'));
            await f.frames(tester);
          }
        }
      }, sources: [iptvFixtureSource('z9')]);
    });
  }
}
