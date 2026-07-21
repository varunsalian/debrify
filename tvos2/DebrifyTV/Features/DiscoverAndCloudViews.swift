import SwiftUI

struct DiscoverView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var shelves: [CatalogShelf] = []
    @State private var discoveryShelves: [DiscoveryShelf] = []
    @State private var type = "all"
    @State private var loading = true

    private var filtered: [CatalogShelf] {
        type == "all" ? shelves : shelves.filter { $0.catalog.type == type }
    }

    private var filteredDiscovery: [DiscoveryShelf] {
        guard type != "all" else { return discoveryShelves }
        return discoveryShelves.compactMap { shelf in
            let items = shelf.items.filter { $0.mediaType == type }
            return items.isEmpty ? nil : DiscoveryShelf(id: shelf.id, title: shelf.title, subtitle: shelf.subtitle, items: items)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            ScreenHeader(title: "Discover", subtitle: "Browse every installed addon catalog") { environment.select(.search) }
            Picker("Media type", selection: $type) {
                Text("Everything").tag("all"); Text("Movies").tag("movie"); Text("Series").tag("series")
            }.pickerStyle(.segmented).frame(maxWidth: 680)

            if loading { ProgressView("Loading discovery catalogs…").frame(maxWidth: .infinity, maxHeight: .infinity) }
            else if filtered.isEmpty && filteredDiscovery.isEmpty { EmptyState(symbol: "safari", title: "No catalogs", message: "Install an addon with movie or series catalogs, then return here.") }
            else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 34) {
                        ForEach(filteredDiscovery) { shelf in DiscoveryMediaShelf(shelf: shelf) }
                        ForEach(filtered) { shelf in DiscoverRow(shelf: shelf) }
                    }.padding(18)
                }
            }
        }
        .padding(48).background(DebrifyTheme.background)
        .task {
            async let discovery: Void = loadDiscovery()
            async let addons: Void = load()
            _ = await (discovery, addons)
        }
    }

    private func load() async {
        loading = true
        defer { loading = false }
        var result: [CatalogShelf] = []
        for addon in environment.stremio.addons {
            for catalog in addon.catalogs where ["movie", "series"].contains(catalog.type) && catalog.extra?.contains(where: { $0.isRequired == true }) != true {
                guard let items = try? await environment.stremio.catalog(catalog, addon: addon), !items.isEmpty else { continue }
                result.append(CatalogShelf(id: "discover:\(addon.id):\(catalog.type):\(catalog.id)", title: catalog.name ?? "\(addon.name) · \(catalog.type.capitalized)", addonID: addon.id, catalog: catalog, items: Array(items.prefix(12))))
                shelves = result
            }
        }
    }

    private func loadDiscovery() async {
        discoveryShelves = await environment.discovery.homeShelves()
    }
}

private struct DiscoverRow: View {
    @Environment(AppEnvironment.self) private var environment
    let shelf: CatalogShelf
    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                VStack(alignment: .leading) {
                    Text(shelf.title).font(.title2.bold())
                    Text(shelf.catalog.type.capitalized).foregroundStyle(DebrifyTheme.muted)
                }
                Spacer()
                Button("See All") { environment.open(.seeAll(shelf.catalog, shelf.addonID)) }.buttonStyle(.bordered)
            }
            ScrollView(.horizontal) {
                LazyHStack(spacing: 27) {
                    ForEach(shelf.items) { item in MediaCard(item: item) { environment.open(.details(item)) } }
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 18)
            }
            .scrollClipDisabled()
        }
    }
}

struct CatalogSeeAllView: View {
    @Environment(AppEnvironment.self) private var environment
    let catalog: AddonCatalog
    let addonID: String
    @State private var items: [MediaItem] = []
    @State private var loading = false
    @State private var reachedEnd = false
    @State private var error: String?
    @State private var sort = "default"

    private var visibleItems: [MediaItem] {
        switch sort {
        case "title": items.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case "year": items.sorted { ($0.year ?? 0) > ($1.year ?? 0) }
        default: items
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                ScreenHeader(title: catalog.name ?? catalog.id, subtitle: "\(catalog.type.capitalized) · infinite catalog")
                Picker("Sort", selection: $sort) { Text("Catalog order").tag("default"); Text("Title").tag("title"); Text("Newest").tag("year") }.frame(width: 330)
            }
            if let error, items.isEmpty { EmptyState(symbol: "exclamationmark.triangle", title: "Catalog unavailable", message: error) }
            else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 210), spacing: 27)], spacing: 30) {
                        ForEach(visibleItems) { item in
                            MediaCard(item: item) { environment.open(.details(item)) }
                                .onAppear { if item.id == visibleItems.last?.id { Task { await loadMore() } } }
                        }
                        if loading { ProgressView().frame(width: 210, height: 315) }
                    }.padding(18)
                }
            }
        }
        .padding(48).background(DebrifyTheme.background)
        .task { await loadMore() }
    }

    private func loadMore() async {
        guard !loading, !reachedEnd, let addon = environment.stremio.addons.first(where: { $0.id == addonID }) else { return }
        loading = true
        defer { loading = false }
        do {
            let page = try await environment.stremio.catalog(catalog, addon: addon, skip: items.count)
            var known = Set(items.map(\.id))
            let additions = page.filter { known.insert($0.id).inserted }
            items.append(contentsOf: additions)
            reachedEnd = additions.isEmpty
            error = nil
        } catch { self.error = error.localizedDescription }
    }
}

struct CloudView: View {
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 28) {
                ScreenHeader(title: "Cloud", subtitle: "All debrid providers and WebDAV in one place") { environment.select(.search) }
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 20), count: 3),
                    spacing: 20
                ) {
                    ForEach(ProviderKind.allCases) { kind in
                        Button { environment.open(environment.providers.connected.contains(kind) ? .providerLibrary(kind) : .providerAccount(kind)) } label: {
                            CloudServiceCard(title: kind.rawValue, detail: environment.providers.connected.contains(kind) ? "Connected · Browse files" : "Connect securely", symbol: kind == .torBox ? "shippingbox.fill" : "bolt.horizontal.circle.fill", connected: environment.providers.connected.contains(kind))
                        }.debrifyCardButton()
                    }
                    Button { environment.select(.webDAV) } label: {
                        CloudServiceCard(title: "WebDAV", detail: environment.webDAV.configuration == nil ? "Connect an HTTPS server" : "Connected · Browse files", symbol: "externaldrive.connected.to.line.below.fill", connected: environment.webDAV.configuration != nil)
                    }.debrifyCardButton()
                }
                Text("Downloads & transfers").font(.title2.bold())
                Button { environment.select(.downloads) } label: {
                    Label("View active and completed transfers", systemImage: "arrow.down.circle.fill").font(.title2.bold()).padding(28).frame(maxWidth: .infinity, alignment: .leading)
                }.debrifyCardButton()
            }.padding(48)
        }.background(DebrifyTheme.background)
    }
}

private struct CloudServiceCard: View {
    let title: String
    let detail: String
    let symbol: String
    let connected: Bool
    var body: some View {
        HStack(spacing: 20) {
            Image(systemName: symbol).font(.system(size: 31)).foregroundStyle(DebrifyTheme.indigoLight).frame(width: 45)
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.headline.bold()).lineLimit(1).minimumScaleFactor(0.78)
                Text(detail).font(.caption).foregroundStyle(DebrifyTheme.muted).lineLimit(2)
            }
            Spacer()
            Image(systemName: connected ? "checkmark.circle.fill" : "chevron.right").foregroundStyle(connected ? DebrifyTheme.success : DebrifyTheme.muted)
        }.padding(18).frame(maxWidth: .infinity, minHeight: 96)
    }
}
