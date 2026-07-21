import XCTest
@testable import DebrifyTV

final class ModelAndPersistenceTests: XCTestCase {
    func testMediaProgressIsClamped() {
        let normal = MediaItem(id: "1", title: "A", progressSeconds: 25, durationSeconds: 100)
        let overflow = MediaItem(id: "2", title: "B", progressSeconds: 125, durationSeconds: 100)
        XCTAssertEqual(normal.progress, 0.25)
        XCTAssertEqual(overflow.progress, 1)
    }

    func testPlaylistRoundTrip() {
        let suite = "DebrifyTVTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = UserDefaultsPersistenceStore(defaults: defaults)
        let original = [MediaItem(id: "movie", title: "Movie", year: 2026)]
        store.save(original, for: .playlist)
        let restored = store.load([MediaItem].self, for: .playlist)
        XCTAssertEqual(restored, original)
    }

    func testEverySidebarDestinationHasAUniqueIdentityAndSymbol() {
        XCTAssertEqual(Set(Destination.allCases.map(\.id)).count, Destination.allCases.count)
        XCTAssertTrue(Destination.allCases.allSatisfy { !$0.symbol.isEmpty })
    }

    func testProviderTransferWithoutDirectLinkCanExposeFocusableChildren() {
        let child = ProviderChildFile(id: "77", name: "Episode.mkv", size: 1_000, mimeType: "video/x-matroska")
        let transfer = ProviderFile(id: "tb-1", name: "Season", size: 1_000, status: "cached", progress: 1, link: nil, createdAt: nil, kind: ProviderKind.torBox.rawValue, remoteID: "42", sourceType: "torrent", children: [child])
        XCTAssertNil(transfer.link)
        XCTAssertEqual(transfer.children, [child])
        XCTAssertEqual(transfer.remoteID, "42")
    }

    func testStreamSourceRoundTripPreservesEphemeralHeaders() throws {
        let source = StreamSource(id: "webdav", name: "File", url: URL(string: "https://example.com/file.mp4")!, provider: "WebDAV", details: "4K • 12.4 GB", fileName: "release.mkv", headers: ["Authorization": "Basic redacted"])
        let decoded = try JSONDecoder().decode(StreamSource.self, from: JSONEncoder().encode(source))
        XCTAssertEqual(decoded, source)
        XCTAssertEqual(decoded.details, "4K • 12.4 GB")
        XCTAssertEqual(decoded.fileName, "release.mkv")
    }

    func testMediaItemRoundTripPreservesStremioType() throws {
        let item = MediaItem(id: "episode", title: "An Episode", externalID: "tt1234567:2:4", mediaType: "seriesEpisode", seasonNumber: 2, episodeNumber: 4)
        let decoded = try JSONDecoder().decode(MediaItem.self, from: JSONEncoder().encode(item))
        XCTAssertEqual(decoded.mediaType, "seriesEpisode")
        XCTAssertEqual(decoded.seasonNumber, 2)
        XCTAssertEqual(decoded.episodeNumber, 4)
    }

    func testStremioSearchUsesProtocolExtraPath() {
        let catalog = AddonCatalog(id: "top", type: "movie", name: "Popular", extra: [AddonExtra(name: "search", isRequired: false, options: nil)])
        let url = StremioService.catalogURL(baseURL: URL(string: "https://v3-cinemeta.strem.io")!, catalog: catalog, query: "game of thrones")
        XCTAssertEqual(url.absoluteString, "https://v3-cinemeta.strem.io/catalog/movie/top/search=game%20of%20thrones.json")
        XCTAssertNil(URLComponents(url: url, resolvingAgainstBaseURL: false)?.query)
    }

    func testStremioPaginationKeepsSearchAndSkipInProtocolExtraPath() {
        let catalog = AddonCatalog(id: "top", type: "series", name: "Top", extra: nil)
        let url = StremioService.catalogURL(
            baseURL: URL(string: "https://v3-cinemeta.strem.io")!,
            catalog: catalog,
            query: "severance",
            skip: 40
        )
        XCTAssertEqual(url.absoluteString, "https://v3-cinemeta.strem.io/catalog/series/top/search=severance&skip=40.json")
        XCTAssertNil(URLComponents(url: url, resolvingAgainstBaseURL: false)?.query)
    }

    func testStremioSeriesUsesEpisodeMetadataAndStreamPaths() {
        let baseURL = URL(string: "https://v3-cinemeta.strem.io")!
        XCTAssertEqual(
            StremioService.metaURL(baseURL: baseURL, type: "series", id: "tt1234567").absoluteString,
            "https://v3-cinemeta.strem.io/meta/series/tt1234567.json"
        )
        XCTAssertEqual(
            StremioService.streamURL(baseURL: baseURL, type: "series", id: "tt1234567:2:4").absoluteString,
            "https://v3-cinemeta.strem.io/stream/series/tt1234567:2:4.json"
        )
    }

    func testTorrentioMetadataIsExtractedForSourceComparison() {
        let metadata = TorrentStreamMetadata.parse(
            name: "[RD+] Torrentio\n1080p",
            details: "Example.Show.S01E01.1080p.WEB-DL.x265.mkv\n👤 42 💾 2.31 GB ⚙️ ThePirateBay",
            fileName: nil,
            videoSize: nil,
            bingeGroup: "torrentio|1080p|WEB-DL|x265"
        )
        XCTAssertEqual(metadata.resolution, "1080p")
        XCTAssertEqual(metadata.fileSizeBytes, 2_480_343_613)
        XCTAssertEqual(metadata.videoCodec?.lowercased(), "x265")
        XCTAssertEqual(metadata.releaseType?.lowercased(), "web-dl")
        XCTAssertEqual(metadata.container, "MKV")
        XCTAssertEqual(metadata.indexer, "ThePirateBay")
        XCTAssertEqual(metadata.seeders, 42)
        XCTAssertEqual(metadata.isCached, true)
    }

    func testWebDAVFilenameProducesCinemetaArtworkHint() {
        XCTAssertEqual(
            WebDAVMediaHint.parse("Alpha.Males.S04E03.1080p.WEB-DL.mkv"),
            WebDAVMediaHint(query: "Alpha Males", preferredType: "series")
        )
        XCTAssertEqual(
            WebDAVMediaHint.parse("Project.Hail.Mary.2026.2160p.WEB-DL.mkv"),
            WebDAVMediaHint(query: "Project Hail Mary", preferredType: nil)
        )
    }
}
