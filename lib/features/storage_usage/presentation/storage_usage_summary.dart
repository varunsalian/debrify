// The total at the top of the storage page: one bar split by category, with
// a legend underneath.
import 'package:debrify/features/storage_usage/application/storage_usage_report.dart';
import 'package:debrify/features/storage_usage/models/storage_category_text.dart';
import 'package:debrify/features/storage_usage/models/storage_usage_models.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:flutter/material.dart';

/// Fixed hues per category, so a color means the same thing on every scan.
Color storageCategoryColor(StorageCategory category) => switch (category) {
  StorageCategory.iptvCatalogs => const Color(0xFF5B8DEF),
  StorageCategory.debrifyTv => const Color(0xFF9B6BE8),
  StorageCategory.imageCache => const Color(0xFF3FB8A9),
  StorageCategory.guideDownloads => const Color(0xFFE8A23B),
  StorageCategory.guideCache => const Color(0xFFD9C24A),
  StorageCategory.recordings => const Color(0xFFE5677A),
  StorageCategory.downloads => const Color(0xFF6CC56C),
  StorageCategory.logs => const Color(0xFF8A9BB0),
  StorageCategory.preferences => const Color(0xFFC08A5B),
  StorageCategory.otherDatabases => const Color(0xFF4FA3D9),
  StorageCategory.other => const Color(0xFF6E7681),
};

class StorageUsageSummary extends StatelessWidget {
  const StorageUsageSummary({super.key, required this.report});

  final StorageUsageReport report;

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    final t = app.settings;
    final scan = report.scan;
    final categories = sortedStorageCategories(scan);
    final total = scan.totalBytes;
    final time = TimeOfDay.fromDateTime(report.scannedAt).format(context);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: t.panel,
        borderRadius: app.shape.br(14),
        border: Border.all(color: t.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            formatStorageBytes(total),
            style: TextStyle(
              fontSize: 30,
              fontWeight: FontWeight.w800,
              color: app.core.tx,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '${scan.fileCount} files · scanned at $time',
            style: TextStyle(fontSize: 12, color: t.dim),
          ),
          const SizedBox(height: 14),
          Semantics(
            label: 'Storage split by kind',
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: SizedBox(
                height: 12,
                child: total == 0
                    ? ColoredBox(color: t.panel2)
                    : Row(
                        children: [
                          for (final entry in categories)
                            Flexible(
                              // At least one flex unit so a tiny slice still
                              // shows; the legend carries the exact sizes.
                              flex: (entry.value * 1000 / total).ceil(),
                              child: ColoredBox(
                                color: storageCategoryColor(entry.key),
                              ),
                            ),
                        ],
                      ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 14,
            runSpacing: 6,
            children: [
              for (final entry in categories)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 9,
                      height: 9,
                      decoration: BoxDecoration(
                        color: storageCategoryColor(entry.key),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      entry.key.label,
                      style: TextStyle(fontSize: 11.5, color: t.dim),
                    ),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }
}
