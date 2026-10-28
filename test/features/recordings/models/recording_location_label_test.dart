// The location label shared by the recording snackbars and the DVR footer:
// a custom SAF tree names itself (display name, or "Chosen folder" when the
// picker gave none), a custom desktop path passes through verbatim, and
// everything else falls back to the default folder text. Pure function, so
// no SharedPreferences or store setup is needed here.

import 'package:debrify/features/recordings/models/recording_output_settings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('recordingLocationLabel', () {
    test('default settings show the default folder', () {
      expect(
        recordingLocationLabel(const RecordingOutputSettings()),
        'Downloads/Debrify/Recordings',
      );
    });

    test('a SAF tree with a display name shows that name', () {
      expect(
        recordingLocationLabel(
          const RecordingOutputSettings(
            treeUri: 'content://tree',
            treeDisplayName: 'Network Share',
          ),
        ),
        'Network Share',
      );
    });

    test('a SAF tree without a usable display name says Chosen folder', () {
      expect(
        recordingLocationLabel(
          const RecordingOutputSettings(treeUri: 'content://tree'),
        ),
        'Chosen folder',
      );
      expect(
        recordingLocationLabel(
          const RecordingOutputSettings(
            treeUri: 'content://tree',
            treeDisplayName: '',
          ),
        ),
        'Chosen folder',
      );
    });

    test('a custom desktop path is shown verbatim', () {
      expect(
        recordingLocationLabel(
          const RecordingOutputSettings(directoryPath: '/mnt/share/recordings'),
        ),
        '/mnt/share/recordings',
      );
    });

    test('an empty tree uri falls through to the path, then the default', () {
      expect(
        recordingLocationLabel(
          const RecordingOutputSettings(
            treeUri: '',
            directoryPath: r'D:\Recordings',
          ),
        ),
        r'D:\Recordings',
      );
      expect(
        recordingLocationLabel(const RecordingOutputSettings(treeUri: '')),
        'Downloads/Debrify/Recordings',
      );
    });
  });
}
