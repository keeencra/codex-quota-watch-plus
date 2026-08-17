import AVFoundation
import SwiftUI
import UIKit

struct PairingScannerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var authorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)

    let onPairing: (PairingPayload) -> Void
    let onError: (String) -> Void

    var body: some View {
        NavigationStack {
            Group {
                switch authorizationStatus {
                case .authorized:
                    PairingScannerView(
                        onCode: handle(code:),
                        onFailure: { message in
                            onError(message)
                            dismiss()
                        }
                    )
                    .ignoresSafeArea(edges: .bottom)
                case .notDetermined:
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("Camera access is needed for QR pairing.")
                            .foregroundStyle(.secondary)
                    }
                    .task {
                        let granted = await AVCaptureDevice.requestAccess(for: .video)
                        authorizationStatus = granted ? .authorized : .denied
                    }
                default:
                    ContentUnavailableView(
                        "Camera Access Needed",
                        systemImage: "camera.viewfinder",
                        description: Text("Enable camera access in Settings, or paste WATCH_TOKEN manually.")
                    )
                }
            }
            .navigationTitle("Scan Pairing QR")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                Button("Cancel") { dismiss() }
            }
        }
    }

    private func handle(code: String) {
        do {
            let payload = try PairingPayload.parse(code)
            onPairing(payload)
            dismiss()
        } catch {
            onError("Invalid pairing QR")
            dismiss()
        }
    }
}

private struct PairingScannerView: UIViewRepresentable {
    let onCode: (String) -> Void
    let onFailure: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onCode: onCode, onFailure: onFailure)
    }

    func makeUIView(context: Context) -> ScannerPreviewView {
        let view = ScannerPreviewView()
        context.coordinator.configure(previewView: view)
        return view
    }

    func updateUIView(_ uiView: ScannerPreviewView, context: Context) {}

    static func dismantleUIView(_ uiView: ScannerPreviewView, coordinator: Coordinator) {
        coordinator.stop()
    }

    final class Coordinator: NSObject, AVCaptureMetadataOutputObjectsDelegate {
        private let session = AVCaptureSession()
        private let onCode: (String) -> Void
        private let onFailure: (String) -> Void
        private var didEmitCode = false
        private var isConfigured = false

        init(onCode: @escaping (String) -> Void, onFailure: @escaping (String) -> Void) {
            self.onCode = onCode
            self.onFailure = onFailure
        }

        func configure(previewView: ScannerPreviewView) {
            guard !isConfigured else { return }
            isConfigured = true

            guard let device = AVCaptureDevice.default(for: .video) else {
                onFailure("Camera is not available.")
                return
            }

            do {
                let input = try AVCaptureDeviceInput(device: device)
                guard session.canAddInput(input) else {
                    onFailure("Camera input is not available.")
                    return
                }
                session.addInput(input)
            } catch {
                onFailure(error.localizedDescription)
                return
            }

            let output = AVCaptureMetadataOutput()
            guard session.canAddOutput(output) else {
                onFailure("QR scanner output is not available.")
                return
            }
            session.addOutput(output)
            output.setMetadataObjectsDelegate(self, queue: .main)
            output.metadataObjectTypes = [.qr]

            previewView.previewLayer.session = session
            previewView.previewLayer.videoGravity = .resizeAspectFill

            DispatchQueue.global(qos: .userInitiated).async {
                self.session.startRunning()
            }
        }

        func stop() {
            guard session.isRunning else { return }
            DispatchQueue.global(qos: .userInitiated).async {
                self.session.stopRunning()
            }
        }

        func metadataOutput(
            _ output: AVCaptureMetadataOutput,
            didOutput metadataObjects: [AVMetadataObject],
            from connection: AVCaptureConnection
        ) {
            guard !didEmitCode,
                  let object = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
                  object.type == .qr,
                  let code = object.stringValue else { return }
            didEmitCode = true
            stop()
            onCode(code)
        }
    }
}

private final class ScannerPreviewView: UIView {
    override class var layerClass: AnyClass {
        AVCaptureVideoPreviewLayer.self
    }

    var previewLayer: AVCaptureVideoPreviewLayer {
        layer as! AVCaptureVideoPreviewLayer
    }
}
