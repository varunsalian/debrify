import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('release transfer diagnostics use a retained Android log priority', () {
    final rules = File('android/app/proguard-rules.pro').readAsStringSync();
    final removalBlock = rules.substring(
      rules.indexOf('# Remove logging for better performance in release'),
      rules.indexOf('# Keep Android TV specific classes'),
    );
    expect(removalBlock, contains('public static *** d(...);'));
    expect(removalBlock, contains('public static *** v(...);'));
    expect(removalBlock, contains('public static *** i(...);'));
    expect(removalBlock, isNot(contains('public static *** w(...);')));

    final activity = File(
      'android/app/src/main/kotlin/com/debrify/app/MainActivity.kt',
    ).readAsStringSync();
    expect(
      activity,
      contains('android.util.Log.w("DEBRIFY_TRANSFER", message)'),
    );
    expect(
      activity,
      isNot(contains('android.util.Log.i("DEBRIFY_TRANSFER", message)')),
    );
  });

  test('native transfer sink accepts only structured bounded messages', () {
    final activity = File(
      'android/app/src/main/kotlin/com/debrify/app/MainActivity.kt',
    ).readAsStringSync();
    expect(activity, contains('message.startsWith("DEBRIFY_TRANSFER ")'));
    expect(activity, contains('.take(1_024)'));
  });
}
