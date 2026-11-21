import Foundation
import Testing
@testable import Overscape

@MainActor
struct ThumbnailLoaderTests {
    @Test func aGIFFileGetsAThumbnailAndAFolderDoesNot() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("sub"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        // A GIF picture of 1 × 1 pixel.
        let gif = try #require(Data(base64Encoded: "R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7"))
        try gif.write(to: root.appendingPathComponent("a.gif"))
        let entries = FolderLoader.entries(in: root)
        let file = try #require(entries.first { $0.name == "a.gif" })
        let folder = try #require(entries.first { $0.name == "sub" })

        #expect(ThumbnailLoader.cached(file) == nil)
        #expect(await ThumbnailLoader.thumbnail(for: file, size: 64, scale: 1) != nil)
        #expect(ThumbnailLoader.cached(file) != nil)
        #expect(await ThumbnailLoader.thumbnail(for: folder, size: 64, scale: 1) == nil)
    }
}
