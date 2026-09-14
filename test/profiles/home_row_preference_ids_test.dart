import 'dart:convert';

import 'package:debrify/services/profiles/home_row_preference_ids.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const ids = {'resource-phone': 'resource-tablet'};

  test('only recognized Home preferences remap complete addon prefixes', () {
    final rows = [
      'resource-phone:movie:top',
      'resource-phone:series:catalog:with:colons',
      'resource-phone-other:movie:top',
      'cw:movies',
      'trakt:shows',
      'collection:resource-phone',
      'unknown-provider:movie:top',
      'resource-phone::top',
      'resource-phone:movie:',
    ];
    final encoded = jsonEncode(rows);
    for (final key in HomeRowPreferenceIds.keys) {
      expect(
        jsonDecode(HomeRowPreferenceIds.remap(key, encoded, ids) as String),
        [
          'resource-tablet:movie:top',
          'resource-tablet:series:catalog:with:colons',
          ...rows.skip(2),
        ],
      );
    }
    expect(
      HomeRowPreferenceIds.remap('sidebar_configuration_v1', encoded, ids),
      same(encoded),
    );
    expect(
      HomeRowPreferenceIds.remap('unrelated', encoded, ids),
      same(encoded),
    );
  });

  test(
    'list representation, input immutability and no-op identity are preserved',
    () {
      const original = ['resource-phone:movie:top', 'cw:series'];
      expect(HomeRowPreferenceIds.remap('home_row_order_v1', original, ids), [
        'resource-tablet:movie:top',
        'cw:series',
      ]);
      expect(original.first, 'resource-phone:movie:top');
      expect(
        HomeRowPreferenceIds.remap('home_row_order_v1', original, {}),
        same(original),
      );
      expect(
        HomeRowPreferenceIds.remap('home_row_order_v1', original, {
          'other': 'new',
        }),
        same(original),
      );
    },
  );

  test('refresh drops only catalog rows owned by removed resources', () {
    final value = jsonEncode([
      'resource-phone:movie:top',
      'removed:movie:top',
      'removed-extra:movie:top',
      'collection:removed',
      'cw:movies',
    ]);
    expect(
      jsonDecode(
        HomeRowPreferenceIds.remap(
              'home_disabled_sections_v1',
              value,
              ids,
              droppedResourceIds: {'removed'},
            )
            as String,
      ),
      [
        'resource-tablet:movie:top',
        'removed-extra:movie:top',
        'collection:removed',
        'cw:movies',
      ],
    );
  });

  test('malformed and future preference formats are not reinterpreted', () {
    for (final value in <Object?>[
      null,
      false,
      12,
      '{bad json',
      '{"items":[]}',
      '[1,"resource-phone:movie:top"]',
    ]) {
      expect(
        HomeRowPreferenceIds.remap('home_row_order_v1', value, ids),
        same(value),
      );
    }
  });
}
