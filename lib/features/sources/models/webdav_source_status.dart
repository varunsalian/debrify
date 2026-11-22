/// Where one WebDAV server's title search stands.
enum WebDavSearchPhase {
  /// Listing folders; [WebDavSourceStatus.slow] says it is taking a while.
  searching,

  /// Every promising folder was checked.
  done,

  /// Stopped at the folder budget before checking everything promising.
  folderLimit,

  /// Stopped at the time limit; rows found so far stay.
  timedOut,

  /// The server could not be searched at all.
  failed,
}

/// Why a server could not be searched.
enum WebDavFailure { signIn, unreachable, notFound, tooLarge, noAccess, other }

/// One server's live search state, shown while Sources is still searching and
/// summarized afterwards. Immutable; each update is a new value.
final class WebDavSourceStatus {
  const WebDavSourceStatus({
    required this.key,
    required this.name,
    required this.phase,
    this.foldersChecked = 0,
    this.found = 0,
    this.slow = false,
    this.failedFolders = 0,
    this.failure,
    this.unreachable = false,
  });

  /// The rows' source key, `webdav:<server id>`.
  final String key;
  final String name;
  final WebDavSearchPhase phase;
  final int foldersChecked;
  final int found;

  /// The server has been answering for longer than a moment.
  final bool slow;

  /// Folders that could not be opened; the rest of the search went on.
  final int failedFolders;

  /// Why the search failed; [summary] puts it in words.
  final WebDavFailure? failure;

  /// The server never answered (offline, wrong address, no network).
  final bool unreachable;

  bool get searching => phase == WebDavSearchPhase.searching;

  String get label => 'WebDAV · $name';

  String get _folders =>
      foldersChecked == 1 ? '1 folder' : '$foldersChecked folders';

  /// Live progress line while searching.
  String get progressMessage {
    final base = foldersChecked == 0
        ? 'Looking through $label…'
        : 'Looking through $label… $_folders checked';
    if (!slow) return base;
    return '$base. WebDAV servers list one folder at a time, so big '
        'libraries take a little longer.';
  }

  /// Summary after the search, or null when there is nothing to explain.
  /// Stopping early is not worth a note once something was found.
  String? get resultMessage => summary(withLabel: true);

  /// [resultMessage] without the server name, for places that already show
  /// it (the Cinema provider rail).
  String? summary({required bool withLabel}) {
    final who = withLabel ? label : 'This server';
    final on = withLabel ? ' on $label' : '';
    return switch (phase) {
      WebDavSearchPhase.searching => withLabel ? progressMessage : 'Searching…',
      WebDavSearchPhase.failed => _failureText(withLabel: withLabel),
      WebDavSearchPhase.timedOut when found > 0 => null,
      WebDavSearchPhase.timedOut when foldersChecked == 0 =>
        "$who didn't answer in time. Check that it is online.",
      WebDavSearchPhase.timedOut =>
        '$who is slow to list its folders, so the search stopped after '
            '$_folders. Try again in a moment.',
      WebDavSearchPhase.folderLimit when found > 0 => null,
      WebDavSearchPhase.folderLimit =>
        'Stopped after checking $_folders$on. Folders named after the '
            'title (like "Movies/Dune (2021)" or "TV/Show/Season 1") are '
            'found fastest.',
      WebDavSearchPhase.done =>
        failedFolders > 0 && found == 0
            ? 'Some folders$on could not be opened, so a match may be '
                  'missing.'
            : null,
    };
  }

  String _failureText({required bool withLabel}) {
    final it = withLabel ? label : 'the server';
    final subject = withLabel ? label : 'The server';
    return switch (failure ?? WebDavFailure.other) {
      WebDavFailure.signIn =>
        '$subject rejected its sign-in. Check the username and password in '
            'WebDAV settings.',
      WebDavFailure.unreachable =>
        "Couldn't reach $it. Check that it is online.",
      WebDavFailure.notFound =>
        "$subject's folder was not found. Check its address in WebDAV "
            'settings.',
      WebDavFailure.tooLarge => 'A folder on $it is too large to search.',
      WebDavFailure.noAccess => '$subject is not available to this profile.',
      WebDavFailure.other => "Couldn't search $it.",
    };
  }

  /// Shown after a finished search that found nothing and had nothing else
  /// to explain, with how far it looked.
  String get nothingFoundMessage => foldersChecked <= 1
      ? 'No files named after this title.'
      : 'Checked $_folders and found no files named after this title.';

  /// Whether the summary is a problem the user may want to act on.
  bool get hasIssue =>
      phase != WebDavSearchPhase.searching && resultMessage != null;

  WebDavSourceStatus copyWith({
    WebDavSearchPhase? phase,
    int? foldersChecked,
    int? found,
    bool? slow,
    int? failedFolders,
    WebDavFailure? failure,
    bool? unreachable,
  }) => WebDavSourceStatus(
    key: key,
    name: name,
    phase: phase ?? this.phase,
    foldersChecked: foldersChecked ?? this.foldersChecked,
    found: found ?? this.found,
    slow: slow ?? this.slow,
    failedFolders: failedFolders ?? this.failedFolders,
    failure: failure ?? this.failure,
    unreachable: unreachable ?? this.unreachable,
  );
}
