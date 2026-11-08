import 'package:debrify/services/startup_error_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // mpv's wording for each case. Not every line reaches the error stream
  // (media_kit forwards only some modules and levels); the rules still have
  // to classify whatever does arrive correctly.
  const fatal = {
    'Failed to open https://cdn.example/movie.mkv.': 'open_failed',
    "Cannot open file '/tmp/x.mkv': No such file or directory": 'open_failed',
    'No protocol handler found to open URL foo://x': 'open_failed',
    'The protocol is either unsupported, or was disabled at compile-time.':
        'open_failed',
    'Failed to open https://cdn.example/movie.mkv?sub=en.srt.': 'open_failed',
    'Failed to open https://cdn.sub.example/movie.mkv.': 'open_failed',
    'Failed to recognize file format.': 'format',
    'No video or audio streams selected.': 'no_streams',
    'Could not open codec.': 'codec',
    "Failed to initialize a decoder for codec 'hevc'.": 'codec',
    'Error opening/initializing the selected video_out (--vo) device.':
        'video_output',
    'tcp: Connection to tcp://10.0.0.1:80 failed: Connection refused':
        'network',
    'HTTP 403 Forbidden': 'http_status',
    'http error 404': 'http_status',
    'Server said HTTP: 503': 'http_status',
  };
  const benign = {
    'Could not open/initialize audio device -> no sound.': 'audio_device',
    'Failed to open https://subs.example/track.vtt?token=a.': 'subtitle',
    'Failed to open /tmp/addon-subs/en.srt.': 'subtitle',
    'Can not open external file https://audio.example/track.m4a.':
        'external_file',
    'Error while decoding frame!': 'decode',
    'Error decoding audio.': 'audio_decode',
    "Cannot open file '/tmp/addon-subs/en.srt': No such file or directory":
        'subtitle',
    'h264: Failed setup for format videotoolbox_vld: hwaccel initialisation '
            'returned error.':
        'hwdec',
  };
  const unknown = [
    'Something odd at https://host.example/secret-token',
    'Reconnect to https://host.example:443/a failed once',
    'Segment https://host.example/500/chunk.ts was slow',
    'Server returned 404 Not Found',
    'Connection refused',
  ];

  group('StartupErrorPolicy.classify', () {
    for (final entry in fatal.entries) {
      test('fatal: ${entry.key}', () {
        final type = StartupErrorPolicy.classify(entry.key);
        expect(type.kind, StartupErrorKind.fatal);
        expect(type.label, entry.value);
      });
    }
    for (final entry in benign.entries) {
      test('benign: ${entry.key}', () {
        final type = StartupErrorPolicy.classify(entry.key);
        expect(type.kind, StartupErrorKind.benign);
        expect(type.label, entry.value);
      });
    }
    for (final message in unknown) {
      test('unknown, labelled without its text: $message', () {
        final type = StartupErrorPolicy.classify(message);
        expect(type.kind, StartupErrorKind.unknown);
        expect(type.label, 'other');
      });
    }
  });

  group('StartupErrorTally', () {
    StartupErrorClass of(String message) =>
        StartupErrorPolicy.classify(message);

    test('VOD leaves unknown errors to the timeout; channels reject them', () {
      final unknownError = of('fixture ordinary source error');
      expect(
        StartupErrorTally(rejectUnknown: false).rejects(unknownError),
        isFalse,
      );
      expect(
        StartupErrorTally(rejectUnknown: true).rejects(unknownError),
        isTrue,
      );
    });

    test('benign errors never reject, except decode errors that repeat', () {
      final tally = StartupErrorTally(rejectUnknown: true);
      for (var i = 0; i < 100; i++) {
        expect(
          tally.rejects(of('Could not open/initialize audio device')),
          isFalse,
        );
      }
      final decode = of('Error while decoding frame!');
      for (var i = 1; i < StartupErrorTally.maxDecodeErrors; i++) {
        expect(tally.rejects(decode), isFalse, reason: 'decode error $i');
      }
      expect(tally.rejects(decode), isTrue);
    });

    test('broken audio never counts towards the decode bound', () {
      final tally = StartupErrorTally(rejectUnknown: true);
      final audio = of('Error decoding audio.');
      for (var i = 0; i < StartupErrorTally.maxDecodeErrors * 2; i++) {
        expect(tally.rejects(audio), isFalse);
      }
    });

    test('a connection failure after data arrived is left to the timeout', () {
      final tally = StartupErrorTally(rejectUnknown: false);
      final network = of('tcp: Connection reset by peer');
      expect(tally.rejects(network), isTrue);
      expect(tally.rejects(network, hasData: true), isFalse);
      expect(tally.rejects(of('Failed to open x.mkv'), hasData: true), isTrue);
    });

    test('each label is new once per attempt', () {
      final tally = StartupErrorTally(rejectUnknown: false);
      expect(tally.isFirst('decode'), isTrue);
      expect(tally.isFirst('decode'), isFalse);
      expect(tally.isFirst('audio_device'), isTrue);
    });
  });
}
