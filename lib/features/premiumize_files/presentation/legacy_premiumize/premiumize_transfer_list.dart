import 'dart:async';

import 'package:debrify/models/premiumize_transfer.dart';
import 'package:debrify/screens/debrify_tv/widgets/tv_focus_scroll_wrapper.dart';
import 'package:debrify/theme/app_theme.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:flutter/material.dart';

import 'premiumize_catalog_state.dart';

typedef PremiumizeTransferListDeps = ({
  PremiumizeCatalogState catalogState,
  BuildContext Function() context,
  Future<void> Function() clearFinishedTransfers,
  Future<void> Function(PremiumizeTransfer transfer) deleteTransfer,
});

class PremiumizeTransferList {
  PremiumizeTransferList(this._deps);
  final PremiumizeTransferListDeps _deps;

  Widget buildTransfersList() {
    if (_deps.catalogState.isLoadingTransfers &&
        _deps.catalogState.transfers.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_deps.catalogState.transfers.isEmpty) {
      return ListView(
        children: [
          const SizedBox(height: 120),
          Center(
            child: Column(
              children: [
                Icon(
                  Icons.swap_vert_rounded,
                  size: 64,
                  color: Colors.grey.shade400,
                ),
                const SizedBox(height: 16),
                Text(
                  'No Transfers',
                  style: Theme.of(_deps.context()).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                Text(
                  'Magnets you add appear here while they download.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
        ],
      );
    }

    final app = AppThemeScope.of(_deps.context());
    final hasFinished = _deps.catalogState.transfers.any((t) => t.isFinished);
    return Column(
      children: [
        if (hasFinished)
          Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: TextButton.icon(
                onPressed: _deps.clearFinishedTransfers,
                icon: const Icon(Icons.cleaning_services_outlined, size: 18),
                label: const Text('Clear finished'),
              ),
            ),
          ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: _deps.catalogState.transfers.length,
            itemBuilder: (context, index) =>
                buildTransferCard(_deps.catalogState.transfers[index], app),
          ),
        ),
      ],
    );
  }

  Widget buildTransferCard(PremiumizeTransfer transfer, AppTheme app) {
    Color statusColor;
    IconData statusIcon;
    if (transfer.isFinished) {
      statusColor = const Color(0xFF22C55E);
      statusIcon = Icons.check_circle_outline;
    } else if (transfer.isError) {
      statusColor = const Color(0xFFEF4444);
      statusIcon = Icons.error_outline;
    } else {
      statusColor = const Color(0xFFFB923C);
      statusIcon = Icons.downloading_rounded;
    }

    return TvFocusScrollWrapper(
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
        decoration: BoxDecoration(
          color: app.fade(app.core.tx, 0.05),
          borderRadius: app.shape.br(12),
          border: Border.all(color: app.fade(app.core.tx, 0.07)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(statusIcon, color: statusColor),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    transfer.name,
                    style: const TextStyle(
                      fontWeight: FontWeight.w500,
                      fontSize: 14,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  icon: const Icon(
                    Icons.delete_outline,
                    size: 20,
                    color: Colors.red,
                  ),
                  tooltip: 'Delete transfer',
                  onPressed: () => _deps.deleteTransfer(transfer),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (transfer.isRunning) ...[
              ClipRRect(
                borderRadius: app.shape.br(4),
                child: LinearProgressIndicator(
                  value: transfer.progress > 0 ? transfer.progress : null,
                  minHeight: 5,
                  backgroundColor: app.fade(app.core.tx, 0.08),
                  valueColor: AlwaysStoppedAnimation(statusColor),
                ),
              ),
              const SizedBox(height: 6),
            ],
            Text(
              transfer.message ??
                  (transfer.isFinished
                      ? 'Finished'
                      : transfer.isError
                      ? 'Error'
                      : '${transfer.progressPercent}%'),
              style: TextStyle(color: statusColor, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}
