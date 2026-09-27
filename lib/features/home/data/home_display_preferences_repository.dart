import '../../../models/home_preferences.dart' show HomeCardOrientation;
import '../models/home_display_preferences.dart';

class HomeDisplayPreferencesRepository {
  const HomeDisplayPreferencesRepository({
    required this.readFocusDetails,
    required this.readAnimationsEnabled,
    required this.readAnimationStyle,
    required this.readOrientation,
    required this.readHideTitles,
    required this.readHideAddonNames,
    required this.readHideCollectionNames,
  });

  final Future<bool> Function() readFocusDetails;
  final Future<bool> Function() readAnimationsEnabled;
  final Future<String> Function() readAnimationStyle;
  final Future<HomeCardOrientation> Function() readOrientation;
  final Future<bool> Function() readHideTitles;
  final Future<bool> Function() readHideAddonNames;
  final Future<bool> Function() readHideCollectionNames;

  /// Preserve the three sequential reads followed by the four parallel reads.
  /// Retired work stops before another reader can resolve an incoming profile.
  Future<HomeDisplayPreferences?> read({
    required bool Function() isCurrent,
  }) async {
    if (!isCurrent()) return null;
    final focus = await readFocusDetails();
    if (!isCurrent()) return null;
    final animations = await readAnimationsEnabled();
    if (!isCurrent()) return null;
    final style = await readAnimationStyle();
    if (!isCurrent()) return null;
    final cards = await Future.wait<Object>([
      readOrientation(),
      readHideTitles(),
      readHideAddonNames(),
      readHideCollectionNames(),
    ]);
    if (!isCurrent()) return null;
    return (
      orientation: cards[0] as HomeCardOrientation,
      hideTitlesAndRatings: cards[1] as bool,
      hideCatalogAddonNames: cards[2] as bool,
      hideCollectionNames: cards[3] as bool,
      spotlightFocusDetails: focus,
      animationsEnabled: animations,
      animationStyle: style,
    );
  }
}
