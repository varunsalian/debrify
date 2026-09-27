import 'package:collection/collection.dart';

import '../../../models/home_preferences.dart';
import '../../../services/home_list_rows.dart';
import '../../../services/home_row_order.dart';
import '../models/home_catalog_preferences.dart';

typedef HomeConfigurationChanges = ({
  bool changed,
  bool reloadBoard,
  bool reloadHero,
  bool reloadIptv,
});

/// Decide which data families need refreshing. The caller owns committing the
/// new configuration and dispatching effects after its request/profile checks.
HomeConfigurationChanges homeConfigurationChanges({
  required HomeCatalogPreferences previous,
  required HomeCatalogPreferences next,
  required bool previousHideWatched,
  required bool hideWatched,
  required String previousCollectionsSignature,
  required String collectionsSignature,
  required bool isHome,
}) {
  final disabledSame =
      previous.disabled.length == next.disabled.length &&
      next.disabled.containsAll(previous.disabled);
  final heroSame =
      previous.heroSource.mode == next.heroSource.mode &&
      const ListEquality<String>().equals(
        previous.heroSource.ids,
        next.heroSource.ids,
      );
  final orderSame = HomeRowOrder.equals(previous.rowOrder, next.rowOrder);
  final watchedSame = previousHideWatched == hideWatched;
  final collectionsSame = previousCollectionsSignature == collectionsSignature;
  List<HomeExtraRow> family(List<HomeExtraRow> rows, bool iptv) => [
    for (final row in rows)
      if (HomeExtraRowIds.isIptv(row.id) == iptv) row,
  ];
  // Record equality compares id and title; order remains significant within a
  // family. Moving an IPTV row across a tracker row alone changes neither.
  final boardExtrasSame = const ListEquality<HomeExtraRow>().equals(
    family(previous.extras, false),
    family(next.extras, false),
  );
  final iptvExtrasSame = const ListEquality<HomeExtraRow>().equals(
    family(previous.extras, true),
    family(next.extras, true),
  );
  final reloadBoard =
      !disabledSame ||
      !boardExtrasSame ||
      !watchedSame ||
      !collectionsSame ||
      (!orderSame && isHome);
  return (
    changed:
        !disabledSame ||
        !heroSame ||
        !orderSame ||
        !watchedSame ||
        !collectionsSame ||
        !boardExtrasSame ||
        !iptvExtrasSame,
    reloadBoard: reloadBoard,
    reloadHero: !reloadBoard && !heroSame && isHome,
    reloadIptv: !iptvExtrasSame,
  );
}
