import 'package:debrify/models/premiumize_folder_item.dart';
import 'package:debrify/models/premiumize_transfer.dart';

class PremiumizeCatalogState {
  String? apiKey;

  bool premiumizeEnabled = false;

  bool isLoading = false;

  bool initialLoad = true;

  String errorMessage = '';

  // Cloud files state.
  final List<PremiumizeFolderItem> items = [];

  // Transfers state.
  final List<PremiumizeTransfer> transfers = [];

  bool isLoadingTransfers = false;
}
