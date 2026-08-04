import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../utils/tv_keys.dart';

/// In-app DPAD keyboard for TV.
///
/// Rationale: TV IMEs (Gboard TV et al.) never engage their DPAD-navigation
/// mode for Flutter's text input on many devices (flutter/flutter#177360 —
/// Chromecast with Google TV, some Philips/Samsung panels), so the system
/// keyboard opens but its keys can't be reached with the remote. This keyboard
/// is ordinary Flutter widgets driven by ordinary key events, so it behaves
/// identically on every device and the system IME is never summoned
/// ([TextInputType.none] on the backing field).
///
/// The panel never takes focus. The owning field (TvTextField) keeps focus on
/// its editor, forwards DPAD events to [TvKeyboardController.handleKey], and
/// applies the resulting edits — so there is exactly one focus owner and no
/// focus hand-off to go wrong mid-type.

/// What pressing a key does. [insert] carries its text in [TvKey.insert].
/// [systemIme] hands the session over to the real system keyboard — the only
/// path that wakes the Google TV phone-remote keyboard and voice input, both
/// of which only engage while the TV is showing a system IME session.
enum TvKeyAction {
  insert,
  space,
  backspace,
  clear,
  shift,
  page,
  submit,
  systemIme,
  voice,
}

class TvKey {
  const TvKey.insert(this.insert)
    : action = TvKeyAction.insert,
      label = insert,
      icon = null,
      flex = 2;

  const TvKey.action(this.action, {this.label = '', this.icon, this.flex = 2})
    : insert = '';

  final TvKeyAction action;
  final String insert;
  final String label;
  final IconData? icon;

  /// Width weight within its row (space bar is wide, letters are uniform).
  final int flex;
}

List<TvKey> _insertRow(String chars) => [
  for (final c in chars.split('')) TvKey.insert(c),
];

/// Letter page. [shift] renders/inserts uppercase; digits ride along on top so
/// common "title year" queries never need the symbol page.
List<List<TvKey>> _letterPage(bool shift) {
  String c(String s) => shift ? s.toUpperCase() : s;
  return [
    _insertRow('1234567890'),
    _insertRow(c('qwertyuiop')),
    _insertRow(c('asdfghjkl')),
    [
      TvKey.action(TvKeyAction.shift, icon: Icons.keyboard_capslock_rounded),
      ..._insertRow(c('zxcvbnm')),
      TvKey.action(TvKeyAction.backspace, icon: Icons.backspace_outlined),
    ],
  ];
}

final List<List<TvKey>> _symbolPage = [
  _insertRow('!@#\$%^&*()'),
  _insertRow('-_=+[]{}\\|'),
  _insertRow(';:\'",.<>/?'),
  [
    const TvKey.insert('`'),
    const TvKey.insert('~'),
    const TvKey.insert('€'),
    const TvKey.insert('£'),
    TvKey.action(TvKeyAction.backspace, icon: Icons.backspace_outlined),
  ],
];

/// Bottom action row, shared by both pages. The smartphone key switches this
/// edit session to the system IME (phone-remote typing); the mic key dictates
/// in-app and is present ONLY when the device actually has a recognizer (a
/// dead mic button is worse than no button).
List<TvKey> _actionRow(int page, String submitLabel, bool voice) => [
  TvKey.action(TvKeyAction.page, label: page == 0 ? '?123' : 'ABC', flex: 3),
  TvKey.action(TvKeyAction.systemIme, icon: Icons.smartphone_rounded, flex: 3),
  if (voice)
    TvKey.action(TvKeyAction.voice, icon: Icons.mic_rounded, flex: 3),
  TvKey.action(TvKeyAction.space, icon: Icons.space_bar_rounded, flex: voice ? 5 : 6),
  TvKey.action(TvKeyAction.clear, label: 'Clear', flex: 3),
  TvKey.action(TvKeyAction.submit, label: submitLabel, flex: 4),
];

/// Highlight position + key routing for one open keyboard. Owned by the field
/// that opened it; the panel below just renders whatever this holds.
class TvKeyboardController extends ChangeNotifier {
  TvKeyboardController({
    required this.onInsert,
    required this.onBackspace,
    required this.onClear,
    required this.onSubmit,
    required this.onSystemIme,
    required this.onVoice,
    required this.onVoiceStop,
    this.submitLabel = 'Search',
    bool startShifted = false,
    bool voiceAvailable = false,
  }) : shift = startShifted,
       _voice = voiceAvailable;

  final ValueChanged<String> onInsert;
  final VoidCallback onBackspace;
  final VoidCallback onClear;
  final VoidCallback onSubmit;
  final VoidCallback onSystemIme;
  final VoidCallback onVoice;

  /// OK pressed while listening — "I'm done talking", transcribe it.
  final VoidCallback onVoiceStop;
  final String submitLabel;

  // ───────────────────────────────────────────────────────── dictation state
  // The panel swaps the key grid for a listening card while this is set, so
  // voice never puts a second surface (or a second text box) on screen.

  bool _listening = false;
  String _partial = '';
  double _level = 0;
  String? _status;
  String? _notice;

  bool get listening => _listening;

  /// Best transcript so far — empty until the engine emits its first partial.
  String get partial => _partial;

  /// Mic loudness, already normalised to 0..1 for the meter.
  double get level => _level;

  /// The line under the mic: what the recognizer is doing right now.
  String get status => _status ?? 'Listening…';

  /// Transient message shown above the keys (a declined permission, a failed
  /// session). Cleared by the owning field.
  String? get notice => _notice;

  void beginListening() {
    _listening = true;
    _partial = '';
    _level = 0;
    _status = 'Starting…';
    _notice = null;
    notifyListeners();
  }

  void updateListening({String? partial, double? level, String? status}) {
    if (!_listening) return;
    if (partial != null) _partial = partial;
    if (level != null) _level = level.clamp(0.0, 1.0);
    if (status != null) _status = status;
    notifyListeners();
  }

  /// Back to the keys. [notice] explains a failure; a clean finish passes none.
  void endListening({String? notice}) {
    if (!_listening && _notice == notice) return;
    _listening = false;
    _partial = '';
    _level = 0;
    _status = null;
    _notice = notice;
    notifyListeners();
  }

  void clearNotice() {
    if (_notice == null) return;
    _notice = null;
    notifyListeners();
  }

  /// Whether the mic key is in the action row. Set once the availability
  /// probe lands (see [setVoiceAvailable]) — the row is rebuilt from this on
  /// every render, so the key simply appears.
  bool _voice;

  /// Called when the device probe resolves. Clamps the highlight: the action
  /// row grows by one key, and a highlight sitting past the old end would
  /// otherwise point at nothing.
  void setVoiceAvailable(bool value) {
    if (_voice == value) return;
    _voice = value;
    final grid = rows;
    row = row.clamp(0, grid.length - 1);
    col = col.clamp(0, grid[row].length - 1);
    notifyListeners();
  }

  int page = 0;
  bool shift;
  int row = 0;
  int col = 0;

  List<List<TvKey>> get rows => [
    ...(page == 0 ? _letterPage(shift) : _symbolPage),
    _actionRow(page, submitLabel, _voice),
  ];

  /// Routes one key event from the owning field. Returns true when consumed
  /// (arrows + OK). Characters, back, etc. are left for the caller.
  bool handleKey(KeyEvent event) {
    if (event is KeyUpEvent) return false;
    final key = event.logicalKey;
    // While the mic is open there is no grid to navigate: OK finishes the
    // dictation early, and arrows are swallowed so a stray press can't move a
    // highlight the user can't even see. (Back is the field's — it cancels.)
    if (_listening) {
      if (isActivateKey(key)) {
        onVoiceStop();
        return true;
      }
      return key == LogicalKeyboardKey.arrowLeft ||
          key == LogicalKeyboardKey.arrowRight ||
          key == LogicalKeyboardKey.arrowUp ||
          key == LogicalKeyboardKey.arrowDown;
    }
    if (key == LogicalKeyboardKey.arrowLeft) return nav(-1, 0);
    if (key == LogicalKeyboardKey.arrowRight) return nav(1, 0);
    if (key == LogicalKeyboardKey.arrowUp) return nav(0, -1);
    if (key == LogicalKeyboardKey.arrowDown) return nav(0, 1);
    if (isActivateKey(key)) {
      activateHighlighted();
      return true;
    }
    return false;
  }

  /// Moves the highlight one step. Vertical clamps at the top/bottom rows;
  /// horizontal WRAPS — left from the leftmost key lands on the rightmost and
  /// vice versa, so long reaches across a row are one press, not nine.
  bool nav(int dx, int dy) {
    final grid = rows;
    row = (row + dy).clamp(0, grid.length - 1);
    final rowLen = grid[row].length;
    col = col.clamp(0, rowLen - 1);
    if (dx != 0) {
      col = (col + dx + rowLen) % rowLen;
    }
    notifyListeners();
    return true;
  }

  void activateHighlighted() {
    final grid = rows;
    final r = row.clamp(0, grid.length - 1);
    activate(grid[r][col.clamp(0, grid[r].length - 1)]);
  }

  void activate(TvKey key) {
    switch (key.action) {
      case TvKeyAction.insert:
        onInsert(key.insert);
        // One-shot shift, like a phone keyboard.
        if (shift) shift = false;
      case TvKeyAction.space:
        onInsert(' ');
      case TvKeyAction.backspace:
        onBackspace();
      case TvKeyAction.clear:
        onClear();
      case TvKeyAction.shift:
        shift = !shift;
      case TvKeyAction.page:
        page = page == 0 ? 1 : 0;
        row = row.clamp(0, rows.length - 1);
        col = col.clamp(0, rows[row].length - 1);
      case TvKeyAction.submit:
        onSubmit();
        return; // the field closes the keyboard; nothing left to repaint
      case TvKeyAction.systemIme:
        onSystemIme();
        return; // the field takes the panel down; nothing left to repaint
      case TvKeyAction.voice:
        onVoice();
        // The field flips this controller into its listening state once the
        // mic is actually open (permission first); nothing to repaint yet.
        return;
    }
    notifyListeners();
  }
}

/// The rendered keyboard panel. Purely presentational: highlight and layout
/// come from [controller]; pointer taps route back through it so hybrid
/// touch devices keep working.
class TvKeyboardPanel extends StatelessWidget {
  const TvKeyboardPanel({super.key, required this.controller});

  final TvKeyboardController controller;

  static const _bg = Color(0xF01A1630); // settings-panel purple, near-opaque
  static const _accent = Color(0xFF7B5CFF);

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 620),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: _bg,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
        ),
        child: ListenableBuilder(
          listenable: controller,
          builder: (context, _) {
            // Dictation takes over the panel's own body — no second surface,
            // no system text box, same box in the same place.
            if (controller.listening) {
              return _ListeningView(controller: controller);
            }
            final grid = controller.rows;
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (controller.notice != null) _NoticeBar(text: controller.notice!),
                for (var r = 0; r < grid.length; r++)
                  Row(
                    children: [
                      for (var c = 0; c < grid[r].length; c++)
                        Expanded(
                          flex: grid[r][c].flex,
                          child: _KeyCap(
                            keyDef: grid[r][c],
                            highlighted:
                                r == controller.row && c == controller.col,
                            lit:
                                grid[r][c].action == TvKeyAction.shift &&
                                controller.shift,
                            onTap: () => controller.activate(grid[r][c]),
                          ),
                        ),
                    ],
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// The panel while the microphone is open. Sized to the key grid it replaces
/// (5 rows of 44) so the panel doesn't jump when dictation starts or ends.
class _ListeningView extends StatelessWidget {
  const _ListeningView({required this.controller});

  final TvKeyboardController controller;

  @override
  Widget build(BuildContext context) {
    final heard = controller.partial;
    return SizedBox(
      height: 220,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              // Halo scales with mic loudness — the only thing on this panel
              // that animates, and it moves at most ~10 times a second
              // (native throttles the level frames) so weak TV GPUs cope.
              AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                width: 56 + 44 * controller.level,
                height: 56 + 44 * controller.level,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: TvKeyboardPanel._accent.withValues(alpha: 0.22),
                ),
              ),
              Container(
                width: 56,
                height: 56,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: TvKeyboardPanel._accent,
                ),
                alignment: Alignment.center,
                child: const Icon(
                  Icons.mic_rounded,
                  size: 28,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Fixed box: the transcript growing from one line to two must not
          // shove the mic around mid-sentence.
          SizedBox(
            height: 52,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  heard.isEmpty ? 'Speak now' : heard,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: heard.isEmpty ? 16 : 20,
                    fontWeight: heard.isEmpty ? FontWeight.w500 : FontWeight.w600,
                    color: heard.isEmpty
                        ? Colors.white.withValues(alpha: 0.55)
                        : Colors.white,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            controller.status,
            style: TextStyle(
              fontSize: 12,
              color: Colors.white.withValues(alpha: 0.55),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'OK to finish  ·  BACK to cancel',
            style: TextStyle(
              fontSize: 11,
              letterSpacing: 0.4,
              color: Colors.white.withValues(alpha: 0.38),
            ),
          ),
        ],
      ),
    );
  }
}

/// One-line explanation above the keys after a dictation that couldn't run
/// (permission declined, recognizer error). The field clears it on a timer.
class _NoticeBar extends StatelessWidget {
  const _NoticeBar({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 6, left: 2, right: 2),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: TvKeyboardPanel._accent.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(
            Icons.mic_off_rounded,
            size: 15,
            color: Colors.white.withValues(alpha: 0.75),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                color: Colors.white.withValues(alpha: 0.85),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _KeyCap extends StatelessWidget {
  const _KeyCap({
    required this.keyDef,
    required this.highlighted,
    required this.lit,
    required this.onTap,
  });

  final TvKey keyDef;
  final bool highlighted;

  /// Latched state (shift while active) when not highlighted.
  final bool lit;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // Snap, don't tween — per-keypress decoration lerps jank weak TV GPUs.
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 40,
        margin: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: highlighted
              ? TvKeyboardPanel._accent
              : lit
              ? TvKeyboardPanel._accent.withValues(alpha: 0.35)
              : Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(8),
        ),
        alignment: Alignment.center,
        child: keyDef.icon != null
            ? Icon(
                keyDef.icon,
                size: 18,
                color: highlighted
                    ? Colors.white
                    : Colors.white.withValues(alpha: 0.8),
              )
            : FittedBox(
                // Keycaps are fixed 40px boxes: at large TV font-scale
                // settings the label shrinks instead of bleeding across rows.
                fit: BoxFit.scaleDown,
                child: Text(
                  keyDef.label,
                  maxLines: 1,
                  style: TextStyle(
                    color: highlighted
                        ? Colors.white
                        : Colors.white.withValues(alpha: 0.85),
                    fontSize: 15,
                    fontWeight: highlighted ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ),
      ),
    );
  }
}
