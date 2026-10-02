import 'package:debrify/screens/settings/settings_search.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'settings_leaf_builder.dart';

extension SettingsLeafSlice10 on SettingsLeafBuilder {
  List<SettingsSearchEntry> leafSlice10() {
    return [
      // The recording switches live on the IPTV page, but only where the
      // engine can actually run (Android 10+) — same gate as the DVR row.
      if (summaries.recordingSearchable) ...[
        leaf(
          'IPTV Playlists',
          'Background recording engine',
          'Keep recordings running when you zap or leave the app',
          const [
            'background',
            'engine',
            'recording',
            'dvr',
            'scheduled',
            'player-tied',
          ],
        ),
        leaf(
          'IPTV Playlists',
          'Simultaneous recordings',
          'How many recordings can run at once',
          const [
            'simultaneous',
            'concurrent',
            'parallel',
            'at once',
            'connections',
            'limit',
          ],
        ),
        leaf(
          'IPTV Playlists',
          'Battery optimization',
          'Exclude Debrify so recordings survive doze',
          const [
            'battery',
            'doze',
            'optimization',
            'background',
            'killed',
            'stops',
          ],
        ),
      ],
      // Gated on a backend that actually records — the Android engine OR the
      // desktop recorder. NOT on [_recordingSearchable] alone (Android-only,
      // which would hide these on desktop where they work), and not ungated
      // (on iOS neither backend exists: scheduling raises a storage error and
      // the library is permanently empty).
      if (deps.recordingSupported()) ...[
        leaf(
          'Recordings',
          'Schedule a recording',
          'Record a channel at a set date and time',
          const [
            'schedule',
            'timer',
            'record later',
            'date',
            'start time',
            'alarm',
          ],
        ),
        leaf(
          'Recordings',
          'Recordings library',
          'Your recorded files, and where they are saved',
          const [
            'library',
            'recorded',
            'files',
            'folder',
            'storage',
            'downloads',
            'delete recording',
          ],
        ),
      ],

      if (ProfileRuntime.mode == ProfileRuntimeMode.profileCommitted) ...[
        leaf(
          'Profiles',
          'Ask who\'s watching at startup',
          'Show the profile picker whenever Debrify opens',
          const [
            'always ask',
            'profile behavior',
            'profile picker',
            'startup',
            'launch',
            'who is watching',
          ],
        ),
        leaf(
          'Profiles',
          'Send profiles to TV',
          'Transfer profiles, connections and PINs to another device',
          const [
            'household',
            'transfer',
            'pair',
            'remote',
            'connections',
            'pins',
            'setup',
          ],
        ),
        leaf(
          'Profiles',
          'Manage profiles',
          'Create, edit, switch, enable, disable or delete a profile',
          const [
            'current profile',
            'other profiles',
            'create profile',
            'edit profile',
            'switch profile',
            'delete profile',
            'disable profile',
            'enable profile',
            'name',
            'avatar',
            'save name and avatar',
            'choose image or gif',
            'pin',
            'pin protection',
            'set pin',
            'change pin',
            'remove pin',
            'access',
            'admin',
            'member',
            'kid',
            'profile diagnostics',
          ],
        ),
      ],
    ];
  }
}
