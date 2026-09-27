import '../../../models/advanced_search_selection.dart';

/// One answer shared by the detail Resume label and the Play action.
/// Source priority preserves attribution even when a finished episode advances:
/// 0 Trakt, 1 Simkl, 2 MDBList, 3 local, null for a fallback or fresh title.
typedef HomeSeriesResumeResult = ({
  bool started,
  int season,
  int episode,
  double? simklProgress,
  AdvancedSearchSelection? selection,
  int? sourcePrio,
});

/// An actual saved/paused position, before winner selection and advancement.
/// A retained original selection carries tracker percentages into playback.
typedef HomeSeriesResumeCandidate = ({
  int sourcePriority,
  int? timestampMs,
  int season,
  int episode,
  double? progress,
  bool finished,
  AdvancedSearchSelection? selection,
});
