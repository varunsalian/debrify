import SwiftUI

struct SettingsView: View {
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 32) {
                ScreenHeader(title: "Settings", subtitle: "Accounts, sources, playback, and security")
                SettingsSection(title: "Debrid & cloud providers") {
                    ForEach(ProviderKind.allCases) { kind in
                        SettingsRow(symbol: "key.fill", title: kind.rawValue, detail: environment.providers.connected.contains(kind) ? "Connected" : "Not connected") { environment.open(.providerAccount(kind)) }
                    }
                }
                SettingsSection(title: "Connected servers") {
                    NavigationLink { WebDAVSetupView() } label: { SettingsRowLabel(symbol: "externaldrive.fill", title: "WebDAV", detail: environment.webDAV.configuration?.baseURL.host ?? "Not configured") }
                    NavigationLink { XtreamSetupView() } label: { SettingsRowLabel(symbol: "dot.radiowaves.left.and.right", title: "Xtream / IPTV", detail: environment.xtream.configuration?.baseURL.host ?? "Not configured") }
                    SettingsRow(symbol: "puzzlepiece.extension.fill", title: "Stremio addons", detail: "\(environment.stremio.addons.count) installed") { environment.select(.addons) }
                }
                SettingsSection(title: "Discovery catalogs") {
                    NavigationLink { TraktSetupView() } label: {
                        SettingsRowLabel(symbol: "chart.line.uptrend.xyaxis", title: "Trakt public lists", detail: environment.discovery.isTraktConfigured ? "Trending & Most Anticipated active" : "Client ID required")
                    }
                    NavigationLink { TMDBSetupView() } label: {
                        SettingsRowLabel(symbol: "movieclapper.fill", title: "TMDB New Releases", detail: environment.discovery.isTMDBConfigured ? "Connected" : "Optional token required")
                    }
                }
                SettingsSection(title: "Playback") {
                    Toggle(isOn: Binding(
                        get: { environment.playbackPreferences.alwaysOpenInInfuse },
                        set: { environment.setAlwaysOpenInInfuse($0) }
                    )) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Always open videos in Infuse").font(.headline)
                            Text("Uses Infuse for provider and Stremio streams. Streams requiring private headers remain in Debrify.")
                                .font(.subheadline)
                                .foregroundStyle(DebrifyTheme.muted)
                        }
                    }
                    Text("Playback progress from Infuse is not currently added to Debrify's Continue Watching list.")
                        .font(.caption)
                        .foregroundStyle(DebrifyTheme.muted)
                }
                SettingsSection(title: "Security") {
                    Label("Keychain-only credentials", systemImage: "lock.shield.fill").foregroundStyle(DebrifyTheme.success)
                    Label("HTTPS required for credential-bearing servers", systemImage: "network.badge.shield.half.filled").foregroundStyle(DebrifyTheme.success)
                    Label("Private-network addon destinations blocked", systemImage: "checkmark.shield.fill").foregroundStyle(DebrifyTheme.success)
                    Label("LAN remote control disabled", systemImage: "antenna.radiowaves.left.and.right.slash").foregroundStyle(DebrifyTheme.success)
                }
                SettingsSection(title: "About") {
                    Text("Debrify 2 for Apple TV").font(.headline)
                    Text("Native SwiftUI tvOS edition").foregroundStyle(DebrifyTheme.muted)
                }
            }.padding(55)
        }
    }
}

struct TraktSetupView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var clientID = ""
    @State private var error: String?
    @State private var busy = false

    var body: some View {
        Form {
            Section("Trakt Public Catalogs") {
                Text("Adds Trending and Most Anticipated rows. Create a Trakt API application and paste only its client ID. A client secret is neither requested nor stored.")
                SecureField("Trakt API client ID", text: $clientID)
            }
            if let error { Text(error).foregroundStyle(.red) }
            Button(busy ? "Validating…" : "Validate and connect") { Task { await connect() } }
                .disabled(clientID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || busy)
            if environment.discovery.isTraktConfigured {
                Label("Connected · client ID stored in Keychain", systemImage: "checkmark.shield.fill").foregroundStyle(DebrifyTheme.success)
                Button("Disconnect Trakt", role: .destructive) {
                    do { try environment.discovery.disconnectTrakt(); error = nil }
                    catch { self.error = error.localizedDescription }
                }
            }
        }
        .navigationTitle("Trakt Discovery")
    }

    private func connect() async {
        busy = true; defer { busy = false }
        do {
            try await environment.discovery.configureTrakt(clientID: clientID)
            clientID = ""
            error = nil
        } catch { self.error = error.localizedDescription }
    }
}

struct TMDBSetupView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var token = ""
    @State private var error: String?
    @State private var busy = false

    var body: some View {
        Form {
            Section("TMDB New Releases") {
                Text("Adds New Movies and New & Airing Series rows. Create a free API Read Access Token in your TMDB account, then paste it here.")
                SecureField("TMDB API Read Access Token", text: $token)
            }
            if let error { Text(error).foregroundStyle(.red) }
            Button(busy ? "Validating…" : "Validate and connect") { Task { await connect() } }
                .disabled(token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || busy)
            if environment.discovery.isTMDBConfigured {
                Label("Connected · token stored in Keychain", systemImage: "checkmark.shield.fill").foregroundStyle(DebrifyTheme.success)
                Button("Disconnect TMDB", role: .destructive) {
                    do { try environment.discovery.disconnectTMDB(); error = nil }
                    catch { self.error = error.localizedDescription }
                }
            }
        }
        .navigationTitle("TMDB Discovery")
    }

    private func connect() async {
        busy = true; defer { busy = false }
        do {
            try await environment.discovery.configureTMDB(readAccessToken: token)
            token = ""
            error = nil
        } catch { self.error = error.localizedDescription }
    }
}

private struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content
    var body: some View { VStack(alignment: .leading, spacing: 18) { Text(title).font(.title2.bold()); VStack(alignment: .leading, spacing: 14) { content }.padding(25).frame(maxWidth: .infinity, alignment: .leading).background(DebrifyTheme.surface, in: RoundedRectangle(cornerRadius: 20)) } }
}

private struct SettingsRow: View {
    let symbol: String, title: String, detail: String
    let action: () -> Void
    var body: some View { Button(action: action) { SettingsRowLabel(symbol: symbol, title: title, detail: detail) }.buttonStyle(.plain) }
}

private struct SettingsRowLabel: View {
    let symbol: String, title: String, detail: String
    var body: some View { HStack(spacing: 18) { Image(systemName: symbol).font(.title2).foregroundStyle(DebrifyTheme.indigoLight).frame(width: 38); Text(title).font(.headline); Spacer(); Text(detail).foregroundStyle(DebrifyTheme.muted); Image(systemName: "chevron.right").foregroundStyle(DebrifyTheme.muted) }.padding(.vertical, 8) }
}

struct WebDAVSetupView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var server = "https://"
    @State private var username = ""
    @State private var password = ""
    @State private var error: String?
    @State private var busy = false
    var body: some View { Form {
        Section("Secure WebDAV") { TextField("HTTPS server URL", text: $server); TextField("Username", text: $username); SecureField("Password", text: $password) }
        if let error { Text(error).foregroundStyle(.red) }
        Button(busy ? "Connecting…" : "Connect") { Task { await connect() } }.disabled(busy)
        if environment.webDAV.configuration != nil { Button("Disconnect", role: .destructive) { try? environment.webDAV.disconnect() } }
    }.navigationTitle("WebDAV Setup") }
    private func connect() async { guard let url = URL(string: server) else { error = "Invalid URL"; return }; busy = true; defer { busy = false }; do { try await environment.webDAV.configure(url: url, username: username, password: password); password = ""; error = nil } catch { self.error = error.localizedDescription } }
}

struct XtreamSetupView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var server = "https://"
    @State private var username = ""
    @State private var password = ""
    @State private var error: String?
    @State private var busy = false
    var body: some View { Form {
        Section("Secure Xtream API") { TextField("HTTPS server URL", text: $server); TextField("Username", text: $username); SecureField("Password", text: $password) }
        if let error { Text(error).foregroundStyle(.red) }
        Button(busy ? "Connecting…" : "Connect") { Task { await connect() } }.disabled(busy)
        if environment.xtream.configuration != nil { Button("Disconnect", role: .destructive) { try? environment.xtream.disconnect() } }
    }.navigationTitle("IPTV Setup") }
    private func connect() async { guard let url = URL(string: server) else { error = "Invalid URL"; return }; busy = true; defer { busy = false }; do { try await environment.xtream.configure(url: url, username: username, password: password); password = ""; error = nil } catch { self.error = error.localizedDescription } }
}
