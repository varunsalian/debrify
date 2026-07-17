import SwiftUI
import UIKit

struct AddonsView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var manifestURL = ""
    @State private var error: String?
    @State private var installing = false
    @FocusState private var urlFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 25) {
            ScreenHeader(title: "Addons", subtitle: "Install secure Stremio-compatible catalogs")
            Text("Marketplace").font(.title2.bold())
            HStack(spacing: 24) {
                MarketplaceCard(
                    title: "Cinemeta",
                    detail: "Official movie and series metadata catalogs",
                    symbol: "film.stack.fill",
                    actionTitle: environment.stremio.addons.contains(where: { $0.id.lowercased().contains("cinemeta") }) ? "Installed" : "Install"
                ) { Task { await installPreset(StremioService.cinemetaManifestURL) } }
                MarketplaceCard(
                    title: "Torrentio & personal addons",
                    detail: "Paste your personalized HTTPS manifest below. Tokens remain in Keychain.",
                    symbol: "link.badge.plus",
                    actionTitle: "Enter URL"
                ) { urlFocused = true }
            }
            HStack {
                TextField("https://example.com/manifest.json", text: $manifestURL)
                    .textFieldStyle(.plain).padding(18).background(DebrifyTheme.surface, in: RoundedRectangle(cornerRadius: 15))
                    .focused($urlFocused)
                Button(installing ? "Installing…" : "Install") { Task { await install() } }
                    .buttonStyle(.borderedProminent).tint(DebrifyTheme.indigo).disabled(manifestURL.isEmpty || installing)
            }
            if let error { Text(error).foregroundStyle(.red) }
            if environment.stremio.addons.isEmpty {
                EmptyState(symbol: "puzzlepiece.extension", title: "No addons installed", message: "Only HTTPS public-network manifests are accepted. Addons cannot access this Apple TV or private devices on your network.")
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 380), spacing: 25)], spacing: 25) {
                        ForEach(environment.stremio.addons) { addon in
                            VStack(alignment: .leading, spacing: 13) {
                                HStack { RemoteImage(url: addon.logo).frame(width: 70, height: 70).clipShape(RoundedRectangle(cornerRadius: 14)); Text(addon.name).font(.title2.bold()) }
                                Text(addon.description ?? "Stremio addon").foregroundStyle(DebrifyTheme.muted).lineLimit(3)
                                Text("\(addon.catalogs.count) catalogs").font(.caption)
                                Button("Remove", role: .destructive) {
                                    do { try environment.stremio.remove(addon) }
                                    catch { self.error = error.localizedDescription }
                                }.buttonStyle(.bordered)
                            }.padding(24).frame(maxWidth: .infinity, minHeight: 220, alignment: .leading).debrifyCard()
                        }
                    }.padding(18)
                }
            }
        }.padding(55)
    }

    private func install() async {
        guard let url = URL(string: manifestURL) else { error = "Enter a valid HTTPS URL"; return }
        installing = true; defer { installing = false }
        do { _ = try await environment.stremio.install(manifestURL: url); manifestURL = ""; error = nil }
        catch { self.error = error.localizedDescription }
    }

    private func installPreset(_ url: URL) async {
        installing = true; defer { installing = false }
        do { _ = try await environment.stremio.install(manifestURL: url); error = nil }
        catch { self.error = error.localizedDescription }
    }
}

private struct MarketplaceCard: View {
    let title: String
    let detail: String
    let symbol: String
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            Label(title, systemImage: symbol).font(.title2.bold())
            Text(detail).foregroundStyle(DebrifyTheme.muted).lineLimit(2)
            Spacer()
            Button(actionTitle, action: action).buttonStyle(.borderedProminent).tint(DebrifyTheme.indigo)
        }.padding(24).frame(maxWidth: .infinity, minHeight: 190, alignment: .leading).debrifyCard()
    }
}

struct StremioView: View {
    @Environment(AppEnvironment.self) private var environment
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 34) {
                ScreenHeader(title: "Stremio TV", subtitle: "Catalogs from installed addons") { environment.open(.search) }
                if environment.stremio.addons.isEmpty {
                    EmptyState(symbol: "sparkles.tv", title: "Install an addon first", message: "Open Addons from the sidebar to add a secure public manifest.").frame(height: 500)
                } else {
                    ForEach(environment.stremio.addons) { addon in
                        VStack(alignment: .leading, spacing: 18) {
                            Text(addon.name).font(.title2.bold())
                            ScrollView(.horizontal) {
                                HStack(spacing: 22) {
                                    ForEach(addon.catalogs) { catalog in
                                        Button { environment.open(.stremioCatalog(catalog)) } label: {
                                            VStack(alignment: .leading, spacing: 16) {
                                                Image(systemName: "rectangle.stack.fill").font(.system(size: 48)).foregroundStyle(DebrifyTheme.indigoLight)
                                                Text(catalog.name ?? catalog.id).font(.headline)
                                                Text(catalog.type.capitalized).foregroundStyle(DebrifyTheme.muted)
                                            }.padding(24).frame(width: 300, height: 160, alignment: .leading)
                                        }.debrifyCardButton()
                                    }
                                }.padding(18)
                            }
                        }
                    }
                }
            }.padding(55)
        }
    }
}

struct StremioCatalogView: View {
    @Environment(AppEnvironment.self) private var environment
    let catalog: AddonCatalog
    @State private var items: [MediaItem] = []
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 25) {
            ScreenHeader(title: catalog.name ?? catalog.id, subtitle: catalog.type.capitalized)
            if let error { EmptyState(symbol: "exclamationmark.triangle", title: "Catalog unavailable", message: error) }
            else if items.isEmpty { ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity) }
            else { ScrollView { LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 30)], spacing: 30) { ForEach(items) { item in MediaCard(item: item) { environment.open(.details(item)) } } }.padding(18) } }
        }.padding(55).background(DebrifyTheme.background).task { await load() }
    }

    private func load() async {
        guard let addon = environment.stremio.addons.first(where: { $0.catalogs.contains(catalog) }) else { error = "The addon was removed"; return }
        do { items = try await environment.stremio.catalog(catalog, addon: addon) } catch { self.error = error.localizedDescription }
    }
}

struct WebDAVView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var entries: [WebDAVEntry] = []
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 25) {
            ScreenHeader(title: "WebDAV", subtitle: environment.webDAV.configuration?.baseURL.host ?? "Secure cloud file browsing")
            if environment.webDAV.configuration == nil {
                EmptyState(symbol: "externaldrive.badge.plus", title: "Connect a WebDAV server", message: "Add an HTTPS WebDAV account in Settings. Plain HTTP credentials are rejected.")
                Button("Open Settings") { environment.select(.settings) }.buttonStyle(.borderedProminent).tint(DebrifyTheme.indigo)
            } else if let error { EmptyState(symbol: "exclamationmark.triangle", title: "WebDAV unavailable", message: error) }
            else { WebDAVEntriesGrid(entries: entries) }
        }.padding(55).task { await load(path: "") }
    }

    private func load(path: String) async {
        guard environment.webDAV.configuration != nil else { return }
        do { entries = try await environment.webDAV.list(path: path) } catch { self.error = error.localizedDescription }
    }
}

private struct WebDAVEntriesGrid: View {
    @Environment(AppEnvironment.self) private var environment
    let entries: [WebDAVEntry]
    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 460), spacing: 24)], spacing: 24) {
                ForEach(entries) { entry in
                    Button { open(entry) } label: {
                        HStack(spacing: 18) {
                            MatchedMediaArtwork(
                                title: entry.name,
                                placeholderSymbol: entry.isDirectory ? "folder.fill" : "play.rectangle.fill",
                                allowsMatching: !entry.isDirectory,
                                contentMode: .fit
                            )
                            .frame(width: 110, height: 165)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            VStack(alignment: .leading) { Text(entry.name).font(.headline).lineLimit(2); Text(entry.contentType ?? (entry.isDirectory ? "Folder" : "Media")).foregroundStyle(DebrifyTheme.muted).lineLimit(1) }
                        }.padding(14).frame(maxWidth: .infinity, minHeight: 193, alignment: .leading)
                    }.debrifyCardButton()
                }
            }.padding(18)
        }
    }
    private func open(_ entry: WebDAVEntry) {
        if entry.isDirectory { environment.open(.webDAVDirectory(entry)) }
        else if let source = try? environment.webDAV.streamSource(for: entry) {
            Task {
                let artworkURL = await environment.stremio.artworkURL(forWebDAVName: entry.name)
                let item = MediaItem(id: "webdav:\(entry.href)", title: entry.name, posterURL: artworkURL, provider: "WebDAV")
                await environment.play(item, source: source)
            }
        }
    }
}

struct WebDAVDirectoryView: View {
    @Environment(AppEnvironment.self) private var environment
    let entry: WebDAVEntry
    @State private var entries: [WebDAVEntry] = []
    @State private var error: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 25) {
            ScreenHeader(title: entry.name, subtitle: "WebDAV folder")
            if let error { EmptyState(symbol: "exclamationmark.triangle", title: "Folder unavailable", message: error) } else { WebDAVEntriesGrid(entries: entries) }
        }.padding(55).background(DebrifyTheme.background).task { do { entries = try await environment.webDAV.list(path: entry.href) } catch { self.error = error.localizedDescription } }
    }
}

struct IPTVView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var categories: [IPTVCategory] = []
    @State private var kind: IPTVKind = .live
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 25) {
            ScreenHeader(title: "IPTV", subtitle: environment.xtream.configuration?.baseURL.host ?? "Xtream live TV, movies, and series")
            if environment.xtream.configuration == nil {
                EmptyState(symbol: "dot.radiowaves.left.and.right", title: "Connect an IPTV service", message: "Add an HTTPS Xtream account in Settings. Credentials stay in Keychain.")
                Button("Open Settings") { environment.select(.settings) }.buttonStyle(.borderedProminent).tint(DebrifyTheme.indigo)
            } else {
                Picker("Type", selection: $kind) { Text("Live").tag(IPTVKind.live); Text("Movies").tag(IPTVKind.vod); Text("Series").tag(IPTVKind.series) }.pickerStyle(.segmented).frame(maxWidth: 650)
                if let error { EmptyState(symbol: "exclamationmark.triangle", title: "IPTV unavailable", message: error) }
                else { ScrollView { LazyVGrid(columns: [GridItem(.adaptive(minimum: 320), spacing: 25)], spacing: 25) { ForEach(categories) { category in Button { environment.open(.iptvCategory(category)) } label: { Label(category.name, systemImage: category.kind == .live ? "antenna.radiowaves.left.and.right" : "film.fill").padding(24).frame(maxWidth: .infinity, minHeight: 105, alignment: .leading) }.debrifyCardButton() } }.padding(18) } }
            }
        }.padding(55).task(id: kind) { await load() }
    }
    private func load() async { guard environment.xtream.configuration != nil else { return }; do { categories = try await environment.xtream.categories(kind: kind); error = nil } catch { self.error = error.localizedDescription } }
}

struct IPTVChannelView: View {
    @Environment(AppEnvironment.self) private var environment
    let category: IPTVCategory
    @State private var channels: [IPTVChannel] = []
    @State private var seriesItems: [IPTVSeries] = []
    @State private var error: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 25) {
            ScreenHeader(title: category.name, subtitle: category.kind.rawValue.capitalized)
            if let error { EmptyState(symbol: "exclamationmark.triangle", title: "Channels unavailable", message: error) }
            else if category.kind == .series {
                ScrollView { LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 28)], spacing: 28) {
                    ForEach(seriesItems) { series in
                        Button { environment.open(.iptvSeries(series)) } label: {
                            VStack(alignment: .leading, spacing: 10) { RemoteImage(url: series.coverURL).frame(width: 210, height: 315).clipped(); Text(series.name).font(.headline).lineLimit(2) }.frame(width: 210, alignment: .leading)
                        }.debrifyCardButton()
                    }
                }.padding(18) }
            }
            else { ScrollView { LazyVGrid(columns: [GridItem(.adaptive(minimum: 290), spacing: 25)], spacing: 25) { ForEach(channels) { channel in Button { play(channel) } label: { HStack { RemoteImage(url: channel.iconURL).frame(width: 75, height: 75).clipShape(RoundedRectangle(cornerRadius: 12)); Text(channel.name).font(.headline).lineLimit(2) }.padding(18).frame(maxWidth: .infinity, minHeight: 110, alignment: .leading) }.debrifyCardButton() } }.padding(18) } }
        }.padding(55).background(DebrifyTheme.background).task { do { if category.kind == .series { seriesItems = try await environment.xtream.series(category: category) } else { channels = try await environment.xtream.channels(category: category) } } catch { self.error = error.localizedDescription } }
    }
    private func play(_ channel: IPTVChannel) {
        let item = MediaItem(id: "iptv:\(channel.id)", title: channel.name, posterURL: channel.iconURL, provider: "IPTV")
        let source = StreamSource(id: channel.id, name: channel.name, url: channel.streamURL, provider: "IPTV")
        Task { await environment.play(item, source: source) }
    }
}

struct IPTVSeriesView: View {
    @Environment(AppEnvironment.self) private var environment
    let series: IPTVSeries
    @State private var episodes: [IPTVEpisode] = []
    @State private var error: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 25) {
            ScreenHeader(title: series.name, subtitle: series.plot)
            if let error { EmptyState(symbol: "exclamationmark.triangle", title: "Episodes unavailable", message: error) }
            else if episodes.isEmpty { ProgressView("Loading episodes…").frame(maxWidth: .infinity, maxHeight: .infinity) }
            else { ScrollView { LazyVGrid(columns: [GridItem(.adaptive(minimum: 330), spacing: 24)], spacing: 24) {
                ForEach(episodes) { episode in
                    Button { play(episode) } label: {
                        HStack { Image(systemName: "play.circle.fill").font(.system(size: 42)).foregroundStyle(DebrifyTheme.indigoLight); VStack(alignment: .leading) { Text(episode.title).font(.headline).lineLimit(2); Text("Season \(episode.season) • Episode \(episode.episode)").foregroundStyle(DebrifyTheme.muted) } }.padding(22).frame(maxWidth: .infinity, minHeight: 110, alignment: .leading)
                    }.debrifyCardButton()
                }
            }.padding(18) } }
        }.padding(55).background(DebrifyTheme.background).task { do { episodes = try await environment.xtream.episodes(series: series) } catch { self.error = error.localizedDescription } }
    }
    private func play(_ episode: IPTVEpisode) {
        let item = MediaItem(id: "iptv:series:\(episode.id)", title: episode.title, subtitle: "S\(episode.season) E\(episode.episode)", posterURL: series.coverURL, provider: "IPTV")
        let source = StreamSource(id: episode.id, name: episode.title, url: episode.streamURL, provider: "IPTV")
        Task { await environment.play(item, source: source) }
    }
}

struct YouTubeView: View {
    @State private var input = ""
    @State private var error: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            ScreenHeader(title: "YouTube", subtitle: "Open a supported video in the YouTube app")
            TextField("https://www.youtube.com/watch?v=…", text: $input).textFieldStyle(.plain).padding(20).background(DebrifyTheme.surface, in: RoundedRectangle(cornerRadius: 16))
            Button("Open YouTube") { open() }.buttonStyle(.borderedProminent).tint(.red)
            if let error { Text(error).foregroundStyle(.red) }
            EmptyState(symbol: "play.rectangle.fill", title: "Uses the official handler", message: "Debrify does not extract or proxy YouTube media. The system opens valid youtube.com or youtu.be links in the installed app.")
        }.padding(55)
    }
    private func open() {
        guard let url = URL(string: input), let host = url.host?.lowercased(), host == "youtu.be" || host == "youtube.com" || host.hasSuffix(".youtube.com") else { error = "Enter a valid YouTube URL"; return }
        UIApplication.shared.open(url) { success in if !success { error = "YouTube could not be opened" } }
    }
}
