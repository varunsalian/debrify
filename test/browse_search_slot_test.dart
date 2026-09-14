import 'package:debrify/screens/browse_screen.dart';
import 'package:debrify/theme/app_theme.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:debrify/widgets/browse/browse_search_header.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(Widget child) => MaterialApp(
  home: AppThemeScope(theme: AppThemes.legacy, child: child),
);

void main() {
  testWidgets('default Browse layout mounts its owned search once', (
    tester,
  ) async {
    BrowseViewArgs? received;
    await tester.pumpWidget(
      _host(
        BrowseScreen(
          tabIndex: 14,
          hintText: 'Search',
          submitOnly: true,
          isTelevision: false,
          viewBuilder: (args) {
            received = args;
            return const SizedBox.expand();
          },
        ),
      ),
    );

    expect(find.byType(BrowseSearchHeader), findsOneWidget);
    expect(received?.searchHeader, isNull);
  });

  testWidgets('embedded Browse layout hands the same search to its view', (
    tester,
  ) async {
    BrowseViewArgs? received;
    await tester.pumpWidget(
      _host(
        BrowseScreen(
          tabIndex: 13,
          hintText: 'Search channels',
          submitOnly: true,
          isTelevision: true,
          embedSearchHeaderInView: true,
          viewBuilder: (args) {
            received = args;
            return Column(
              children: [
                args.searchHeader!,
                const Expanded(child: Text('IPTV')),
              ],
            );
          },
        ),
      ),
    );

    expect(received?.searchHeader, isNotNull);
    expect(find.byType(BrowseSearchHeader), findsOneWidget);
  });
}
