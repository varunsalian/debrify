import 'dart:convert';
import 'dart:io';

import 'package:debrify/models/playback_resume_policy.dart';
import 'package:debrify/screens/video_player_screen.dart';
import 'package:flutter_test/flutter_test.dart';

import 'debrify_tv_handoff.dart';

void expectStremioTvPlayer(
  VideoPlayerScreen player,
  String site,
  Map<String, Object?> supplied,
) {
  final ledger =
      jsonDecode(
            File('dev/tool/stremio_tv_handoff_ledger.json').readAsStringSync(),
          )
          as Map;
  final entry = (ledger['sites'] as List).cast<Map>().singleWhere(
    (entry) => entry['site'] == site,
  );
  final nativeOnly = (ledger['native_only_arguments'] as List).cast<String>();
  final passed = (entry['arguments'] as List)
      .cast<Map>()
      .map((argument) => argument['name'] as String)
      .where((name) => !nativeOnly.contains(name))
      .toSet();
  expect(supplied.keys.toSet(), passed, reason: '$site supplied fields');
  final defaults = ledger['constructor_defaults'] as Map;
  for (final field in debrifyTvPlayerFields(player).entries) {
    if (passed.contains(field.key)) {
      expect(field.value, supplied[field.key], reason: '$site ${field.key}');
    } else {
      final Object? expected = switch (defaults[field.key]) {
        null => null,
        'false' => false,
        'true' => true,
        '40' => 40,
        'PlaybackResumePolicy.sourceSpecific' =>
          PlaybackResumePolicy.sourceSpecific,
        final value => throw StateError(
          'Unclassified default ${field.key}: $value',
        ),
      };
      expect(field.value, expected, reason: '$site default ${field.key}');
    }
  }
}
