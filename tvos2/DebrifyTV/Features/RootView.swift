import SwiftUI

struct RootView: View {
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        @Bindable var environment = environment
        NavigationStack(path: $environment.navigationPath) {
            HStack(spacing: 0) {
                SidebarView(selection: $environment.selectedDestination)
                destinationView
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(DebrifyTheme.background)
                    .focusSection()
            }
            .ignoresSafeArea()
            .navigationDestination(for: Route.self, destination: routeView)
        }
        .confirmationDialog(
            environment.confirmation?.title ?? "Confirm",
            isPresented: Binding(get: { environment.confirmation != nil }, set: { if !$0 { environment.confirmation = nil } }),
            titleVisibility: .visible
        ) {
            Button("Continue", role: .destructive) {
                guard let pending = environment.confirmation else { return }
                environment.confirmation = nil
                Task { await pending.action() }
            }
            Button("Cancel", role: .cancel) { environment.confirmation = nil }
        } message: { Text(environment.confirmation?.message ?? "") }
        .overlay(alignment: .top) {
            if let toast = environment.toast {
                Text(toast).font(.headline).padding(.horizontal, 28).padding(.vertical, 14)
                    .background(.ultraThinMaterial, in: Capsule()).padding(.top, 35)
                    .task { try? await Task.sleep(for: .seconds(2)); if environment.toast == toast { environment.toast = nil } }
            }
        }
        .task { await environment.prepare() }
    }

    @ViewBuilder
    private var destinationView: some View {
        switch environment.selectedDestination {
        case .home: HomeView()
        case .search: SearchView()
        case .discover: DiscoverView()
        case .cloud: CloudView()
        case .playlist: PlaylistView()
        case .downloads: TransfersView()
        case .debrifyTV: DebrifyTVView()
        case .realDebrid: ProviderLibraryView(kind: .realDebrid)
        case .torBox: ProviderLibraryView(kind: .torBox)
        case .pikPak: ProviderLibraryView(kind: .pikPak)
        case .premiumize: ProviderLibraryView(kind: .premiumize)
        case .allDebrid: ProviderLibraryView(kind: .allDebrid)
        case .addons: AddonsView()
        case .settings: SettingsView()
        case .stremio: StremioView()
        case .webDAV: WebDAVView()
        case .iptv: IPTVView()
        case .youtube: YouTubeView()
        }
    }

    @ViewBuilder
    private func routeView(_ route: Route) -> some View {
        switch route {
        case .search: SearchView()
        case .details(let item): DetailView(item: item)
        case .player(let item, let source): PlayerScreen(item: item, source: source)
        case .providerAccount(let kind): ProviderAccountView(kind: kind)
        case .providerLibrary(let kind): ProviderLibraryView(kind: kind)
        case .providerFolder(let file, let kind): ProviderFolderView(file: file, kind: kind)
        case .stremioCatalog(let catalog): StremioCatalogView(catalog: catalog)
        case .webDAVDirectory(let entry): WebDAVDirectoryView(entry: entry)
        case .iptvCategory(let category): IPTVChannelView(category: category)
        case .iptvSeries(let series): IPTVSeriesView(series: series)
        case .seeAll(let catalog, let addonID): CatalogSeeAllView(catalog: catalog, addonID: addonID)
        }
    }
}

private struct SidebarView: View {
    @Binding var selection: Destination
    @FocusState private var focused: Destination?
    private let destinations: [Destination] = [
        .home, .search, .discover, .cloud, .playlist, .downloads,
        .addons, .iptv, .youtube, .settings
    ]

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 7) {
                HStack(spacing: 14) {
                    Image(systemName: "play.square.stack.fill").font(.title)
                    Text("DEBRIFY 2").font(.headline.bold())
                }
                .foregroundStyle(DebrifyTheme.indigoLight).padding(.vertical, 25)

                ForEach(destinations) { destination in
                    Button {
                        selection = destination
                    } label: {
                        Label(destination.rawValue, systemImage: destination.symbol)
                            .font(.headline)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 18).padding(.vertical, 13)
                            .background(selection == destination ? DebrifyTheme.indigo.opacity(0.28) : .clear, in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                    .focused($focused, equals: destination)
                }
            }
            .padding(.horizontal, 15)
        }
        .frame(width: focused == nil ? 270 : 325)
        .focusSection()
        .background(DebrifyTheme.sidebar)
        .animation(.easeOut(duration: 0.18), value: focused)
    }
}
