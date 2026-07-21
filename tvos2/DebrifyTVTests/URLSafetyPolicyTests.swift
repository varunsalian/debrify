import XCTest
@testable import DebrifyTV

final class URLSafetyPolicyTests: XCTestCase {
    func testCredentialBearingHTTPIsRejected() {
        XCTAssertThrowsError(try URLSafetyPolicy.validate(URL(string: "http://example.com/api")!, credentialBearing: true)) { error in
            XCTAssertEqual(error as? NetworkPolicyError, .insecureTransport)
        }
    }

    func testHTTPSPublicHostIsAllowed() {
        XCTAssertNoThrow(try URLSafetyPolicy.validate(URL(string: "https://api.real-debrid.com/rest/1.0/user")!, credentialBearing: true, blockPrivateNetworks: true))
    }

    func testPrivateIPv4RangesAreBlockedForImports() {
        for host in ["127.0.0.1", "10.0.0.3", "172.16.1.1", "192.168.1.5", "169.254.2.3", "224.0.0.1"] {
            XCTAssertThrowsError(try URLSafetyPolicy.validate(URL(string: "https://\(host)/manifest.json")!, blockPrivateNetworks: true), host)
        }
    }

    func testLocalNamesAndIPv6AreBlockedForImports() {
        for url in ["https://localhost/manifest.json", "https://media.local/manifest.json", "https://[::1]/manifest.json", "https://[fe80::1]/manifest.json"] {
            XCTAssertThrowsError(try URLSafetyPolicy.validate(URL(string: url)!, blockPrivateNetworks: true), url)
        }
    }
}

