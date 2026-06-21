import SwiftUI
import AVFoundation
import UIKit

// MARK: - Flash Mode Enum
enum FlashMode {
    case off, on, auto

    var avFlashMode: AVCaptureDevice.FlashMode {
        switch self {
        case .off: return .off
        case .on: return .on
        case .auto: return .auto
        }
    }
}

// MARK: - Main Camera View
struct CameraView: View {
    @StateObject private var cameraService = CameraService()
    @Binding var isPresented: Bool
    var onImageCaptured: (UIImage) -> Void

    @State private var previewImage: UIImage?
    @State private var showZoomSlider = false

    var body: some View {
        ZStack {
            if let image = previewImage {
                VStack {
                    Spacer()
                    HStack {
                        Button("Retake") {
                            previewImage = nil
                            cameraService.clearPendingPhoto()
                            cameraService.restartSession()
                        }
                        .padding()
                        .foregroundColor(.white)
                        Spacer()
                        Button("Use Photo") {
                            cameraService.confirmCapturedPhoto()
                        }
                        .padding()
                        .foregroundColor(.white)
                    }
                    .background(Color.black.opacity(0.6))
                }
                .background(
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .ignoresSafeArea()
                )
            } else {
                CameraPreview(
                    session: cameraService.session,
                    cameraPosition: cameraService.currentCameraPosition,
                    cameraService: cameraService,
                    showZoomSlider: $showZoomSlider
                )
                .ignoresSafeArea()
                
                VStack {
                    // Top row with close button and camera controls
                    HStack {
                        // Close button on top left
                        Button(action: {
                            previewImage = nil
                            cameraService.clearPendingPhoto() // Clear pending photo when retaking
                            isPresented = false
                        }) {
                            Image(systemName: "xmark")
                                .font(.system(size: 24))
                                .foregroundColor(.white)
                                .padding()
                        }
                        
                        Spacer()
                        
                        // Camera switch button on top right
                        Button(action: {
                            cameraService.switchCamera()
                        }) {
                            Image(systemName: "arrow.triangle.2.circlepath.camera")
                                .font(.system(size: 24))
                                .foregroundColor(.white)
                                .padding()
                        }
                    }
                    
                    // Flash toggle button below camera switch
                    HStack {
                        Spacer()
                        Button(action: {
                            cameraService.toggleFlashMode()
                        }) {
                            Image(systemName: flashIcon(for: cameraService.flashMode))
                                .font(.system(size: 24))
                                .foregroundColor(.white)
                                .padding()
                        }
                    }
                    
                    Spacer()
                    
                    // Zoom slider (only visible during zoom and on back camera)
                    if showZoomSlider && cameraService.currentCameraPosition == .back {
                        HStack {
                            Text("1×")
                                .font(.caption)
                                .foregroundColor(.white)
                            
                            Slider(
                                value: $cameraService.zoomFactor,
                                in: 1.0...min(cameraService.maxZoomFactor, 5.0),
                                step: 0.1
                            )
                            .accentColor(.white)
                            
                            Text("\(String(format: "%.1f", min(cameraService.maxZoomFactor, 5.0)))×")
                                .font(.caption)
                                .foregroundColor(.white)
                        }
                        .padding(.horizontal, 40)
                        .padding(.vertical, 8)
                        .background(Color.black.opacity(0.6))
                        .cornerRadius(20)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                        .animation(.easeInOut(duration: 0.3), value: showZoomSlider)
                    }
                    
                    // Capture button at bottom
                    ZStack {
                        // Decorative border
                        Circle()
                            .stroke(Color.black, lineWidth: 6)
                            .frame(width: 70, height: 70)
                        Circle()
                            .stroke(Color.white, lineWidth: 4)
                            .frame(width: 70, height: 70)
                        // Tappable inner button
                        Button(action: {
                            cameraService.capturePhoto()
                        }) {
                            Circle()
                                .fill(Color.white)
                                .frame(width: 62, height: 62)
                        }
                    }
                    .shadow(radius: 5)
                    .padding(.bottom, 30)
                }
                .padding()
            }
        }
        .onAppear {
            cameraService.start()
            cameraService.onPhotoCapture = { image in
                onImageCaptured(image)
                isPresented = false
            }
            cameraService.onImageCapturedForPreview = { image in
                previewImage = image
            }
            // Set up callback to close camera when app is backgrounded
            cameraService.onAppBackgrounded = {
                isPresented = false
            }
        }
        .onDisappear {
            cameraService.stop()
        }
        .alert("Camera Error", isPresented: Binding(get: { cameraService.captureError != nil }, set: { if !$0 { cameraService.captureError = nil }})) {
            Button("OK", role: .cancel) {
                cameraService.captureError = nil
            }
        } message: {
            Text(cameraService.captureError ?? "An unknown camera error occurred.")
        }
    }

    // Helper for flash icon
    func flashIcon(for mode: FlashMode) -> String {
        switch mode {
        case .off: return "bolt.slash.fill"
        case .on: return "bolt.fill"
        case .auto: return "bolt.badge.a.fill"
        }
    }
}

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    let cameraPosition: AVCaptureDevice.Position

    @ObservedObject var cameraService: CameraService
    @Binding var showZoomSlider: Bool

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .black

        // Setup preview layer
        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = .resizeAspectFill

        // Set initial frame
        previewLayer.frame = view.bounds
        view.layer.addSublayer(previewLayer)
        context.coordinator.previewLayer = previewLayer

        // Configure mirroring
        configureMirroring(for: previewLayer, position: cameraPosition)

        // Add pinch gesture recognizer
        let pinchGesture = UIPinchGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePinch(_:)))
        view.addGestureRecognizer(pinchGesture)
        
        // Store reference to the binding in coordinator
        context.coordinator.showZoomSlider = $showZoomSlider

        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        guard let previewLayer = context.coordinator.previewLayer else { return }
        
        // Update frame
        previewLayer.frame = uiView.bounds
        
        // Update mirroring when camera position changes
        configureMirroring(for: previewLayer, position: cameraPosition)
    }
    
    private func configureMirroring(for previewLayer: AVCaptureVideoPreviewLayer, position: AVCaptureDevice.Position) {
        // Small delay to ensure connection is established
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            guard let connection = previewLayer.connection else { return }
            
            if position == .front {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = true
            } else {
                connection.automaticallyAdjustsVideoMirroring = true
                // Don't set isVideoMirrored when automatic mirroring is enabled
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(cameraService: cameraService, showZoomSlider: $showZoomSlider)
    }

    class Coordinator: NSObject {
        var previewLayer: AVCaptureVideoPreviewLayer?
        private var cameraService: CameraService
        var showZoomSlider: Binding<Bool>!

        init(cameraService: CameraService, showZoomSlider: Binding<Bool>) {
            self.cameraService = cameraService
            self.showZoomSlider = showZoomSlider
        }

        private var lastZoom: CGFloat = 1.0
        private var hideSliderTimer: Timer?

        @objc func handlePinch(_ pinch: UIPinchGestureRecognizer) {
            // Only allow zoom on back camera
            guard cameraService.currentCameraPosition == .back else { return }
            guard let device = cameraService.currentDevice else { return }

            if pinch.state == .began {
                lastZoom = cameraService.zoomFactor
                
                // Show zoom slider
                DispatchQueue.main.async {
                    self.showZoomSlider.wrappedValue = true
                }
                
                // Cancel any existing timer
                hideSliderTimer?.invalidate()
            }

            let newZoom = lastZoom * pinch.scale
            let clampedZoom = max(1.0, min(newZoom, min(device.activeFormat.videoMaxZoomFactor, 5.0)))

            cameraService.zoomFactor = clampedZoom
            
            if pinch.state == .ended || pinch.state == .cancelled {
                // Start timer to hide slider after 2 seconds of inactivity
                hideSliderTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { _ in
                    DispatchQueue.main.async {
                        self.showZoomSlider.wrappedValue = false
                    }
                }
            }
        }
    }
}

// MARK: - Camera Service (AVCaptureSession) - UPDATED
class CameraService: NSObject, ObservableObject {
    let session = AVCaptureSession()
    private let output = AVCapturePhotoOutput()
    private var capturedImagePendingConfirmation: UIImage?

    @Published var currentCameraPosition: AVCaptureDevice.Position = .back
    @Published var flashMode: FlashMode = .auto
    @Published var isSessionConfigured = false
    @Published var captureError: String? = nil

    @Published var zoomFactor: CGFloat = 1.0 {
        didSet {
            setZoom(factor: zoomFactor)
        }
    }
    
    @Published var maxZoomFactor: CGFloat = 10.0

    var onPhotoCapture: ((UIImage) -> Void)?
    var onImageCapturedForPreview: ((UIImage) -> Void)?
    var onAppBackgrounded: (() -> Void)? // New callback for when app is backgrounded

    private var isConfigured = false

    var currentDevice: AVCaptureDevice? {
        session.inputs.compactMap { ($0 as? AVCaptureDeviceInput)?.device }.first
    }

    override init() {
        super.init()
        // Don't configure here - wait for start() to be called
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private func configureSession(position: AVCaptureDevice.Position) {
        // Ensure we're on a background queue for session configuration
        DispatchQueue.global(qos: .userInitiated).async {
            self.session.beginConfiguration()
            self.session.sessionPreset = .photo

            // Remove all inputs
            for input in self.session.inputs {
                self.session.removeInput(input)
            }

            // Remove all outputs
            for output in self.session.outputs {
                self.session.removeOutput(output)
            }

            // Discover all camera device types for this position
            let discoverySession = AVCaptureDevice.DiscoverySession(
                deviceTypes: [
                    .builtInWideAngleCamera,
                    .builtInTelephotoCamera,
                    .builtInUltraWideCamera
                ],
                mediaType: .video,
                position: position
            )

            guard let device = discoverySession.devices.first else {
                print("[CameraService] No camera found for position \(position).")
                self.session.commitConfiguration()
                return
            }

            do {
                let input = try AVCaptureDeviceInput(device: device)
                if self.session.canAddInput(input) && self.session.canAddOutput(self.output) {
                    self.session.addInput(input)
                    self.session.addOutput(self.output)
                } else {
                    print("[CameraService] Cannot add input or output")
                    self.session.commitConfiguration()
                    return
                }
            } catch {
                print("[CameraService] Error creating AVCaptureDeviceInput: \(error)")
                self.session.commitConfiguration()
                return
            }

            self.session.commitConfiguration()
            
            // Update on main thread
            DispatchQueue.main.async {
                self.isConfigured = true
                self.isSessionConfigured = true
                // Update max zoom factor based on current device
                if let device = self.currentDevice {
                    self.maxZoomFactor = device.activeFormat.videoMaxZoomFactor
                }
            }
            
            // Start the session immediately after configuration
            if !self.session.isRunning {
                self.session.startRunning()
            }
        }
    }

    func start() {
        // Configure session if not already configured
        if !isConfigured {
            configureSession(position: currentCameraPosition)
        } else if !session.isRunning {
            DispatchQueue.global(qos: .userInitiated).async {
                self.session.startRunning()
            }
        }
    }

    func stop() {
        if session.isRunning {
            DispatchQueue.global(qos: .userInitiated).async {
                self.session.stopRunning()
            }
        }
    }

    func switchCamera() {
        currentCameraPosition = (currentCameraPosition == .back) ? .front : .back
        isConfigured = false // Reset configuration flag
        configureSession(position: currentCameraPosition)
        zoomFactor = 1.0  // Reset zoom when switching cameras
    }

    func toggleFlashMode() {
        switch flashMode {
        case .off: flashMode = .on
        case .on: flashMode = .auto
        case .auto: flashMode = .off
        }
    }

    func capturePhoto() {
        let settings = AVCapturePhotoSettings()
        if output.supportedFlashModes.contains(flashMode.avFlashMode) {
            settings.flashMode = flashMode.avFlashMode
        }
        
        guard let connection = output.connection(with: .video), connection.isActive, connection.isEnabled else {
            print("[CameraService] Cannot capture photo: no active video connection.")
            DispatchQueue.main.async {
                self.captureError = "Camera is unavailable. Please try again when the camera is ready."
            }
            return
        }

        connection.videoOrientation = currentVideoOrientation()
        output.capturePhoto(with: settings, delegate: self)
    }
    
    private func currentVideoOrientation() -> AVCaptureVideoOrientation {
        let deviceOrientation = UIDevice.current.orientation
        
        switch deviceOrientation {
        case .portrait:
            return .portrait
        case .portraitUpsideDown:
            return .portraitUpsideDown
        case .landscapeLeft:
            return .landscapeRight
        case .landscapeRight:
            return .landscapeLeft
        default:
            return .portrait
        }
    }

    func confirmCapturedPhoto() {
        guard let image = capturedImagePendingConfirmation else { return }
        print("[CameraService] User confirmed photo")
        onPhotoCapture?(image)
        capturedImagePendingConfirmation = nil
    }
    
    // New function to clear pending photo when retaking
    func clearPendingPhoto() {
        print("[CameraService] Clearing pending photo")
        capturedImagePendingConfirmation = nil
    }
    
    // New function to properly restart the session for retake
    func restartSession() {
        print("[CameraService] Restarting session for retake")
        DispatchQueue.global(qos: .userInitiated).async {
            if self.session.isRunning {
                self.session.stopRunning()
            }
            
            // Small delay to ensure session is fully stopped
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.isConfigured = false
                self.isSessionConfigured = false
                self.start()
            }
        }
    }

    private func setZoom(factor: CGFloat) {
        guard let device = currentDevice else { return }
        do {
            try device.lockForConfiguration()
            let zoom = max(1.0, min(factor, device.activeFormat.videoMaxZoomFactor))
            device.videoZoomFactor = zoom
            device.unlockForConfiguration()
        } catch {
            print("[CameraService] Failed to set zoom: \(error)")
        }
    }

    @objc func handleAppDidEnterBackground() {
        print("[CameraService] App entered background")
        
        // First, trigger camera close callback
        DispatchQueue.main.async {
            self.onAppBackgrounded?()
        }
        
        // Only save photo if there's a pending image (user is in preview mode)
        if let image = capturedImagePendingConfirmation {
            print("[CameraService] Auto-saving photo due to background")
            UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
            onPhotoCapture?(image)
            capturedImagePendingConfirmation = nil
        } else {
            print("[CameraService] No pending photo to save - user was in live camera view")
        }
    }
}

// MARK: - AVCapturePhotoCaptureDelegate
extension CameraService: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishProcessingPhoto photo: AVCapturePhoto,
                     error: Error?) {
        guard let data = photo.fileDataRepresentation(),
              var image = UIImage(data: data) else {
            print("[CameraService] Failed to process photo")
            return
        }

        // Fix orientation if needed
        image = fixImageOrientation(image)

        print("[CameraService] Photo captured, awaiting confirmation")
        capturedImagePendingConfirmation = image

        DispatchQueue.main.async {
            self.onImageCapturedForPreview?(image)
        }
    }
    
    private func fixImageOrientation(_ image: UIImage) -> UIImage {
        // If the image is already in the correct orientation, return it as-is
        if image.imageOrientation == .up {
            return image
        }
        
        // Create a graphics context and draw the image in the correct orientation
        UIGraphicsBeginImageContextWithOptions(image.size, false, image.scale)
        image.draw(in: CGRect(origin: .zero, size: image.size))
        let normalizedImage = UIGraphicsGetImageFromCurrentImageContext() ?? image
        UIGraphicsEndImageContext()
        
        return normalizedImage
    }
}