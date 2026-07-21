import Foundation
import Observation

@MainActor
@Observable
final class AppEnvironment {
    let api: APIClient
    let secrets: SecretStore
    let persistence: PersistenceStore
    let providers: ProviderRegistry
    let stremio: StremioService
    let webDAV: WebDAVService
    let xtream: XtreamService
    let playback: PlaybackController
    let externalPlayer: InfuseLauncher
    let search: UnifiedSearchService
    let discovery: DiscoveryService

    var selectedDestination: Destination = .home
    var navigationPath: [Route] = []
    var playlist: [MediaItem] = []
    var continueWatching: [MediaItem] = []
    var favorites: [MediaItem] = []
    var confirmation: PendingConfirmation?
    var toast: String?
    var playbackPreferences = PlaybackPreferences()

    init(
        api: APIClient,
        secrets: SecretStore,
        persistence: PersistenceStore,
        providers: ProviderRegistry,
        stremio: StremioService,
        webDAV: WebDAVService,
        xtream: XtreamService,
        playback: PlaybackController,
        externalPlayer: InfuseLauncher,
        search: UnifiedSearchService,
        discovery: DiscoveryService
    ) {
        self.api = api
        self.secrets = secrets
        self.persistence = persistence
        self.providers = providers
        self.stremio = stremio
        self.webDAV = webDAV
        self.xtream = xtream
        self.playback = playback
        self.externalPlayer = externalPlayer
        self.search = search
        self.discovery = discovery
        restoreLocalState()
    }

    static func live() -> AppEnvironment {
        let api = APIClient()
        let secrets = KeychainSecretStore(service: "com.debrify.tv2")
        let persistence = UserDefaultsPersistenceStore()
        let providers = ProviderRegistry(api: api, secrets: secrets)
        let stremio = StremioService(api: api, secrets: secrets, persistence: persistence)
        let webDAV = WebDAVService(api: api, secrets: secrets, persistence: persistence)
        let xtream = XtreamService(api: api, secrets: secrets, persistence: persistence)
        let playback = PlaybackController(persistence: persistence)
        let externalPlayer = InfuseLauncher()
        let search = UnifiedSearchService(providers: providers, stremio: stremio, xtream: xtream)
        let discovery = DiscoveryService(api: api, secrets: secrets)
        return AppEnvironment(
            api: api,
            secrets: secrets,
            persistence: persistence,
            providers: providers,
            stremio: stremio,
            webDAV: webDAV,
            xtream: xtream,
            playback: playback,
            externalPlayer: externalPlayer,
            search: search,
            discovery: discovery
        )
    }

    func select(_ destination: Destination) {
        selectedDestination = destination
        navigationPath.removeAll()
    }

    func open(_ route: Route) { navigationPath.append(route) }

    func prepare() async {
        try? await stremio.ensureCinemeta()
    }

    func setAlwaysOpenInInfuse(_ enabled: Bool) {
        playbackPreferences.alwaysOpenInInfuse = enabled
        persistence.save(playbackPreferences, for: .playbackPreferences)
    }

    func play(_ item: MediaItem, source: StreamSource) async {
        guard playbackPreferences.alwaysOpenInInfuse else {
            open(.player(item, source))
            return
        }

        guard source.headers.isEmpty else {
            toast = "This stream needs private headers, so it will play in Debrify"
            open(.player(item, source))
            return
        }

        let opened = await externalPlayer.open(item: item, source: source)
        if !opened {
            toast = "Infuse could not be opened. Make sure Infuse is installed and updated"
        }
    }

    func addToPlaylist(_ item: MediaItem) {
        guard !playlist.contains(where: { $0.id == item.id }) else { return }
        playlist.append(item)
        persistLocalState()
        toast = "Added to Playlist"
    }

    func removeFromPlaylist(_ item: MediaItem) {
        playlist.removeAll { $0.id == item.id }
        persistLocalState()
    }

    func toggleFavorite(_ item: MediaItem) {
        if favorites.contains(where: { $0.id == item.id }) {
            favorites.removeAll { $0.id == item.id }
            toast = "Removed from Favorites"
        } else {
            favorites.insert(item, at: 0)
            toast = "Added to Favorites"
        }
        persistLocalState()
    }

    func isFavorite(_ item: MediaItem) -> Bool {
        favorites.contains { $0.id == item.id }
    }

    func recordProgress(for item: MediaItem, seconds: Double, duration: Double) {
        var updated = item
        updated.progressSeconds = seconds
        updated.durationSeconds = duration
        continueWatching.removeAll { $0.id == item.id }
        if duration > 0, seconds / duration < 0.95, seconds > 10 {
            continueWatching.insert(updated, at: 0)
        }
        persistLocalState()
    }

    private func restoreLocalState() {
        playlist = persistence.load([MediaItem].self, for: .playlist) ?? []
        continueWatching = persistence.load([MediaItem].self, for: .continueWatching) ?? []
        favorites = persistence.load([MediaItem].self, for: .favorites) ?? []
        playbackPreferences = persistence.load(PlaybackPreferences.self, for: .playbackPreferences) ?? PlaybackPreferences()
    }

    private func persistLocalState() {
        persistence.save(playlist, for: .playlist)
        persistence.save(continueWatching, for: .continueWatching)
        persistence.save(favorites, for: .favorites)
    }
}

struct PendingConfirmation: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    let action: @MainActor () async -> Void
}
