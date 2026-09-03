import 'dart:ui' show Color;

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:debrify/models/stream_badge_rules.dart';
import 'package:debrify/services/stream_badge_matcher.dart';
import 'package:debrify/services/stream_badges_service.dart';

const _sample = r'''
{
  "groups": [
    {"id": "gq", "name": "Quality", "color": "#FF27C04F", "isExpanded": true},
    {"id": "gr", "name": "Resolution", "color": "#FFFFBE01", "isExpanded": true}
  ],
  "filters": [
    {"id": "q-r", "groupId": "gq", "name": "Remux", "pattern": "(?i)\\bremux\\b",
     "type": "filter", "isEnabled": true, "imageURL": "https://x/remux.png",
     "tagColor": "#E600E932", "tagStyle": "filled", "textColor": "#27C04F", "borderColor": "#FF00FF37"},
    {"id": "r-4k", "groupId": "gr", "name": "4K",
     "pattern": "(?i)^(?=.*(?:2160[pi]?|4k|uhd))(?!.*(?:1080[pi]?|720[pi]?))",
     "type": "filter", "isEnabled": true, "imageURL": "",
     "tagColor": "#FFBE01", "tagStyle": "filled and bordered", "textColor": "#FFBE01", "borderColor": "#FFBE01"},
    {"id": "p-vidlink", "groupId": "gp", "name": "⚡ Vidlink", "pattern": "(?i)vidlink",
     "type": "filter", "isEnabled": true, "tagColor": "#FF00D2FF", "tagStyle": "outlined",
     "textColor": "#00D2FF", "borderColor": "#FF00D2FF"},
    {"id": "off", "groupId": "gq", "name": "Off", "pattern": "(?i)bluray",
     "type": "filter", "isEnabled": false, "tagStyle": "filled"},
    {"id": "bad", "groupId": "gq", "name": "Broken", "pattern": "(?i)([unclosed",
     "type": "filter", "isEnabled": true, "tagStyle": "filled"},
    {"id": "ch", "groupId": "gc", "name": "5.1",
     "pattern": "^(?=.*[^0-9]5[. ][01](?![0-9]))(?!.*[^0-9][7-8][. ][01](?![0-9]))",
     "type": "filter", "isEnabled": true, "tagStyle": "filled", "tagColor": "#00000000"}
  ]
}
''';

void main() {
  group('StreamBadgeRuleset.parse', () {
    test('reads groups, rules, colours and styles', () {
      final set = StreamBadgeRuleset.parse(_sample);
      expect(set.groups.map((g) => g.name), ['Quality', 'Resolution']);
      expect(set.groups.first.color, const Color(0xFF27C04F));
      expect(set.rules, hasLength(6));
      expect(set.enabledCount, 5);

      final remux = set.rules.first;
      expect(remux.name, 'Remux');
      expect(remux.style, StreamBadgeStyle.filled);
      expect(remux.tagColor, const Color(0xE600E932));
      expect(remux.textColor, const Color(0xFF27C04F));
      expect(remux.imageUrl, 'https://x/remux.png');

      final fourK = set.rules[1];
      expect(fourK.style, StreamBadgeStyle.filledBordered);
      expect(fourK.imageUrl, isNull, reason: 'empty imageURL is no image');

      expect(set.rules[2].style, StreamBadgeStyle.outlined);
      expect(set.rules[3].enabled, isFalse);
      expect(set.invalidRules.map((r) => r.name), ['Broken']);
      // A fully transparent placeholder colour is treated as absent.
      expect(set.rules[5].tagColor, isNull);
    });

    test('rejects non-JSON and empty documents', () {
      expect(() => StreamBadgeRuleset.parse('nope'), throwsFormatException);
      expect(
        () => StreamBadgeRuleset.parse('{"groups": [], "filters": []}'),
        throwsFormatException,
      );
      expect(() => StreamBadgeRuleset.parse('[1,2]'), throwsFormatException);
    });

    test('round-trips through toJson', () {
      final set = StreamBadgeRuleset.parse(_sample);
      final again = StreamBadgeRuleset.fromJson(set.toJson());
      expect(again.rules.length, set.rules.length);
      expect(again.rules[1].pattern, set.rules[1].pattern);
      expect(again.rules[1].tagColor, set.rules[1].tagColor);
      expect(again.rules[2].style, StreamBadgeStyle.outlined);
      expect(again.rules[3].enabled, isFalse);
    });
  });

  group('compileBadgePattern', () {
    test('turns a leading (?i) into case-insensitive matching', () {
      final r = compileBadgePattern(r'(?i)\bremux\b')!;
      expect(r.hasMatch('Movie.2020.REMUX.mkv'), isTrue);
      expect(r.hasMatch('remuxed'), isFalse);
      final cs = compileBadgePattern(r'\bREMUX\b')!;
      expect(cs.hasMatch('a remux b'), isFalse);
    });

    test('supports the lookaheads community presets rely on', () {
      final fourK = compileBadgePattern(
        r'(?i)^(?=.*(?:2160[pi]?|4k|uhd))(?!.*(?:1080[pi]?|720[pi]?))',
      )!;
      expect(fourK.hasMatch('Film 2160p HDR'), isTrue);
      expect(fourK.hasMatch('Film 4K + 1080p pack'), isFalse);
      expect(compileBadgePattern('(?i)([unclosed'), isNull);
      expect(compileBadgePattern('   '), isNull);
    });
  });

  group('parseBadgeColor', () {
    test('accepts RGB and ARGB, rejects junk and transparent', () {
      expect(parseBadgeColor('#FFBE01'), const Color(0xFFFFBE01));
      expect(parseBadgeColor('#E600E932'), const Color(0xE600E932));
      expect(parseBadgeColor('#00000000'), isNull);
      expect(parseBadgeColor('red'), isNull);
      expect(parseBadgeColor(42), isNull);
      expect(encodeBadgeColor(const Color(0xE600E932)), '#E600E932');
    });
  });

  group('StreamBadgeMatcher', () {
    test('matches on name or description, skips disabled and broken rules', () {
      final m = StreamBadgeMatcher([StreamBadgeRuleset.parse(_sample)]);
      expect(m.rules.map((r) => r.name), ['Remux', '4K', '⚡ Vidlink', '5.1']);

      final byName = m.matchesFor(name: 'Movie.2019.2160p.REMUX.mkv');
      expect(byName.map((r) => r.name), ['Remux', '4K']);

      final byDesc = m.matchesFor(
        name: 'Movie',
        description: 'Vidlink • 4K • 5.1 • 12 GB',
      );
      expect(byDesc.map((r) => r.name), ['4K', '⚡ Vidlink', '5.1']);

      expect(m.matchesFor(name: 'Plain 1080p BluRay'), isEmpty);
    });

    test('memoises repeated lookups', () {
      final m = StreamBadgeMatcher([StreamBadgeRuleset.parse(_sample)]);
      final a = m.matchesFor(name: 'X REMUX', description: 'd');
      final b = m.matchesFor(name: 'X REMUX', description: 'd');
      expect(identical(a, b), isTrue);
    });

    test('empty matcher never matches', () {
      expect(StreamBadgeMatcher.empty.matchesFor(name: 'REMUX 4K'), isEmpty);
    });
  });

  group('StreamBadgesService', () {
    TestWidgetsFlutterBinding.ensureInitialized();

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      StreamBadgesService.instance.resetProfileScope();
    });

    test('import, replace by id, toggle, remove; matcher follows', () async {
      final svc = StreamBadgesService.instance;
      await svc.warmUp();
      expect(svc.matcher.value.isEmpty, isTrue);

      final first = await svc.importJson(_sample, name: 'Preset');
      expect(first.replaced, isFalse);
      expect(first.ruleset.enabledCount, 5);
      expect(svc.matcher.value.rules, hasLength(4));

      final again = await svc.importJson(_sample, name: 'Preset');
      expect(again.replaced, isTrue);
      expect(await svc.getSources(), hasLength(1));

      await svc.setSourceEnabled(first.source.id, false);
      expect(svc.matcher.value.isEmpty, isTrue);
      await svc.setSourceEnabled(first.source.id, true);
      expect(svc.matcher.value.rules, hasLength(4));

      await svc.setEnabled(false);
      expect(svc.matcher.value.isEmpty, isTrue);
      await svc.setEnabled(true);
      expect(svc.matcher.value.rules, hasLength(4));

      await svc.remove(first.source.id);
      expect(await svc.getSources(), isEmpty);
      expect(svc.matcher.value.isEmpty, isTrue);
    });

    test('backup round-trip merges by id', () async {
      final svc = StreamBadgesService.instance;
      await svc.warmUp();
      await svc.importJson(_sample, name: 'Preset');
      final exported = await svc.exportJson();
      expect(exported, hasLength(1));

      await svc.clear();
      final counts = await svc.applyBackup(exported);
      expect(counts.imported, 1);
      expect((await svc.getSources()).single.name, 'Preset');
      final again = await svc.applyBackup([...exported, 'junk']);
      expect(again.alreadyPresent, 1);
      expect(again.failed, 1);
    });

    test('rejects a non-http link without touching storage', () async {
      final svc = StreamBadgesService.instance;
      await expectLater(
        svc.importFromUrl('ftp://nope/badges.json'),
        throwsFormatException,
      );
      expect(await svc.getSources(), isEmpty);
    });
  });
}
