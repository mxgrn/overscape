import AppKit
import SwiftUI

struct FolderCardView: View {
    let card: FolderCard
    let model: CanvasModel

    @GestureState private var dragOffset: CGSize = .zero
    @State private var selection: FileEntry.ID?

    static let width: CGFloat = 490
    static let rowHeight: CGFloat = 27
    static let maxListHeight: CGFloat = 640

    private static let sizeColumn: CGFloat = 70
    private static let dateColumn: CGFloat = 120

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            columnHeaders
            Divider()
            list
        }
        .frame(width: Self.width)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.accentColor.opacity(0.5), lineWidth: 1.5)
        )
        .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
        .offset(x: card.position.x + dragOffset.width, y: card.position.y + dragOffset.height)
    }

    // MARK: - Parts

    private var header: some View {
        ZStack {
            HStack(spacing: 6) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: card.url.path))
                    .resizable()
                    .frame(width: 16, height: 16)
                Text(card.title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
            }
            HStack {
                Button {
                    model.close(card.id)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Close card")
                Spacer()
                Text("\(card.entries.count)")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
        }
        .frame(height: 32)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .gesture(moveGesture)
    }

    private var columnHeaders: some View {
        HStack(spacing: 8) {
            Text("Name").frame(maxWidth: .infinity, alignment: .leading)
            Text("Size").frame(width: Self.sizeColumn, alignment: .trailing)
            Text("Date Modified").frame(width: Self.dateColumn, alignment: .leading)
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .frame(height: 24)
    }

    private var list: some View {
        let contentHeight = CGFloat(max(card.entries.count, 1)) * Self.rowHeight
        return ScrollView {
            LazyVStack(spacing: 0) {
                if card.entries.isEmpty {
                    Text("Empty folder")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .frame(height: Self.rowHeight)
                }
                ForEach(Array(card.entries.enumerated()), id: \.element.id) { index, entry in
                    row(entry, index: index)
                }
            }
        }
        .frame(height: min(contentHeight, Self.maxListHeight))
    }

    private func row(_ entry: FileEntry, index: Int) -> some View {
        let isSelected = selection == entry.id
        return HStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: entry.url.path))
                    .resizable()
                    .frame(width: 16, height: 16)
                Text(entry.name)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(Self.format(size: entry.size))
                .foregroundStyle(.secondary)
                .frame(width: Self.sizeColumn, alignment: .trailing)

            Text(entry.modified.map(Self.format(date:)) ?? "--")
                .foregroundStyle(.secondary)
                .frame(width: Self.dateColumn, alignment: .leading)
        }
        .font(.system(size: 13))
        .padding(.horizontal, 10)
        .frame(height: Self.rowHeight)
        .background(rowBackground(isSelected: isSelected, index: index))
        .contentShape(Rectangle())
        .onTapGesture { selection = entry.id }
    }

    private func rowBackground(isSelected: Bool, index: Int) -> Color {
        if isSelected { return Color.accentColor.opacity(0.2) }
        return index.isMultiple(of: 2) ? .clear : Color.primary.opacity(0.035)
    }

    // MARK: - Dragging

    private var moveGesture: some Gesture {
        DragGesture(coordinateSpace: .global)
            // The translation is in screen points. Divide by the zoom to get canvas points.
            .updating($dragOffset) { value, state, _ in
                state = CGSize(width: value.translation.width / model.zoom, height: value.translation.height / model.zoom)
            }
            .onChanged { _ in model.bringToFront(card.id) }
            .onEnded { value in
                model.move(card.id, to: CGPoint(
                    x: card.position.x + value.translation.width / model.zoom,
                    y: card.position.y + value.translation.height / model.zoom
                ))
            }
    }

    // MARK: - Formatting

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd.MM.yy, HH:mm"
        return formatter
    }()

    static func format(date: Date) -> String {
        dateFormatter.string(from: date)
    }

    static func format(size: Int64?) -> String {
        guard let size else { return "--" }
        return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }
}
