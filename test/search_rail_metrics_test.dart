import 'package:debrify/utils/home_rail_metrics.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final height in [540.0, 720.0, 1080.0]) {
    testWidgets('TV search enlarges cards without changing Home at $height', (tester) async {
      await tester.pumpWidget(MediaQuery(
        data: MediaQueryData(size: Size(1920, height)),
        child: Builder(builder: (context) {
          final home = homeRailPosterWidth(context, isTelevision: true);
          final search = homeRailPosterWidth(context, isTelevision: true, searchResults: true);
          expect(home, (height * .17).clamp(92.0, 140.0));
          expect(search, greaterThan(home));
          expect(search, lessThanOrEqualTo(180));
          return const SizedBox();
        }),
      ));
    });
  }
}
