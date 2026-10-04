import 'dart:async';

import 'package:debrify/services/profiles/device_key_provider.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

/// Holds the actual persistence adapter before its write, rather than delaying
/// a page callback that would obscure the captured-scope boundary.
class IptvHeldPreferences extends InMemorySharedPreferencesStore {
  IptvHeldPreferences(super.data) : super.withData();
  final writes = <({String key, Object value})>[];
  String? failRemoveKey;

  @override
  Future<bool> remove(String key) async {
    if (key == failRemoveKey) throw StateError('removal probe default');
    return super.remove(key);
  }

  String? holdKey;
  Completer<void>? entered;
  Completer<void>? release;

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    writes.add((key: key, value: value));
    if (key == holdKey) {
      entered!.complete();
      await release!.future;
    }
    return super.setValue(valueType, key, value);
  }
}

class IptvHeldCipher extends MemoryDeviceSecretCipher {
  IptvHeldCipher() : super(List<int>.generate(32, (i) => i + 1));
  bool holdSeal = false;
  Completer<void>? entered;
  Completer<void>? release;

  @override
  Future<String> seal(
    List<int> plaintext, {
    required List<int> associatedData,
  }) async {
    if (holdSeal) {
      holdSeal = false;
      entered!.complete();
      await release!.future;
    }
    return super.seal(plaintext, associatedData: associatedData);
  }
}
