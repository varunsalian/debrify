import 'dart:async';
import 'package:debrify/services/main_page_bridge.dart';
import 'package:debrify/services/storage/tv_display_storage.dart';
import 'package:debrify/utils/platform_util.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import '../../../../support/alldebrid_files_fixture.dart';

void main() {
  setUp(() {
    PlatformUtil.debugSetAndroidTvCached(true);
    TvDisplayStorage.tvKeyboardEnabledCached = false;
  });
  tearDown(() {
    PlatformUtil.debugSetAndroidTvCached(null);
    TvDisplayStorage.tvKeyboardEnabledCached = true;
  });
  testWidgets(
    'root search hardware Up Down Right clear Left and Enter restore real focus',
    (t) => allDebridCase(t, (f) async {
      await f.mount(t);
      await f.search(t, 'Library');
      expect(f.focus('searchFocusNode').hasFocus, isTrue);
      await t.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await t.pump();
      expect(f.focus('toolbarSearchFocusNode').hasFocus, isTrue);
      f.focus('searchFocusNode').requestFocus();
      await t.pump();
      await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await t.pump();
      expect(f.focus('firstItemFocusNode').hasFocus, isTrue);
      f.focus('searchFocusNode').requestFocus();
      await t.pump();
      await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await t.pump();
      expect(f.focus('searchClearFocusNode').hasFocus, isTrue);
      await t.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await t.pump();
      expect(f.focus('searchFocusNode').hasFocus, isTrue);
      expect(f.member('searchQuery'), 'Library');
      await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await t.pump();
      await t.sendKeyEvent(LogicalKeyboardKey.enter);
      await t.pump();
      expect(f.member('searchQuery'), '');
      expect(t.widget<TextField>(find.byType(TextField)).controller!.text, '');
      expect(f.focus('searchFocusNode').hasFocus, isTrue);
      expect(f.member('visibleMagnets') as List, hasLength(3));
      expect(f.log, [adList()]);
    }),
  );
  testWidgets(
    'file search hardware Up Down exits to Back and the first file',
    (t) => allDebridCase(t, (f) async {
      await f.mount(t);
      await f.open(t);
      await f.search(t, 'S01', file: true);
      expect(f.focus('fileSearchFocusNode').hasFocus, isTrue);
      await t.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await t.pump();
      expect(f.focus('backButtonFocusNode').hasFocus, isTrue);
      f.focus('fileSearchFocusNode').requestFocus();
      await t.pump();
      await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await t.pump();
      expect(f.focus('firstItemFocusNode').hasFocus, isTrue);
      expect(f.member('fileSearchQuery'), 'S01');
      expect(f.log, [adList(), adFiles('z9')]);
    }),
  );
  for (final web in [false, true]) {
    testWidgets(
      'add dialog hardware Down leaves the field for actions web=$web',
      (t) => allDebridCase(t, (f) async {
        await f.mount(t);
        if (web) {
          await f.web(t);
        }
        await f.tap(t, find.byTooltip(web ? 'Add link' : 'Add magnet link'));
        final editable = t.widget<EditableText>(find.byType(EditableText));
        expect(editable.focusNode.hasFocus, isTrue);
        await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await t.pump();
        expect(editable.focusNode.hasFocus, isFalse);
        final target = FocusManager.instance.primaryFocus?.context;
        expect(target, isNotNull);
        expect(target!.findAncestorWidgetOfExactType<TextButton>(), isNotNull);
        await f.tap(t, find.text('Cancel'));
        expect(f.log, [adList(), if (web) adLinks()]);
      }),
    );
  }
  testWidgets(
    'TV focus request before a held initial load focuses first row only after load',
    (t) => allDebridCase(t, (f) async {
      final held = Completer<http.Response>();
      f.held['/v4.1/magnet/status'] = held;
      await f.mount(t);
      await f.until(t, () => f.requests.length == 1);
      expect(MainPageBridge.requestTvContentFocus(), isTrue);
      await t.pump();
      expect(f.member('shouldFocusOnLoad'), isTrue);
      expect(f.focus('firstItemFocusNode').hasFocus, isFalse);
      held.complete(f.listResponse());
      await f.until(t, () => f.member('loading') == false);
      await t.pump();
      await t.pump();
      expect(f.focus('firstItemFocusNode').hasFocus, isTrue);
      expect(f.member('shouldFocusOnLoad'), isFalse);
      expect(f.log, [adList()]);
    }),
  );
}
