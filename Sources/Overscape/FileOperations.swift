import Foundation

/// Operations on files and folders on disk, with the rules that Finder uses.
enum FileOperations {
    // Symlinks are resolved before paths are compared, so that two different paths to the same
    // folder compare equal. An item that is a symlink is not resolved: the operation is on the link.

    private static func folderPath(_ folder: URL) -> [String] {
        folder.resolvingSymlinksInPath().pathComponents
    }

    private static func itemPath(_ item: URL) -> [String] {
        folderPath(item.deletingLastPathComponent()) + [item.lastPathComponent]
    }

    /// True when `folder` is the folder that contains `item`.
    static func isItem(_ item: URL, directlyIn folder: URL) -> Bool {
        folderPath(item.deletingLastPathComponent()) == folderPath(folder)
    }

    /// True when `folder` is `item` or is in `item`, at any depth. Such a folder cannot receive the item.
    static func isFolder(_ folder: URL, inOrEqualTo item: URL) -> Bool {
        folderPath(folder).starts(with: itemPath(item))
    }

    /// Finder moves an item when the source and the destination are on the same volume.
    static func isSameVolume(_ first: URL, _ second: URL) -> Bool {
        guard let firstID = try? first.resourceValues(forKeys: [.volumeIdentifierKey]).volumeIdentifier,
              let secondID = try? second.resourceValues(forKeys: [.volumeIdentifierKey]).volumeIdentifier
        else { return true }
        return firstID.isEqual(secondID)
    }

    /// A URL in `folder` for the item, with a name that is free at this time.
    /// When the name is taken, the name gets a suffix as in Finder:
    /// "a copy.txt", "a copy 2.txt" for a copy and "a 2.txt", "a 3.txt" for a move.
    static func freeURL(for item: URL, in folder: URL, isCopy: Bool) -> URL {
        let name = item.lastPathComponent
        let direct = folder.appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath: direct.path) else { return direct }

        // A dot in a folder name does not start an extension.
        let hasExtension = !FolderLoader.isDirectory(item) && !item.pathExtension.isEmpty
        let ending = hasExtension ? ".\(item.pathExtension)" : ""
        let base = String(name.dropLast(ending.count)) + (isCopy ? " copy" : "")
        var number = isCopy ? 1 : 2
        while true {
            let candidate = folder.appendingPathComponent((number == 1 ? base : "\(base) \(number)") + ending)
            if !FileManager.default.fileExists(atPath: candidate.path) { return candidate }
            number += 1
        }
    }

    /// Copies the item into the folder. Returns the URL of the copy.
    static func copy(_ item: URL, into folder: URL) throws -> URL {
        let target = freeURL(for: item, in: folder, isCopy: true)
        try FileManager.default.copyItem(at: item, to: target)
        return target
    }

    /// Moves the item into the folder. Returns the new URL of the item.
    static func move(_ item: URL, into folder: URL) throws -> URL {
        let target = freeURL(for: item, in: folder, isCopy: false)
        try FileManager.default.moveItem(at: item, to: target)
        return target
    }

    /// Moves the item to the Trash. Returns the URL of the item in the Trash, when the system gives it.
    static func trash(_ item: URL) throws -> URL? {
        var trashed: NSURL?
        try FileManager.default.trashItem(at: item, resultingItemURL: &trashed)
        return trashed as URL?
    }
}

/// Reports the changes in the list of items of a folder.
enum FolderWatcher {
    /// Gives a value each time an item is added to the folder, removed from it or renamed in it.
    /// The stream ends when the folder cannot be opened.
    static func changes(in folder: URL) -> AsyncStream<Void> {
        AsyncStream { continuation in
            let descriptor = open(folder.path, O_EVTONLY)
            guard descriptor >= 0 else {
                continuation.finish()
                return
            }
            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: descriptor, eventMask: [.write, .rename, .delete], queue: .main
            )
            source.setEventHandler { continuation.yield() }
            source.setCancelHandler { close(descriptor) }
            continuation.onTermination = { _ in source.cancel() }
            source.resume()
        }
    }
}
