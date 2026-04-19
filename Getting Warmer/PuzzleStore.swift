import Foundation
import Observation

@Observable
class PuzzleStore {
    var puzzles: [StoredPuzzle] = []

    private let fileURL: URL = {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("puzzles.json")
    }()

    init() {
        puzzles = load()
    }

    func save(_ puzzle: StoredPuzzle) {
        puzzles.append(puzzle)
        persist()
    }

    func update(_ puzzle: StoredPuzzle) {
        guard let index = puzzles.firstIndex(where: { $0.id == puzzle.id }) else { return }
        puzzles[index] = puzzle
        persist()
    }

    func delete(_ puzzle: StoredPuzzle) {
        puzzles.removeAll { $0.id == puzzle.id }
        persist()
    }

    private func load() -> [StoredPuzzle] {
        guard
            let data = try? Data(contentsOf: fileURL),
            let decoded = try? JSONDecoder().decode([StoredPuzzle].self, from: data)
        else { return [] }
        return decoded
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(puzzles) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}
