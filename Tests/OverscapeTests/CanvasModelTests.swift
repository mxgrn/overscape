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

    @Test func zoomStaysInRange() {
        let model = CanvasModel()

        model.zoom(by: 100, around: .zero)

        #expect(model.zoom == CanvasModel.zoomRange.upperBound)
    }
}
