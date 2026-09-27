import 'package:debrify/features/home/application/home_stage_art_failures.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('retains 512 failed URLs then clears before remembering the next', () {
    final failures = HomeStageArtFailures();
    for (var i = 0; i < 512; i++) {
      failures.remember('url-$i');
    }
    for (var i = 0; i < 512; i++) {
      expect(failures.contains('url-$i'), isTrue);
    }
    failures.remember('next');
    expect(failures.contains('next'), isTrue);
    for (var i = 0; i < 512; i++) {
      expect(failures.contains('url-$i'), isFalse);
    }
  });

  test(
    'duplicates below capacity do not consume slots; at capacity they clear',
    () {
      final failures = HomeStageArtFailures();
      for (var i = 0; i < 512; i++) {
        failures.remember('same');
      }
      failures.remember('second');
      expect(failures.contains('same'), isTrue);
      for (var i = 0; i < 510; i++) {
        failures.remember('url-$i');
      }
      failures.remember('same');
      expect(failures.contains('same'), isTrue);
      expect(failures.contains('second'), isFalse);
      expect(failures.contains('url-509'), isFalse);
    },
  );
}
