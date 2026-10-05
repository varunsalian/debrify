import 'package:debrify/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_bindings.dart';

class DebrifyTvSections {
  // TEMP(debrify_tv): borrows remaining facade callbacks; removed in step 7.
  final DebrifyTvDependencies legacy;
  DebrifyTvSections(DebrifyTvDependencies deps) : legacy = deps {
    deps.sections = this;
  }
}
