import 'dart:async';
import 'dart:isolate';
import 'package:flutter/foundation.dart';

import '../models/stream_badge_rules.dart';

enum StreamBadgeFailure { tooManyRules, preparation, matching, worker }

enum StreamBadgeMatchStatus { resolved, deferred, unavailable }

class StreamBadgeMatchResult {
  const StreamBadgeMatchResult(this.status, [this.badges = const []]);
  final StreamBadgeMatchStatus status;
  final List<StreamBadgeRule> badges;
}

/// A bounded, cancellable matcher shared by Flutter and native source lists.
/// No imported regular expression executes on the UI isolate.
class StreamBadgeMatcher {
  StreamBadgeMatcher(List<StreamBadgeRuleset> rulesets)
    : this._(rulesets, _badgeWorker);

  @visibleForTesting
  StreamBadgeMatcher.withWorker(
    List<StreamBadgeRuleset> rulesets,
    void Function(SendPort) entryPoint,
  ) : this._(rulesets, entryPoint);

  StreamBadgeMatcher._(List<StreamBadgeRuleset> rulesets, this._entryPoint)
    : rules = List.unmodifiable([
        for (final set in rulesets)
          for (final rule in set.rules)
            if (rule.enabled && rule.regex != null) rule,
      ]) {
    if (rules.length > maxRules) {
      _fail(StreamBadgeFailure.tooManyRules);
    }
  }
  final void Function(SendPort) _entryPoint;

  static final StreamBadgeMatcher empty = StreamBadgeMatcher(const []);
  final List<StreamBadgeRule> rules;
  bool get isEmpty => rules.isEmpty;
  static const maxInputLength = 8192;
  static const maxPending = 64;
  static const maxRules = 512;
  static const _matchTimeout = Duration(milliseconds: 500);
  static const _startTimeout = Duration(seconds: 3);
  static const _prepareTimeout = Duration(seconds: 5);
  static const _coldMatchTimeout = Duration(seconds: 2);
  final _cache = <String, List<StreamBadgeRule>>{};
  final _pending = <String, _BadgeRequest>{};
  Isolate? _worker;
  ReceivePort? _receive;
  ReceivePort? _errors;
  bool _prepared = false;
  bool _cold = true;
  SendPort? _send;
  Timer? _deadline;
  bool _starting = false;
  bool _disposed = false;
  bool _failed = false;
  String? _active;
  bool get failed => _failed;
  final failure = ValueNotifier<bool>(false);
  StreamBadgeFailure? _failureReason;
  StreamBadgeFailure? get failureReason => _failureReason;
  String get failureMessage => switch (failureReason) {
    StreamBadgeFailure.tooManyRules =>
      'Too many active badge rules (maximum 512). Disable or remove a preset to resume matching.',
    StreamBadgeFailure.preparation =>
      'Badge presets could not finish loading. Toggle stream badges off and on to retry, or disable a preset.',
    _ =>
      'Badge matching stopped because a preset took too long or could not run. Disable or replace the affected preset to try again.',
  };

  Future<List<StreamBadgeRule>> matchesFor({
    required String name,
    String? description,
  }) async =>
      (await matchResultFor(name: name, description: description)).badges;

  /// Already resolved badges, including a resolved empty list. A synchronous
  /// cache hit lets remounted source rows keep their very first layout instead
  /// of briefly collapsing the strip while awaiting an already completed job.
  /// This never runs patterns or starts work on the calling isolate.
  List<StreamBadgeRule>? cachedMatchesFor({
    required String name,
    String? description,
  }) {
    if (_disposed ||
        _failed ||
        name.length > maxInputLength ||
        (description?.length ?? 0) > maxInputLength) {
      return null;
    }
    final key = '$name\u0000${description ?? ''}';
    final hit = _cache.remove(key);
    if (hit != null) _cache[key] = hit;
    return hit;
  }

  Future<StreamBadgeMatchResult> matchResultFor({
    required String name,
    String? description,
  }) {
    if (_disposed || _failed) {
      return Future.value(
        const StreamBadgeMatchResult(StreamBadgeMatchStatus.unavailable),
      );
    }
    if (rules.isEmpty ||
        name.length > maxInputLength ||
        (description?.length ?? 0) > maxInputLength) {
      return Future.value(
        const StreamBadgeMatchResult(StreamBadgeMatchStatus.resolved),
      );
    }
    final key = '$name\u0000${description ?? ''}';
    final hit = cachedMatchesFor(name: name, description: description);
    if (hit != null) {
      return Future.value(
        StreamBadgeMatchResult(StreamBadgeMatchStatus.resolved, hit),
      );
    }
    final existing = _pending[key];
    if (existing != null) return existing.result.future;
    // Preserve admitted work instead of evicting it into a false empty result.
    // Mounted clients retry deferred admission; the worker queue stays bounded.
    if (_pending.length >= maxPending) {
      return Future.value(
        const StreamBadgeMatchResult(StreamBadgeMatchStatus.deferred),
      );
    }
    final request = _BadgeRequest(name, description);
    _pending[key] = request;
    _pump();
    return request.result.future;
  }

  void _pump() {
    if (_disposed || _failed || _active != null || _pending.isEmpty) return;
    if (!_prepared) {
      if (!_starting) _start();
      return;
    }
    final key = _pending.keys.first;
    _active = key;
    final request = _pending[key]!;
    _deadline = Timer(
      _cold ? _coldMatchTimeout : _matchTimeout,
      () => _fail(StreamBadgeFailure.matching),
    );
    _send!.send([key, request.name, request.description]);
  }

  Future<void> _start() async {
    _starting = true;
    final receive = ReceivePort();
    _receive = receive;
    final errors = ReceivePort();
    _errors = errors;
    errors.listen((_) => _fail(StreamBadgeFailure.worker));
    _deadline = Timer(
      _startTimeout,
      () => _fail(StreamBadgeFailure.preparation),
    );
    receive.listen((message) {
      if (_disposed || _failed) return;
      if (message is SendPort) {
        _send = message;
        _deadline?.cancel();
        _deadline = Timer(
          _prepareTimeout,
          () => _fail(StreamBadgeFailure.preparation),
        );
        _send!.send([for (final rule in rules) rule.pattern]);
      } else if (message == 'ready' && !_prepared && _send != null) {
        _prepared = true;
        _deadline?.cancel();
        _pump();
      } else if (message is List &&
          message.length == 2 &&
          message.first is String &&
          message[1] is List) {
        final key = message.first as String;
        if (key != _active) return;
        _deadline?.cancel();
        final indices = (message[1] as List).cast<int>();
        final result = List<StreamBadgeRule>.unmodifiable([
          for (final i in indices) rules[i],
        ]);
        _cold = false;
        _cache[key] = result;
        if (_cache.length > 400) _cache.remove(_cache.keys.first);
        _active = null;
        _pending
            .remove(key)
            ?.result
            .complete(
              StreamBadgeMatchResult(StreamBadgeMatchStatus.resolved, result),
            );
        _pump();
      } else {
        _fail(StreamBadgeFailure.worker);
      }
    });
    try {
      final worker = await Isolate.spawn(
        _entryPoint,
        receive.sendPort,
        onError: errors.sendPort,
        onExit: errors.sendPort,
        debugName: 'stream-badges',
      );
      if (_disposed || _failed) {
        worker.kill(priority: Isolate.immediate);
      } else {
        _worker = worker;
      }
    } catch (_) {
      _fail(StreamBadgeFailure.worker);
    }
  }

  void _fail(StreamBadgeFailure reason) {
    if (_disposed || _failed) return;
    _failed = true;
    _failureReason = reason;
    failure.value = true;
    _stop();
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _stop();
    failure.dispose();
  }

  void _stop() {
    _deadline?.cancel();
    _worker?.kill(priority: Isolate.immediate);
    _worker = null;
    _receive?.close();
    _receive = null;
    _errors?.close();
    _errors = null;
    _send = null;
    _active = null;
    for (final request in _pending.values) {
      if (!request.result.isCompleted) {
        request.result.complete(
          const StreamBadgeMatchResult(StreamBadgeMatchStatus.unavailable),
        );
      }
    }
    _pending.clear();
    _cache.clear();
  }
}

class _BadgeRequest {
  _BadgeRequest(this.name, this.description);
  final String name;
  final String? description;
  final result = Completer<StreamBadgeMatchResult>();
}

void _badgeWorker(SendPort output) {
  final input = ReceivePort();
  output.send(input.sendPort);
  List<RegExp?>? rules;
  input.listen((message) {
    final values = message as List;
    if (rules == null) {
      // Keep this entry point independent of dart:ui model instances.
      rules = [
        for (final value in values) compileBadgePattern(value as String),
      ];
      output.send('ready');
      return;
    }
    final name = values[1] as String;
    final description = values[2] as String?;
    output.send([
      values[0],
      [
        for (var i = 0; i < rules!.length; i++)
          if (rules![i]?.hasMatch(name) == true ||
              (description != null && rules![i]?.hasMatch(description) == true))
            i,
      ],
    ]);
  });
}
