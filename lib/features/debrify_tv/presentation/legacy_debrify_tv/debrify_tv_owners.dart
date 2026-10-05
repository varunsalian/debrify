import 'package:debrify/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_focus_state.dart';
import 'package:debrify/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_library_state.dart';
import 'package:debrify/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_prefetch_state.dart';
import 'package:debrify/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_progress_state.dart';
import 'package:debrify/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_session_state.dart';
import 'package:debrify/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_settings_state.dart';
import 'package:debrify/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_stage_state.dart';

class DebrifyTvOwners {
  final DebrifyTvLibraryState library = DebrifyTvLibraryState();
  final DebrifyTvStageState stage = DebrifyTvStageState();
  final DebrifyTvSettingsState settings = DebrifyTvSettingsState();
  final DebrifyTvSessionState session = DebrifyTvSessionState();
  final DebrifyTvPrefetchState prefetch = DebrifyTvPrefetchState();
  final DebrifyTvProgressState progress = DebrifyTvProgressState();
  final DebrifyTvFocusState focus = DebrifyTvFocusState();
}
