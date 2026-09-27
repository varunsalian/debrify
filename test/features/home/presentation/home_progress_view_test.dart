import 'package:debrify/features/home/presentation/home_progress_view.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'retained grid map reads new snapshots without copying or retaining removed keys',
    () {
      Map<String, double> current = Map.unmodifiable({
        'first': .25,
        'removed': .5,
      });
      final retained = HomeProgressView(() => current);
      expect(retained['first'], .25);
      current = Map.unmodifiable({'first': .75, 'added': .1});
      expect(retained['first'], .75);
      expect(retained['removed'], isNull);
      expect(retained.keys, ['first', 'added']);
      expect(retained.length, 2);
      expect(Map.of(retained), {'first': .75, 'added': .1});
      current = const {};
      expect(retained, isEmpty);
    },
  );

  test('borrowers cannot replace, clear, or remove controller progress', () {
    final current = <String, double>{'first': .25};
    final view = HomeProgressView(() => current);
    expect(() => view['first'] = .5, throwsUnsupportedError);
    expect(view.clear, throwsUnsupportedError);
    expect(() => view.remove('first'), throwsUnsupportedError);
    expect(current, {'first': .25});
  });
}
