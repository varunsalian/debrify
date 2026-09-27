import 'package:flutter/material.dart';
import '../../../models/series_source.dart';
import '../../../theme/app_theme_scope.dart';

/// One bound-source row for the edit dialog (index badge, name, provider
/// chip, delete). Ported from the catalog/aggregated detail flow.
Widget buildHomeBoundSourceTile(
  BuildContext context, {
  required Key key,
  required SeriesSource source,
  required int index,
  required VoidCallback onDelete,
  bool showDragHandle = true,
}) {
  final app = AppThemeScope.of(context);
  Color serviceColor;
  String serviceLabel;
  switch (source.debridService) {
    case 'rd':
      serviceColor = const Color(0xFF10B981);
      serviceLabel = 'Real-Debrid';
    case 'torbox':
      serviceColor = const Color(0xFF3B82F6);
      serviceLabel = 'TorBox';
    case 'pikpak':
      serviceColor = const Color(0xFFF59E0B);
      serviceLabel = 'PikPak';
    case 'premiumize':
      serviceColor = const Color(0xFFFB923C);
      serviceLabel = 'Premiumize';
    case 'alldebrid':
      serviceColor = const Color(0xFF26A69A);
      serviceLabel = 'AllDebrid';
    case SeriesSource.localService:
      serviceColor = const Color(0xFF60A5FA);
      serviceLabel = 'Local';
    case SeriesSource.addonDirectService:
      serviceColor = const Color(0xFFA78BFA);
      serviceLabel = 'Direct addon';
    case SeriesSource.iptvDirectService:
      serviceColor = const Color(0xFFEF4444);
      serviceLabel = 'IPTV';
    default:
      serviceColor = Colors.white54;
      serviceLabel = source.debridService;
  }

  return Container(
    key: key,
    margin: const EdgeInsets.only(bottom: 6),
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    decoration: BoxDecoration(
      color: app.fade(app.core.tx, 0.05),
      borderRadius: app.shape.br(8),
      border: Border.all(color: app.fade(app.core.tx, 0.08)),
    ),
    child: Row(
      children: [
        if (showDragHandle) ...[
          Container(
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: const Color(0xFF60A5FA).withValues(alpha: 0.15),
              borderRadius: app.shape.br(6),
            ),
            child: Text(
              '${index + 1}',
              style: const TextStyle(
                color: Color(0xFF60A5FA),
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 8),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                source.torrentName,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 3),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: serviceColor.withValues(alpha: 0.15),
                  borderRadius: app.shape.br(3),
                ),
                child: Text(
                  serviceLabel,
                  style: TextStyle(
                    color: serviceColor,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
        IconButton(
          icon: Icon(Icons.close_rounded, size: 16, color: app.home.danger),
          onPressed: onDelete,
          tooltip: 'Remove source',
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
        ),
        if (showDragHandle)
          Icon(
            Icons.drag_handle_rounded,
            size: 18,
            color: app.core.tx.withValues(alpha: 0x3D / 0xFF),
          ),
      ],
    ),
  );
}
