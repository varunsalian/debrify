import 'package:debrify/services/mdblist/mdblist_service.dart';
import 'package:debrify/services/simkl/simkl_service.dart';
import 'package:debrify/services/stremio_service.dart';
import 'package:debrify/services/trakt/trakt_service.dart';

class EpisodesPanelServices {
  final StremioService stremioService = StremioService.instance;

  final TraktService traktService = TraktService.instance;

  final SimklService simklService = SimklService.instance;

  final MdblistService mdblistService = MdblistService.instance;
}
