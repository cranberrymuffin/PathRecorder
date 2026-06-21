import SwiftUI
import MapKit
import Foundation
import AVFoundation

struct LivePathMapView: View {
    @ObservedObject var locationManager: LocationManager
    @ObservedObject var pathStorage: PathStorage
    @State private var region: MKCoordinateRegion?
    @State private var isAutoCentering: Bool = true
    @State private var showCamera = false
    @State private var capturedImage: UIImage?
    @State private var hasCurrentGPS: Bool = false // Track if we have current GPS
    @State private var showCameraPermissionAlert = false

    init(locationManager: LocationManager, pathStorage: PathStorage) {
        self.locationManager = locationManager
        self.pathStorage = pathStorage
        updateRegion()
    }
    
    private func updateRegion() {
        // Only update region if a valid location is available
        if let currentLocation = locationManager.currentLocation, !locationManager.isPaused {
            region = MKCoordinateRegion(
                center: currentLocation.coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.002, longitudeDelta: 0.002)
            )
            hasCurrentGPS = true
        } else if let lastLocation = locationManager.lastRecordedLocation {
            region = MKCoordinateRegion(
                center: lastLocation.coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.002, longitudeDelta: 0.002)
            )
            hasCurrentGPS = true // This is old data, not current GPS
        }
    }
    
    var body: some View {
        ZStack {
            LiveMapViewControllerRepresentable(
                region: $region,
                locations: locationManager.locations,
                isAutoCentering: isAutoCentering,
                isPaused: locationManager.isPaused,
                onMapTouched: {
                    isAutoCentering = false
                }
            )
            .onChange(of: locationManager.locations.count) { _, _ in
                if isAutoCentering {
                    updateRegion()
                }
            }
            .onChange(of: locationManager.currentLocation) { _, _ in
                // Update when current location changes
                if isAutoCentering {
                    updateRegion()
                }
            }
            .onChange(of: locationManager.isPaused) { _, newValue in
                isAutoCentering = true
                updateRegion()
            }
            .onAppear {
                isAutoCentering = true
                updateRegion()
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                isAutoCentering = true
                updateRegion()
            }

            // Show GPS loading overlay if we don't have current GPS data
            if !hasCurrentGPS {
                VStack {
                    Spacer()
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle())
                        .scaleEffect(1.6)
                    Text("Waiting for GPS...")
                        .font(.headline)
                        .padding(.top, 8)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black.opacity(1))
                .zIndex(10) // Ensure overlay appears on top
            }

            // Camera and centering buttons side by side (top right)
            VStack {
                HStack {
                    Spacer()
    // Centering button (only when auto-centering is disabled)
                    if !isAutoCentering {
                        Button(action: {
                            isAutoCentering = true
                            updateRegion()
                        }) {
                            Image(systemName: "location.fill")
                                .padding()
                                .background(Color.white.opacity(0.8))
                                .clipShape(Circle())
                                .shadow(radius: 2)
                        }
                        .padding(.trailing, 8)
                    }
    // Camera button (only when not paused)
                    if !locationManager.isPaused {
                        Button(action: {
                            // Check camera authorization before showing camera
                            switch AVCaptureDevice.authorizationStatus(for: .video) {
                            case .authorized:
                                showCamera = true
                            case .notDetermined:
                                AVCaptureDevice.requestAccess(for: .video) { granted in
                                    DispatchQueue.main.async {
                                        if granted {
                                            showCamera = true
                                        } else {
                                            showCameraPermissionAlert = true
                                        }
                                    }
                                }
                            case .denied, .restricted:
                                showCameraPermissionAlert = true
                            @unknown default:
                                break
                            }
                        }) {
                            Image(systemName: "camera.fill")
                                .padding()
                                .background(Color.white.opacity(0.8))
                                .clipShape(Circle())
                                .shadow(radius: 2)
                        }
                    }
                }
                .padding()
                Spacer()
            }
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraView(isPresented: $showCamera, onImageCaptured: { image in
                capturedImage = image
                // Save photo to current path
                if let location = locationManager.currentLocation {
                    let filename = "photo_\(UUID().uuidString).jpg"
                    let photo = PathPhoto(
                        timestamp: Date(),
                        image: image,
                        imageFilename: filename
                    )
                    locationManager.addPhoto(photo)
                }
            })
        }
        .alert("Camera Access Needed", isPresented: $showCameraPermissionAlert) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("To take photos, please allow camera access in Settings.")
        }
    }
}
