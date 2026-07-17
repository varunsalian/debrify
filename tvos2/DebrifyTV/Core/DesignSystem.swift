import SwiftUI

enum DebrifyTheme {
    static let background = Color(red: 0.025, green: 0.027, blue: 0.055)
    static let sidebar = Color(red: 0.039, green: 0.039, blue: 0.078)
    static let surface = Color(red: 0.078, green: 0.09, blue: 0.14)
    static let elevated = Color(red: 0.102, green: 0.102, blue: 0.18)
    static let indigo = Color(red: 0.388, green: 0.4, blue: 0.945)
    static let indigoLight = Color(red: 0.506, green: 0.545, blue: 0.973)
    static let success = Color(red: 0.2, green: 0.78, blue: 0.45)
    static let muted = Color.white.opacity(0.62)
    static let posterSize = CGSize(width: 210, height: 315)
}

struct FocusCardModifier: ViewModifier {
    @Environment(\.isFocused) private var focused

    func body(content: Content) -> some View {
        content
            .background(DebrifyTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(focused ? DebrifyTheme.indigoLight : .white.opacity(0.08), lineWidth: focused ? 5 : 1)
            }
            .shadow(color: focused ? DebrifyTheme.indigo.opacity(0.45) : .clear, radius: 22)
            .scaleEffect(focused ? 1.055 : 1)
            .animation(.easeOut(duration: 0.16), value: focused)
    }
}

struct DebrifyCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        FocusedDebrifyCard(label: configuration.label, isPressed: configuration.isPressed)
    }
}

private struct FocusedDebrifyCard<Label: View>: View {
    @Environment(\.isFocused) private var focused
    let label: Label
    let isPressed: Bool

    var body: some View {
        label
            .background(focused ? DebrifyTheme.indigo.opacity(0.38) : DebrifyTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(focused ? DebrifyTheme.indigoLight : .white.opacity(0.08), lineWidth: focused ? 7 : 1)
            }
            .overlay(alignment: .topTrailing) {
                if focused {
                    Image(systemName: "circle.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(13)
                }
            }
            .shadow(color: focused ? DebrifyTheme.indigoLight.opacity(0.85) : .clear, radius: 30)
            .scaleEffect(focused ? 1.075 : 1)
            .opacity(isPressed ? 0.78 : 1)
            .animation(.easeOut(duration: 0.16), value: focused)
            .animation(.easeOut(duration: 0.08), value: isPressed)
    }
}

extension View {
    func debrifyCard() -> some View { modifier(FocusCardModifier()) }

    func debrifyCardButton() -> some View {
        buttonStyle(DebrifyCardButtonStyle())
            .focusEffectDisabled()
    }
}

struct RemoteImage: View {
    let url: URL?
    var contentMode: ContentMode = .fill

    var body: some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .success(let image): image.resizable().aspectRatio(contentMode: contentMode)
            case .failure: placeholder
            case .empty: ZStack { placeholder; ProgressView() }
            @unknown default: placeholder
            }
        }
    }

    private var placeholder: some View {
        ZStack {
            LinearGradient(colors: [DebrifyTheme.elevated, DebrifyTheme.sidebar], startPoint: .topLeading, endPoint: .bottomTrailing)
            Image(systemName: "film.stack.fill").font(.system(size: 50)).foregroundStyle(.white.opacity(0.25))
        }
    }
}

struct MatchedMediaArtwork: View {
    @Environment(AppEnvironment.self) private var environment
    let title: String
    var directURL: URL? = nil
    var placeholderSymbol = "play.rectangle.fill"
    var allowsMatching = true
    var contentMode: ContentMode = .fill
    @State private var matchedURL: URL?
    @State private var loaded = false

    private var artworkURL: URL? { directURL ?? matchedURL }

    var body: some View {
        ZStack {
            LinearGradient(colors: [DebrifyTheme.elevated, DebrifyTheme.sidebar], startPoint: .topLeading, endPoint: .bottomTrailing)
            if let artworkURL {
                RemoteImage(url: artworkURL, contentMode: contentMode)
            } else {
                Image(systemName: placeholderSymbol)
                    .font(.system(size: 42)).foregroundStyle(DebrifyTheme.indigoLight)
                if allowsMatching, !loaded { ProgressView().scaleEffect(0.7) }
            }
        }
        .task(id: "\(title)|\(directURL?.absoluteString ?? "")") {
            guard directURL == nil, allowsMatching else { loaded = true; return }
            matchedURL = await environment.stremio.artworkURL(forWebDAVName: title)
            loaded = true
        }
    }
}

struct MediaCard: View {
    let item: MediaItem
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                MatchedMediaArtwork(title: item.title, directURL: item.posterURL, contentMode: .fit)
                    .frame(width: DebrifyTheme.posterSize.width, height: DebrifyTheme.posterSize.height)
                    .background(DebrifyTheme.elevated)
                    .clipped()
                Text(item.title).font(.headline).lineLimit(1)
                Text(item.subtitle ?? item.provider ?? " ").font(.caption).foregroundStyle(DebrifyTheme.muted).lineLimit(1)
                if item.progress > 0 {
                    ProgressView(value: item.progress).tint(DebrifyTheme.indigoLight)
                }
            }
            .frame(width: DebrifyTheme.posterSize.width, alignment: .leading)
        }
        .debrifyCardButton()
    }
}

struct EmptyState: View {
    let symbol: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 22) {
            Image(systemName: symbol).font(.system(size: 78)).foregroundStyle(DebrifyTheme.indigoLight)
            Text(title).font(.title.bold())
            Text(message).font(.title3).foregroundStyle(DebrifyTheme.muted).multilineTextAlignment(.center).frame(maxWidth: 650)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ScreenHeader: View {
    let title: String
    var subtitle: String?
    var action: (() -> Void)?

    var body: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.system(size: 42, weight: .bold))
                if let subtitle { Text(subtitle).font(.title3).foregroundStyle(DebrifyTheme.muted) }
            }
            Spacer()
            if let action {
                Button(action: action) { Label("Search", systemImage: "magnifyingglass") }
                    .buttonStyle(.borderedProminent).tint(DebrifyTheme.indigo)
            }
        }
    }
}
