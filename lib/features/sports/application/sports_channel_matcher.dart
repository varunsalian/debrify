// Matches one fixture against the user's guide listings and channel list.
//
// Application layer: pure functions over the models in `models/`. It never
// touches a database or a playlist; the guide snapshot is handed in by the
// caller so matching stays deterministic and testable.
import 'package:debrify/features/sports/application/sports_names.dart';
import 'package:debrify/features/sports/models/sports_models.dart';

/// Programme titles containing one of these are recap shows, not the live game.
const List<String> kSportsNonLiveWords = [
  'highlights',
  'replay',
  'review',
  'preview',
  'classics',
  'rewind',
  'magazine',
  'reaction',
  'analysis',
  'goals show',
];

/// A listing may start this far from kick-off and still be the live broadcast.
const Duration _timingTolerance = Duration(hours: 2);

/// Motor-sport context words a non-team listing title must also mention.
const List<String> _motorsportPhrases = ['grand prix', 'formula 1', 'f1'];

const int _maxPossibleOptions = 8;

final RegExp _grandPrixPhrase = RegExp(r'\bgrand prix\b');

/// Normalized title needles used to find [event] in EPG titles.
///
/// Team games contribute every variant of both teams (deduped); non-team
/// events contribute their title without the `grand prix` boilerplate.
List<String> sportsTitleNeedles(SportsEvent event) {
  if (event.isTeamEvent) {
    final needles = <String>[];
    for (final team in <SportsTeam>[event.home!, event.away!]) {
      for (final variant in teamNameVariants(team)) {
        if (!needles.contains(variant)) needles.add(variant);
      }
    }
    return needles;
  }
  final title = normalizeSportsText(event.title ?? '');
  if (title.isEmpty) return const [];
  final needle = normalizeSportsText(title.replaceAll(_grandPrixPhrase, ' '));
  return needle.isEmpty ? const [] : [needle];
}

/// Finds guide-confirmed and possible watch options for [event].
///
/// Guide options are listings whose title names the match at the right time,
/// grouped per channel base name into one option holding the best-quality
/// copy. Possible options come from the event's broadcasters.
SportsWatchOptions matchSportsEvent(
  SportsEvent event, {
  required List<SportsGuideListing> listings,
  required List<SportsChannelRef> channels,
}) {
  final guideGroups = _guideGroups(event, listings);
  final guide = _guideOptions(event, guideGroups);
  final possible = _possibleOptions(
    event,
    channels,
    guideBases: guideGroups.keys.toSet(),
  );
  return SportsWatchOptions(guide: guide, possible: possible);
}

/// Qualifying listings grouped by channel base name, in listing input order.
Map<String, List<SportsGuideListing>> _guideGroups(
  SportsEvent event,
  List<SportsGuideListing> listings,
) {
  final homeVariants = event.isTeamEvent
      ? teamNameVariants(event.home!)
      : const <String>[];
  final awayVariants = event.isTeamEvent
      ? teamNameVariants(event.away!)
      : const <String>[];
  final needles = event.isTeamEvent
      ? const <String>[]
      : sportsTitleNeedles(event);
  final groups = <String, List<SportsGuideListing>>{};
  for (final listing in listings) {
    if (!_qualifies(
      listing,
      event,
      homeVariants: homeVariants,
      awayVariants: awayVariants,
      needles: needles,
    )) {
      continue;
    }
    final base = channelBaseName(listing.channel.name);
    groups.putIfAbsent(base, () => <SportsGuideListing>[]).add(listing);
  }
  return groups;
}

List<SportsWatchOption> _guideOptions(
  SportsEvent event,
  Map<String, List<SportsGuideListing>> groups,
) {
  final options = <SportsWatchOption>[];
  for (final members in groups.values) {
    final best = _bestQualityIndex(
      members,
      (l) => channelQualityRank(l.channel.name),
    );
    final chosen = members[best];
    final variants = <SportsChannelRef>[
      for (var i = 0; i < members.length; i++)
        if (i != best) members[i].channel,
    ];
    options.add(
      SportsWatchOption(
        channel: chosen.channel,
        kind: SportsMatchKind.guide,
        listing: chosen,
        variants: variants,
      ),
    );
  }
  options.sort((a, b) {
    final deltaA = a.listing!.start.difference(event.start).abs();
    final deltaB = b.listing!.start.difference(event.start).abs();
    final byDelta = deltaA.compareTo(deltaB);
    if (byDelta != 0) return byDelta;
    return a.channel.name.compareTo(b.channel.name);
  });
  return options;
}

bool _qualifies(
  SportsGuideListing listing,
  SportsEvent event, {
  required List<String> homeVariants,
  required List<String> awayVariants,
  required List<String> needles,
}) {
  if (!_timingMatches(listing, event)) return false;
  final title = normalizeSportsText(listing.title);
  if (kSportsNonLiveWords.any((word) => sportsTextContains(title, word))) {
    return false;
  }
  if (event.isTeamEvent) {
    return homeVariants.any((v) => sportsTextContains(title, v)) &&
        awayVariants.any((v) => sportsTextContains(title, v));
  }
  if (needles.isEmpty) return false;
  return sportsTextContains(title, needles.first) &&
      _motorsportPhrases.any((phrase) => sportsTextContains(title, phrase));
}

bool _timingMatches(SportsGuideListing listing, SportsEvent event) {
  final delta = listing.start.difference(event.start).abs();
  if (delta <= _timingTolerance) return true;
  return !listing.start.isAfter(event.start) &&
      listing.stop.isAfter(event.start);
}

List<SportsWatchOption> _possibleOptions(
  SportsEvent event,
  List<SportsChannelRef> channels, {
  required Set<String> guideBases,
}) {
  // Insertion order keeps broadcaster order, then channel order.
  final groups = <String, List<SportsChannelRef>>{};
  for (final broadcaster in event.broadcasts) {
    final needle = channelBaseName(broadcaster);
    if (needle.isEmpty) continue;
    // Bases grouped by an earlier broadcaster already hold every channel that
    // matches this needle, so they are skipped; bases opened by this
    // broadcaster keep collecting their remaining copies.
    final grouped = groups.keys.toSet();
    for (final channel in channels) {
      final base = channelBaseName(channel.name);
      if (base.isEmpty) continue;
      if (guideBases.contains(base) || grouped.contains(base)) continue;
      if (!_broadcasterMatches(needle, base)) continue;
      groups.putIfAbsent(base, () => <SportsChannelRef>[]).add(channel);
    }
  }
  final options = <SportsWatchOption>[];
  for (final members in groups.values) {
    if (options.length >= _maxPossibleOptions) break;
    final best = _bestQualityIndex(members, (c) => channelQualityRank(c.name));
    final variants = <SportsChannelRef>[
      for (var i = 0; i < members.length; i++)
        if (i != best) members[i],
    ];
    options.add(
      SportsWatchOption(
        channel: members[best],
        kind: SportsMatchKind.broadcaster,
        variants: variants,
      ),
    );
  }
  return options;
}

/// `'tnt sports'` matches the base name `'tnt sports'` and its numbered
/// siblings `'tnt sports 2'`, `'tnt sports 10'`, but not `'tnt sports extra'`.
bool _broadcasterMatches(String broadcasterBase, String channelBase) {
  if (channelBase == broadcasterBase) return true;
  if (!channelBase.startsWith('$broadcasterBase ')) return false;
  final suffix = channelBase.substring(broadcasterBase.length + 1);
  return suffix.isNotEmpty && _digits.hasMatch(suffix);
}

final RegExp _digits = RegExp(r'^[0-9]+$');

int _bestQualityIndex<T>(List<T> items, int Function(T item) rank) {
  var best = 0;
  var bestRank = rank(items.first);
  for (var i = 1; i < items.length; i++) {
    final value = rank(items[i]);
    if (value > bestRank) {
      best = i;
      bestRank = value;
    }
  }
  return best;
}
