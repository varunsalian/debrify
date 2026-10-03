import 'iptv_status_chip_types.dart';

class IptvLoadStatusPolicy {
  static String formatLoadBytes(int bytes) {
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    if (bytes >= 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '$bytes B';
  }

  static String formatLoadElapsed(Duration d) {
    final minutes = d.inMinutes;
    final seconds = d.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  /// "12.4 / 50.0 MB" when the transfer is observable, "42.1 MB" when only the
  /// landed size is known, null when there is no honest number to show — a
  /// buffered fetch that has not landed yet must not imply progress it cannot
  /// measure.

  static String? loadBytesLabel(int? bytes, int? totalBytes) {
    if (bytes == null) return null;
    if (totalBytes != null && totalBytes > 0) {
      return '${formatLoadBytes(bytes)} / ${formatLoadBytes(totalBytes)}';
    }
    if (bytes == 0) return null;
    return formatLoadBytes(bytes);
  }

  /// Whether a stage owning [incoming] may take the chip from [current].
  /// Pure, so the priority rule is testable without pumping the page.

  static bool chipClaimAllowed(int current, int incoming) =>
      incoming >= current;

  /// Priority ranks, exposed for the same reason.

  static int get chipRankNone => ChipOwner.none.index;

  static int get chipRankGuide => ChipOwner.guide.index;

  static int get chipRankMaintenance => ChipOwner.maintenance.index;

  static int get chipRankRefresh => ChipOwner.refresh.index;
}
