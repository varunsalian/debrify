import XCTest
@testable import DebrifyTV

final class InfuseLauncherTests: XCTestCase {
    func testPlaybackURLPreservesSignedStreamURLAndFilename() throws {
        let streamURL = try XCTUnwrap(URL(string: "https://cdn.example.test/video.mkv?token=a%2Bb&expires=123"))
        let item = MediaItem(id: "movie", title: "A Movie & Friends")
        let source = StreamSource(id: "source", name: "4K", url: streamURL, provider: "TorBox")

        let url = try XCTUnwrap(InfuseLauncher.playbackURL(item: item, source: source))
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let values = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).compactMap { item in
            item.value.map { (item.name, $0) }
        })

        XCTAssertEqual(components.scheme, "infuse")
        XCTAssertEqual(components.host, "x-callback-url")
        XCTAssertEqual(components.path, "/play")
        XCTAssertEqual(values["url"], streamURL.absoluteString)
        XCTAssertEqual(values["filename"], item.title)
        XCTAssertFalse(url.absoluteString.contains("url=https://"))
        XCTAssertTrue(url.absoluteString.contains("url=https%3A%2F%2F"))
        XCTAssertTrue(url.absoluteString.contains("%253F") == false)
    }

    func testPlaybackPreferencesDefaultToInternalPlayer() {
        XCTAssertFalse(PlaybackPreferences().alwaysOpenInInfuse)
    }
}
