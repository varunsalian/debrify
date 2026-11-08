/// How the startup check treats one message from the player's error stream.
///
/// media_kit forwards mpv's error-level lines from the file, stream, vd, ad
/// and cplayer modules, plus ffmpeg lines that start with "tcp:", without
/// their module prefix. Many of them do not stop playback: no usable audio
/// device, a subtitle file that fails to load, a damaged frame at the start
/// of a broadcast recording. Rejecting a source on any of them skipped
/// sources that would have played.
enum StartupErrorKind {
  /// The source cannot play: it failed to open, the server refused it, or a
  /// decoder or the video output cannot start. Reject it now.
  fatal,

  /// Known not to stop playback on its own. Decode errors are the exception
  /// once they repeat (see [StartupErrorTally]).
  benign,

  /// Anything else. VOD startup lets the source keep trying until it plays
  /// or its startup timeout fires; channel startup still rejects it.
  unknown,
}

/// A fixed-vocabulary classification. [label] is safe for diagnostics: it
/// never contains the message text, which can carry signed URLs.
typedef StartupErrorClass = ({StartupErrorKind kind, String label});

abstract final class StartupErrorPolicy {
  /// "HTTP 403", "http error 404", "HTTP: 500". A bare three-digit number is
  /// not enough: ports, paths and timestamps contain them.
  static final RegExp _httpStatus = RegExp(r'\bhttp(?: error)?:? ?[45]\d\d\b');
  static const Set<String> _subtitleExtensions = {
    'srt',
    'vtt',
    'webvtt',
    'ass',
    'ssa',
    'sub',
    'idx',
    'sup',
  };

  static StartupErrorClass classify(String error) {
    final text = error.toLowerCase();
    // Benign first: a subtitle URL that fails to open is reported with the
    // same "Failed to open" wording as the video itself.
    if (text.contains('audio device')) {
      return (kind: StartupErrorKind.benign, label: 'audio_device');
    }
    if (text.contains('subtitle') || _isSubtitleOpenFailure(text)) {
      return (kind: StartupErrorKind.benign, label: 'subtitle');
    }
    if (text.contains('can not open external file')) {
      return (kind: StartupErrorKind.benign, label: 'external_file');
    }
    if (text.contains('error while decoding')) {
      return (kind: StartupErrorKind.benign, label: 'decode');
    }
    // Broken audio never blocks the picture, so it is not counted towards
    // the decode bound either.
    if (text.contains('error decoding')) {
      return (kind: StartupErrorKind.benign, label: 'audio_decode');
    }
    if (text.contains('hwaccel') || text.contains('hardware decod')) {
      return (kind: StartupErrorKind.benign, label: 'hwdec');
    }

    if (text.contains('failed to open') ||
        text.contains('cannot open file') ||
        text.contains('no such file') ||
        text.contains('no protocol handler') ||
        text.contains('protocol is either unsupported')) {
      return (kind: StartupErrorKind.fatal, label: 'open_failed');
    }
    if (text.contains('failed to recognize file format')) {
      return (kind: StartupErrorKind.fatal, label: 'format');
    }
    if (text.contains('no video or audio streams')) {
      return (kind: StartupErrorKind.fatal, label: 'no_streams');
    }
    // vd and ad share this wording, so an audio-only decoder failure rejects
    // too: a source that would play silently is worth skipping.
    if (text.contains('could not open codec') ||
        text.contains('failed to initialize a decoder')) {
      return (kind: StartupErrorKind.fatal, label: 'codec');
    }
    if (text.contains('video_out')) {
      return (kind: StartupErrorKind.fatal, label: 'video_output');
    }
    if (text.startsWith('tcp:')) {
      return (kind: StartupErrorKind.fatal, label: 'network');
    }
    if (text.contains('forbidden') ||
        text.contains('unauthorized') ||
        _httpStatus.hasMatch(text)) {
      return (kind: StartupErrorKind.fatal, label: 'http_status');
    }
    return (kind: StartupErrorKind.unknown, label: 'other');
  }

  /// `Failed to open URL.` or `Cannot open file 'PATH'` where the path, not
  /// a query, ends in a subtitle extension.
  static bool _isSubtitleOpenFailure(String text) {
    String? target;
    const open = 'failed to open ';
    const file = "cannot open file '";
    final openAt = text.indexOf(open);
    final fileAt = text.indexOf(file);
    if (openAt >= 0) {
      target = text.substring(openAt + open.length).trim();
      if (target.endsWith('.')) target = target.substring(0, target.length - 1);
    } else if (fileAt >= 0) {
      final rest = text.substring(fileAt + file.length);
      final close = rest.indexOf("'");
      target = close < 0 ? rest : rest.substring(0, close);
    }
    if (target == null) return false;
    final query = target.indexOf(RegExp('[?#]'));
    if (query >= 0) target = target.substring(0, query);
    final dot = target.lastIndexOf('.');
    if (dot < 0 || dot < target.lastIndexOf('/')) return false;
    return _subtitleExtensions.contains(target.substring(dot + 1));
  }
}

/// One startup attempt's errors: decides whether each rejects the attempt
/// and which error types are new, so each is recorded once.
class StartupErrorTally {
  StartupErrorTally({required this.rejectUnknown});

  /// A stream joined between keyframes recovers at the next one; video that
  /// can never decode keeps failing. Without this bound a channel, which has
  /// no startup deadline, would show a black screen indefinitely.
  static const int maxDecodeErrors = 50;

  /// Channels have no startup deadline to fall back on, so they reject
  /// unrecognised errors; VOD leaves those to its timeout.
  final bool rejectUnknown;

  final Set<String> _seen = {};
  int _decodeErrors = 0;

  /// Whether [label] is new for this attempt.
  bool isFirst(String label) => _seen.add(label);

  /// [hasData]: bytes have already arrived. A later "tcp:" failure may be a
  /// reconnect (media opens set reconnect=1), so the timeout decides.
  bool rejects(StartupErrorClass type, {bool hasData = false}) {
    switch (type.kind) {
      case StartupErrorKind.fatal:
        return !(type.label == 'network' && hasData);
      case StartupErrorKind.unknown:
        return rejectUnknown;
      case StartupErrorKind.benign:
        return type.label == 'decode' && ++_decodeErrors >= maxDecodeErrors;
    }
  }
}
