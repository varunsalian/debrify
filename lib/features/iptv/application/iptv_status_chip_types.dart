/// State of the bottom-right background-refresh chip.
enum CatalogChipState { hidden, updating, success, failure }

/// Who currently owns the single status chip, in priority order.
///
/// Background jobs overlap — the guide download starts when the list is
/// presented, the maintenance pipeline two seconds later, and a refresh after
/// that — so without a rank the last writer wins and the chip flickers between
/// unrelated messages. News about the LIST itself outranks news about the
/// guide, and a stage only clears the chip if it still holds it.
enum ChipOwner { none, guide, maintenance, refresh }
