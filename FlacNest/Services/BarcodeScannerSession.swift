import AppKit
import AVFoundation
import Combine
import SwiftUI
import Vision

struct CameraDevice: Identifiable, Equatable {
    let id: String
    let name: String
}

@MainActor
final class BarcodeScannerSession: NSObject, ObservableObject {
    /// Normalized scan window in preview coordinates (origin top-left).
    static let scanGuideRegion = CGRect(x: 0.07, y: 0.40, width: 0.86, height: 0.18)

    @Published private(set) var authorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
    @Published private(set) var isRunning = false
    @Published private(set) var isAnalyzingFrames = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var availableCameras: [CameraDevice] = []
    @Published private(set) var selectedCameraID = ""

    let captureSession = AVCaptureSession()

    private var videoInput: AVCaptureDeviceInput?
    private var videoDataOutput: AVCaptureVideoDataOutput?
    private var didDetectCode = false
    private var lastFrameProcessedAt = Date.distantPast

    private let scanQueue = DispatchQueue(label: "com.flacnest.barcode.scan", qos: .userInitiated)

    var onBarcodeDetected: ((String) -> Void)?

    func prepare() {
        didDetectCode = false
        errorMessage = nil
        isAnalyzingFrames = false
        authorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
        refreshAvailableCameras()

        guard !availableCameras.isEmpty else {
            errorMessage = "No camera was found on this Mac."
            return
        }

        switch authorizationStatus {
        case .authorized:
            configureSessionIfNeeded()
            startRunning()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                Task { @MainActor in
                    guard let self else { return }
                    self.authorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
                    if granted {
                        self.configureSessionIfNeeded()
                        self.startRunning()
                    } else {
                        self.errorMessage = "Camera access is required to scan CD barcodes."
                    }
                }
            }
        case .denied, .restricted:
            errorMessage = "Camera access is required to scan CD barcodes. Enable it in System Settings → Privacy & Security → Camera."
        @unknown default:
            errorMessage = "Camera access is unavailable."
        }
    }

    func stop() {
        isAnalyzingFrames = false
        guard captureSession.isRunning else {
            isRunning = false
            return
        }
        captureSession.stopRunning()
        isRunning = false
    }

    func selectCamera(id: String) {
        guard id != selectedCameraID, availableCameras.contains(where: { $0.id == id }) else { return }

        selectedCameraID = id
        AppSettings.barcodeScannerCameraID = id
        errorMessage = nil

        guard authorizationStatus == .authorized else { return }

        let wasRunning = captureSession.isRunning
        if wasRunning {
            stop()
        }
        configureSessionIfNeeded()
        if wasRunning || !didDetectCode {
            startRunning()
        }
    }

    func refreshAvailableCameras() {
        availableCameras = Self.discoverCameras()

        if let savedID = AppSettings.barcodeScannerCameraID,
           availableCameras.contains(where: { $0.id == savedID }) {
            selectedCameraID = savedID
        } else if let currentDeviceID = videoInput?.device.uniqueID,
                  availableCameras.contains(where: { $0.id == currentDeviceID }) {
            selectedCameraID = currentDeviceID
        } else if let first = availableCameras.first {
            selectedCameraID = first.id
            AppSettings.barcodeScannerCameraID = first.id
        } else {
            selectedCameraID = ""
        }
    }

    static func visionRegionOfInterest(fromTopLeftNormalized rect: CGRect) -> CGRect {
        CGRect(
            x: rect.origin.x,
            y: 1.0 - rect.origin.y - rect.height,
            width: rect.width,
            height: rect.height
        )
    }

    private static func discoverCameras() -> [CameraDevice] {
        let deviceTypes: [AVCaptureDevice.DeviceType] = [
            .builtInWideAngleCamera,
            .external,
            .continuityCamera,
            .externalUnknown,
        ]
        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: deviceTypes,
            mediaType: .video,
            position: .unspecified
        )

        return discoverySession.devices
            .sorted {
                $0.localizedName.localizedCaseInsensitiveCompare($1.localizedName) == .orderedAscending
            }
            .map { device in
                CameraDevice(id: device.uniqueID, name: device.localizedName)
            }
    }

    private func configureSessionIfNeeded() {
        captureSession.beginConfiguration()
        defer { captureSession.commitConfiguration() }

        captureSession.sessionPreset = .high

        if videoDataOutput == nil {
            let output = AVCaptureVideoDataOutput()
            output.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            ]
            output.alwaysDiscardsLateVideoFrames = true
            output.setSampleBufferDelegate(self, queue: scanQueue)

            if captureSession.canAddOutput(output) {
                captureSession.addOutput(output)
                videoDataOutput = output
            } else {
                errorMessage = "Could not configure barcode scanning."
                return
            }
        }

        guard let device = captureDevice(for: selectedCameraID) else {
            errorMessage = "Selected camera is unavailable."
            return
        }

        configureDevice(device)

        if let videoInput, videoInput.device.uniqueID == device.uniqueID {
            return
        }

        if let videoInput {
            captureSession.removeInput(videoInput)
            self.videoInput = nil
        }

        do {
            let input = try AVCaptureDeviceInput(device: device)
            if captureSession.canAddInput(input) {
                captureSession.addInput(input)
                videoInput = input
            } else {
                errorMessage = "Could not open the camera."
            }
        } catch {
            errorMessage = "Could not open the camera: \(error.localizedDescription)"
        }
    }

    private func configureDevice(_ device: AVCaptureDevice) {
        do {
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }

            if device.isFocusModeSupported(.continuousAutoFocus) {
                device.focusMode = .continuousAutoFocus
            }
            if device.isExposureModeSupported(.continuousAutoExposure) {
                device.exposureMode = .continuousAutoExposure
            }
        } catch {
            // Non-fatal; scanning can still work with default camera settings.
        }
    }

    private func captureDevice(for id: String) -> AVCaptureDevice? {
        if let device = AVCaptureDevice(uniqueID: id), device.hasMediaType(.video) {
            return device
        }
        return availableCameras
            .compactMap { AVCaptureDevice(uniqueID: $0.id) }
            .first { $0.hasMediaType(.video) }
    }

    private func startRunning() {
        guard videoInput != nil, videoDataOutput != nil, !captureSession.isRunning else { return }
        captureSession.startRunning()
        isRunning = captureSession.isRunning
        if !isRunning {
            errorMessage = "Could not start the camera."
        }
    }

    private func processFrame(_ sampleBuffer: CMSampleBuffer) {
        guard !didDetectCode else { return }

        let now = Date()
        guard now.timeIntervalSince(lastFrameProcessedAt) >= 0.15 else { return }
        lastFrameProcessedAt = now
        isAnalyzingFrames = true

        let request = VNDetectBarcodesRequest()
        request.symbologies = [.ean13, .ean8, .upce, .code128, .code39, .itf14]
        request.regionOfInterest = Self.visionRegionOfInterest(fromTopLeftNormalized: Self.scanGuideRegion)

        let handler = VNImageRequestHandler(
            cmSampleBuffer: sampleBuffer,
            orientation: .up,
            options: [:]
        )

        do {
            try handler.perform([request])
            guard
                let observation = request.results?.first,
                let payload = observation.payloadStringValue
            else {
                return
            }
            handleDetectedBarcode(payload)
        } catch {
            return
        }
    }

    private func handleDetectedBarcode(_ value: String) {
        guard !didDetectCode else { return }
        let normalized = LibraryViewModel.normalizeBarcode(value)
        guard !normalized.isEmpty else { return }

        didDetectCode = true
        isAnalyzingFrames = false
        stop()
        onBarcodeDetected?(normalized)
    }
}

extension BarcodeScannerSession: AVCaptureVideoDataOutputSampleBufferDelegate {
    nonisolated func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        Task { @MainActor in
            self.processFrame(sampleBuffer)
        }
    }
}

struct ScanRegionGuide: View {
    let normalizedRegion: CGRect
    var isActive: Bool = true

    var body: some View {
        GeometryReader { geometry in
            let scanFrame = CGRect(
                x: normalizedRegion.origin.x * geometry.size.width,
                y: normalizedRegion.origin.y * geometry.size.height,
                width: normalizedRegion.width * geometry.size.width,
                height: normalizedRegion.height * geometry.size.height
            )

            ZStack {
                Path { path in
                    path.addRect(CGRect(origin: .zero, size: geometry.size))
                    path.addRoundedRect(in: scanFrame, cornerSize: CGSize(width: 10, height: 10))
                }
                .fill(.black.opacity(0.52), style: FillStyle(eoFill: true))

                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(.white.opacity(0.95), lineWidth: 2)
                    .frame(width: scanFrame.width, height: scanFrame.height)
                    .position(x: scanFrame.midX, y: scanFrame.midY)

                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(isActive ? Color.accentColor : Color.white.opacity(0.35), lineWidth: 1.5)
                    .frame(width: scanFrame.width, height: scanFrame.height)
                    .position(x: scanFrame.midX, y: scanFrame.midY)

                Text("Align barcode here")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(.black.opacity(0.45), in: Capsule())
                    .position(x: scanFrame.midX, y: scanFrame.maxY + 18)
            }
        }
        .allowsHitTesting(false)
    }
}

final class CameraPreviewView: NSView {
    private let previewLayer: AVCaptureVideoPreviewLayer

    init(session: AVCaptureSession) {
        previewLayer = AVCaptureVideoPreviewLayer(session: session)
        super.init(frame: .zero)
        wantsLayer = true
        layer = previewLayer
        previewLayer.videoGravity = .resizeAspectFill
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func layout() {
        super.layout()
        previewLayer.frame = bounds
    }
}

struct CameraPreview: NSViewRepresentable {
    let session: AVCaptureSession

    func makeNSView(context: Context) -> CameraPreviewView {
        CameraPreviewView(session: session)
    }

    func updateNSView(_ nsView: CameraPreviewView, context: Context) {}
}
