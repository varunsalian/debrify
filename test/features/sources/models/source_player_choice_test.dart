import 'package:debrify/features/sources/models/source_player_choice.dart';
import 'package:debrify/features/sources/models/source_row_actions.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  SourcePlayerChoice? other(
    String mode,
    SourceRowActionKind kind, {
    bool externalAllowed = true,
  }) => SourcePlayerChoice.alternateTo(
    mode,
    kind: kind,
    externalAllowed: externalAllowed,
  );

  test('the built-in default offers the external player', () {
    for (final kind in [
      SourceRowActionKind.torrent,
      SourceRowActionKind.addon,
      SourceRowActionKind.iptv,
    ]) {
      expect(
        other('debrify', kind),
        SourcePlayerChoice.external,
        reason: '$kind',
      );
    }
  });

  test('an external or DeoVR default offers the Debrify player', () {
    expect(
      other('external', SourceRowActionKind.torrent),
      SourcePlayerChoice.debrify,
    );
    expect(
      other('deovr', SourceRowActionKind.addon),
      SourcePlayerChoice.debrify,
    );
    // Even where external players are off, the way back stays available.
    expect(
      other('external', SourceRowActionKind.iptv, externalAllowed: false),
      SourcePlayerChoice.debrify,
    );
  });

  test('no external offer where it cannot work or is not allowed', () {
    expect(
      other('debrify', SourceRowActionKind.torrent, externalAllowed: false),
      isNull,
    );
    // Media-server streams always play in Debrify: no offer either way.
    expect(other('debrify', SourceRowActionKind.mediaServer), isNull);
    expect(other('external', SourceRowActionKind.mediaServer), isNull);
    // Browser links have no player at all.
    expect(other('debrify', SourceRowActionKind.external), isNull);
    expect(other('external', SourceRowActionKind.external), isNull);
  });

  test('modes match the launcher setting values', () {
    expect(SourcePlayerChoice.debrify.mode, 'debrify');
    expect(SourcePlayerChoice.external.mode, 'external');
  });
}
