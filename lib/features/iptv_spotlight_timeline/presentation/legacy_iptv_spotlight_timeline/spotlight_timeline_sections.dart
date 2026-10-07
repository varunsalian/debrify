import 'package:debrify/features/iptv_spotlight_timeline/presentation/legacy_iptv_spotlight_timeline/spotlight_timeline_cursor.dart';
import 'package:debrify/features/iptv_spotlight_timeline/presentation/legacy_iptv_spotlight_timeline/spotlight_timeline_dependencies.dart';
import 'package:debrify/features/iptv_spotlight_timeline/presentation/legacy_iptv_spotlight_timeline/spotlight_timeline_frame.dart';
import 'package:debrify/features/iptv_spotlight_timeline/presentation/legacy_iptv_spotlight_timeline/spotlight_timeline_guide_loading.dart';
import 'package:debrify/features/iptv_spotlight_timeline/presentation/legacy_iptv_spotlight_timeline/spotlight_timeline_rows.dart';
import 'package:debrify/features/iptv_spotlight_timeline/presentation/legacy_iptv_spotlight_timeline/spotlight_timeline_selection.dart';
import 'package:debrify/features/iptv_spotlight_timeline/presentation/legacy_iptv_spotlight_timeline/spotlight_timeline_track.dart';
import 'package:debrify/features/iptv_spotlight_timeline/presentation/legacy_iptv_spotlight_timeline/spotlight_timeline_window.dart';

class SpotlightTimelineSections {
  late final SpotlightTimelineGuideLoading loading;
  late final SpotlightTimelineWindow window;
  late final SpotlightTimelineCursor cursor;
  late final SpotlightTimelineSelectionActions selection;
  late final SpotlightTimelineFrame frame;
  late final SpotlightTimelineRows rows;
  late final SpotlightTimelineTrack track;
  SpotlightTimelineSections(SpotlightTimelineDependencies deps) {
    loading = SpotlightTimelineGuideLoading(deps);
    window = SpotlightTimelineWindow(deps);
    cursor = SpotlightTimelineCursor(deps);
    selection = SpotlightTimelineSelectionActions(deps);
    frame = SpotlightTimelineFrame(deps);
    rows = SpotlightTimelineRows(deps);
    track = SpotlightTimelineTrack(deps);
  }
}
