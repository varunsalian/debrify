import 'package:debrify/models/debrify_tv/channel.dart';
import 'package:debrify/models/debrify_tv/channel_stats.dart';
import 'package:debrify/models/debrify_tv_cache.dart';
import 'package:debrify/screens/debrify_tv/layouts/debrify_tv_view.dart';
import 'package:debrify/screens/debrify_tv/layouts/spotlight_phone.dart';
import 'package:debrify/services/text_brightness.dart';
import 'package:debrify/theme/app_theme.dart';
import 'package:debrify/theme/app_theme_adapter.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

final _space = DebrifyTvChannel(
  id: 'space',
  name: 'Space Night',
  keywords: ['galaxy', 'sci-fi'],
  avoidNsfw: true,
  channelNumber: 3,
  createdAt: _fixtureDate,
  updatedAt: _fixtureDate,
);

final _comedy = DebrifyTvChannel(
  id: 'comedy',
  name: 'Comedy Club',
  keywords: ['standup'],
  avoidNsfw: true,
  channelNumber: 12,
  createdAt: _fixtureDate,
  updatedAt: _fixtureDate,
);

final _fixtureDate = DateTime.utc(2026);

void main() {
  final surfaces = <({String name, Size size, double textScale})>[
    (name: 'compact phone', size: const Size(320, 700), textScale: 1),
    (
      name: 'compact phone at 200% text',
      size: const Size(320, 700),
      textScale: 2,
    ),
    (name: 'landscape phone', size: const Size(844, 390), textScale: 1),
    (name: 'tablet', size: const Size(820, 1180), textScale: 1),
    (name: 'desktop', size: const Size(1440, 900), textScale: 1),
  ];

  for (final surface in surfaces) {
    testWidgets(
      '${surface.name} stays centered, scrollable, and overflow-free',
      (tester) async {
        await _pumpPhone(
          tester,
          size: surface.size,
          textScale: surface.textScale,
        );

        final search = find.byKey(
          const ValueKey<String>('debrify-tv-phone-search'),
        );
        final searchRect = tester.getRect(search);
        expect(searchRect.center.dx, closeTo(surface.size.width / 2, 0.5));
        expect(searchRect.width, lessThanOrEqualTo(712.1));
        expect(tester.takeException(), isNull);

        final heading = tester.renderObject<RenderParagraph>(
          find.text('Channels'),
        );
        expect(heading.didExceedMaxLines, isFalse);
        expect(find.byTooltip('Settings').hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('compact phone keeps management actions in one row', (
    tester,
  ) async {
    var settingsOpened = false;
    await _pumpPhone(
      tester,
      size: const Size(320, 700),
      onSettings: () => settingsOpened = true,
    );

    final add = tester.getCenter(find.text('Add'));
    final import = tester.getCenter(find.text('Import'));
    final export = tester.getCenter(find.text('Export'));
    final settings = find.byKey(
      const ValueKey<String>('debrify-tv-phone-settings'),
    );

    expect(add.dy, closeTo(import.dy, 0.5));
    expect(import.dy, closeTo(export.dy, 0.5));
    expect(add.dx, lessThan(import.dx));
    expect(import.dx, lessThan(export.dx));
    expect(tester.getCenter(settings).dy, lessThan(add.dy));

    await tester.tap(settings);
    await tester.pump();
    expect(settingsOpened, isTrue);
  });

  for (final surface in <({String name, Size size})>[
    (name: 'mobile', size: const Size(390, 844)),
    (name: 'desktop', size: const Size(1440, 900)),
  ]) {
    testWidgets('${surface.name} Export action invokes channel export', (
      tester,
    ) async {
      var exportOpened = false;
      await _pumpPhone(
        tester,
        size: surface.size,
        onExport: () => exportOpened = true,
        onDeleteAll: _noop,
      );

      await tester.tap(find.text('Export'));
      await tester.pump();

      expect(exportOpened, isTrue);
    });
  }

  testWidgets('large text reflows management and sheet actions', (
    tester,
  ) async {
    await _pumpPhone(tester, size: const Size(320, 700), textScale: 2);

    final add = tester.getCenter(find.text('Add'));
    final import = tester.getCenter(find.text('Import'));
    final export = tester.getCenter(find.text('Export'));
    final settings = tester.getCenter(
      find.byKey(const ValueKey<String>('debrify-tv-phone-settings')),
    );
    expect(add.dy, closeTo(import.dy, 0.5));
    expect(add.dx, lessThan(import.dx));
    expect(export.dy, greaterThan(add.dy));
    expect(settings.dy, lessThan(add.dy));

    await tester.scrollUntilVisible(
      find.text('Space Night'),
      -180,
      scrollable: _touchScrollable,
    );
    await tester.tap(find.text('Space Night'));
    await tester.pumpAndSettle();

    final pin = tester.getCenter(find.text('Pin'));
    final edit = tester.getCenter(find.text('Edit'));
    final share = tester.getCenter(find.text('Share'));
    expect(pin.dx, closeTo(edit.dx, 0.5));
    expect(edit.dx, closeTo(share.dx, 0.5));
    expect(pin.dy, lessThan(edit.dy));
    expect(edit.dy, lessThan(share.dy));

    await tester.scrollUntilVisible(
      find.text('Delete channel'),
      120,
      scrollable: find
          .descendant(
            of: find.byType(SingleChildScrollView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();
    expect(find.text('Delete channel').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('phone search filters by name, keyword, and channel number', (
    tester,
  ) async {
    await _pumpPhone(tester);

    final search = find.byKey(
      const ValueKey<String>('debrify-tv-phone-search'),
    );
    expect(search, findsOneWidget);
    expect(find.text('Space Night'), findsOneWidget);
    expect(find.text('Comedy Club'), findsOneWidget);

    await tester.enterText(search, 'galaxy');
    await tester.pump();

    expect(find.text('1 of 2 channels'), findsOneWidget);
    expect(find.text('Space Night'), findsOneWidget);
    expect(find.text('Comedy Club'), findsNothing);

    await tester.enterText(search, '12');
    await tester.pump();

    expect(find.text('Space Night'), findsNothing);
    expect(find.text('Comedy Club'), findsOneWidget);
  });

  testWidgets('phone channel row has a direct one-tap play action', (
    tester,
  ) async {
    final watched = <String>[];
    await _pumpPhone(tester, onWatch: (channel) => watched.add(channel.id));

    await tester.tap(find.byTooltip('Play Space Night'));
    await tester.pump();

    expect(watched, ['space']);
    expect(find.text('Tune in'), findsNothing);
  });

  testWidgets('phone channel details retain the Tune in play action', (
    tester,
  ) async {
    final watched = <String>[];
    await _pumpPhone(tester, onWatch: (channel) => watched.add(channel.id));

    await tester.tap(find.text('Space Night'));
    await tester.pumpAndSettle();
    expect(find.text('Tune in'), findsOneWidget);

    await tester.tap(find.text('Tune in'));
    await tester.pumpAndSettle();

    expect(watched, ['space']);
    expect(find.text('Tune in'), findsNothing);
  });

  testWidgets('phone search explains an empty result and can be cleared', (
    tester,
  ) async {
    await _pumpPhone(tester);

    final search = find.byKey(
      const ValueKey<String>('debrify-tv-phone-search'),
    );
    await tester.enterText(search, 'documentary');
    await tester.pump();

    expect(find.text('No channels match “documentary”'), findsOneWidget);
    expect(find.text('Space Night'), findsNothing);

    await tester.tap(find.text('Clear search'));
    await tester.pump();

    expect(find.text('Space Night'), findsOneWidget);
    expect(find.text('Comedy Club'), findsOneWidget);
  });
}

Finder get _touchScrollable => find
    .descendant(
      of: find.byKey(const ValueKey<String>('debrify-tv-touch-scroll')),
      matching: find.byType(Scrollable),
    )
    .first;

Future<void> _pumpPhone(
  WidgetTester tester, {
  Size size = const Size(390, 844),
  double textScale = 1,
  ValueChanged<DebrifyTvChannel>? onWatch,
  VoidCallback? onExport,
  VoidCallback? onDeleteAll,
  VoidCallback? onSettings,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final theme = AppThemes.byId('spotlight');
  await tester.pumpWidget(
    MaterialApp(
      theme: AppThemeAdapter.themed(theme, TextBrightness.bright),
      builder: (context, child) => AppThemeScope(
        theme: theme,
        child: MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
      ),
      home: Scaffold(
        body: SpotlightPhoneArm(
          bottomInset: 0,
          view: DebrifyTvView(
            channels: [_space, _comedy],
            favoriteIds: const {},
            railHealth: const <String, DebrifyTvRailHealth>{},
            stats: null,
            busy: false,
            onQuickPlay: _noop,
            onAdd: _noop,
            onImport: _noop,
            onExport: onExport ?? _noop,
            onDeleteAll: onDeleteAll ?? _noop,
            onSettings: onSettings ?? _noop,
            onWatch: onWatch ?? _noopChannel,
            onEdit: _noopChannel,
            onShare: _noopChannel,
            onDelete: _noopChannel,
            onToggleFavorite: _noopChannel,
            onChannelFocused: _noopChannel,
            onWatchOne: _noopTorrent,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void _noop() {}

void _noopChannel(DebrifyTvChannel _) {}

void _noopTorrent(DebrifyTvChannel _, CachedTorrent __) {}
