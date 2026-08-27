import 'file.dart';

/// An offline download PikPak is working on: a magnet it is fetching into the
/// user's drive.
///
/// [fileId] is what the caller polls and eventually plays; it is set as soon as
/// PikPak has created the destination entry, which is usually before [phase]
/// reaches [PikPakPhase.complete].
class PikPakTask {
  final String id;
  final String name;

  /// The drive entry this task is filling in. Empty until PikPak creates it.
  final String fileId;

  final PikPakPhase phase;

  /// 0–100. PikPak omits it on tasks that have not started.
  final int progress;

  /// PikPak's own explanation when [phase] is [PikPakPhase.error].
  final String? message;

  const PikPakTask({
    required this.id,
    required this.name,
    required this.fileId,
    required this.phase,
    this.progress = 0,
    this.message,
  });

  bool get isComplete => phase == PikPakPhase.complete;
  bool get hasFailed => phase == PikPakPhase.error;
  bool get isRunning =>
      phase == PikPakPhase.running || phase == PikPakPhase.pending;

  /// PikPak answers an add in three shapes and the caller cannot tell which in
  /// advance: `{task: {...}}` with the destination in `file_id`, `{file: {...}}`
  /// where the entry's own `id` IS the destination, or a bare task from
  /// getTaskStatus. All three land here so no call site has to branch.
  static PikPakTask fromJson(Map json) {
    if (json['file'] is Map) {
      final file = json['file'] as Map;
      final id = '${file['id'] ?? ''}';
      return PikPakTask(
        id: id,
        name: '${file['name'] ?? ''}',
        fileId: id,
        phase: PikPakPhase.parse(file['phase']),
        progress: int.tryParse('${file['progress'] ?? ''}') ?? 0,
      );
    }

    final map = json['task'] is Map ? json['task'] as Map : json;
    return PikPakTask(
      id: '${map['id'] ?? ''}',
      name: '${map['name'] ?? ''}',
      fileId: '${map['file_id'] ?? ''}',
      phase: PikPakPhase.parse(map['phase']),
      progress: int.tryParse('${map['progress'] ?? ''}') ?? 0,
      message: switch (map['message']) {
        final String text when text.isNotEmpty => text,
        _ => null,
      },
    );
  }

  /// The drive entry to poll and eventually play, or null while PikPak has not
  /// created it yet. Never falls back to [id]: in the `{task: ...}` shape that
  /// is a task id, and polling it as a file id always fails.
  String? get destinationId => fileId.isEmpty ? null : fileId;
}
