import Foundation
import Testing
@testable import Overscape

@MainActor
struct CanvasModelTests {
    @Test func zoomKeepsThePointUnderTheAnchorInPlace() {
        let model = CanvasModel()
        model.pan(by: CGSize(width: 40, height: -10))
        let anchor = CGPoint(x: 300, y: 200)
        let before = model.canvasPoint(fromView: anchor)

        model.zoom(by: 2, around: anchor)

        #expect(model.zoom == 2)
        #expect(model.canvasPoint(fromView: anchor) == before)
    }

    @Test func childCardsKeepTheOrderOfTheirRows() throws {
        let root = try makeFolder(subfolders: ["a", "b", "c"])
        defer { try? FileManager.default.removeItem(at: root) }
        let model = CanvasModel()
        model.addFolders([root], at: CGPoint(x: 100, y: 100))
        let parent = model.cards[0]
        let rows = parent.entries.map(\.url)

        // Open the bottom row first, then the top row (it must go above),
        // then the middle row (no space, so the bottom card must move down).
        model.openChild(of: parent.id, folder: rows[2])
        model.openChild(of: parent.id, folder: rows[0])
        model.openChild(of: parent.id, folder: rows[1])
        model.openChild(of: parent.id, folder: rows[0])

        #expect(model.cards.count == 4)
        let children = try rows.map { row in try #require(model.cards.first { $0.url == row }) }
        #expect(children.allSatisfy { $0.position.x == 100 + CardLayout.width + CardLayout.childSpacing })
        for (upper, lower) in zip(children, children.dropFirst()) {
            #expect(upper.position.y + upper.height + CardLayout.siblingSpacing <= lower.position.y)
        }
    }

    @Test func closeAlsoClosesChildCards() throws {
        let root = try makeFolder(subfolders: ["a"])
        defer { try? FileManager.default.removeItem(at: root) }
        let model = CanvasModel()
        model.addFolders([root], at: .zero)
        model.openChild(of: model.cards[0].id, folder: model.cards[0].entries[0].url)
        #expect(model.cards.count == 2)

        model.close(model.cards[0].id)

        #expect(model.cards.isEmpty)
    }

    private func makeFolder(subfolders: [String]) throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        for name in subfolders {
            try FileManager.default.createDirectory(at: root.appendingPathComponent(name), withIntermediateDirectories: true)
        }
        return root
    }

    @Test func zoomStaysInRange() {
        let model = CanvasModel()

        model.zoom(by: 100, around: .zero)

        #expect(model.zoom == CanvasModel.zoomRange.upperBound)
    }
}
