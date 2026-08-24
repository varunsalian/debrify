import 'package:debrify/screens/alldebrid/alldebrid_files_screen.dart';
import 'package:debrify/screens/debrid_downloads_screen.dart';
import 'package:debrify/screens/torbox/torbox_downloads_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('Real-Debrid source picker exposes torrent and DDL libraries', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: DebridDownloadsScreen(
          isPushedRoute: true,
          selectSourceMode: true,
          onSourceSelected: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Torrent Downloads'), findsOneWidget);
    expect(find.text('DDL Downloads'), findsOneWidget);

    await tester.tap(find.text('DDL Downloads'));
    await tester.pumpAndSettle();

    expect(find.text('Error Loading DDL Downloads'), findsOneWidget);
    await tester.pump(const Duration(seconds: 11));
  });

  testWidgets('TorBox source picker exposes torrent and web libraries', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: TorboxDownloadsScreen(
          isPushedRoute: true,
          initialSearchQuery: 'Movie title',
          selectSourceMode: true,
          onSourceSelected: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Torrents'), findsOneWidget);
    expect(find.text('Web Downloads'), findsOneWidget);
    expect(find.text('Movie title'), findsOneWidget);

    await tester.tap(find.text('Web Downloads'));
    await tester.pumpAndSettle();

    expect(find.text('Movie title'), findsNothing);
    expect(find.textContaining('view web downloads'), findsOneWidget);
    await tester.pump(const Duration(seconds: 11));
  });

  testWidgets('AllDebrid source picker exposes magnet and web libraries', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AllDebridFilesScreen(
          isPushedRoute: true,
          selectSourceMode: true,
          onSourceSelected: (_) async {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Torrent Downloads'), findsOneWidget);
    expect(find.text('Web Downloads'), findsOneWidget);

    await tester.tap(find.text('Web Downloads'));
    await tester.pumpAndSettle();

    expect(
      find.text('Add your AllDebrid API key in Settings first.'),
      findsOneWidget,
    );
  });
}
