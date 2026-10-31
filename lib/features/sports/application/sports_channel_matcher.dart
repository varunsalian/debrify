// Matches one fixture against the user's guide listings and channel list.
//
// Application layer: pure functions over the models in `models/`. It never
// touches a database or a playlist; the guide snapshot is handed in by the
// caller so matching stays deterministic and testable.
import 'package:debrify/features/sports/application/sports_names.dart';
import 'package:debrify/features/sports/application/sports_stream_names.dart';
import 'package:debrify/features/sports/models/sports_guide_contract.dart';
import 'package:debrify/features/sports/models/sports_leagues.dart';
import 'package:debrify/features/sports/models/sports_models.dart';

/// A listing may start this far from kick-off and still be the live broadcast.
const Duration _timingTolerance = Duration(hours: 2);

/// Days after the first of a multi-day event, a listing found only by airing
/// near now must be this long: live Test or golf coverage runs for hours,
/// while the news and highlights slots naming both sides run 20-60 minutes.
const Duration _minLaterDayCoverage = Duration(minutes: 90);

/// Live this long after its scheduled start, an event is on a later day of a
/// multi-day fixture; a single-day game running late (rain, a long order of
/// play) stays below it and keeps matching hour-long guide slots.
const Duration _laterDayAfter = Duration(hours: 12);

/// Context words a non-team listing title must also mention, per sport, so a
/// venue or tournament name alone (a news show, a travel programme) does not
/// count as the broadcast.
const Map<SportKind, List<String>> _contextPhrases = {
  SportKind.motorsport: [
    'grand prix',
    'formula 1',
    'f1',
    'nascar',
    'indycar',
    'indy',
  ],
  SportKind.golf: ['golf', 'pga', 'lpga'],
  SportKind.combat: ['ufc', 'mma'],
};

/// Before the tournament proper: `'Xfinity 500 at Martinsville'` names the
/// venue after `at`; `'UFC Fight Night: Moicano vs. Nolan'` names the fighters
/// after the colon.
/// Suffixes that follow a surname and identify nobody on their own.
const Set<String> _nameSuffixes = {'jr', 'sr', 'ii', 'iii', 'iv'};

/// The last real name word of a fighter, 4+ letters (short or numeric words
/// match too many unrelated listings).
String? _surname(String side) {
  final words = normalizeSportsText(side)
      .split(' ')
      .where((w) => w.isNotEmpty && !_nameSuffixes.contains(w))
      .toList();
  if (words.isEmpty) return null;
  final last = words.last;
  if (last.length < 4 || RegExp(r'^[0-9]+$').hasMatch(last)) return null;
  return last;
}

final RegExp _atVenue = RegExp(r'\bat\s+(.+)$');
final RegExp _versus = RegExp(r'\s+(?:vs?\.?)\s+');

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
      for (final variant in sportsSideVariants(event, team)) {
        if (!needles.contains(variant)) needles.add(variant);
      }
    }
    for (final pair in sportsCodePairs(event)) {
      if (!needles.contains(pair)) needles.add(pair);
    }
    return needles;
  }
  final raw = event.title ?? '';
  final title = normalizeSportsText(raw);
  if (title.isEmpty) return const [];
  switch (sportsLeagueById(event.leagueId)?.sport) {
    case SportKind.combat:
      // Fighter surnames: listings say "Moicano v Nolan" or "Moicano vs Nolan".
      // A title without "vs" names no fighters ("UFC 310"): no needles, so
      // only the broadcaster fallback applies rather than a guess.
      final colon = raw.indexOf(':');
      final bout = colon >= 0 ? raw.substring(colon + 1) : raw;
      final sides = bout.split(_versus);
      if (sides.length < 2) return const [];
      return [
        for (final side in sides)
          if (_surname(side) case final name?) name,
      ];
    case SportKind.golf:
      // Sponsors come and go in listings ("Mexico Open" vs "VidantaWorld
      // Mexico Open"): match the last two words. Then the tour's own
      // coverage title, which never names the event ("Live: PGA Tour
      // Golf"); a tour plays one event a week, so live tour coverage is it.
      final words = title.split(' ');
      return [
        words.skip(words.length > 2 ? words.length - 2 : 0).join(' '),
        ...?_golfTourTitles[event.leagueId],
      ];
    case SportKind.motorsport:
      final venue = _atVenue.firstMatch(title)?.group(1);
      if (venue != null && venue.isNotEmpty) return [venue];
    default:
      break;
  }
  final needle = normalizeSportsText(title.replaceAll(_grandPrixPhrase, ' '));
  return needle.isEmpty ? const [] : [needle];
}

/// The names one side of [event] goes by: [teamNameVariants], plus the
/// player's surname in tennis, where listings and stream names say "Sinner v
/// Alcaraz" while the feed says "Jannik Sinner". (A women's team's name
/// without "Women" is allowed only where a stream name says it is a women's
/// game; see sportsChannelNamesMatch.)
List<String> sportsSideVariants(SportsEvent event, SportsTeam side) {
  final variants = teamNameVariants(side);
  if (sportsLeagueById(event.leagueId)?.sport != SportKind.tennis) {
    return variants;
  }
  final surname = _surname(side.name);
  return surname == null || variants.contains(surname)
      ? variants
      : [...variants, surname];
}

/// Coverage titles of a golf tour, by league id ("PGA Tour Champions Golf"
/// is another tour and does not contain "pga tour golf").
const Map<String, List<String>> _golfTourTitles = {
  'pga': ['pga tour golf'],
  'lpga': ['lpga tour golf', 'lpga golf'],
};

/// Country-code pairs a cricket listing may name the game by ("RSA v AUS",
/// "aus vs rsa"), from [kCricketCountryCodes] and the feed's abbreviations.
/// Empty for other sports and for sides without a known code.
List<String> sportsCodePairs(SportsEvent event) {
  if (!event.isTeamEvent ||
      sportsLeagueById(event.leagueId)?.sport != SportKind.cricket) {
    return const [];
  }
  List<String> codes(SportsTeam team) {
    final out = <String>[
      ...?kCricketCountryCodes[normalizeSportsText(team.name)],
    ];
    final abbreviation = normalizeSportsText(team.abbreviation);
    if (abbreviation.length >= 2 &&
        abbreviation.length <= 4 &&
        !abbreviation.contains(' ') &&
        !out.contains(abbreviation) &&
        out.isNotEmpty) {
      out.add(abbreviation);
    }
    return out;
  }

  final home = codes(event.home!);
  final away = codes(event.away!);
  return [
    for (final h in home)
      for (final a in away)
        for (final separator in const ['v', 'vs']) ...[
          '$h $separator $a',
          '$a $separator $h',
        ],
  ];
}

/// What a guide title or channel name must mention to be about [event]: both
/// sides for a game, else the event's title needles as one side; with when
/// it is on (see [_eventDay]) and its sport.
SportsEventNeedles sportsEventNeedles(SportsEvent event, {DateTime? now}) {
  final around = _eventDay(event, now);
  final sport = sportsLeagueById(event.leagueId)?.sport;
  if (event.isTeamEvent) {
    return SportsEventNeedles(
      [
        sportsSideVariants(event, event.home!),
        sportsSideVariants(event, event.away!),
      ],
      pairs: sportsCodePairs(event),
      around: around,
      sport: sport,
    );
  }
  final needles = sportsTitleNeedles(event);
  return SportsEventNeedles(
    [if (needles.isNotEmpty) needles],
    around: around,
    sport: sport,
  );
}

/// The day a stream of [event] is dated: today while it is live (day three
/// of a Test is today's stream), else its start.
DateTime _eventDay(SportsEvent event, DateTime? now) =>
    event.status == SportsEventStatus.live && now != null
    ? now.toUtc()
    : event.start.toUtc();

/// Finds guide-confirmed and possible watch options for [event].
///
/// Guide options are listings whose title names the match at the right time,
/// grouped per channel base name into one option holding the best-quality
/// copy, followed by channels whose own name names the match (a provider's
/// event stream). Possible options come from the event's broadcasters.
///
/// [tourCoverage] lets a golf event claim its tour's untitled live coverage
/// ("Live: PGA Tour Golf"); the caller turns it off when the tour has more
/// than one event on, as in an opposite-field week.
SportsWatchOptions matchSportsEvent(
  SportsEvent event, {
  required List<SportsGuideListing> listings,
  required List<SportsChannelRef> channels,
  List<SportsChannelRef> namedChannels = const [],
  DateTime? now,
  bool tourCoverage = true,
}) {
  final guideGroups = _guideGroups(event, listings, now, tourCoverage);
  final namedGroups = _namedGroups(event, namedChannels, guideGroups.keys, now);
  final guide = [
    ..._guideOptions(event, guideGroups),
    ..._namedOptions(namedGroups, _eventDay(event, now)),
  ];
  final possible = _possibleOptions(
    event,
    channels,
    guideBases: {...guideGroups.keys, ...namedGroups.keys},
  );
  return SportsWatchOptions(guide: guide, possible: possible);
}

/// Channels whose name is a stream of [event] (see
/// [sportsChannelNamesMatch]), grouped per base name like guide listings;
/// bases already found in the guide are left to their listing.
Map<String, List<SportsChannelRef>> _namedGroups(
  SportsEvent event,
  List<SportsChannelRef> channels,
  Iterable<String> guideBases,
  DateTime? now,
) {
  final groups = <String, List<SportsChannelRef>>{};
  if (!event.isTeamEvent || channels.isEmpty) return groups;
  final home = sportsSideVariants(event, event.home!);
  final away = sportsSideVariants(event, event.away!);
  final around = _eventDay(event, now);
  final sport = sportsLeagueById(event.leagueId)?.sport;
  final taken = guideBases.toSet();
  for (final channel in channels) {
    if (!sportsChannelNamesMatch(
      channel.name,
      home,
      away,
      around: around,
      sport: sport,
    )) {
      continue;
    }
    final base = channelBaseName(channel.name);
    if (base.isEmpty || taken.contains(base)) continue;
    groups.putIfAbsent(base, () => <SportsChannelRef>[]).add(channel);
  }
  return groups;
}

/// One option per group: streams dated the event's day first, then undated
/// ones, then those a day off (a local date across midnight, or yesterday's
/// stream left up); input order breaks ties.
List<SportsWatchOption> _namedOptions(
  Map<String, List<SportsChannelRef>> groups,
  DateTime around,
) {
  int gap(SportsWatchOption option) =>
      switch (sportsChannelNameDayGap(option.channel.name, around)) {
        0 => 0,
        null => 1,
        _ => 2,
      };
  final options = _namedGroupOptions(groups);
  final order = [for (var i = 0; i < options.length; i++) i]
    ..sort((a, b) {
      final byGap = gap(options[a]).compareTo(gap(options[b]));
      return byGap != 0 ? byGap : a.compareTo(b);
    });
  return [for (final i in order) options[i]];
}

List<SportsWatchOption> _namedGroupOptions(
  Map<String, List<SportsChannelRef>> groups,
) => [
  for (final members in groups.values)
    () {
      final best = _bestQualityIndex(
        members,
        (c) => channelQualityRank(c.name),
      );
      return SportsWatchOption(
        channel: members[best],
        kind: SportsMatchKind.channelName,
        variants: [
          for (var i = 0; i < members.length; i++)
            if (i != best) members[i],
        ],
      );
    }(),
];

/// Qualifying listings grouped by channel base name, in listing input order.
Map<String, List<SportsGuideListing>> _guideGroups(
  SportsEvent event,
  List<SportsGuideListing> listings,
  DateTime? now,
  bool tourCoverage,
) {
  final homeVariants = event.isTeamEvent
      ? sportsSideVariants(event, event.home!)
      : const <String>[];
  final awayVariants = event.isTeamEvent
      ? sportsSideVariants(event, event.away!)
      : const <String>[];
  final needles = event.isTeamEvent
      ? const <String>[]
      : sportsTitleNeedles(event);
  final pairs = sportsCodePairs(event);
  final groups = <String, List<SportsGuideListing>>{};
  for (final listing in listings) {
    if (!_qualifies(
      listing,
      event,
      now: now,
      homeVariants: homeVariants,
      awayVariants: awayVariants,
      pairs: pairs,
      needles: needles,
      tourCoverage: tourCoverage,
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
  required DateTime? now,
  required List<String> homeVariants,
  required List<String> awayVariants,
  required List<String> pairs,
  required List<String> needles,
  required bool tourCoverage,
}) {
  if (!_timingMatches(listing, event, now)) return false;
  final title = normalizeSportsText(listing.title);
  if (kSportsNonLiveWords.any((word) => sportsTextContains(title, word))) {
    return false;
  }
  if (event.isTeamEvent) {
    return (homeVariants.any((v) => sportsTextContains(title, v)) &&
            awayVariants.any((v) => sportsTextContains(title, v))) ||
        sportsTitleNamesCodePair(title, pairs);
  }
  if (needles.isEmpty) return false;
  final sport = sportsLeagueById(event.leagueId)?.sport ?? SportKind.motorsport;
  final context =
      _contextPhrases[sport] ?? _contextPhrases[SportKind.motorsport]!;
  if (!context.any((phrase) => sportsTextContains(title, phrase))) return false;
  // A fight card is found by either fighter; a golf event by its name or by
  // its tour's live coverage; other events by their needle.
  if (sport == SportKind.golf &&
      tourCoverage &&
      sportsTextContains(title, 'live') &&
      needles.skip(1).any((tour) => sportsTextContains(title, tour))) {
    return true;
  }
  return sport == SportKind.combat
      ? needles.any((needle) => sportsTextContains(title, needle))
      : sportsTextContains(title, needles.first);
}

bool _timingMatches(
  SportsGuideListing listing,
  SportsEvent event,
  DateTime? now,
) {
  final delta = listing.start.difference(event.start).abs();
  if (delta <= _timingTolerance) return true;
  if (!listing.start.isAfter(event.start) &&
      listing.stop.isAfter(event.start)) {
    return true;
  }
  // Multi-day events (Test cricket, golf) started days ago: while they are
  // live, today's broadcast is the listing airing now or starting soon.
  if (now != null && event.status == SportsEventStatus.live) {
    if (now.difference(event.start) >= _laterDayAfter &&
        listing.stop.difference(listing.start) < _minLaterDayCoverage) {
      return false;
    }
    final airing = !listing.start.isAfter(now) && listing.stop.isAfter(now);
    return airing || listing.start.difference(now).abs() <= _timingTolerance;
  }
  return false;
}

List<SportsWatchOption> _possibleOptions(
  SportsEvent event,
  List<SportsChannelRef> channels, {
  required Set<String> guideBases,
}) {
  // Insertion order keeps broadcaster order, then channel order.
  final groups = <String, List<SportsChannelRef>>{};
  for (final broadcaster in event.broadcasts) {
    final needles = sportsBroadcasterNeedles(broadcaster);
    if (needles.isEmpty) continue;
    // Bases grouped by an earlier broadcaster already hold every channel that
    // matches this needle, so they are skipped; bases opened by this
    // broadcaster keep collecting their remaining copies.
    final grouped = groups.keys.toSet();
    for (final channel in channels) {
      final base = channelBaseName(channel.name);
      if (base.isEmpty) continue;
      if (guideBases.contains(base) || grouped.contains(base)) continue;
      if (!needles.any((needle) => _broadcasterMatches(needle, base))) {
        continue;
      }
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
