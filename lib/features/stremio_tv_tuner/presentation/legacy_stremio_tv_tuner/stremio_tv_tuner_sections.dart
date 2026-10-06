import 'package:debrify/features/stremio_tv_tuner/presentation/legacy_stremio_tv_tuner/stremio_tv_tuner_channels.dart';
import 'package:debrify/features/stremio_tv_tuner/presentation/legacy_stremio_tv_tuner/stremio_tv_tuner_dependencies.dart';
import 'package:debrify/features/stremio_tv_tuner/presentation/legacy_stremio_tv_tuner/stremio_tv_tuner_dial.dart';
import 'package:debrify/features/stremio_tv_tuner/presentation/legacy_stremio_tv_tuner/stremio_tv_tuner_layout.dart';
import 'package:debrify/features/stremio_tv_tuner/presentation/legacy_stremio_tv_tuner/stremio_tv_tuner_sheets.dart';

class StremioTvTunerSections {
  late final StremioTvTunerChannels channels;
  late final StremioTvTunerDial dial;
  late final StremioTvTunerSheets sheets;
  late final StremioTvTunerLayout layout;
  StremioTvTunerSections(StremioTvTunerDependencies deps) {
    channels = StremioTvTunerChannels(deps);
    dial = StremioTvTunerDial(deps);
    sheets = StremioTvTunerSheets(deps);
    layout = StremioTvTunerLayout(deps);
  }
}
