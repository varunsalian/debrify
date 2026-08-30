import 'package:flutter/material.dart';

import '../../theme/app_theme_scope.dart';
import '../../utils/tv_keys.dart';

/// The two manual source searches available from a series' primary Play hold.
enum DetailPrimarySourceChoice { seasonPacks, episode }

/// Asks which kind of series sources to show after the user holds Play.
///
/// The sheet is wrapped in [TvHeldKeyGuard] because a remote hold opens it
/// while OK is still down. Without the guard, the first key repeat can
/// immediately activate the autofocused first row.
Future<DetailPrimarySourceChoice?> showDetailPrimarySourcesSheet(
  BuildContext context, {
  required String title,
  required bool isTelevision,
  String? episodeLabel,
}) {
  final app = AppThemeScope.of(context);
  return showModalBottomSheet<DetailPrimarySourceChoice>(
    context: context,
    backgroundColor: app.sheetSurface,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) => TvHeldKeyGuard(
      child: SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 2, 20, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Choose sources',
                      style: TextStyle(
                        color: app.core.tx,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: app.fade(app.core.tx, 0.45),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              _SourceChoiceRow(
                autofocus: isTelevision,
                icon: Icons.inventory_2_rounded,
                label: 'Season pack sources',
                description: 'Browse complete-series and full-season results.',
                onTap: () => Navigator.of(
                  sheetContext,
                ).pop(DetailPrimarySourceChoice.seasonPacks),
              ),
              _SourceChoiceRow(
                icon: Icons.video_library_rounded,
                label: 'Episode sources',
                description: episodeLabel == null
                    ? 'Browse sources for the episode Play would open.'
                    : 'Browse sources for $episodeLabel.',
                onTap: () => Navigator.of(
                  sheetContext,
                ).pop(DetailPrimarySourceChoice.episode),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    ),
  );
}

class _SourceChoiceRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String description;
  final VoidCallback onTap;
  final bool autofocus;

  const _SourceChoiceRow({
    required this.icon,
    required this.label,
    required this.description,
    required this.onTap,
    this.autofocus = false,
  });

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        autofocus: autofocus,
        focusColor: app.fade(app.core.tx, 0.12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 13, 18, 13),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Icon(icon, color: app.core.tx, size: 24),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        color: app.core.tx,
                        fontSize: 15.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      description,
                      style: TextStyle(
                        color: app.fade(app.core.tx, 0.5),
                        fontSize: 13,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
