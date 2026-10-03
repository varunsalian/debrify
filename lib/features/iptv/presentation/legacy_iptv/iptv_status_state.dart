import 'dart:async';

import 'package:debrify/features/iptv/application/iptv_status_chip_types.dart';

class IptvStatusState {
  // Background catalog refresh (stale-while-revalidate) status chip.
  // `updating` appears only when the revalidate is genuinely slow (a real
  // network fetch), so instant in-memory-cache revalidates never flash it.
  CatalogChipState chipState = CatalogChipState.hidden;

  String chipMessage = '';

  // ── Blocking-load status ────────────────────────────────────────────────
  // A first load of a big panel is several seconds behind a spinner, and
  // silence reads as "frozen". These carry what is happening plus a real
  // number when one exists.
  //
  // Deliberately NOT setState-ed per update: byte callbacks fire per network
  // chunk, and repainting on each would be exactly the UI-isolate churn this
  // page has spent so long shedding. They are plain fields, and [_loadTicker]
  // repaints once a second — which also makes the elapsed clock tick.
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
