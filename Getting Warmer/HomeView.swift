import SwiftUI

struct HomeView: View {
    @Environment(LocationManager.self) var locationManager

    var body: some View {
        NavigationStack {
            VStack(spacing: 32) {
                VStack(spacing: 8) {
                    Image(systemName: "mappin.and.ellipse")
                        .font(.system(size: 64))
                        .foregroundStyle(.tint)
                    Text("Warmer Circles")
                        .font(.largeTitle.bold())
                    Text("Hide it. Find it.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                VStack(spacing: 16) {
                    NavigationLink {
                        ProducerView()
                    } label: {
                        Label("Create Puzzle", systemImage: "plus.circle.fill")
                            .frame(maxWidth: .infinity)
                            .padding()
                    }
                    .buttonStyle(.borderedProminent)

                    NavigationLink {
                        ScannerView()
                    } label: {
                        Label("Scan Puzzle", systemImage: "qrcode.viewfinder")
                            .frame(maxWidth: .infinity)
                            .padding()
                    }
                    .buttonStyle(.bordered)

                    NavigationLink {
                        PuzzleListView()
                    } label: {
                        Label("My Puzzles", systemImage: "list.bullet")
                            .frame(maxWidth: .infinity)
                            .padding()
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(32)
            .onAppear {
                locationManager.requestPermission()
            }
        }
    }
}
