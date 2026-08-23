import 'package:debrify/services/mdblist/mdblist_menu_helpers.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('paused title exposes MDBList Continue Watching removal', () {
    final options = buildMdblistMenuOptions(
      authenticated: true,
      isSeries: false,
      inContinueWatching: true,
    );

    expect(
      options.map((option) => option.action),
      contains(MdblistItemMenuAction.removeFromContinueWatching),
    );
  });

  test('non-playback title does not expose Continue Watching removal', () {
    final options = buildMdblistMenuOptions(
      authenticated: true,
      isSeries: false,
    );

    expect(
      options.map((option) => option.action),
      isNot(contains(MdblistItemMenuAction.removeFromContinueWatching)),
    );
  });
}
