import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import '../../../support/settings_widgets_source.dart';

String compact(String source) => source.replaceAll(RegExp(r'\s+'), '');

void main() {
  test('all 60 manifest declarations have exactly one physical owner', () {
    expect(settingsWidgetsManifest(), hasLength(60));
    for (final row in settingsWidgetsManifest()) {
      expect(
        () => settingsWidgetsDeclaration(row['original_name']!),
        returnsNormally,
        reason: row['original_name'],
      );
    }
  });
  test('S summary focus labels creation points and ordered disposal', () {
    final body = compact(
      settingsWidgetsDeclaration('_ConnectionsSummaryState'),
    );
    const labels = [
      'torbox',
      'premiumize',
      'alldebrid',
      'pikpak',
      'webdav',
      'media-servers',
      'indexer-managers',
      'iptv',
      'tracking',
      'trakt',
      'simkl',
      'mdblist',
    ];
    for (final label in labels) {
      expect(body, contains("debugLabel:'settings-$label'"));
    }
    const nodes = [
      '_torboxFocusNode',
      '_premiumizeFocusNode',
      '_allDebridFocusNode',
      '_pikpakFocusNode',
      '_webDavFocusNode',
      '_mediaServersFocusNode',
      '_indexerManagersFocusNode',
      '_iptvFocusNode',
      '_trackingFocusNode',
      '_traktFocusNode',
      '_simklFocusNode',
      '_mdblistFocusNode',
    ];
    expect(
      body,
      contains(
        'voiddispose(){${nodes.map((n) => '$n.dispose();').join()}super.dispose();}',
      ),
    );
    expect(
      body,
      contains(
        "finalFocusNode_mediaServersFocusNode=FocusNode(debugLabel:'settings-media-servers',);",
      ),
    );
    expect('latefinalFocusNode'.allMatches(body), hasLength(11));
    expect(body, contains('super.initState();_torboxFocusNode=FocusNode'));
    expect(body, isNot(contains('widget.firstCardFocusNode?.dispose')));
  });
  test(
    'S motion dependency hook reveal guard wrapper disposal and borrowed ownership',
    () {
      final card = compact(settingsWidgetsDeclaration('_ConnectionCardState'));
      expect(
        card,
        contains(
          'voiddidChangeDependencies(){super.didChangeDependencies();_motion=AppMotion.of(context);}',
        ),
      );
      expect(
        card,
        contains(
          'if(target.context!=null){tvRevealMinimal(target.context!,duration:_motion.scaled(constDuration(milliseconds:200)),);',
        ),
      );
      expect(
        card,
        contains('voiddispose(){_wrapNode.dispose();super.dispose();}'),
      );
      for (final name in [
        '_SettingsTileState',
        '_SettingsToggleTileState',
        '_SettingsLookHeroState',
      ]) {
        final body = compact(settingsWidgetsDeclaration(name));
        expect(
          body,
          contains(
            'FocusNodeget_node=>widget.focusNode??(_ownNode??=FocusNode());',
          ),
        );
        expect(
          body,
          contains('voiddispose(){_ownNode?.dispose();super.dispose();}'),
        );
        expect(body, contains('boolget_focused=>_node.hasFocus;'));
        expect(body, isNot(contains('widget.focusNode?.dispose')));
      }
    },
  );
  test(
    'S rendering fallback remains Automatic and memo is private to one owner',
    () {
      expect(
        compact(settingsWidgetsDeclaration('tvRenderQualityLabel')),
        contains("return'Automatic';"),
      );
      final rows = settingsWidgetsManifest().where(
        (r) => [
          '_settingsThemeBase',
          '_settingsThemeApp',
          '_settingsThemeCache',
          'settingsPageTheme',
          '_buildSettingsPageTheme',
        ].contains(r['original_name']),
      );
      expect(rows.map((r) => r['destination_file']!).toSet(), hasLength(1));
      for (final name in [
        '_settingsThemeBase',
        '_settingsThemeApp',
        '_settingsThemeCache',
      ]) {
        expect(settingsWidgetsDeclaration(name), isNot(contains('=')));
      }
    },
  );
  test(
    'staged service show lists import boundaries DAG and dormant completion',
    () {
      final files = settingsWidgetsPhysicalFiles();
      final graph = <String, Set<String>>{};
      for (final entry in files.entries) {
        final facade = entry.key == settingsWidgetsFacade;
        final directives = RegExp(
          r"^import\s+'([^']+)'([^;]*);",
          multiLine: true,
        ).allMatches(entry.value);
        for (final directive in directives) {
          final uri = directive[1]!;
          final relative = uri.startsWith('package:debrify/')
              ? 'lib/${uri.substring('package:debrify/'.length)}'
              : uri.startsWith('package:') || uri.startsWith('dart:')
              ? uri
              : File(entry.key).absolute.uri.resolve(uri).path;
          if (relative.contains('/services/')) {
            expect(
              relative.endsWith('/services/main_page_bridge.dart') ||
                  relative.endsWith(
                    '/services/profiles/profile_bootstrap.dart',
                  ),
              isTrue,
              reason: '${entry.key}: $uri',
            );
          }
          expect(
            relative,
            isNot(
              matches(
                r'(?:^|/)(?:storage|players?|player_launch|launchers?)/|(?:package:)(?:http|shared_preferences|sqflite)/|video_player_launcher\.dart',
              ),
            ),
          );
          expect(relative, isNot(contains('player')));
          if (relative.contains('launcher')) {
            expect(uri.startsWith('package:url_launcher/'), isTrue);
          }
          if (uri.startsWith('package:url_launcher/')) {
            expect(
              facade || entry.key.endsWith('/settings_links.dart'),
              isTrue,
            );
          }
        }
        if (facade) {
          continue;
        }
        expect(entry.value, isNot(contains('screens/')));
        expect(
          entry.value,
          isNot(
            matches(
              r"import.*(?:http|shared_preferences|sqflite|storage|player|video_player_launcher)",
            ),
          ),
        );
        for (final match in RegExp(
          r"import 'package:debrify/services/([^']+)'([^;]*);",
        ).allMatches(entry.value)) {
          final allowed = switch (entry.key.split('/').last) {
            'settings_connection_card.dart' =>
              "main_page_bridge.dart show MainPageBridge",
            'settings_legacy_mode_dialog.dart' =>
              "profiles/profile_bootstrap.dart show ProfileBootstrap",
            _ => '',
          };
          expect('${match[1]}${match[2]}', allowed);
        }
        if (entry.value.contains('url_launcher/')) {
          expect(entry.key.endsWith('/settings_links.dart'), isTrue);
        }
        graph[entry.key] = {
          for (final match in RegExp(
            r"import 'package:debrify/(features/settings_widgets/[^']+)';",
          ).allMatches(entry.value))
            'lib/${match[1]}',
        };
      }
      void visit(String node, Set<String> stack) {
        expect(stack.contains(node), isFalse, reason: 'cycle $node');
        for (final next in graph[node] ?? <String>{}) {
          visit(next, {...stack, node});
        }
      }

      for (final node in graph.keys) {
        visit(node, {});
      }
      if (settingsWidgetsComplete) {
        for (final path
            in settingsWidgetsManifest()
                .map((r) => r['destination_file']!)
                .toSet()) {
          expect(File(path).existsSync(), isTrue, reason: path);
        }
        expect(settingsWidgetsSpans(files[settingsWidgetsFacade]!), isEmpty);
        final facade = files[settingsWidgetsFacade]!;
        expect(facade, isNot(matches(RegExp(r'^\s*import ', multiLine: true))));
        expect(RegExp(r'\bshow\b').allMatches(facade), isNotEmpty);
      }
    },
  );
}
