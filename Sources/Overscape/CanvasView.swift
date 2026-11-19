import SwiftUI

struct CanvasView: View {
    @State private var model = CanvasModel()
    @State private var isTargeted = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            DotGrid()

            if model.cards.isEmpty {
                Text("Drag a folder here")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .allowsHitTesting(false)
            }

            ForEach(model.cards) { card in
                FolderCardView(card: card, model: model)
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
            model.addFolders(urls, at: CGPoint(x: location.x - 20, y: location.y - 15))
        } isTargeted: { isTargeted = $0 }
    }
}

/// The dotted background of the canvas.
struct DotGrid: View {
    var spacing: CGFloat = 20

    var body: some View {
        Canvas { context, size in
            let color = Color.secondary.opacity(0.35)
            var y = spacing / 2
            while y < size.height {
                var x = spacing / 2
                while x < size.width {
                    context.fill(Path(ellipseIn: CGRect(x: x - 1, y: y - 1, width: 2, height: 2)), with: .color(color))
                    x += spacing
                }
                y += spacing
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
