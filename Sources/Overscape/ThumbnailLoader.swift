import AppKit
import QuickLookThumbnailing

/// Makes the thumbnails that icon mode shows in place of the file icons, as Finder does.
@MainActor
enum ThumbnailLoader {
    /// The thumbnails that are ready. The system removes items when memory is low.
    private static let cache = NSCache<NSString, NSImage>()

    /// The thumbnail of the item, if it is ready. This does not start the work.
    static func cached(_ entry: FileEntry) -> NSImage? {
        cache.object(forKey: key(entry))
    }

    /// A static picture of the content of the file, not larger than `size` points.
    /// Returns nil for a folder and for a file that macOS cannot make a thumbnail for.
    /// Such an item keeps its icon.
    static func thumbnail(for entry: FileEntry, size: CGFloat, scale: CGFloat) async -> NSImage? {
        guard !entry.isDirectory else { return nil }
        if let image = cached(entry) { return image }

        let request = QLThumbnailGenerator.Request(
            fileAt: entry.url, size: CGSize(width: size, height: size), scale: scale,
            representationTypes: .thumbnail
        )
        guard let image = await generate(request) else { return nil }
        cache.setObject(image, forKey: key(entry))
        return image
    }

    private nonisolated static func generate(_ request: QLThumbnailGenerator.Request) async -> NSImage? {
        try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request).nsImage
    }

    /// A changed file has a different date, so it gets a new thumbnail.
    private static func key(_ entry: FileEntry) -> NSString {
        "\(entry.url.path)|\(entry.modified?.timeIntervalSince1970 ?? 0)" as NSString
    }
}
