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
        let file = ThumbnailLoader.Request(entry: try #require(entries.first { $0.name == "a.gif" }), iconSize: 64)
        let folder = ThumbnailLoader.Request(entry: try #require(entries.first { $0.name == "sub" }), iconSize: 64)

        #expect(ThumbnailLoader.cached(file) == nil)
        #expect(await ThumbnailLoader.thumbnail(for: file, scale: 1) != nil)
        #expect(ThumbnailLoader.cached(file) != nil)
        #expect(await ThumbnailLoader.thumbnail(for: folder, scale: 1) == nil)
    }

    @Test func aThumbnailIsNotSmallerThanTheIcon() throws {
        let entry = FileEntry(url: URL(fileURLWithPath: "/a.gif"), name: "a.gif", isDirectory: false, size: nil, modified: nil)

        #expect(ThumbnailLoader.Request(entry: entry, iconSize: 40).size == 64)
        #expect(ThumbnailLoader.Request(entry: entry, iconSize: 65).size == 128)
        #expect(ThumbnailLoader.Request(entry: entry, iconSize: 256).size == 256)
    }
}
