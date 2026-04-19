import SwiftUI
import MapKit
import CoreLocation

struct QRItem: Identifiable {
    let id = UUID()
    let image: UIImage
}

struct DraftStop: Identifiable {
    let id = UUID()
    var coordinate: CLLocationCoordinate2D?
    var radius: String = "50"
    var message: String = ""
}

struct ProducerView: View {
    @Environment(PuzzleStore.self) var puzzleStore
    @Environment(LocationManager.self) var locationManager
    @Environment(\.dismiss) private var dismiss

    @State private var puzzleName: String = ""
    @State private var stops: [DraftStop] = [DraftStop()]
    @State private var selectedStopIndex: Int = 0
    @State private var cameraPosition: MapCameraPosition = .region(MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
        span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
    ))
    @State private var qrItem: QRItem?
    @State private var errorMessage: String?
    @State private var showingError = false

    @State private var searchText = ""
    @State private var searchResults: [MKMapItem] = []
    @State private var searchTask: Task<Void, Never>? = nil
    @FocusState private var searchFocused: Bool

    private var allStopsValid: Bool {
        !puzzleName.trimmingCharacters(in: .whitespaces).isEmpty &&
        stops.allSatisfy { $0.coordinate != nil && !$0.message.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search bar
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search for a location…", text: $searchText)
                    .autocorrectionDisabled()
                    .focused($searchFocused)
                    .onChange(of: searchText) { _, new in
                        searchTask?.cancel()
                        guard !new.trimmingCharacters(in: .whitespaces).isEmpty else {
                            searchResults = []
                            return
                        }
                        searchTask = Task {
                            try? await Task.sleep(for: .milliseconds(400))
                            guard !Task.isCancelled else { return }
                            let req = MKLocalSearch.Request()
                            req.naturalLanguageQuery = new
                            let response = try? await MKLocalSearch(request: req).start()
                            await MainActor.run { searchResults = response?.mapItems ?? [] }
                        }
                    }
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                        searchResults = []
                        searchTask?.cancel()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(.systemBackground))

            Divider()

            ZStack(alignment: .top) {
                MapReader { proxy in
                    Map(position: $cameraPosition) {
                        ForEach(stops.indices, id: \.self) { i in
                            if let coord = stops[i].coordinate {
                                Marker("Stop \(i + 1)", coordinate: coord)
                                    .tint(i == selectedStopIndex ? .red : .blue)
                            }
                        }
                    }
                    .frame(height: 200)
                    .onTapGesture { screenPosition in
                        if let coord = proxy.convert(screenPosition, from: .local) {
                            stops[selectedStopIndex].coordinate = coord
                            searchResults = []
                            searchFocused = false
                        }
                    }
                    .mapControls { MapCompass() }
                    .overlay(alignment: .top) {
                        if searchResults.isEmpty {
                            let placed = stops[selectedStopIndex].coordinate != nil
                            Text(placed
                                 ? "Stop \(selectedStopIndex + 1) placed — tap to move"
                                 : "Tap map to place Stop \(selectedStopIndex + 1)")
                                .font(.caption)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(.ultraThinMaterial)
                                .cornerRadius(8)
                                .padding(.top, 8)
                        }
                    }
                }

                if !searchResults.isEmpty {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(searchResults, id: \.self) { item in
                                Button {
                                    let coord = item.placemark.coordinate
                                    stops[selectedStopIndex].coordinate = coord
                                    cameraPosition = .region(MKCoordinateRegion(
                                        center: coord,
                                        span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                                    ))
                                    searchTask?.cancel()
                                    searchText = ""
                                    searchResults = []
                                    searchFocused = false
                                } label: {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.name ?? "")
                                            .font(.subheadline)
                                            .foregroundStyle(.primary)
                                        if let subtitle = item.placemark.title, subtitle != item.name {
                                            Text(subtitle)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                                .lineLimit(1)
                                        }
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                Divider().padding(.leading, 12)
                            }
                        }
                    }
                    .frame(maxHeight: 220)
                    .background(.regularMaterial)
                    .cornerRadius(12)
                    .shadow(color: .black.opacity(0.15), radius: 6, y: 3)
                    .padding(.horizontal, 8)
                    .padding(.top, 8)
                }
            }

            Form {
                Section("Puzzle") {
                    TextField("Name (shown to the player)", text: $puzzleName)
                }

                Section("Stops") {
                    ForEach(stops.indices, id: \.self) { i in
                        stopRow(index: i)
                    }
                    .onDelete { indexSet in
                        guard stops.count > 1 else { return }
                        stops.remove(atOffsets: indexSet)
                        selectedStopIndex = min(selectedStopIndex, stops.count - 1)
                    }
                    .onMove { from, to in
                        let selectedID = stops[selectedStopIndex].id
                        stops.move(fromOffsets: from, toOffset: to)
                        selectedStopIndex = stops.firstIndex(where: { $0.id == selectedID }) ?? 0
                    }

                    Button {
                        stops.append(DraftStop())
                        selectedStopIndex = stops.count - 1
                    } label: {
                        Label("Add Stop", systemImage: "plus.circle")
                    }
                }

                Section {
                    Button { generateQR() } label: {
                        Label("Generate QR Code", systemImage: "qrcode")
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                    .disabled(!allStopsValid)

                    Button { saveLocally() } label: {
                        Label("Save Locally (No QR)", systemImage: "square.and.arrow.down")
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                    .disabled(!allStopsValid)
                }
            }
        }
        .navigationTitle("Create Puzzle")
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) { EditButton() }
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                }
            }
        }
        .onAppear {
            if let loc = locationManager.location {
                cameraPosition = .region(MKCoordinateRegion(
                    center: loc.coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
                ))
            }
        }
        .sheet(item: $qrItem) { item in
            QRCodeView(image: item.image, puzzleName: puzzleName)
        }
        .alert("Error", isPresented: $showingError, presenting: errorMessage) { _ in
            Button("OK", role: .cancel) {}
        } message: { msg in
            Text(msg)
        }
    }

    @ViewBuilder
    private func stopRow(index i: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "\(i + 1).circle.fill")
                    .foregroundStyle(selectedStopIndex == i ? Color.accentColor : .secondary)
                Text("Stop \(i + 1)")
                    .font(.headline)
                    .foregroundStyle(selectedStopIndex == i ? Color.accentColor : .primary)
                Spacer()
                Button(stops[i].coordinate == nil ? "Place" : "Move") {
                    selectedStopIndex = i
                }
                .font(.caption)
                .buttonStyle(.bordered)
                .tint(selectedStopIndex == i ? Color.accentColor : nil)
            }

            if let coord = stops[i].coordinate {
                Text(String(format: "%.5f, %.5f", coord.latitude, coord.longitude))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            TextField("Message when reached", text: $stops[i].message, axis: .vertical)
                .lineLimit(2...4)

            HStack {
                Text("Unlock radius (m)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                TextField("50", text: $stops[i].radius)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 60)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture { selectedStopIndex = i }
    }

    private func buildPuzzle() -> (Puzzle, StoredPuzzle)? {
        guard !puzzleName.trimmingCharacters(in: .whitespaces).isEmpty else {
            fail("Give the puzzle a name.")
            return nil
        }
        for (i, stop) in stops.enumerated() {
            guard stop.coordinate != nil else {
                fail("Stop \(i + 1) has no location — tap the map to place it.")
                return nil
            }
            guard let r = Double(stop.radius), r > 0 else {
                fail("Stop \(i + 1) has an invalid radius.")
                return nil
            }
            guard !stop.message.trimmingCharacters(in: .whitespaces).isEmpty else {
                fail("Stop \(i + 1) needs a message.")
                return nil
            }
        }
        let puzzleStops = stops.map { stop in
            PuzzleStop(
                lat: stop.coordinate!.latitude,
                lon: stop.coordinate!.longitude,
                radius: Double(stop.radius)!,
                message: stop.message.trimmingCharacters(in: .whitespaces)
            )
        }
        let puzzle = Puzzle(name: puzzleName.trimmingCharacters(in: .whitespaces), stops: puzzleStops, version: 1)
        let stored = StoredPuzzle(id: UUID(), puzzle: puzzle, createdAt: Date(), solved: false)
        return (puzzle, stored)
    }

    private func generateQR() {
        guard let (puzzle, stored) = buildPuzzle() else { return }
        do {
            let json = try JSONEncoder().encode(puzzle)
            guard let jsonString = String(data: json, encoding: .utf8),
                  let image = makeQRImage(from: jsonString) else {
                fail("Failed to render QR image.")
                return
            }
            puzzleStore.save(stored)
            qrItem = QRItem(image: image)
        } catch {
            fail("Encoding failed: \(error.localizedDescription)")
        }
    }

    private func saveLocally() {
        guard let (_, stored) = buildPuzzle() else { return }
        puzzleStore.save(stored)
        dismiss()
    }

    private func fail(_ msg: String) {
        errorMessage = msg
        showingError = true
    }

}
