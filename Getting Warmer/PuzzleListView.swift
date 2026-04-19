import SwiftUI

struct PuzzleListView: View {
    @Environment(PuzzleStore.self) var puzzleStore
    @State private var pendingDelete: StoredPuzzle?
    @State private var shareImage: UIImage?
    @State private var shareTitle: String = ""

    var body: some View {
        List {
            ForEach(puzzleStore.puzzles.reversed()) { stored in
                NavigationLink {
                    GameView(storedPuzzle: stored)
                } label: {
                    PuzzleRow(stored: stored)
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        pendingDelete = stored
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                    Button {
                        if let data = try? JSONEncoder().encode(stored.puzzle),
                           let json = String(data: data, encoding: .utf8),
                           let img = makeQRImage(from: json) {
                            shareImage = img
                            shareTitle = stored.puzzle.name
                        }
                    } label: {
                        Label("Share", systemImage: "qrcode")
                    }
                    .tint(.blue)
                }
            }
        }
        .confirmationDialog(
            "Delete \"\(pendingDelete?.puzzle.name ?? "")\"?",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let p = pendingDelete { puzzleStore.delete(p) }
                pendingDelete = nil
            }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        }
        .sheet(item: Binding(
            get: { shareImage.map { ShareImageWrapper(image: $0, name: shareTitle) } },
            set: { if $0 == nil { shareImage = nil } }
        )) { wrapper in
            QRCodeView(image: wrapper.image, puzzleName: wrapper.name)
        }
        .navigationTitle("My Puzzles")
        .overlay {
            if puzzleStore.puzzles.isEmpty {
                ContentUnavailableView(
                    "No Puzzles Yet",
                    systemImage: "qrcode",
                    description: Text("Create a puzzle or scan a QR code to get started.")
                )
            }
        }
    }
}

private struct PuzzleRow: View {
    let stored: StoredPuzzle

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: stored.solved ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(stored.solved ? .green : .secondary)
                .font(.title3)

            VStack(alignment: .leading, spacing: 4) {
                Text(stored.puzzle.name.isEmpty ? "Untitled Puzzle" : stored.puzzle.name)
                    .font(.headline)
                    .lineLimit(2)

                HStack(spacing: 8) {
                    let stopCount = stored.puzzle.stops.count
                    if stored.solved {
                        Label(stopCount == 1 ? "Solved" : "All \(stopCount) stops complete", systemImage: "checkmark")
                    } else if stopCount > 1 {
                        Label("Stop \(stored.currentStopIndex + 1) of \(stopCount)", systemImage: "map")
                    } else {
                        Label(formatDistance(stored.puzzle.stops[0].radius), systemImage: "scope")
                    }
                    Text("·")
                    Text(stored.createdAt.formatted(date: .abbreviated, time: .omitted))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct ShareImageWrapper: Identifiable {
    let id = UUID()
    let image: UIImage
    let name: String
}
