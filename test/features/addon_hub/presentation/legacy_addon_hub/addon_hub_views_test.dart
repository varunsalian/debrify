import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/services/main_page_bridge.dart';
import 'package:debrify/services/stremio_marketplace_service.dart';
import 'package:debrify/services/stremio_service.dart';
import 'package:debrify/widgets/see_all/stremio_dropdown.dart';
import 'package:debrify/widgets/tv_text_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;

import '../../../../support/addon_hub_fixture.dart';

const requireLinux = bool.fromEnvironment(
  'ADDON_HUB_REQUIRE_ORIGINAL_LINUX',
  defaultValue: true,
);
const captureLinux = bool.fromEnvironment(
  'ADDON_HUB_CAPTURE_ORIGINAL_LINUX',
  defaultValue: false,
);

void main() {
  testWidgets(
    'mount only loads installed inventory and closes owned engine client',
    (t) async {
      await hubCase(t, (f) async {
        await f.mount(t);
        expect(f.requests, isEmpty);
        expect(
          f.clients,
          hasLength(3),
        ); // two convenience warm fetches, one owned client
        expect(f.clients.take(2).every((c) => c.closed), isTrue);
        expect(f.clients.last.closed, isFalse);
        expect(f.member('enginesLoadedOnce'), isFalse);
        expect(f.member('marketLoadedFor'), isNull);
        final s = f.key.currentState!;
        final before = f.access;
        expect(f.ids('installed'), ['z9', 'com.linvo.cinemeta', 'a2']);
        expect(before['onAddonsChanged'], f.member('onAddonsChanged'));
        expect(before['onEnginesChanged'], f.member('onEnginesChanged'));
        expect(before['tvFocusHandler'], f.member('tvFocusHandler'));
        await t.pumpWidget(const SizedBox.shrink());
        expect(s.mounted, isFalse);
        expect(f.clients.last.closed, isTrue);
        final prefs = await SharedPreferences.getInstance();
        final revision = before['installedLoadRevision'];
        await prefs.setString('stremio_metadata_provider_v1', 'automatic');
        expect(revision, 1);
      });
    },
  );
  testWidgets('later tab 7 handler survives hub disposal', (t) async {
    await hubCase(t, (f) async {
      await f.mount(t);
      var sentinel = 0;
      void handler() => sentinel++;
      MainPageBridge.registerTvContentFocusHandler(7, handler);
      await t.pumpWidget(const SizedBox.shrink());
      MainPageBridge.requestTvContentFocus();
      expect(sentinel, 1);
      MainPageBridge.unregisterTvContentFocusHandler(7, handler);
    });
  });
  testWidgets(
    'installed collection displayed in stored order and snapshots fresh',
    (t) async {
      await hubCase(t, (f) async {
        await f.mount(t);
        final ys = [
          'Zulu',
          'Cinemeta',
          'Alpha',
        ].map((name) => t.getTopLeft(find.text(name)).dy).toList();
        expect(ys[0], lessThan(ys[1]));
        expect(ys[1], lessThan(ys[2]));
        final snapshot = f.member('installed') as List<StremioAddon>;
        snapshot.clear();
        expect(f.ids('installed'), ['z9', 'com.linvo.cinemeta', 'a2']);
        expect((await f.saved(t)).map((a) => a.id), [
          'z9',
          'com.linvo.cinemeta',
          'a2',
        ]);
        expect(f.requests, isEmpty);
      });
    },
  );
  for (final preference in [null, 'automatic', 'missing', 'z9']) {
    testWidgets(
      'metadata provider order labels and selected value $preference',
      (t) async {
        await hubCase(t, (f) async {
          final selected = preference == 'z9'
              ? StremioService.metadataProviderValue(f.installed.first)
              : preference;
          if (selected != null) {
            await StremioService.instance.setMetadataProviderPreference(
              selected,
            );
          }
          await f.mount(t);
          final dd = t.widget<StremioDropdown<String>>(
            find.byWidgetPredicate(
              (w) =>
                  w is StremioDropdown<String> &&
                  w.focusNode == f.member('metadataFocus'),
            ),
          );
          expect(dd.options.map((o) => o.label), [
            'Cinemeta · Recommended',
            'Zulu',
            'Alpha',
            'Automatic',
          ]);
          expect(
            dd.value,
            preference == 'automatic'
                ? 'automatic'
                : preference == 'z9'
                ? selected
                : StremioService.metadataProviderValue(f.installed[1]),
          );
          expect(f.requests, isEmpty);
        });
      },
    );
  }
  testWidgets(
    'no Cinemeta and disabled or missing base meta providers choose Automatic',
    (t) async {
      await hubCase(t, (f) async {
        final list = [
          hubAddon('z9', 'Zulu', resources: const ['stream']),
          hubAddon('a2', 'Alpha', enabled: false),
        ];
        SharedPreferences.setMockInitialValues({
          'stremio_addons_v1':
              '[${list.map((a) => a.toJson()).map((a) => const JsonEncoder().convert(a)).join(',')}]',
        });
        StremioService.instance.invalidateCache();
        await f.mount(t);
        final dd = t.widget<StremioDropdown<String>>(
          find.byWidgetPredicate(
            (w) =>
                w is StremioDropdown<String> &&
                w.focusNode == f.member('metadataFocus'),
          ),
        );
        expect(dd.options.map((o) => o.label), ['Automatic']);
        expect(dd.value, 'automatic');
      });
    },
  );
  for (final width in [
    375.0,
    479.0,
    480.0,
    527.0,
    528.0,
    579.0,
    580.0,
    581.0,
    582.0,
    1000.0,
  ]) {
    testWidgets('responsive original constraints at viewport $width', (
      t,
    ) async {
      await hubCase(t, (f) async {
        await f.mount(t, width: width);
        final manage = t.widget<StremioDropdown<dynamic>>(
          find.byWidgetPredicate(
            (w) => w is StremioDropdown && w.focusNode == f.member('kindFocus'),
          ),
        );
        expect(manage.label, width < 480 ? isNull : 'Manage');
        final meta = find.text('Metadata provider');
        final layout = find
            .ancestor(of: meta, matching: find.byType(LayoutBuilder))
            .first;
        expect(t.getSize(layout).width, width - 82);
        final children = <Widget>[];
        t.element(layout).visitChildElements((e) => children.add(e.widget));
        expect(children.single is Column, width < 582);
        final title = find.text('Zulu');
        final version = find.text('v.1.0.0').first;
        expect(
          t.getTopLeft(version).dy > t.getTopLeft(title).dy + 10,
          width < 528,
        );
        expect(t.takeException(), isNull);
      });
    });
  }
  testWidgets(
    'filter dropdown order, empty types dropped, alias-aware trimmed search',
    (t) async {
      await hubCase(t, (f) async {
        SharedPreferences.setMockInitialValues({
          'stremio_addons_v1': const JsonEncoder().convert([
            hubAddon('z9', 'Zulu', alias: 'Special alias').toJson(),
            hubAddon('m5', 'Middle', types: const []).toJson(),
            hubAddon('a2', 'Alpha', types: const ['series']).toJson(),
          ]),
        });
        StremioService.instance.invalidateCache();
        await f.mount(t);
        final type = t.widget<StremioDropdown<String>>(
          find.byWidgetPredicate(
            (w) =>
                w is StremioDropdown<String> &&
                w.focusNode == f.member('typeFocus'),
          ),
        );
        expect(type.options.map((o) => o.label), [
          'All',
          'Movies',
          'Series',
          'Channels',
          'TV',
          'Anime',
        ]);
        await f.dropdown(t, 'All', 'Movies');
        expect(find.text('Special alias'), findsOneWidget);
        expect(find.text('Middle'), findsNothing);
        expect(find.text('Alpha'), findsNothing);
        await t.tap(find.byIcon(Icons.search_rounded).first);
        await t.pump();
        await t.pump();
        await t.enterText(find.byType(TextField), '  aLiAs  ');
        await t.pump();
        expect(f.member('search'), 'aLiAs');
        expect(find.text('Special alias'), findsOneWidget);
        await t.enterText(find.byType(TextField), 'Zulu');
        await t.pump();
        expect(find.text('No matches'), findsOneWidget);
        await t.tap(find.byIcon(Icons.close_rounded));
        await t.pump();
        expect(f.member('searchOpen'), isFalse);
        expect(f.member('search'), '');
      });
    },
  );
  testWidgets('capability chip order precedes debrid warning', (t) async {
    await hubCase(t, (f) async {
      await f.mount(t);
      final row = find.ancestor(
        of: find.text('Zulu'),
        matching: find.byWidgetPredicate(
          (w) => w.runtimeType.toString().endsWith('InstalledRow'),
        ),
      );
      final chips = t
          .widgetList<Text>(
            find.descendant(of: row, matching: find.byType(Text)),
          )
          .map((w) => w.data)
          .where(
            (s) => [
              'STREAMS',
              'CATALOG',
              'METADATA',
              'SUBTITLES',
              'NEEDS DEBRID',
            ].contains(s),
          )
          .toList();
      expect(chips, [
        'STREAMS',
        'CATALOG',
        'METADATA',
        'SUBTITLES',
        'NEEDS DEBRID',
      ]);
    });
  });
  testWidgets(
    'market keeps service list identity and order, nav skips installed and grows only',
    (t) async {
      await hubCase(t, (f) async {
        await f.mount(t);
        await f.dropdown(t, 'Installed', 'Official');
        expect(f.ids('market'), ['m7', 'z9', 'b3']);
        final list = await StremioMarketplaceService.instance.fetchOfficial();
        expect(
          (f.member('marketIdenticalTo') as bool Function(Object))(list),
          isTrue,
        );
        expect(f.requests, isEmpty);
        final nodes = f.member('marketNodes') as List<FocusNode>;
        expect(nodes.map((n) => n.debugLabel), [
          'market-row-0',
          'market-row-1',
        ]);
        expect(nodes.every((n) => n.context != null), isTrue);
        await t.tap(find.byIcon(Icons.search_rounded).first);
        await t.pump();
        await t.pump();
        await t.enterText(find.byType(TextField), 'Middle');
        await t.pump();
        final shrunk = f.member('marketNodes') as List<FocusNode>;
        expect(shrunk, nodes);
        expect(shrunk[1].context!.mounted, isFalse);
        await f.dropdown(t, 'Official', 'Installed');
        await f.dropdown(t, 'Installed', 'Official');
        expect(f.requests, isEmpty);
      });
    },
  );
  testWidgets(
    'filter DOWN search arrows submit and search close restore original focus',
    (t) async {
      await hubCase(t, (f) async {
        await f.mount(t);
        (f.member('typeFocus') as FocusNode).requestFocus();
        await t.pump();
        await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await t.pump();
        expect((f.member('metadataFocus') as FocusNode).hasFocus, isTrue);
        await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await t.pump();
        expect((f.member('firstRowFocus') as FocusNode).hasFocus, isTrue);
        await t.tap(find.byIcon(Icons.search_rounded).first);
        await t.pump();
        await t.pump();
        expect((f.member('searchFocus') as FocusNode).hasFocus, isTrue);
        final text = t.widget<TvTextField>(find.byType(TvTextField));
        text.onDownArrow!();
        await t.pump();
        expect((f.member('metadataFocus') as FocusNode).hasFocus, isTrue);
        text.onUpArrow!();
        await t.pump();
        expect((f.member('searchBtnFocus') as FocusNode).hasFocus, isTrue);
        text.onSubmitted!('');
        await t.pump();
        expect((f.member('metadataFocus') as FocusNode).hasFocus, isTrue);
        await t.tap(find.byIcon(Icons.search_rounded).first);
        await t.pump();
        expect((f.member('searchBtnFocus') as FocusNode).hasFocus, isTrue);
      });
    },
  );
  testWidgets(
    'LEFT exits leftmost to sidebar including null, caret LEFT ignored',
    (t) async {
      await hubCase(t, (f) async {
        await f.mount(t);
        var sidebar = 0;
        MainPageBridge.focusTvSidebar = () => sidebar++;
        (f.member('kindFocus') as FocusNode).requestFocus();
        await t.pump();
        await t.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
        await t.pump();
        expect(sidebar, 1);
        MainPageBridge.focusTvSidebar = null;
        await t.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
        await t.pump();
        expect((f.member('kindFocus') as FocusNode).hasFocus, isTrue);
        await t.tap(find.byIcon(Icons.search_rounded).first);
        await t.pump();
        await t.pump();
        MainPageBridge.focusTvSidebar = () => sidebar++;
        await t.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
        expect(sidebar, 1);
      });
    },
  );
  testWidgets(
    'market button Down Up KeyDown and Repeat preserve nav and activate once',
    (t) async {
      await hubCase(t, (f) async {
        await f.mount(t);
        await f.dropdown(t, 'Installed', 'Official');
        final nodes = f.member('marketNodes') as List<FocusNode>;
        nodes.first.requestFocus();
        await t.pump();
        await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await t.pump();
        expect(nodes.last.hasFocus, isTrue);
        await t.sendKeyEvent(LogicalKeyboardKey.arrowUp);
        await t.pump();
        expect(nodes.first.hasFocus, isTrue);
        await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await t.pump();
        final response = Completer<http.Response>();
        f.held['https://b3.addon.test/manifest.json'] = response;
        await t.sendKeyDownEvent(LogicalKeyboardKey.enter);
        await f.until(t, () => f.requests.isNotEmpty);
        await t.sendKeyRepeatEvent(LogicalKeyboardKey.enter);
        expect(f.requests, ['GET https://b3.addon.test/manifest.json']);
        await t.sendKeyUpEvent(LogicalKeyboardKey.enter);
        response.complete(f.json(hubManifest('b3', 'Beta')));
        await f.until(t, () => f.ids('installed').contains('b3'));
        await t.pump();
        await t.pump();
        await t.pumpAndSettle();
        expect(f.member('marketNodes'), nodes);
        expect(nodes.last.hasFocus, isFalse);
        expect((await f.saved(t)).map((e) => e.id), [
          'z9',
          'com.linvo.cinemeta',
          'a2',
          'b3',
        ]);
        expect(f.requests, ['GET https://b3.addon.test/manifest.json']);
      });
    },
  );
  testWidgets('TV setter after real check changes dropdown input mode', (
    t,
  ) async {
    await hubCase(t, (f) async {
      await f.mount(t);
      (f.member('setTv') as void Function(bool))(true);
      await t.pump();
      expect(
        t
            .widgetList<StremioDropdown<dynamic>>(
              find.byWidgetPredicate((w) => w is StremioDropdown),
            )
            .every((dd) => dd.isTelevision),
        isTrue,
      );
    });
  });
  for (final view in [
    'installed_narrow',
    'installed_wide',
    'official',
    'engines',
    'options',
    'dialog',
  ]) {
    testWidgets('reachable pixel golden $view', (t) async {
      if (Platform.isLinux && !captureLinux && !requireLinux) {
        markTestSkipped('Original Linux goldens pending before builder moves');
        return;
      }
      await hubCase(t, (f) async {
        await f.mount(t, width: view == 'installed_narrow' ? 375 : 1000);
        if (view == 'official') await f.dropdown(t, 'Installed', 'Official');
        if (view == 'engines') {
          await f.engines(t); // available only: no wall-clock subtitles
        }
        if (view == 'options' || view == 'dialog') await f.tap(t, 'Zulu');
        if (view == 'dialog') await f.tap(t, 'View details');
        FocusManager.instance.primaryFocus?.unfocus();
        await t.pumpAndSettle();
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile(
            '../../../../goldens/addon_hub/${Platform.isLinux ? 'linux' : 'macos'}/$view.png',
          ),
        );
      });
    });
  }
}
