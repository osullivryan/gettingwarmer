import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins

func makeQRImage(from string: String) -> UIImage? {
    let context = CIContext()
    let filter = CIFilter.qrCodeGenerator()
    filter.message = Data(string.utf8)
    filter.correctionLevel = "M"
    guard let output = filter.outputImage else { return nil }
    let scaled = output.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
    guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }
    return UIImage(cgImage: cgImage)
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

struct QRCodeView: View {
    let image: UIImage
    let puzzleName: String
    @Environment(\.dismiss) private var dismiss
    @State private var showingShareSheet = false

    var body: some View {
        VStack(spacing: 24) {
            Text("Puzzle QR Code")
                .font(.title2.bold())

            if !puzzleName.isEmpty {
                Text(puzzleName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Image(uiImage: image)
                .interpolation(.none)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 300, maxHeight: 300)
                .padding(16)
                .background(Color.white)
                .cornerRadius(12)
                .shadow(radius: 4)

            Text("Share this with someone to let them solve your puzzle.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Button {
                showingShareSheet = true
            } label: {
                Label("Share QR Code", systemImage: "square.and.arrow.up")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)

            Button("Done") { dismiss() }
                .buttonStyle(.bordered)
        }
        .padding()
        .presentationDetents([.large])
        .sheet(isPresented: $showingShareSheet) {
            ShareSheet(items: [image])
        }
    }
}
