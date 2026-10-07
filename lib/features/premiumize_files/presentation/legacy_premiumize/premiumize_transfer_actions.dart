import 'dart:async';

import 'package:debrify/models/premiumize_transfer.dart';
import 'package:debrify/services/premiumize_service.dart';
import 'package:flutter/material.dart';

import 'premiumize_catalog_state.dart';

typedef PremiumizeTransferActionsDeps = ({
  PremiumizeCatalogState catalogState,
  BuildContext Function() context,
  bool Function() mounted,
  void Function(VoidCallback) setState,
  void Function(String message, {bool isError, Duration? duration})
  showSnackBar,
  Future<void> Function() loadTransfers,
});

class PremiumizeTransferActions {
  PremiumizeTransferActions(this._deps);
  final PremiumizeTransferActionsDeps _deps;

  // ── Transfers ────────────────────────────────────────────────────────────────

  Future<void> deleteTransfer(PremiumizeTransfer transfer) async {
    final apiKey = _deps.catalogState.apiKey;
    if (apiKey == null || apiKey.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: _deps.context(),
      builder: (context) => AlertDialog(
        title: const Text('Delete Transfer'),
        content: Text('Remove "${transfer.name}" from your transfers?'),
        actions: [
          TextButton(
            autofocus: true,
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await PremiumizeService.deleteTransfer(apiKey, transfer.id);
      if (!_deps.mounted()) return;
      _deps.setState(
        () => _deps.catalogState.transfers.removeWhere(
          (t) => t.id == transfer.id,
        ),
      );
      _deps.showSnackBar('Transfer removed', isError: false);
    } catch (e) {
      _deps.showSnackBar('Failed to remove transfer: $e', isError: true);
    }
  }

  Future<void> clearFinishedTransfers() async {
    final apiKey = _deps.catalogState.apiKey;
    if (apiKey == null || apiKey.isEmpty) return;
    try {
      await PremiumizeService.clearFinishedTransfers(apiKey);
      _deps.showSnackBar('Cleared finished transfers', isError: false);
      await _deps.loadTransfers();
    } catch (e) {
      _deps.showSnackBar('Failed to clear: $e', isError: true);
    }
  }
}
