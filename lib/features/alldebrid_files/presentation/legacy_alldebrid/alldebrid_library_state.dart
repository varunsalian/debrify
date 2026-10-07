import 'package:debrify/models/alldebrid_link.dart';
import 'package:debrify/models/alldebrid_magnet.dart';

class AllDebridLibraryState {
  String? apiKey;

  bool loading = true;

  String? error;

  List<AllDebridMagnet> magnets = [];

  // Saved-links ("Web Downloads") library. Loaded lazily on first switch.
  List<AllDebridLink> links = [];

  bool loadingLinks = false;

  bool linksLoadedOnce = false;

  String? linksError;
}
