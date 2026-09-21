/// Visibility of optional, content-bearing bands on the details page.
///
/// These are presentation choices only. Metadata provider preferences still
/// decide whether availability data is fetched at all; this policy decides
/// which pieces of that data the details page renders.
class DetailPageSectionVisibility {
  const DetailPageSectionVisibility({
    this.whereToWatch = true,
    this.rent = true,
    this.buy = true,
    this.availabilityLink = true,
    this.didYouKnow = true,
  });

  static const defaults = DetailPageSectionVisibility();

  final bool whereToWatch;
  final bool rent;
  final bool buy;
  final bool availabilityLink;
  final bool didYouKnow;

  bool get showsAnyAvailability =>
      whereToWatch || rent || buy || availabilityLink;

  bool showsAvailabilityKind(String kind) => switch (kind) {
    'flatrate' || 'free' || 'ads' => whereToWatch,
    'rent' => rent,
    'buy' => buy,
    _ => false,
  };

  DetailPageSectionVisibility copyWith({
    bool? whereToWatch,
    bool? rent,
    bool? buy,
    bool? availabilityLink,
    bool? didYouKnow,
  }) => DetailPageSectionVisibility(
    whereToWatch: whereToWatch ?? this.whereToWatch,
    rent: rent ?? this.rent,
    buy: buy ?? this.buy,
    availabilityLink: availabilityLink ?? this.availabilityLink,
    didYouKnow: didYouKnow ?? this.didYouKnow,
  );

  @override
  bool operator ==(Object other) =>
      other is DetailPageSectionVisibility &&
      other.whereToWatch == whereToWatch &&
      other.rent == rent &&
      other.buy == buy &&
      other.availabilityLink == availabilityLink &&
      other.didYouKnow == didYouKnow;

  @override
  int get hashCode =>
      Object.hash(whereToWatch, rent, buy, availabilityLink, didYouKnow);
}
