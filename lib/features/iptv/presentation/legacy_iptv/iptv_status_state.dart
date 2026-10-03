import 'dart:async';

import 'package:debrify/features/iptv/application/iptv_status_chip_types.dart';

class IptvStatusState {
  CatalogChipState chipState = CatalogChipState.hidden;

  String chipMessage = '';

  String? loadPhase;

  int? loadBytes;

  int? loadTotalBytes;

  DateTime? loadStartedAt;

  Timer? loadTicker;

  /// Past this, a load is slow enough that the user deserves to be told it is
  /// normal rather than left guessing.
  static const slowLoadHint = Duration(seconds: 10);

  ChipOwner chipOwner = ChipOwner.none;

  Timer? chipShowTimer;

  Timer? maintenanceChipTimer;

  Timer? chipHideTimer;

  int lastGuideMb = -1;
}
