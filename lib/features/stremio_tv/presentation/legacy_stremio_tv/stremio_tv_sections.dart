import 'package:debrify/features/stremio_tv/presentation/legacy_stremio_tv/stremio_tv_bindings.dart';

class StremioTvSections {
  // TEMP(stremio_tv): direct borrowed callbacks; removed by step 5.
  final StremioTvDependencies legacy;
  StremioTvSections(StremioTvDependencies deps) : legacy = deps {
    deps.sections = this;
  }
}
