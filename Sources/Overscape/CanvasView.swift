import SwiftUI

struct CanvasView: View {
    @State private var model = CanvasModel()
    @State private var isTargeted = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            DotGrid(zoom: model.zoom, pan: model.pan)

            CanvasEventView(
                onPan: { model.pan(by: $0) },
                onMagnify: { model.zoom(by: $0, around: $1) }
            )

            ZStack(alignment: .topLeading) {
                ForEach(model.cards) { card in
                    FolderCardView(card: card, model: model)
                }
            }
            .scaleEffect(model.zoom, anchor: .topLeading)
            .offset(model.pan)

            if model.cards.isEmpty {
                Text("Drag a folder here")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .allowsHitTesting(false)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .overlay {
            if isTargeted {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.accentColor, lineWidth: 3)
                    .allowsHitTesting(false)
            }
        }
        .dropDestination(for: URL.self) { urls, location in
            // Place the top-left corner of the card near the cursor.
            let corner = CGPoint(x: location.x - 20, y: location.y - 15)
            return model.addFolders(urls, at: model.canvasPoint(fromView: corner))
        } isTargeted: { isTargeted = $0 }
    }
}

/// The dotted background of the canvas. It moves and scales with the viewport.
struct DotGrid: View {
    var zoom: CGFloat
    var pan: CGSize
    var spacing: CGFloat = 20

    var body: some View {
        Canvas { context, size in
            let step = spacing * zoom
            guard step >= 6 else { return } // Too dense to be useful.
            let color = Color.secondary.opacity(0.35)
            let startX = pan.width.truncatingRemainder(dividingBy: step) - step
            let startY = pan.height.truncatingRemainder(dividingBy: step) - step
            var y = startY
            while y < size.height {
                var x = startX
                while x < size.width {
                    context.fill(Path(ellipseIn: CGRect(x: x - 1, y: y - 1, width: 2, height: 2)), with: .color(color))
                    x += step
                }
                y += step
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .allowsHitTesting(false)
    }
}
