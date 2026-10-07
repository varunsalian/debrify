import 'package:flutter_test/flutter_test.dart';
import '../../../../support/alldebrid_files_fixture.dart';

void main() {
  testWidgets(
    'HTTP fixture original ready-only load uses success envelope and exact authorization',
    (t) => allDebridCase(t, (f) async {
      f.magnets.add(adMagnet('processing', status: 2));
      await f.mount(t);
      expect(f.ids, ['z9', 'a2', 'm5']);
      expect(f.member('loading'), isFalse);
      expect(f.member('error'), isNull);
      expect(f.log, [adList()]);
      expect(f.member('linksLoadedOnce'), isFalse);
    }),
  );
}
