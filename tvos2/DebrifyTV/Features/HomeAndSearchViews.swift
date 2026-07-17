import SwiftUI
import UIKit

struct CatalogShelf: Identifiable {
    let id: String
    let title: String
    let addonID: String
    let catalog: AddonCatalog
    let items: [MediaItem]
}

struct HomeView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var shelves: [CatalogShelf] = []
    @State private var discoveryShelves: [DiscoveryShelf] = []
    @State private var loading = true

    private var hero: MediaItem? {
        environment.continueWatching.first ?? discoveryShelves.first?.items.first ?? shelves.first?.items.first
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 34) {
                if let hero { HomeHero(item: hero) }
                else { ScreenHeader(title: "Home", subtitle: "Your secure Stremio-style catalog board") { environment.select(.search) } }

                if !environment.continueWatching.isEmpty {
                    MediaShelf(title: "Continue Watching", items: environment.continueWatching)
                }
                if !environment.favorites.isEmpty {
                    MediaShelf(title: "Favorites", items: environment.favorites)
                }
                if !environment.playlist.isEmpty {
                    MediaShelf(title: "Your Playlist", items: environment.playlist)
                }

                ForEach(discoveryShelves) { shelf in
                    DiscoveryMediaShelf(shelf: shelf)
                }

                ForEach(shelves) { shelf in
                    CatalogShelfView(shelf: shelf)
                }

                if loading { ProgressView("Loading addon catalogs…").frame(maxWidth: .infinity).padding(80) }
                else if shelves.isEmpty && environment.continueWatching.isEmpty {
                    EmptyState(symbol: "sparkles.tv", title: "Build your home", message: "Install an HTTPS Stremio addon to add catalogs. Cinemeta is installed automatically.")
                        .frame(height: 380)
                }
            }
            .padding(48)
        }
        .background(DebrifyTheme.background)
        .task {
            async let discovery: Void = loadDiscovery()
            async let catalogs: Void = loadCatalogs()
            _ = await (discovery, catalogs)
        }
    }

    private func loadCatalogs() async {
        loading = true
        defer { loading = false }
        var loaded: [CatalogShelf] = []
        for addon in environment.stremio.addons {
            for catalog in addon.catalogs.prefix(4) where catalog.extra?.contains(where: { $0.isRequired == true }) != true {
                guard let items = try? await environment.stremio.catalog(catalog, addon: addon), !items.isEmpty else { continue }
                loaded.append(CatalogShelf(id: "\(addon.id):\(catalog.type):\(catalog.id)", title: catalog.name ?? "\(addon.name) · \(catalog.type.capitalized)", addonID: addon.id, catalog: catalog, items: Array(items.prefix(16))))
                shelves = loaded
                if loaded.count >= 7 { return }
            }
        }
    }

    private func loadDiscovery() async {
        discoveryShelves = await environment.discovery.homeShelves()
    }
}

private struct HomeHero: View {
    @Environment(AppEnvironment.self) private var environment
    let item: MediaItem
    @State private var findingTrailer = false

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            RemoteImage(url: item.backdropURL ?? item.posterURL)
                .frame(height: 480).clipped()
                .overlay(LinearGradient(colors: [.clear, DebrifyTheme.background.opacity(0.45), DebrifyTheme.background], startPoint: .top, endPoint: .bottom))
            VStack(alignment: .leading, spacing: 15) {
                Text(item.title).font(.system(size: 52, weight: .bold)).lineLimit(1)
                Text(item.overview ?? "Discover movies and series from your installed catalogs.")
                    .font(.title3).foregroundStyle(.white.opacity(0.78)).lineLimit(3).frame(maxWidth: 850, alignment: .leading)
                HStack(spacing: 16) {
                    Button { environment.open(.details(item)) } label: { Label("Details", systemImage: "play.fill") }
                        .buttonStyle(.borderedProminent).tint(DebrifyTheme.indigo)
                    Button { Task { await openTrailer() } } label: { Label(findingTrailer ? "Finding…" : "Trailer", systemImage: "play.rectangle.fill") }
                        .buttonStyle(.bordered).disabled(findingTrailer)
                    Button { environment.toggleFavorite(item) } label: {
                        Label(environment.isFavorite(item) ? "Favorited" : "Favorite", systemImage: environment.isFavorite(item) ? "heart.fill" : "heart")
                    }.buttonStyle(.bordered)
                }
            }.padding(42)
        }
        .clipShape(RoundedRectangle(cornerRadius: 26))
    }

    private func openTrailer() async {
        findingTrailer = true
        defer { findingTrailer = false }
        guard let url = await environment.stremio.trailerURL(for: item) else {
            environment.toast = "No trailer was provided for this title"
            return
        }
        await UIApplication.shared.open(url)
    }
}

struct MediaShelf: View {
    @Environment(AppEnvironment.self) private var environment
    let title: String
    let items: [MediaItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title).font(.title2.bold())
            ScrollView(.horizontal) {
                LazyHStack(spacing: 27) {
                    ForEach(items) { item in MediaCard(item: item) { environment.open(.details(item)) } }
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 18)
            }
            .scrollClipDisabled()
        }
    }
}

struct DiscoveryMediaShelf: View {
    @Environment(AppEnvironment.self) private var environment
    let shelf: DiscoveryShelf

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(shelf.title).font(.title2.bold())
            Text(shelf.subtitle).font(.subheadline).foregroundStyle(DebrifyTheme.muted)
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

private struct CatalogShelfView: View {
    @Environment(AppEnvironment.self) private var environment
    let shelf: CatalogShelf

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(shelf.title).font(.title2.bold())
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

struct SearchView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var query = ""
    @State private var groups: [SearchResultGroup] = []
    @State private var activeSource = "all"
    @State private var typeFilter = "all"
    @State private var sort = "relevance"
    @State private var selected = Set<String>()
    @State private var selectionMode = false
    @State private var isLoading = false

    private var visibleGroups: [SearchResultGroup] {
        groups.compactMap { group in
            guard activeSource == "all" || activeSource == group.id else { return nil }
            var items = group.items.filter { typeFilter == "all" || $0.mediaType == typeFilter }
            if sort == "title" { items.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending } }
            if sort == "year" { items.sort { ($0.year ?? 0) > ($1.year ?? 0) } }
            return items.isEmpty ? nil : SearchResultGroup(id: group.id, title: group.title, symbol: group.symbol, items: items)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("Search").font(.largeTitle.bold())
                Spacer()
                Button(selectionMode ? "Done" : "Select") { selectionMode.toggle(); if !selectionMode { selected.removeAll() } }.buttonStyle(.bordered)
                if selectionMode && !selected.isEmpty {
                    Button("Add \(selected.count) to Playlist") { addSelectionToPlaylist() }.buttonStyle(.borderedProminent).tint(DebrifyTheme.indigo)
                }
            }
            HStack {
                TextField("Movies, shows, IPTV, and cloud files", text: $query)
                    .textFieldStyle(.plain).font(.title2).padding(18).background(DebrifyTheme.surface, in: RoundedRectangle(cornerRadius: 15))
                    .onSubmit { Task { await performSearch() } }
                Button("Search") { Task { await performSearch() } }.buttonStyle(.borderedProminent).tint(DebrifyTheme.indigo)
            }.focusSection()
            SearchControls(activeSource: $activeSource, typeFilter: $typeFilter, sort: $sort)

            if isLoading { ProgressView("Searching each connected engine…").frame(maxWidth: .infinity, maxHeight: .infinity) }
            else if visibleGroups.isEmpty {
                EmptyState(symbol: "magnifyingglass", title: query.isEmpty ? "Search everything" : "No matching results", message: "Results appear separately from addons, cloud providers, and IPTV so you can see where each source came from.")
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 30) {
                        ForEach(visibleGroups) { group in
                            VStack(alignment: .leading, spacing: 14) {
                                Label(group.title, systemImage: group.symbol).font(.title2.bold())
                                LazyVGrid(columns: [GridItem(.adaptive(minimum: 210), spacing: 26)], spacing: 28) {
                                    ForEach(group.items) { item in
                                        ZStack(alignment: .topLeading) {
                                            MediaCard(item: item) { activate(item) }
                                            if selectionMode {
                                                Image(systemName: selected.contains(item.id) ? "checkmark.circle.fill" : "circle")
                                                    .font(.title).foregroundStyle(selected.contains(item.id) ? DebrifyTheme.indigoLight : .white)
                                                    .padding(10)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }.padding(18)
                }
            }
        }
        .padding(48).background(DebrifyTheme.background)
    }

    private func performSearch() async {
        isLoading = true
        selected.removeAll()
        groups = await environment.search.searchGroups(query)
        isLoading = false
    }

    private func activate(_ item: MediaItem) {
        if selectionMode {
            if !selected.insert(item.id).inserted { selected.remove(item.id) }
        } else { environment.open(.details(item)) }
    }

    private func addSelectionToPlaylist() {
        for item in groups.flatMap(\.items) where selected.contains(item.id) { environment.addToPlaylist(item) }
        selected.removeAll(); selectionMode = false
    }
}

private struct SearchControls: View {
    @Binding var activeSource: String
    @Binding var typeFilter: String
    @Binding var sort: String

    var body: some View {
        HStack(spacing: 16) {
            Picker("Source", selection: $activeSource) {
                Text("All Sources").tag("all"); Text("Catalogs").tag("catalog"); Text("Cloud").tag("cloud"); Text("IPTV").tag("iptv")
            }.frame(width: 350)
            Picker("Type", selection: $typeFilter) {
                Text("All Types").tag("all"); Text("Movies").tag("movie"); Text("Series").tag("series")
            }.frame(width: 300)
            Picker("Sort", selection: $sort) {
                Text("Relevance").tag("relevance"); Text("Title").tag("title"); Text("Newest").tag("year")
            }.frame(width: 300)
        }.focusSection()
    }
}

struct DebrifyTVView: View {
    @Environment(AppEnvironment.self) private var environment
    var body: some View {
        EmptyState(symbol: "rectangle.stack.badge.play.fill", title: "Now built into Search", message: "Catalog discovery, Torrentio sources, connected clouds, and IPTV are unified in the new Search tab.")
            .overlay(alignment: .bottom) { Button("Open Search") { environment.select(.search) }.buttonStyle(.borderedProminent).tint(DebrifyTheme.indigo).padding(80) }
    }
}
