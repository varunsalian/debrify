import Foundation

enum Destination: String, CaseIterable, Identifiable, Codable {
    case home = "Home"
    case search = "Search"
    case discover = "Discover"
    case cloud = "Cloud"
    case playlist = "Playlist"
    case downloads = "Downloads"
    case debrifyTV = "Debrify TV"
    case realDebrid = "Real-Debrid"
    case torBox = "TorBox"
    case pikPak = "PikPak"
    case addons = "Addons"
    case settings = "Settings"
    case stremio = "Stremio TV"
    case webDAV = "WebDAV"
    case premiumize = "Premiumize"
    case allDebrid = "AllDebrid"
    case iptv = "IPTV"
    case youtube = "YouTube"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .home: "house.fill"
        case .search: "magnifyingglass"
        case .discover: "safari.fill"
        case .cloud: "cloud.fill"
        case .playlist: "list.bullet.rectangle.fill"
        case .downloads: "arrow.down.circle.fill"
        case .debrifyTV: "tv.fill"
        case .realDebrid: "bolt.horizontal.circle.fill"
        case .torBox: "shippingbox.fill"
        case .pikPak: "cloud.fill"
        case .addons: "puzzlepiece.extension.fill"
        case .settings: "gearshape.fill"
        case .stremio: "sparkles.tv.fill"
        case .webDAV: "externaldrive.connected.to.line.below.fill"
        case .premiumize: "crown.fill"
        case .allDebrid: "link.circle.fill"
        case .iptv: "dot.radiowaves.left.and.right"
        case .youtube: "play.rectangle.fill"
        }
    }
}

enum Route: Hashable {
    case search
    case details(MediaItem)
    case player(MediaItem, StreamSource)
    case providerAccount(ProviderKind)
    case providerLibrary(ProviderKind)
    case providerFolder(ProviderFile, ProviderKind)
    case stremioCatalog(AddonCatalog)
    case webDAVDirectory(WebDAVEntry)
    case iptvCategory(IPTVCategory)
    case iptvSeries(IPTVSeries)
    case seeAll(AddonCatalog, String)
}
