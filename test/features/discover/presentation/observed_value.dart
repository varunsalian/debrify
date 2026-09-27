import 'package:flutter/foundation.dart';

class ObservedValue<T> extends ValueNotifier<T> {
  ObservedValue(super.value);
  bool get isObserved => hasListeners;
}
