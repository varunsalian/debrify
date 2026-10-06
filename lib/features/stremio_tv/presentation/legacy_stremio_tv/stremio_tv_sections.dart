import 'package:debrify/features/stremio_tv/presentation/legacy_stremio_tv/stremio_tv_bindings.dart';
import 'package:debrify/features/stremio_tv/presentation/legacy_stremio_tv/stremio_tv_channel_library.dart';
import 'package:debrify/features/stremio_tv/presentation/legacy_stremio_tv/stremio_tv_chrome.dart';
import 'package:debrify/features/stremio_tv/presentation/legacy_stremio_tv/stremio_tv_menu_actions.dart';
import 'package:debrify/features/stremio_tv/presentation/legacy_stremio_tv/stremio_tv_navigation.dart';
import 'package:debrify/features/stremio_tv/presentation/legacy_stremio_tv/stremio_tv_settings_loader.dart';

class StremioTvSections {
  final StremioTvSettingsLoader settings;
  final StremioTvChannelLibrary library;
  final StremioTvMenuActions menuActions;
  final StremioTvChrome chrome;
  final StremioTvNavigation navigation;
  // TEMP(stremio_tv): direct borrowed callbacks; removed by step 5.
  final StremioTvDependencies legacy;
  StremioTvSections(StremioTvDependencies deps)
    : settings = StremioTvSettingsLoader(deps),
      library = StremioTvChannelLibrary(deps),
      menuActions = StremioTvMenuActions(deps),
      chrome = StremioTvChrome(deps),
      navigation = StremioTvNavigation(deps),
      legacy = deps {
    deps.sections = this;
  }
}
