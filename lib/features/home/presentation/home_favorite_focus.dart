import 'package:flutter/painting.dart' show BoxFit;

class HomeFavoriteFocus {
  final String? art;
  final BoxFit fit;
  final String title;
  final String subtitle;
  const HomeFavoriteFocus({
    required this.art,
    this.fit = BoxFit.cover,
    required this.title,
    required this.subtitle,
  });
}
