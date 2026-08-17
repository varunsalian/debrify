import 'dart:async';

import 'package:debrify/services/profiles/profile_runtime.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  // ignore: invalid_use_of_visible_for_testing_member
  ProfileRuntime.debugReset();
  ProfileRuntime.initializeLegacy();
  await testMain();
}
