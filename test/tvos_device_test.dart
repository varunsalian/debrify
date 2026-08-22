import 'package:debrify/utils/tvos_device.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the 2-3 GB units are low-memory, the 4 GB 2022 model is not', () {
    const gib = 1 << 30;
    expect(TvosDevice.isLowMemoryBytes(2 * gib), isTrue); // Apple TV HD
    expect(TvosDevice.isLowMemoryBytes(3 * gib), isTrue); // 4K 2017 and 2021
    expect(TvosDevice.isLowMemoryBytes(4 * gib), isFalse); // 4K 2022
    // Real devices report slightly under the nominal capacity.
    expect(TvosDevice.isLowMemoryBytes(3 * gib - (100 << 20)), isTrue);
    expect(TvosDevice.isLowMemoryBytes(4 * gib - (100 << 20)), isFalse);
  });

  test('an unprobed device stays on the full-power path', () {
    expect(TvosDevice.isLowMemoryBytes(null), isFalse);
    expect(TvosDevice.isLowMemoryBytes(0), isFalse);
    expect(TvosDevice.isLowMemoryBytes(-1), isFalse);
  });
}
