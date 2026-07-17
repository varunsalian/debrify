import AVKit
import SwiftUI

struct DetailView: View {
    let item: MediaItem

    var body: some View {
        if item.mediaType == "series" {
            SeriesDetailView(item: item)
        } else {
            PlayableDetailView(item: item)
        }
    }
}

private struct PlayableDetailView: View {
    @Environment(AppEnvironment.self) private var environment
    let item: MediaItem
    @State private var sources: [StreamSource] = []
    @State private var isLoading = true

    private var usesLandscapeArtwork: Bool { item.mediaType == "seriesEpisode" }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            RemoteImage(url: item.backdropURL ?? item.posterURL)
                .overlay(LinearGradient(colors: [.clear, DebrifyTheme.background.opacity(0.82), DebrifyTheme.background], startPoint: .top, endPoint: .bottom))
                .ignoresSafeArea()
            HStack(alignment: .bottom, spacing: 45) {
                RemoteImage(url: item.posterURL, contentMode: .fill)
                    .frame(width: usesLandscapeArtwork ? 440 : 340, height: usesLandscapeArtwork ? 248 : 510)
                    .background(DebrifyTheme.elevated)
                    .clipShape(RoundedRectangle(cornerRadius: 22))
                    .clipped()
                VStack(alignment: .leading, spacing: 22) {
                    Text(item.title).font(.system(size: 52, weight: .bold))
                    HStack { if let year = item.year { Text(String(year)) }; Text(item.provider ?? "Debrify") }.foregroundStyle(DebrifyTheme.muted)
                    Text(item.overview ?? "Choose a source to start playback.").font(.title3).foregroundStyle(.white.opacity(0.82)).lineLimit(5).frame(maxWidth: 850, alignment: .leading)
                    HStack(spacing: 18) {
                        if let source = sources.first {
                            Button(item.progress > 0 ? "Resume" : "Play") { Task { await environment.play(item, source: source) } }
                                .buttonStyle(.borderedProminent).tint(DebrifyTheme.indigo)
                        }
                        Button { environment.addToPlaylist(item) } label: { Label("Playlist", systemImage: "plus") }.buttonStyle(.bordered)
                        Button { environment.toggleFavorite(item) } label: { Label(environment.isFavorite(item) ? "Favorited" : "Favorite", systemImage: environment.isFavorite(item) ? "heart.fill" : "heart") }.buttonStyle(.bordered)
                    }
                    if isLoading { ProgressView("Finding sources…") }
                    else if sources.isEmpty {
                        Text("No playable Torrentio sources were returned for this title.")
                            .font(.title3).foregroundStyle(DebrifyTheme.muted)
                    }
                    else if !sources.isEmpty {
                        Text("Sources").font(.title2.bold())
                        ScrollView(.horizontal) {
                            HStack(spacing: 18) {
                                ForEach(sources) { source in
                                    Button { Task { await environment.play(item, source: source) } } label: {
                                        SourceCard(source: source)
                                    }
                                    .debrifyCardButton()
                                }
                            }
                            .padding(24)
                        }
                        .contentMargins(.horizontal, -24)
                    }
                }
            }
            .padding(60)
        }
        .task { await loadSources() }
    }

    private func loadSources() async {
        if let url = item.streamURL {
            sources = [StreamSource(id: item.id, name: item.title, url: url, provider: item.provider ?? "Direct")]
        } else {
            sources = await environment.stremio.streams(for: item)
        }
        isLoading = false
    }
}

private struct SeriesDetailView: View {
    @Environment(AppEnvironment.self) private var environment
    let item: MediaItem
    @State private var episodes: [MediaItem] = []
    @State private var selectedSeason = 1
    @State private var isLoading = true
    @State private var error: String?

    private var seasons: [Int] {
        Array(Set(episodes.compactMap(\.seasonNumber))).sorted()
    }

    private var visibleEpisodes: [MediaItem] {
        episodes.filter { $0.seasonNumber == selectedSeason }
    }

    var body: some View {
        ZStack {
            RemoteImage(url: item.backdropURL ?? item.posterURL)
                .overlay(DebrifyTheme.background.opacity(0.8))
                .ignoresSafeArea()
            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .top, spacing: 34) {
                    RemoteImage(url: item.posterURL, contentMode: .fit)
                        .frame(width: 260, height: 390)
                        .background(DebrifyTheme.elevated)
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                    VStack(alignment: .leading, spacing: 15) {
                        Text(item.title).font(.system(size: 48, weight: .bold))
                        HStack {
                            if let year = item.year { Text(String(year)) }
                            Text(item.provider ?? "Stremio")
                        }
                        .foregroundStyle(DebrifyTheme.muted)
                        Text(item.overview ?? "Choose a season and episode.")
                            .font(.title3).foregroundStyle(.white.opacity(0.82)).lineLimit(4)
                        Button { environment.addToPlaylist(item) } label: {
                            Label("Playlist", systemImage: "plus")
                        }
                        .buttonStyle(.bordered)
                        Button { environment.toggleFavorite(item) } label: {
                            Label(environment.isFavorite(item) ? "Favorited" : "Favorite", systemImage: environment.isFavorite(item) ? "heart.fill" : "heart")
                        }.buttonStyle(.bordered)
                    }
                }

                if isLoading {
                    ProgressView("Loading seasons and episodes…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error {
                    EmptyState(symbol: "exclamationmark.triangle", title: "Episodes unavailable", message: error)
                } else if episodes.isEmpty {
                    EmptyState(symbol: "rectangle.stack.badge.play", title: "No episodes found", message: "Cinemeta did not return episode information for this series.")
                } else {
                    ScrollView(.horizontal) {
                        HStack(spacing: 14) {
                            ForEach(seasons, id: \.self) { season in
                                Button("Season \(season)") { selectedSeason = season }
                                    .buttonStyle(.borderedProminent)
                                    .tint(selectedSeason == season ? DebrifyTheme.indigo : DebrifyTheme.elevated)
                            }
                        }
                        .padding(.horizontal, 14)
                    }
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 460), spacing: 22)], spacing: 22) {
                            ForEach(visibleEpisodes) { episode in
                                Button { environment.open(.details(episode)) } label: {
                                    HStack(spacing: 18) {
                                        RemoteImage(url: episode.posterURL)
                                            .frame(width: 170, height: 96)
                                            .background(DebrifyTheme.elevated)
                                            .clipShape(RoundedRectangle(cornerRadius: 12))
                                        VStack(alignment: .leading, spacing: 7) {
                                            Text(episode.title).font(.headline).lineLimit(2)
                                            Text(episode.subtitle ?? "Episode").foregroundStyle(DebrifyTheme.muted)
                                        }
                                    }
                                    .padding(14).frame(maxWidth: .infinity, minHeight: 124, alignment: .leading)
                                }
                                .debrifyCardButton()
                            }
                        }
                        .padding(24)
                    }
                }
            }
            .padding(55)
        }
        .task { await loadEpisodes() }
    }

    private func loadEpisodes() async {
        do {
            episodes = try await environment.stremio.episodes(for: item)
            let regularSeasons = seasons.filter { $0 > 0 }
            selectedSeason = regularSeasons.first ?? seasons.first ?? 1
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }
}

private struct SourceCard: View {
    let source: StreamSource

    private var fileSize: String {
        guard let bytes = source.fileSizeBytes else { return "Size not provided" }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private var formatBadges: [String] {
        [source.quality, source.videoCodec, source.releaseType, source.container].compactMap { $0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(source.name).font(.headline).lineLimit(2)
            HStack(spacing: 8) {
                Label(fileSize, systemImage: "internaldrive.fill")
                    .foregroundStyle(source.fileSizeBytes == nil ? DebrifyTheme.muted : .white)
                ForEach(formatBadges, id: \.self) { badge in
                    Text(badge)
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(DebrifyTheme.indigo.opacity(0.35), in: Capsule())
                }
            }
            .font(.caption.bold()).lineLimit(1)
            if let fileName = source.fileName, !fileName.isEmpty {
                Label(fileName, systemImage: "doc.fill")
                    .font(.caption).foregroundStyle(.white.opacity(0.82)).lineLimit(2)
            }
            if let details = source.details, !details.isEmpty {
                Text(details)
                    .font(.caption).foregroundStyle(DebrifyTheme.muted)
                    .lineLimit(5).multilineTextAlignment(.leading)
            }
            Spacer(minLength: 0)
            HStack {
                Label("Addon: \(source.provider)", systemImage: "puzzlepiece.extension.fill")
                if let indexer = source.indexer { Label(indexer, systemImage: "shippingbox.fill") }
                if let seeders = source.seeders { Label("\(seeders)", systemImage: "person.2.fill") }
                if source.isCached == true { Label("Cached", systemImage: "bolt.fill") }
            }
            .font(.caption.bold()).foregroundStyle(DebrifyTheme.indigoLight).lineLimit(1)
        }
        .padding(20)
        .frame(width: 500, height: 240, alignment: .leading)
        .foregroundStyle(.white)
    }
}

struct PlayerScreen: View {
    @Environment(AppEnvironment.self) private var environment
    let item: MediaItem
    let source: StreamSource
    @State private var controlsVisible = true

    var body: some View {
        ZStack(alignment: .bottom) {
            VideoPlayer(player: environment.playback.player).ignoresSafeArea()
            if controlsVisible {
                VStack(spacing: 16) {
                    HStack { Text(item.title).font(.title2.bold()); Spacer(); Text(source.provider).foregroundStyle(DebrifyTheme.muted) }
                    ProgressView(value: environment.playback.position, total: max(environment.playback.duration, 1)).tint(DebrifyTheme.indigoLight)
                    HStack {
                        Text(format(environment.playback.position)); Spacer()
                        Button { environment.playback.seek(by: -15) } label: { Image(systemName: "gobackward.15") }
                        Button { environment.playback.toggle() } label: { Image(systemName: environment.playback.isPlaying ? "pause.fill" : "play.fill") }
                        Button { environment.playback.seek(by: 30) } label: { Image(systemName: "goforward.30") }
                        Spacer(); Text("−\(format(max(environment.playback.duration - environment.playback.position, 0)))")
                    }.font(.title2)
                }
                .padding(34).background(.ultraThinMaterial)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .onAppear { environment.playback.load(item: item, source: source) }
        .onDisappear {
            environment.recordProgress(for: item, seconds: environment.playback.position, duration: environment.playback.duration)
            environment.playback.stop()
        }
        .onPlayPauseCommand { environment.playback.toggle(); revealControls() }
        .onMoveCommand { direction in
            if direction == .left { environment.playback.seek(by: -10) }
            if direction == .right { environment.playback.seek(by: 10) }
            revealControls()
        }
        .onTapGesture { withAnimation { controlsVisible.toggle() } }
    }

    private func revealControls() {
        withAnimation { controlsVisible = true }
        Task { try? await Task.sleep(for: .seconds(4)); withAnimation { controlsVisible = false } }
    }

    private func format(_ seconds: Double) -> String {
        guard seconds.isFinite else { return "0:00" }
        let total = Int(seconds), hours = total / 3600, minutes = (total % 3600) / 60
        return hours > 0 ? String(format: "%d:%02d:%02d", hours, minutes, total % 60) : String(format: "%d:%02d", minutes, total % 60)
    }
}
