import SwiftUI
import AVFoundation

struct ScannerView: View {
    @Environment(PuzzleStore.self) var puzzleStore
    @State private var scannedCode: String?
    @State private var errorMessage: String?
    @State private var navigateToGame = false
    @State private var scannedPuzzle: StoredPuzzle?
    @State private var cameraAccessDenied = false

    var body: some View {
        ZStack {
            if cameraAccessDenied {
                ContentUnavailableView(
                    "Camera Access Required",
                    systemImage: "camera.slash",
                    description: Text("Enable camera access in Settings to scan puzzle QR codes.")
                )
            } else {
                CameraPreview(scannedCode: $scannedCode)
                    .ignoresSafeArea()

                VStack {
                    Spacer()

                    if let error = errorMessage {
                        Text(error)
                            .foregroundStyle(.white)
                            .padding()
                            .background(Color.red.opacity(0.85))
                            .cornerRadius(10)
                            .padding()
                    }

                    Text("Point camera at a puzzle QR code")
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color.black.opacity(0.6))
                        .cornerRadius(10)
                        .padding(.bottom, 32)
                }
            }
        }
        .navigationTitle("Scan Puzzle")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $navigateToGame) {
            if let puzzle = scannedPuzzle {
                GameView(storedPuzzle: puzzle)
            }
        }
        .onAppear {
            checkCameraAccess()
            scannedCode = nil
            errorMessage = nil
        }
        .onChange(of: scannedCode) { _, code in
            guard let code else { return }
            processCode(code)
        }
    }

    private func checkCameraAccess() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .denied, .restricted:
            cameraAccessDenied = true
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                Task { @MainActor in
                    cameraAccessDenied = !granted
                }
            }
        default:
            break
        }
    }

    private func processCode(_ code: String) {
        guard
            let data = code.data(using: .utf8),
            let puzzle = try? JSONDecoder().decode(Puzzle.self, from: data)
        else {
            errorMessage = "Invalid QR code — make sure it's a Getting Warmer puzzle."
            scannedCode = nil
            return
        }
        let stored = StoredPuzzle(id: UUID(), puzzle: puzzle, createdAt: Date(), solved: false)
        puzzleStore.save(stored)
        scannedPuzzle = stored
        navigateToGame = true
    }
}

// MARK: - Camera Preview

struct CameraPreview: UIViewControllerRepresentable {
    @Binding var scannedCode: String?

    func makeUIViewController(context: Context) -> CameraViewController {
        let vc = CameraViewController()
        vc.onScan = { code in
            scannedCode = code
        }
        return vc
    }

    func updateUIViewController(_ uiViewController: CameraViewController, context: Context) {}
}

// MARK: - Camera View Controller

class CameraViewController: UIViewController {
    var onScan: ((String) -> Void)?

    private var captureSession: AVCaptureSession?
    private var previewLayer: AVCaptureVideoPreviewLayer?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        setupSession()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        guard let session = captureSession, !session.isRunning else { return }
        DispatchQueue.global(qos: .userInitiated).async { session.startRunning() }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        captureSession?.stopRunning()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    private func setupSession() {
        let session = AVCaptureSession()
        guard
            let device = AVCaptureDevice.default(for: .video),
            let input = try? AVCaptureDeviceInput(device: device),
            session.canAddInput(input)
        else { return }

        session.addInput(input)

        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else { return }
        session.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: .main)
        output.metadataObjectTypes = [.qr]

        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.frame = view.bounds
        preview.videoGravity = .resizeAspectFill
        view.layer.addSublayer(preview)
        previewLayer = preview

        captureSession = session
        DispatchQueue.global(qos: .userInitiated).async { session.startRunning() }
    }
}

extension CameraViewController: AVCaptureMetadataOutputObjectsDelegate {
    nonisolated func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        guard
            let object = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
            let code = object.stringValue
        else { return }
        Task { @MainActor [weak self] in
            self?.onScan?(code)
        }
    }
}
