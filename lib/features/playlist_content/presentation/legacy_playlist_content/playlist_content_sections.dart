import 'playlist_content_cloud_loading.dart';
import 'playlist_content_content_loading.dart';
import 'playlist_content_initialization.dart';
import 'playlist_content_navigation.dart';
import 'playlist_content_playlist_order.dart';
import 'playlist_content_view_modes.dart';

class PlaylistContentSections {
  PlaylistContentInitialization? initializationSlot;
  PlaylistContentInitialization get initialization => initializationSlot!;
  PlaylistContentNavigation? navigationSlot;
  PlaylistContentNavigation get navigation => navigationSlot!;
  PlaylistContentViewModes? viewModesSlot;
  PlaylistContentViewModes get viewModes => viewModesSlot!;
  PlaylistContentContentLoading? contentLoadingSlot;
  PlaylistContentContentLoading get contentLoading => contentLoadingSlot!;
  PlaylistContentCloudLoading? cloudLoadingSlot;
  PlaylistContentCloudLoading get cloudLoading => cloudLoadingSlot!;
  PlaylistContentPlaylistOrder? playlistOrderSlot;
  PlaylistContentPlaylistOrder get playlistOrder => playlistOrderSlot!;
}
