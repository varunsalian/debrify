import XCTest
@testable import DebrifyTV

final class DiscoveryServiceTests: XCTestCase {
    func testTraktTrendingEntryBecomesPlayableIMDbMedia() throws {
        let json = #"[{"watchers":99,"movie":{"title":"Example","year":2026,"overview":"Plot","genres":["science-fiction"],"ids":{"imdb":"tt1234567","tmdb":42}}}]"#
        let entry = try JSONDecoder().decode([TraktListEntry].self, from: Data(json.utf8))[0]
        let item = try XCTUnwrap(entry.mediaItem(media: .movie, source: "Trakt · Trending"))
        XCTAssertEqual(item.externalID, "tt1234567")
        XCTAssertEqual(item.mediaType, "movie")
        XCTAssertEqual(item.posterURL?.host, "images.metahub.space")
    }

    func testTMDBResultUsesResolvedIMDbIDForTorrentio() throws {
        let json = #"{"id":42,"title":"New Film","overview":"Plot","poster_path":"/poster.jpg","backdrop_path":"/backdrop.jpg","release_date":"2026-07-10"}"#
        let result = try JSONDecoder().decode(TMDBResult.self, from: Data(json.utf8))
        let item = result.mediaItem(media: .movie, imdbID: "tt7654321")
        XCTAssertEqual(item.externalID, "tt7654321")
        XCTAssertEqual(item.year, 2026)
        XCTAssertEqual(item.posterURL?.host, "image.tmdb.org")
    }
}
