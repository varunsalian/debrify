import Foundation

struct SearchResultGroup: Identifiable, Sendable {
    let id: String
    let title: String
    let symbol: String
    let items: [MediaItem]
}

@MainActor
final class UnifiedSearchService {
    private let providers: ProviderRegistry
    private let stremio: StremioService
    private let xtream: XtreamService

    init(providers: ProviderRegistry, stremio: StremioService, xtream: XtreamService) {
        self.providers = providers
        self.stremio = stremio
        self.xtream = xtream
    }

    func search(_ query: String) async -> [MediaItem] {
        await searchGroups(query).flatMap(\.items)
    }

    func searchGroups(_ query: String) async -> [SearchResultGroup] {
        let clean = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard clean.count >= 2 else { return [] }
        async let providerItems = providers.search(clean)
        async let addonItems = stremio.search(clean)
        async let iptvItems = xtream.search(clean)
        let groups = await [
            SearchResultGroup(id: "catalog", title: "Catalogs & Addons", symbol: "sparkles.tv.fill", items: addonItems),
            SearchResultGroup(id: "cloud", title: "Connected Cloud", symbol: "cloud.fill", items: providerItems),
            SearchResultGroup(id: "iptv", title: "IPTV", symbol: "dot.radiowaves.left.and.right", items: iptvItems)
        ]
        return groups.filter { !$0.items.isEmpty }
    }
}
