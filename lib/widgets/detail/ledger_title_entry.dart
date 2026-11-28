import 'package:debrify/features/ledger/application/ledger_title_controller.dart';
import 'package:debrify/features/ledger/models/ledger_title.dart';
import 'package:debrify/features/merged_detail/presentation/merged_ledger_sheet.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Debrify's own tracker on a detail page: joins the tracker's title state to
/// the detail page's sheet. It lives outside `lib/features` because it wires
/// two features together.
///
/// It draws nothing until the tracker is connected and can name the title;
/// each layout supplies its own pill through [builder] and gets the live
/// status plus the tap that opens the sheet.
class LedgerTitleEntry extends StatelessWidget {
  const LedgerTitleEntry({
    super.key,
    required this.titleKey,
    required this.title,
    required this.isTelevision,
    required this.builder,
    this.onWatchedChanged,
  });

  final LedgerTitleKey titleKey;
  final String title;
  final bool isTelevision;

  /// Called once the tracker accepted a change to what is watched, so the
  /// page can refresh its badges and resume label.
  final VoidCallback? onWatchedChanged;
  final Widget Function(
    BuildContext context,
    LedgerTitleStatus status,
    VoidCallback onTap,
  )
  builder;

  /// The title's key: its resolved IMDb id when it has one, else the addon's.
  static LedgerTitleKey keyFor(StremioMeta item) =>
      (imdbId: item.imdbId ?? item.id, contentType: item.type);

  @override
  Widget build(BuildContext context) => LedgerTitleHost(
    titleKey: titleKey,
    title: title,
    isTelevision: isTelevision,
    onWatchedChanged: onWatchedChanged,
    builder: (context, status, onTap) => status == null || onTap == null
        ? const SizedBox.shrink()
        : builder(context, status, onTap),
  );
}

/// The state behind [LedgerTitleEntry], for a layout that needs to know
/// whether the tracker has a button before it builds (Showcase sizes its
/// focus nodes from that). [builder] always runs; its status and tap are null
/// while the tracker is off, signed out or cannot name the title.
class LedgerTitleHost extends StatelessWidget {
  const LedgerTitleHost({
    super.key,
    required this.titleKey,
    required this.title,
    required this.isTelevision,
    required this.builder,
    this.onWatchedChanged,
  });

  final LedgerTitleKey titleKey;
  final String title;
  final bool isTelevision;
  final VoidCallback? onWatchedChanged;
  final Widget Function(
    BuildContext context,
    LedgerTitleStatus? status,
    VoidCallback? onTap,
  )
  builder;

  @override
  Widget build(BuildContext context) {
    // A host mounted outside the app's provider scope (a bare detail page in
    // a widget test) has no tracker state to read, so it gets no button.
    if (context.findAncestorWidgetOfExactType<UncontrolledProviderScope>() ==
        null) {
      return builder(context, null, null);
    }
    return Consumer(
      builder: (context, ref, _) {
        final state = ref.watch(ledgerTitleControllerProvider(titleKey)).value;
        if (state == null || !state.available) {
          return builder(context, null, null);
        }
        return builder(context, state.status, () => _open(context));
      },
    );
  }

  void _open(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppThemeScope.of(context).sheetSurface,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => Consumer(
        builder: (context, ref, _) {
          final provider = ledgerTitleControllerProvider(titleKey);
          final state = ref.watch(provider).value;
          final controller = ref.read(provider.notifier);
          Future<void> watched(Future<bool> Function() change) async {
            if (await change()) onWatchedChanged?.call();
          }

          return MergedLedgerSheet(
            title: title,
            isSeries: titleKey.contentType == 'series',
            isTelevision: isTelevision,
            status: state?.status ?? const LedgerTitleStatus(),
            busy: state == null || state.busy,
            onPlanned: controller.setPlanned,
            onCompleted: (completed) =>
                watched(() => controller.setCompleted(completed)),
            onDropped: controller.setDropped,
            onRate: controller.rate,
            onClearProgress: () => watched(controller.clearProgress),
          );
        },
      ),
    );
  }
}
