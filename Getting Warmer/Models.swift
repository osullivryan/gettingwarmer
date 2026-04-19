import Foundation

struct PuzzleStop: Codable {
    let lat: Double
    let lon: Double
    let radius: Double
    let message: String
}

struct Puzzle: Codable {
    var name: String
    let stops: [PuzzleStop]
    let version: Int

    init(name: String, stops: [PuzzleStop], version: Int) {
        self.name = name
        self.stops = stops
        self.version = version
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name    = (try? c.decode(String.self, forKey: .name)) ?? ""
        stops   = try c.decode([PuzzleStop].self, forKey: .stops)
        version = try c.decode(Int.self, forKey: .version)
    }
}

struct SavedMeasurement: Codable {
    let lat: Double
    let lon: Double
    let radius: Double
    var accuracy: Double
    var stopIndex: Int
}

struct StoredPuzzle: Codable, Identifiable {
    let id: UUID
    let puzzle: Puzzle
    let createdAt: Date
    var solved: Bool
    var solvedAt: Date?
    var currentStopIndex: Int = 0
    var solvedStopIndices: [Int] = []
    var measurements: [SavedMeasurement] = []
}
