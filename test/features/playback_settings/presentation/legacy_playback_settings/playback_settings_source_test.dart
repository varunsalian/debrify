import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late Map<String, dynamic> current;
  late Map<String, dynamic> original;
  setUpAll(() {
    final result = Process.runSync('python3', [
      'dev/tool/playback_settings_source_inventory.py',
    ]);
    expect(result.exitCode, 0, reason: '${result.stderr}');
    current = jsonDecode(result.stdout as String) as Map<String, dynamic>;
    original =
        jsonDecode(
              File(
                'test/features/playback_settings/presentation/legacy_playback_settings/playback_settings_source_original.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;
  });
  test('all 36 listener identities and initialization order stay original', () {
    expect(original['listeners'], hasLength(36));
    expect(current['listeners'], original['listeners']);
    expect(current['lifecycle_prefix'], original['lifecycle_prefix']);
  });
  test('42 resources dispose in order before super', () {
    expect(original['disposals'], hasLength(43));
    expect((original['disposals'] as List).last, 'super');
    expect(current['disposals'], original['disposals']);
  });
  test('every platform predicate and E1–E15 order stays original', () {
    expect(current['predicates'], original['predicates']);
  });
  test('detectors reads and unconditional migrations retain call order', () {
    expect(current['load_calls'], original['load_calls']);
    final calls = current['load_calls'] as List;
    expect(
      calls.indexOf('getAndroidVideoRendererMode'),
      lessThan(calls.indexOf('loadAll')),
    );
    expect(calls.last, 'loadAll');
  });
  for (final item in [
    'unsupported',
    'self_push',
    'tv_aspect_setter',
    'appearance',
  ]) {
    test('original unreachable and navigation contract $item', () {
      expect(current[item], original[item]);
    });
  }
  test('four shell-owned TV text fields and one night-mode key observer', () {
    expect(current['tv_textfields'], original['tv_textfields']);
    expect(current['key_events'], original['key_events']);
    expect((current['tv_textfields'] as Map).values.reduce((a, b) => a + b), 4);
    expect((current['key_events'] as Map).values.reduce((a, b) => a + b), 1);
  });
}
