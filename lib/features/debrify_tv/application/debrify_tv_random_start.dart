const int randomStartPercentDefault = 20;
const int randomStartPercentMin = 10;
const int randomStartPercentMax = 90;
int clampDebrifyTvRandomStartPercent(int? value) {
  final candidate = value ?? randomStartPercentDefault;
  if (candidate < randomStartPercentMin) {
    return randomStartPercentMin;
  }
  if (candidate > randomStartPercentMax) {
    return randomStartPercentMax;
  }
  return candidate;
}

int _parseRandomStartPercent(dynamic value) {
  if (value is int) {
    return clampDebrifyTvRandomStartPercent(value);
  }
  if (value is double) {
    return clampDebrifyTvRandomStartPercent(value.round());
  }
  if (value is String) {
    final parsed = int.tryParse(value);
    if (parsed != null) {
      return clampDebrifyTvRandomStartPercent(parsed);
    }
  }
  return randomStartPercentDefault;
}
