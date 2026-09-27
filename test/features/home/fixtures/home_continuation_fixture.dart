import 'package:debrify/features/home/application/home_local_continuation_controller.dart';
import 'package:debrify/features/home/data/home_local_continuation_repository.dart';
import 'package:debrify/features/home/models/home_continuation_session.dart';
import 'package:debrify/features/home/models/home_local_continuation_state.dart';
import 'package:debrify/models/tracking_source.dart';
import 'package:debrify/services/profiles/profile_session_memory.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

export 'package:debrify/features/home/application/home_local_continuation_controller.dart';
export 'package:debrify/features/home/application/home_local_continuation_dependencies.dart';
export 'package:debrify/features/home/models/home_continuation_session.dart';
export 'package:debrify/models/tracking_source.dart';
export 'package:debrify/services/profiles/profile_session_memory.dart';
export 'package:flutter_riverpod/flutter_riverpod.dart';

HomeLocalContinuationRepository continuationRepository({
  required Future<List<Map<String, dynamic>>> Function() readItems,
  Future<WatchProgressSource> Function()? readSource,
  Future<bool> Function()? readEnabled,
}) => HomeLocalContinuationRepository(
  readProgressSource: readSource ?? () async => WatchProgressSource.local,
  readEnabled: readEnabled ?? () async => true,
  readItems: readItems,
  readAddons: () => throw StateError('Unexpected addons'),
  readEpisode: (_) async => null,
  readMovie: (_) async => null,
);

List<Map<String, dynamic>> history(String title) => [
  {'imdbId': title, 'title': title},
  {
    'imdbId': '$title-series',
    'contentType': 'series',
    'title': '$title-series',
  },
];

HomeContinuationSession continuationSession() => HomeContinuationSession(
  owner: ProfileSessionMemory.captureOwner(),
  viewIdentity: Object(),
);

HomeLocalContinuationController mountContinuation(
  ProviderContainer container,
  HomeContinuationSession session,
) {
  container.listen(homeLocalContinuationProvider(session), (_, _) {});
  return container.read(homeLocalContinuationProvider(session).notifier);
}

Future<void> loadContinuation(
  HomeLocalContinuationController controller, {
  bool Function()? isCurrent,
  void Function()? sourceChanged,
  Future<void> Function()? beforeEnabledRows,
  void Function(HomeLocalContinuationState)? beforeRows,
  void Function(HomeLocalContinuationState, bool Function())? onRows,
}) => controller.load(
  isCurrent: isCurrent ?? () => true,
  onProgressSourceChanged: sourceChanged ?? () {},
  beforeEnabledRows: beforeEnabledRows ?? () async {},
  beforeRows: beforeRows ?? (_) {},
  onRows: onRows ?? (_, _) {},
);
