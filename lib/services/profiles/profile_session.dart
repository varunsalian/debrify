import 'package:flutter/foundation.dart';

import 'profile_runtime.dart';
import 'profile_scope.dart';

class ProfileSession {
  ProfileSession._();

  static ValueListenable<ProfileScope?> get notifier => ProfileRuntime.scope;
  static ProfileScope capture() => ProfileRuntime.capture();
}
