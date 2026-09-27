import '../../../models/advanced_search_selection.dart';

/// Trakt's original launch selection plus its activity time for reconciliation.
typedef HomeTraktResumeSignal = ({AdvancedSearchSelection sel, int? tsMs});

typedef HomeSimklResumeSignal = ({
  int season,
  int episode,
  double? progress,
  DateTime? pausedAt,
});

typedef HomeLocalResumeSignal = ({
  int season,
  int episode,
  double? pct,
  int? tsMs,
  bool finished,
});

/// A label can be started even when its tracker selection lacks coordinates.
typedef HomeResumePosition = ({bool started, int? season, int? episode});

/// Evaluated after tracking-policy reads, preserving auth-settlement timing.
typedef HomeResumeAvailability = ({bool trakt, bool simkl, bool mdblist});
