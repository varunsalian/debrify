import 'package:flutter/material.dart';

import '../../services/transfer/transfer_category.dart';

/// Material icons for [TransferCategoryGlyph]. The service layer carries the
/// semantic glyph id; this is the only place it becomes an [IconData].
extension TransferCategoryGlyphIcon on TransferCategoryGlyph {
  IconData get icon => switch (this) {
    TransferCategoryGlyph.speed => Icons.speed,
    TransferCategoryGlyph.inventory2 => Icons.inventory_2,
    TransferCategoryGlyph.workspacePremium => Icons.workspace_premium_rounded,
    TransferCategoryGlyph.allInclusive => Icons.all_inclusive_rounded,
    TransferCategoryGlyph.cloud => Icons.cloud,
    TransferCategoryGlyph.history => Icons.history_rounded,
    TransferCategoryGlyph.movieFilter => Icons.movie_filter_rounded,
    TransferCategoryGlyph.listAlt => Icons.list_alt_rounded,
    TransferCategoryGlyph.search => Icons.search,
    TransferCategoryGlyph.extension => Icons.extension,
    TransferCategoryGlyph.dns => Icons.dns_rounded,
    TransferCategoryGlyph.manageSearch => Icons.manage_search_rounded,
    TransferCategoryGlyph.liveTv => Icons.live_tv_rounded,
    TransferCategoryGlyph.star => Icons.star_rounded,
    TransferCategoryGlyph.playlistPlay => Icons.playlist_play_rounded,
    TransferCategoryGlyph.folderSpecial => Icons.folder_special_rounded,
    TransferCategoryGlyph.sell => Icons.sell_rounded,
    TransferCategoryGlyph.syncAlt => Icons.sync_alt_rounded,
  };
}

/// Widget-side chrome for a [TransferCategory]: its Material icon.
extension TransferCategoryChrome on TransferCategory {
  IconData get icon => glyph.icon;
}
