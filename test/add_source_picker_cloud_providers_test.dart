import 'package:debrify/widgets/add_source_picker_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows every configured cloud binding provider', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showAddSourcePickerDialog(
              context,
              onTorrentSearch: () {},
              onRealDebrid: () {},
              onTorbox: () {},
              onPremiumize: () {},
              onAllDebrid: () {},
              onPikPak: () {},
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text('Real-Debrid'), findsOneWidget);
    expect(find.text('TorBox'), findsOneWidget);
    expect(find.text('Premiumize'), findsOneWidget);
    expect(find.text('AllDebrid'), findsOneWidget);
    expect(find.text('PikPak'), findsOneWidget);
  });

  testWidgets('omits cloud providers without callbacks', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showAddSourcePickerDialog(
              context,
              onTorrentSearch: () {},
              onPremiumize: () {},
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text('Premiumize'), findsOneWidget);
    expect(find.text('Real-Debrid'), findsNothing);
    expect(find.text('TorBox'), findsNothing);
    expect(find.text('AllDebrid'), findsNothing);
    expect(find.text('PikPak'), findsNothing);
  });
}
