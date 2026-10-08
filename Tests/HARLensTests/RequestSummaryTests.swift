import XCTest
import HARCore
@testable import HARLens

final class RequestSummaryTests: XCTestCase {
    func testUnrepresentableResponseTotalIsUnknown() throws {
        let archive = try HARArchive.decode(Data(#"{"log":{"entries":[{"request":{"method":"GET","url":"https://example.test/a"},"response":{"status":200,"content":{"size":9223372036854775807}}},{"request":{"method":"GET","url":"https://example.test/b"},"response":{"status":200,"content":{"size":1}}}]}}"#.utf8))
        XCTAssertNil(totalResponseBytes(archive.entries))
    }

    func testResponseTotalIncludesOnlyKnownNonnegativeSizes() throws {
        let archive = try HARArchive.decode(Data(#"{"log":{"entries":[{"request":{"method":"GET","url":"https://example.test/a"},"response":{"status":200,"content":{"size":24}}},{"request":{"method":"GET","url":"https://example.test/b"},"response":{"status":200,"content":{"size":-1}}},{"request":{"method":"GET","url":"https://example.test/c"},"response":{"status":200}}]}}"#.utf8))
        XCTAssertEqual(totalResponseBytes(archive.entries), 24)
    }
}
