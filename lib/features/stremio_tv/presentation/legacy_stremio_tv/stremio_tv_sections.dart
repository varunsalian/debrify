import 'package:debrify/features/stremio_tv/presentation/legacy_stremio_tv/stremio_tv_bindings.dart';
import 'package:debrify/features/stremio_tv/presentation/legacy_stremio_tv/stremio_tv_channel_actions.dart';
import 'package:debrify/features/stremio_tv/presentation/legacy_stremio_tv/stremio_tv_channel_library.dart';
import 'package:debrify/features/stremio_tv/presentation/legacy_stremio_tv/stremio_tv_channel_resolve.dart';
import 'package:debrify/features/stremio_tv/presentation/legacy_stremio_tv/stremio_tv_chrome.dart';
import 'package:debrify/features/stremio_tv/presentation/legacy_stremio_tv/stremio_tv_cloud_resolvers.dart';
import 'package:debrify/features/stremio_tv/presentation/legacy_stremio_tv/stremio_tv_debrid_resolvers.dart';
import 'package:debrify/features/stremio_tv/presentation/legacy_stremio_tv/stremio_tv_layout.dart';
import 'package:debrify/features/stremio_tv/presentation/legacy_stremio_tv/stremio_tv_menu_actions.dart';
import 'package:debrify/features/stremio_tv/presentation/legacy_stremio_tv/stremio_tv_navigation.dart';
import 'package:debrify/features/stremio_tv/presentation/legacy_stremio_tv/stremio_tv_play_channel.dart';
import 'package:debrify/features/stremio_tv/presentation/legacy_stremio_tv/stremio_tv_player_guide.dart';
import 'package:debrify/features/stremio_tv/presentation/legacy_stremio_tv/stremio_tv_settings_loader.dart';
import 'package:debrify/features/stremio_tv/presentation/legacy_stremio_tv/stremio_tv_stream_selection.dart';

class StremioTvSections {
  final StremioTvSettingsLoader settings;
  final StremioTvChannelLibrary library;
  final StremioTvMenuActions menuActions;
  final StremioTvChrome chrome;
  final StremioTvStreamSelection streams;
  final StremioTvPlayChannel play;
  final StremioTvChannelResolve resolve;
  final StremioTvPlayerGuide guide;
  final StremioTvDebridResolvers debrid;
  final StremioTvCloudResolvers cloud;
  final StremioTvChannelActions actions;
  final StremioTvNavigation navigation;
  final StremioTvLayout layout;
  StremioTvSections(StremioTvDependencies deps)
    : settings = StremioTvSettingsLoader(deps),
      library = StremioTvChannelLibrary(deps),
      menuActions = StremioTvMenuActions(deps),
      chrome = StremioTvChrome(deps),
      streams = StremioTvStreamSelection(deps),
      play = StremioTvPlayChannel(deps),
      resolve = StremioTvChannelResolve(deps),
      guide = StremioTvPlayerGuide(deps),
      debrid = StremioTvDebridResolvers(deps),
      cloud = StremioTvCloudResolvers(deps),
      actions = StremioTvChannelActions(deps),
      navigation = StremioTvNavigation(deps),
      layout = StremioTvLayout(deps) {
    deps.sections = this;
  }
}
