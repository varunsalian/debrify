import 'package:debrify/features/stremio_tv/presentation/legacy_stremio_tv/stremio_tv_focus_state.dart';

import 'package:debrify/features/stremio_tv/presentation/legacy_stremio_tv/stremio_tv_library_state.dart';

import 'package:debrify/features/stremio_tv/presentation/legacy_stremio_tv/stremio_tv_playback_state.dart';

import 'package:debrify/features/stremio_tv/presentation/legacy_stremio_tv/stremio_tv_settings_state.dart';

class StremioTvOwners {
  final StremioTvLibraryState library = StremioTvLibraryState();
  final StremioTvSettingsState settings = StremioTvSettingsState();
  final StremioTvPlaybackState playback = StremioTvPlaybackState();
  final StremioTvFocusState focus = StremioTvFocusState();
}
