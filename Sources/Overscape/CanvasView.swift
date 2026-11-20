import SwiftUI

struct CanvasView: View {
    let model: CanvasModel
    @State private var isTargeted = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            DotGrid(zoom: model.zoom, pan: model.pan)

            CanvasEventView(
                onPan: { model.pan(by: $0) },
                onMagnify: { model.zoom(by: $0, around: $1) },
                onViewMode: { model.setViewModeOfHoveredCard($0) }
            )

            ZStack(alignment: .topLeading) {
                ConnectorLines(connections: model.connections)
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

/// Curved lines from a row in a parent card to the child card, like in a mind map.
struct ConnectorLines: View {
    let connections: [Connection]

    var body: some View {
        ForEach(connections) { connection in
            let start = connection.start
            let end = connection.end
            let bend = max(abs(end.x - start.x) / 2, 30)
            Path { path in
                path.move(to: start)
                path.addCurve(
                    to: end,
                    control1: CGPoint(x: start.x + bend, y: start.y),
                    control2: CGPoint(x: end.x - bend, y: end.y)
                )
            }
            .stroke(Color.accentColor.opacity(0.8), lineWidth: 1.5)

            Circle()
                .fill(Color.accentColor)
                .frame(width: 6, height: 6)
                .position(end)
        }
        .allowsHitTesting(false)
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
