import XCTest
@testable import HARLens

final class FileStoreTests: XCTestCase {
    @MainActor
    func testLaterOpenRequestWinsEvenWhenItFails() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let suite = "HARLensTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let original = folder.appendingPathComponent("original.har")
        let earlier = folder.appendingPathComponent("earlier.har")
        try Data(#"{"log":{"entries":[]}}"#.utf8).write(to: original)
        try Data(#"{"log":{"entries":[]}}"#.utf8).write(to: earlier)
        let store = FileStore(defaults: defaults)
        await store.open(original).value

        let earlierLoad = store.open(earlier)
        let latestLoad = store.open(folder.appendingPathComponent("missing.har"))
        await latestLoad.value
        await earlierLoad.value

        XCTAssertEqual(store.fileURL, original)
        XCTAssertEqual(store.recentURLs, [original])
        XCTAssertNotNil(store.errorMessage)
        XCTAssertFalse(store.isLoading)
    }

    @MainActor
    func testSuccessfulOpenPersistsDeduplicatedRecents() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let suite = "HARLensTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let first = folder.appendingPathComponent("Первый файл.har")
        let second = folder.appendingPathComponent("second.HAR")
        try Data(#"{"log":{"entries":[]}}"#.utf8).write(to: first)
        try Data(#"{"log":{"entries":[]}}"#.utf8).write(to: second)
        let store = FileStore(defaults: defaults)

        await store.open(first).value
        XCTAssertNotNil(store.archive)
        XCTAssertEqual(store.fileURL, first)
        await store.open(second).value
        await store.open(first).value
        XCTAssertEqual(store.recentURLs, [first, second])
        XCTAssertEqual(FileStore(defaults: defaults).recentURLs, [first, second])
        XCTAssertFalse(store.isLoading)
    }

    @MainActor
    func testFailedOpenPreservesDocumentAndHistory() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let suite = "HARLensTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let good = folder.appendingPathComponent("good.har")
        let broken = folder.appendingPathComponent("broken.har")
        let wrongType = folder.appendingPathComponent("archive.json")
        try Data(#"{"log":{"entries":[]}}"#.utf8).write(to: good)
        try Data("not a HAR".utf8).write(to: broken)
        try Data(#"{"log":{"entries":[]}}"#.utf8).write(to: wrongType)
        let store = FileStore(defaults: defaults)
        await store.open(good).value

        for badURL in [broken, wrongType, folder.appendingPathComponent("missing.har")] {
            await store.open(badURL).value
            XCTAssertNotNil(store.errorMessage)
            XCTAssertNotNil(store.archive)
            XCTAssertEqual(store.fileURL, good)
            XCTAssertEqual(store.recentURLs, [good])
            XCTAssertFalse(store.isLoading)
        }
        store.clearHistory()
        XCTAssertTrue(store.recentURLs.isEmpty)
        XCTAssertTrue(FileStore(defaults: defaults).recentURLs.isEmpty)
        XCTAssertEqual(store.fileURL, good)
    }
}
