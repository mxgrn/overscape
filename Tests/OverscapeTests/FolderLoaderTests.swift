import Foundation
import Testing
@testable import Overscape

struct FolderLoaderTests {
    @Test func listsVisibleItemsNewestFirst() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let file = folder.appendingPathComponent("notes.txt")
        try Data("hello".utf8).write(to: file)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 0)], ofItemAtPath: file.path)
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("sub"), withIntermediateDirectories: false)
        try Data().write(to: folder.appendingPathComponent(".hidden"))

        let entries = FolderLoader.entries(in: folder)

        #expect(entries.map(\.name) == ["sub", "notes.txt"])
        #expect(entries[0].isDirectory && entries[0].size == nil)
        #expect(entries[1].size == 5)
    }
}
