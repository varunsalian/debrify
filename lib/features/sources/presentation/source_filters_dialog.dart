import 'package:flutter/material.dart';

import '../../../models/torrent_filter_state.dart';
import '../../../widgets/torrent_filters_sheet.dart';

/// The modal owns its input snapshot; rebuilding never reads the opening view.
Future<TorrentFilterState?> showSourceFiltersDialog(
  BuildContext context, {
  required TorrentFilterState initialState,
  required bool isSeries,
}) => showDialog<TorrentFilterState>(
  context: context,
  builder: (_) => Dialog(
    backgroundColor: Colors.transparent,
    child: TorrentFiltersSheet(
      initialState: initialState,
      sizeNote: isSeries
          ? 'Not applied to series — pack sizes are per-episode.'
          : 'Applies to movies only — ignored for series.',
    ),
  ),
);
