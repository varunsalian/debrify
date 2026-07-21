import SwiftUI

struct ProviderLibraryView: View {
    @Environment(AppEnvironment.self) private var environment
    let kind: ProviderKind
    @State private var files: [ProviderFile] = []
    @State private var error: String?
    @State private var loading = false
    @State private var magnet = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 25) {
            ScreenHeader(title: kind.rawValue, subtitle: environment.providers.connected.contains(kind) ? "Cloud library and transfers" : "Account not connected") {
                environment.open(.search)
            }
            if !environment.providers.connected.contains(kind) {
                EmptyState(symbol: "person.crop.circle.badge.plus", title: "Connect \(kind.rawValue)", message: "Your credential is validated and stored in Keychain on this Apple TV.")
                Button("Connect account") { environment.open(.providerAccount(kind)) }.buttonStyle(.borderedProminent).tint(DebrifyTheme.indigo)
            } else {
                HStack {
                    TextField("Paste a magnet link", text: $magnet).textFieldStyle(.plain).padding(16).background(DebrifyTheme.surface, in: RoundedRectangle(cornerRadius: 14))
                    Button("Add") { confirmMagnet() }.disabled(!magnet.hasPrefix("magnet:"))
                    Button("Account") { environment.open(.providerAccount(kind)) }
                }.focusSection()
                if loading { ProgressView("Loading \(kind.rawValue)…").frame(maxWidth: .infinity, maxHeight: .infinity) }
                else if let error { EmptyState(symbol: "exclamationmark.triangle", title: "Couldn’t load provider", message: error) }
                else if files.isEmpty { EmptyState(symbol: "shippingbox", title: "Nothing here yet", message: "Cloud files and provider transfers will appear here.") }
                else { ProviderFileGrid(files: files, fixedKind: kind) }
            }
        }
        .padding(55).task(id: kind) { await load() }
    }

    private func load() async {
        guard environment.providers.connected.contains(kind) else { return }
        loading = true; defer { loading = false }
        do { files = try await environment.providers.files(kind); error = nil } catch { self.error = error.localizedDescription }
    }

    private func confirmMagnet() {
        let value = magnet
        environment.confirmation = PendingConfirmation(title: "Add magnet to \(kind.rawValue)?", message: "This starts a remote provider transfer.") {
            do { try await environment.providers.addMagnet(value, using: kind); magnet = ""; await load() }
            catch { self.error = error.localizedDescription }
        }
    }
}

private struct ProviderFileGrid: View {
    @Environment(AppEnvironment.self) private var environment
    let files: [ProviderFile]
    var fixedKind: ProviderKind? = nil
    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 460), spacing: 25)], spacing: 25) {
                ForEach(files) { file in
                    Button { open(file) } label: {
                        HStack(spacing: 18) {
                            MatchedMediaArtwork(title: file.name, placeholderSymbol: file.link == nil ? "arrow.down.circle" : "play.circle.fill", contentMode: .fit)
                                .frame(width: 110, height: 165)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                            VStack(alignment: .leading, spacing: 8) {
                                Text(file.name).font(.headline).lineLimit(2)
                                Text(file.status).foregroundStyle(DebrifyTheme.muted)
                                if let progress = file.progress { ProgressView(value: progress).tint(DebrifyTheme.indigoLight) }
                            }
                        }.padding(14).frame(maxWidth: .infinity, minHeight: 193, alignment: .leading)
                    }.debrifyCardButton()
                }
            }.padding(18)
        }
        .focusSection()
    }

    private func open(_ file: ProviderFile) {
        guard let kind = fixedKind ?? ProviderKind.allCases.first(where: { $0.rawValue == file.kind }) else {
            environment.open(.details(file.mediaItem)); return
        }
        if !file.children.isEmpty {
            environment.open(.providerFolder(file, kind))
        } else if file.link != nil {
            Task { await play(file, child: nil, kind: kind) }
        } else {
            environment.toast = "This transfer has no playable files yet"
        }
    }

    private func play(_ file: ProviderFile, child: ProviderChildFile?, kind: ProviderKind) async {
        do {
            let source = try await environment.providers.resolve(file, child: child, using: kind)
            var item = file.mediaItem
            item.posterURL = await environment.stremio.artworkURL(forWebDAVName: child?.name ?? file.name)
            await environment.play(item, source: source)
        } catch { environment.toast = error.localizedDescription }
    }
}

struct ProviderFolderView: View {
    @Environment(AppEnvironment.self) private var environment
    let file: ProviderFile
    let kind: ProviderKind

    var body: some View {
        VStack(alignment: .leading, spacing: 25) {
            ScreenHeader(title: file.name, subtitle: "Choose a file to play")
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 410), spacing: 24)], spacing: 24) {
                    ForEach(file.children) { child in
                        Button { Task { await play(child) } } label: {
                            HStack(spacing: 18) {
                                Image(systemName: "play.circle.fill").font(.system(size: 42)).foregroundStyle(DebrifyTheme.indigoLight)
                                VStack(alignment: .leading, spacing: 7) {
                                    Text(child.name).font(.headline).lineLimit(2)
                                    if let size = child.size { Text(ByteCountFormatter.string(fromByteCount: size, countStyle: .file)).foregroundStyle(DebrifyTheme.muted) }
                                }
                            }.padding(22).frame(maxWidth: .infinity, minHeight: 120, alignment: .leading)
                        }.debrifyCardButton()
                    }
                }.padding(18)
            }.focusSection()
        }.padding(55).background(DebrifyTheme.background)
    }

    private func play(_ child: ProviderChildFile) async {
        do {
            let source = try await environment.providers.resolve(file, child: child, using: kind)
            var item = file.mediaItem
            item.id = "provider:\(file.id):\(child.id)"
            item.title = child.name
            item.posterURL = await environment.stremio.artworkURL(forWebDAVName: child.name)
            await environment.play(item, source: source)
        } catch { environment.toast = error.localizedDescription }
    }
}

struct ProviderAccountView: View {
    @Environment(AppEnvironment.self) private var environment
    let kind: ProviderKind
    @State private var token = ""
    @State private var account: ProviderAccount?
    @State private var error: String?
    @State private var busy = false

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            ScreenHeader(title: "\(kind.rawValue) Account", subtitle: "Credentials stay in this Apple TV's Keychain")
            if let loadedAccount = account {
                VStack(alignment: .leading, spacing: 14) {
                    Label(loadedAccount.username, systemImage: "person.crop.circle.fill").font(.title2)
                    if let email = loadedAccount.email { Text(email).foregroundStyle(DebrifyTheme.muted) }
                    if let plan = loadedAccount.plan { Text(plan).foregroundStyle(DebrifyTheme.success) }
                    if let expiration = loadedAccount.expiration { Text("Expires \(expiration.formatted(date: .abbreviated, time: .omitted))") }
                }.padding(30).frame(maxWidth: 700, alignment: .leading).background(DebrifyTheme.surface, in: RoundedRectangle(cornerRadius: 20))
                Button("Disconnect", role: .destructive) { try? environment.providers.disconnect(kind); account = nil }.buttonStyle(.bordered)
            } else {
                SecureField("API token or access token", text: $token).textFieldStyle(.plain).padding(20).background(DebrifyTheme.surface, in: RoundedRectangle(cornerRadius: 16)).frame(maxWidth: 900)
                Button(busy ? "Connecting…" : "Validate and connect") { Task { await connect() } }.buttonStyle(.borderedProminent).tint(DebrifyTheme.indigo).disabled(token.isEmpty || busy)
            }
            if let error { Text(error).foregroundStyle(.red) }
            Spacer()
        }.padding(55).task { await loadAccount() }
    }

    private func loadAccount() async {
        guard environment.providers.connected.contains(kind) else { return }
        account = try? await environment.providers.account(kind)
    }
    private func connect() async {
        busy = true; defer { busy = false }
        do { account = try await environment.providers.connect(kind, token: token); token = ""; error = nil }
        catch { self.error = error.localizedDescription }
    }
}

struct TransfersView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var files: [ProviderFile] = []
    @State private var loading = true

    var body: some View {
        VStack(alignment: .leading, spacing: 25) {
            ScreenHeader(title: "Downloads", subtitle: "Provider-side transfers and completed remote downloads")
            if loading { ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity) }
            else if files.isEmpty { EmptyState(symbol: "arrow.down.circle", title: "No remote downloads", message: "tvOS does not maintain a durable offline file library. Transfers managed by your connected providers appear here.") }
            else { ProviderFileGrid(files: files) }
        }.padding(55).task { await load() }
    }

    private func load() async {
        var merged: [ProviderFile] = []
        for kind in environment.providers.connected { merged += (try? await environment.providers.files(kind)) ?? [] }
        files = merged.sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
        loading = false
    }
}

struct PlaylistView: View {
    @Environment(AppEnvironment.self) private var environment
    var body: some View {
        VStack(alignment: .leading, spacing: 25) {
            ScreenHeader(title: "Playlist", subtitle: "Saved for later")
            if environment.playlist.isEmpty { EmptyState(symbol: "list.bullet.rectangle", title: "Your playlist is empty", message: "Open any title and choose Playlist to save it here.") }
            else {
                ScrollView { LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 30)], spacing: 30) {
                    ForEach(environment.playlist) { item in
                        MediaCard(item: item) { environment.open(.details(item)) }
                            .contextMenu { Button("Remove", role: .destructive) { environment.removeFromPlaylist(item) } }
                    }
                }.padding(18) }
            }
        }.padding(55)
    }
}
