import SwiftUI
import MapKit
import CoreLocation

struct CircleGuess: Identifiable {
    let id = UUID()
    let center: CLLocationCoordinate2D
    let radius: Double
    let accuracy: Double
    let index: Int      // drives circle color
    let stopIndex: Int  // which stop this measurement belongs to
}

// Geodesic circle rendered as a polygon so projection distortion doesn't affect accuracy
final class IndexedPolygon: MKPolygon {
    var colorIndex: Int = 0
    var accuracy: Double = 0
}

struct GameView: View {
    let storedPuzzle: StoredPuzzle
    @Environment(PuzzleStore.self) var puzzleStore
    @Environment(LocationManager.self) var locationManager

    @State private var guesses: [CircleGuess] = []
    @State private var hiddenGuessIDs: Set<UUID> = []
    @State private var showGuessList = false
    @State private var estimatedTarget: CLLocationCoordinate2D?
    @State private var lastDistance: Double?
    @State private var unlocked = false
    @State private var unlockedStopMessage: String = ""
    @State private var unlockedStopNumber: Int = 1
    @State private var showAllStops = false
    @State private var activeStopIndex = 0

    private let palette: [Color] = [.blue, .green, .orange, .purple, .pink, .cyan, .mint, .indigo]

    private var puzzle: Puzzle { storedPuzzle.puzzle }
    private var currentStored: StoredPuzzle? {
        puzzleStore.puzzles.first(where: { $0.id == storedPuzzle.id })
    }
    private var currentStopIndex: Int { currentStored?.currentStopIndex ?? 0 }
    private var currentStop: PuzzleStop {
        let idx = showAllStops ? activeStopIndex : currentStopIndex
        return puzzle.stops[min(idx, puzzle.stops.count - 1)]
    }
    private var targetCoord: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: currentStop.lat, longitude: currentStop.lon)
    }
    private var visibleGuesses: [CircleGuess] {
        (showAllStops ? allStopsGuesses : guesses).filter { !hiddenGuessIDs.contains($0.id) }
    }

    // All measurements across every stop, colored by stop index — used by the map in all-stops mode
    private var allStopsGuesses: [CircleGuess] {
        (currentStored ?? storedPuzzle).measurements.map { m in
            CircleGuess(
                center: CLLocationCoordinate2D(latitude: m.lat, longitude: m.lon),
                radius: m.radius,
                accuracy: m.accuracy,
                index: m.stopIndex,
                stopIndex: m.stopIndex
            )
        }
    }

    private var horizontalAccuracy: Double? {
        locationManager.location?.horizontalAccuracy
    }
    private var canMeasure: Bool {
        locationManager.location != nil
    }
    private var accuracyLabel: String {
        horizontalAccuracy.map { formatDistance($0) } ?? "—"
    }
    private var accuracyColor: Color {
        guard let acc = horizontalAccuracy else { return .secondary }
        if acc <= 10 { return .green }
        if acc <= 25 { return .yellow }
        return .red
    }
    private var gpsStatusMessage: String {
        "Waiting for GPS…"
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            GameMapView(
                guesses: visibleGuesses,
                estimatedTarget: (!showAllStops && currentStored?.solved == true) ? estimatedTarget : nil,
                debugTargets: nil,
                palette: palette
            )
            .ignoresSafeArea()

            if currentStored?.solved == true {
                solvedPanel
            } else {
                controlPanel
            }
        }
        .navigationTitle({
            if currentStored?.solved == true { return "Solved" }
            if showAllStops { return "All Stops" }
            if puzzle.stops.count > 1 { return "Stop \(currentStopIndex + 1) of \(puzzle.stops.count)" }
            return "Solve Puzzle"
        }())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                if puzzle.stops.count > 1 && currentStored?.solved != true {
                    Button {
                        showAllStops.toggle()
                        if showAllStops { activeStopIndex = currentStopIndex }
                        loadSavedMeasurements()
                    } label: {
                        Image(systemName: showAllStops ? "map.fill" : "map")
                    }
                }
            }
        }
        .onAppear { loadSavedMeasurements() }
        .onChange(of: activeStopIndex) { loadSavedMeasurements() }
        .sheet(isPresented: $unlocked, onDismiss: loadSavedMeasurements) {
            UnlockView(message: unlockedStopMessage, stopNumber: unlockedStopNumber, totalStops: puzzle.stops.count)
        }
    }

    // MARK: - Control Panel

    private var controlPanel: some View {
        VStack(spacing: 12) {
            if showAllStops {
                let solvedIndices = currentStored?.solvedStopIndices ?? []
                Picker("Stop", selection: $activeStopIndex) {
                    ForEach(puzzle.stops.indices, id: \.self) { i in
                        Text(solvedIndices.contains(i) ? "✓ \(i + 1)" : "Stop \(i + 1)").tag(i)
                    }
                }
                .pickerStyle(.segmented)
            } else if puzzle.stops.count > 1 {
                Text("Stop \(currentStopIndex + 1) of \(puzzle.stops.count)")
                    .font(.subheadline.bold())
                    .foregroundStyle(.blue)
            }

            HStack(spacing: 24) {
                Button {
                    guard !guesses.isEmpty else { return }
                    showGuessList.toggle()
                } label: {
                    VStack {
                        Text("\(guesses.count)")
                            .font(.title2.bold())
                        Text("Guess\(guesses.count == 1 ? "" : "es")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(showGuessList ? Color.accentColor : .primary)

                Divider().frame(height: 32)

                VStack {
                    Text(lastDistance.map { formatDistance($0) } ?? "—")
                        .font(.title2.bold())
                    Text("Last Distance")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Divider().frame(height: 32)

                VStack {
                    Text(accuracyLabel)
                        .font(.title2.bold())
                        .foregroundStyle(accuracyColor)
                    Text("GPS ±")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if showGuessList && !guesses.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(Array(guesses.enumerated()), id: \.element.id) { i, guess in
                            let hidden = hiddenGuessIDs.contains(guess.id)
                            Button {
                                if hidden { hiddenGuessIDs.remove(guess.id) }
                                else { hiddenGuessIDs.insert(guess.id) }
                            } label: {
                                Text("\(i + 1)")
                                    .font(.caption2.bold())
                                    .frame(width: 26, height: 26)
                                    .background(Circle().fill(
                                        palette[guess.index % palette.count].opacity(hidden ? 0.2 : 1.0)
                                    ))
                                    .foregroundStyle(hidden ? Color.secondary : .white)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 2)
                }
            }

            Button(action: takeMeasurement) {
                Label("Measure Distance", systemImage: "circle.dashed")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!canMeasure)

            if !canMeasure {
                Text(gpsStatusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .cornerRadius(20)
        .shadow(radius: 8)
        .padding()
    }

    // MARK: - Solved Panel

    private var solvedPanel: some View {
        VStack(spacing: 14) {
            Label("Puzzle Complete!", systemImage: "trophy.fill")
                .font(.title2.bold())
                .foregroundStyle(.yellow)

            Text(puzzle.stops.last?.message ?? "")
                .font(.body)
                .multilineTextAlignment(.center)
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color.secondary.opacity(0.12))
                .cornerRadius(12)

            HStack(spacing: 0) {
                if puzzle.stops.count > 1 {
                    statCell("\(puzzle.stops.count)", label: "Stops")
                    Divider().frame(height: 36)
                }
                let total = currentStored?.measurements.count ?? guesses.count
                statCell("\(total)", label: total == 1 ? "Measurement" : "Measurements")

                if let stored = currentStored, let solvedAt = stored.solvedAt {
                    Divider().frame(height: 36)
                    statCell(formatDuration(from: stored.createdAt, to: solvedAt), label: "Time to Solve")
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .cornerRadius(20)
        .shadow(radius: 8)
        .padding()
    }

    private func statCell(_ value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.title2.bold())
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Game Logic

    private func loadSavedMeasurements() {
        hiddenGuessIDs = []
        showGuessList = false
        let source = currentStored ?? storedPuzzle

        if showAllStops {
            // Auto-advance to next unsolved stop if the active one is already done
            let solved = source.solvedStopIndices
            if solved.contains(activeStopIndex),
               let next = puzzle.stops.indices.first(where: { !solved.contains($0) }) {
                activeStopIndex = next
            }
        }

        let stopIdx = showAllStops ? activeStopIndex : source.currentStopIndex
        guesses = source.measurements
            .filter { $0.stopIndex == stopIdx }
            .enumerated()
            .map { i, m in
                CircleGuess(
                    center: CLLocationCoordinate2D(latitude: m.lat, longitude: m.lon),
                    radius: m.radius,
                    accuracy: m.accuracy,
                    index: i,
                    stopIndex: m.stopIndex
                )
            }
        lastDistance = guesses.last?.radius
        estimatedTarget = guesses.count >= 2 ? triangulate(guesses) : nil
    }

    private func takeMeasurement() {
        guard let location = locationManager.location else { return }

        let targetLocation = CLLocation(latitude: targetCoord.latitude, longitude: targetCoord.longitude)
        let distance = location.distance(from: targetLocation)
        lastDistance = distance

        let stopIdx = showAllStops ? activeStopIndex : currentStopIndex
        let guess = CircleGuess(center: location.coordinate, radius: distance, accuracy: location.horizontalAccuracy, index: guesses.count, stopIndex: stopIdx)
        guesses.append(guess)

        if guesses.count >= 2 { estimatedTarget = triangulate(guesses) }

        persistMeasurement(location: location, distance: distance)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        if distance < currentStop.radius {
            let alreadySolved = currentStored?.solvedStopIndices.contains(activeStopIndex) ?? false
            if !showAllStops || !alreadySolved {
                unlockedStopMessage = currentStop.message
                unlockedStopNumber = showAllStops
                    ? (currentStored?.solvedStopIndices.count ?? 0) + 1
                    : currentStopIndex + 1
                markStopSolved()
                unlocked = true
            }
        }
    }

    private func persistMeasurement(location: CLLocation, distance: Double) {
        guard var current = puzzleStore.puzzles.first(where: { $0.id == storedPuzzle.id }) else { return }
        let stopIdx = showAllStops ? activeStopIndex : current.currentStopIndex
        current.measurements.append(SavedMeasurement(
            lat: location.coordinate.latitude,
            lon: location.coordinate.longitude,
            radius: distance,
            accuracy: location.horizontalAccuracy,
            stopIndex: stopIdx
        ))
        puzzleStore.update(current)
    }

    private func markStopSolved() {
        guard var current = puzzleStore.puzzles.first(where: { $0.id == storedPuzzle.id }) else { return }
        if showAllStops {
            if !current.solvedStopIndices.contains(activeStopIndex) {
                current.solvedStopIndices.append(activeStopIndex)
            }
            if current.solvedStopIndices.count >= puzzle.stops.count {
                current.solved = true
                current.solvedAt = Date()
            }
        } else {
            let nextIndex = current.currentStopIndex + 1
            if nextIndex >= puzzle.stops.count {
                current.solved = true
                current.solvedAt = Date()
            } else {
                current.currentStopIndex = nextIndex
            }
        }
        puzzleStore.update(current)
    }

    // MARK: - Triangulation

    private func triangulate(_ circles: [CircleGuess]) -> CLLocationCoordinate2D? {
        guard circles.count >= 2 else { return nil }

        let origin = circles[0].center
        let lat0 = origin.latitude * .pi / 180
        let mPerDegLat = 111_132.92 - 559.82 * cos(2 * lat0) + 1.175 * cos(4 * lat0)
        let mPerDegLon = 111_412.84 * cos(lat0) - 93.5 * cos(3 * lat0)
        let r0 = circles[0].radius

        var A: [[Double]] = []
        var b: [Double] = []

        for i in 1..<circles.count {
            let xi = (circles[i].center.longitude - origin.longitude) * mPerDegLon
            let yi = (circles[i].center.latitude - origin.latitude) * mPerDegLat
            let ri = circles[i].radius
            // Subtract circle-0 equation from circle-i: 2xi·x + 2yi·y = r0²−ri²+xi²+yi²
            A.append([2 * xi, 2 * yi])
            b.append(r0 * r0 - ri * ri + xi * xi + yi * yi)
        }

        let (dx, dy) = leastSquares(A: A, b: b)
        return CLLocationCoordinate2D(
            latitude: origin.latitude + dy / mPerDegLat,
            longitude: origin.longitude + dx / mPerDegLon
        )
    }

    private func leastSquares(A: [[Double]], b: [Double]) -> (Double, Double) {
        var ata00 = 0.0, ata01 = 0.0, ata11 = 0.0
        var atb0 = 0.0, atb1 = 0.0
        for i in 0..<A.count {
            ata00 += A[i][0] * A[i][0]
            ata01 += A[i][0] * A[i][1]
            ata11 += A[i][1] * A[i][1]
            atb0  += A[i][0] * b[i]
            atb1  += A[i][1] * b[i]
        }
        let det = ata00 * ata11 - ata01 * ata01
        guard abs(det) > 1e-6 else { return (0, 0) }
        return (
            (ata11 * atb0 - ata01 * atb1) / det,
            (ata00 * atb1 - ata01 * atb0) / det
        )
    }
}

// MARK: - MKMapView wrapper

struct GameMapView: UIViewRepresentable {
    let guesses: [CircleGuess]
    let estimatedTarget: CLLocationCoordinate2D?
    let debugTargets: [CLLocationCoordinate2D]?
    let palette: [Color]

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.showsUserLocation = true
        map.showsCompass = true
        map.showsScale = true
        map.isZoomEnabled = true
        map.isScrollEnabled = true
        map.setUserTrackingMode(.follow, animated: false)

        // User tracking button
        let trackingBtn = MKUserTrackingButton(mapView: map)
        trackingBtn.translatesAutoresizingMaskIntoConstraints = false
        map.addSubview(trackingBtn)
        NSLayoutConstraint.activate([
            trackingBtn.trailingAnchor.constraint(equalTo: map.safeAreaLayoutGuide.trailingAnchor, constant: -10),
            trackingBtn.topAnchor.constraint(equalTo: map.safeAreaLayoutGuide.topAnchor, constant: 10)
        ])

        context.coordinator.mapView = map
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        context.coordinator.palette = palette

        // Rebuild overlays only when the visible set changes (ID-based to avoid flicker)
        let newIDs = guesses.map(\.id)
        if context.coordinator.renderedGuessIDs != newIDs {
            let wasEmpty = context.coordinator.renderedGuessIDs.isEmpty
            context.coordinator.renderedGuessIDs = newIDs
            map.removeOverlays(map.overlays)
            for guess in guesses {
                var coords = geodesicCircleCoordinates(center: guess.center, radius: guess.radius)
                let polygon = IndexedPolygon(coordinates: &coords, count: coords.count)
                polygon.colorIndex = guess.index
                polygon.accuracy = guess.accuracy
                map.addOverlay(polygon, level: .aboveRoads)
            }
            if wasEmpty, let first = guesses.first {
                map.userTrackingMode = .none
                let region = MKCoordinateRegion(
                    center: first.center,
                    latitudinalMeters: first.radius * 2 * 1.5,
                    longitudinalMeters: first.radius * 2 * 1.5
                )
                map.setRegion(region, animated: true)
            }
        }

        // Estimated target annotation
        let estAnnotations = map.annotations.filter { $0 is MKPointAnnotation }
        if let est = estimatedTarget {
            if estAnnotations.isEmpty {
                let ann = MKPointAnnotation()
                ann.coordinate = est
                map.addAnnotation(ann)
            } else if let ann = estAnnotations.first as? MKPointAnnotation {
                ann.coordinate = est
            }
        } else {
            map.removeAnnotations(estAnnotations)
        }

    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    // MARK: Coordinator

    final class Coordinator: NSObject, MKMapViewDelegate {
        var palette: [Color] = []
        var renderedGuessIDs: [UUID] = []
        weak var mapView: MKMapView?


        func mapView(_ map: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let polygon = overlay as? IndexedPolygon else {
                return MKOverlayRenderer(overlay: overlay)
            }
            let renderer = MKPolygonRenderer(polygon: polygon)
            let uiColor = UIColor(palette[polygon.colorIndex % max(palette.count, 1)])
            let lineWidth = CGFloat(max(2.0, min(polygon.accuracy * 0.6, 20.0)))
            renderer.fillColor   = uiColor.withAlphaComponent(0.12)
            renderer.strokeColor = uiColor
            renderer.lineWidth   = lineWidth
            return renderer
        }

        func mapView(_ map: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard !(annotation is MKUserLocation) else { return nil }
            let view = MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: "est")
            view.glyphImage    = UIImage(systemName: "scope")
            view.markerTintColor = .systemRed
            view.titleVisibility = .hidden
            return view
        }
    }
}

// MARK: - Unlock Sheet

struct UnlockView: View {
    let message: String
    let stopNumber: Int
    let totalStops: Int
    @Environment(\.dismiss) private var dismiss

    private var isFinal: Bool { stopNumber == totalStops }

    var body: some View {
        ZStack {
            if isFinal {
                ConfettiView().ignoresSafeArea()
            }

            VStack(spacing: 28) {
                Image(systemName: isFinal ? "trophy.fill" : "mappin.circle.fill")
                    .font(.system(size: 80))
                    .foregroundStyle(isFinal ? .yellow : .green)

                VStack(spacing: 6) {
                    if totalStops > 1 {
                        Text("Stop \(stopNumber) of \(totalStops)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text(isFinal ? "Puzzle Complete!" : "Stop Found!")
                        .font(.largeTitle.bold())
                }

                Text(message)
                    .font(.title3)
                    .multilineTextAlignment(.center)
                    .padding()
                    .background(Color.secondary.opacity(0.12))
                    .cornerRadius(14)

                Button(isFinal ? "Done" : "Next Stop →") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            }
            .padding(32)
        }
        .onAppear {
            if isFinal {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            } else {
                UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
            }
        }
    }
}

// MARK: - Confetti

struct ConfettiView: View {
    struct Piece: Identifiable {
        let id = UUID()
        let x: CGFloat
        let color: Color
        let width: CGFloat
        let height: CGFloat
        let delay: Double
        let duration: Double
        let spin: Double
    }

    @State private var fallen = false

    private let pieces: [Piece] = {
        let colors: [Color] = [.red, .orange, .yellow, .green, .blue, .purple, .pink, .cyan, .mint]
        return (0..<90).map { _ in
            Piece(
                x: CGFloat.random(in: 0.02...0.98),
                color: colors.randomElement()!,
                width: CGFloat.random(in: 7...14),
                height: CGFloat.random(in: 5...10),
                delay: Double.random(in: 0...1.4),
                duration: Double.random(in: 1.8...3.2),
                spin: Double.random(in: 180...720)
            )
        }
    }()

    var body: some View {
        GeometryReader { geo in
            ForEach(pieces) { p in
                Rectangle()
                    .fill(p.color)
                    .frame(width: p.width, height: p.height)
                    .rotationEffect(.degrees(fallen ? p.spin : 0))
                    .position(x: p.x * geo.size.width,
                              y: fallen ? geo.size.height + 20 : -20)
                    .animation(.easeIn(duration: p.duration).delay(p.delay), value: fallen)
            }
        }
        .onAppear { fallen = true }
        .allowsHitTesting(false)
    }
}
