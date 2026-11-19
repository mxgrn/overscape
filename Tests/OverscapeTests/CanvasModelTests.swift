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

    @Test func openChildPlacesCardsRightOfParentAndBelowEachOther() throws {
        let root = try makeFolder(subfolders: ["a", "b"])
        defer { try? FileManager.default.removeItem(at: root) }
        let model = CanvasModel()
        model.addFolders([root], at: CGPoint(x: 100, y: 100))
        let parent = model.cards[0]
        let a = try #require(parent.entries.first { $0.name == "a" }).url
        let b = try #require(parent.entries.first { $0.name == "b" }).url

        model.openChild(of: parent.id, folder: a)
        model.openChild(of: parent.id, folder: b)
        model.openChild(of: parent.id, folder: a)

        #expect(model.cards.count == 3)
        let childA = try #require(model.cards.first { $0.url == a })
        let childB = try #require(model.cards.first { $0.url == b })
        #expect(childA.position.x == 100 + CardLayout.width + CardLayout.childSpacing)
        #expect(childB.position.y == childA.position.y + childA.height + CardLayout.siblingSpacing)
        #expect(model.connections.count == 2)
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
