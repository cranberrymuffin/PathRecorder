import SwiftUI
import MapKit
import Shared

/// Displays a map with polylines and GPS point annotations for a recorded path.
struct PathMapView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var sheetDetent: PresentationDetent = .fraction(0.25)
    @ObservedObject var locationManager: LocationManager
    @ObservedObject var pathStorage: PathStorage
    @ObservedObject var settings: Settings
    @State private var region: MKCoordinateRegion
    @State private var pathSegments: [PathSegment] = []
    @State private var showEditingSheet = false
    @State private var editedName: String
    @State private var recordedPath: RecordedPath
    var showRenameSheetOnAppear: Bool
    var onModifyPath: (() -> Void)?
    @State private var bottomSheetDetent: PresentationDetent = .height(100)

    init(recordedPath: RecordedPath, locationManager: LocationManager, pathStorage: PathStorage, settings: Settings, showRenameSheetOnAppear: Bool = false, onModifyPath: (() -> Void)? = nil) {
        self.locationManager = locationManager
        self.pathStorage = pathStorage
        self.settings = settings
        _recordedPath = State(initialValue: recordedPath)
        // Use segments directly from the new data model
        _pathSegments = State(initialValue: recordedPath.segments)
        // Calculate the proper region to fit all coordinates
        let allCoordinates = recordedPath.segments.flatMap { $0.coordinates }
        let minLat = allCoordinates.map { $0.latitude }.min() ?? 0
        let maxLat = allCoordinates.map { $0.latitude }.max() ?? 0
        let minLon = allCoordinates.map { $0.longitude }.min() ?? 0
        let maxLon = allCoordinates.map { $0.longitude }.max() ?? 0
        let centerLat = (minLat + maxLat) / 2
        let centerLon = (minLon + maxLon) / 2
        let latDelta = (maxLat - minLat) * 1.2
        let lonDelta = (maxLon - minLon) * 1.2
        let initialRegion = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: centerLat, longitude: centerLon),
            span: MKCoordinateSpan(
                latitudeDelta: max(latDelta, 0.001),
                longitudeDelta: max(lonDelta, 0.001)
            )
        )
        _region = State(initialValue: initialRegion)
        _editedName = State(initialValue: recordedPath.name)
        self.showRenameSheetOnAppear = showRenameSheetOnAppear
        self.onModifyPath = onModifyPath
    }

    // Holds all photos at a tapped coordinate
    @State private var selectedPhotos: [PathPhoto]? = nil
    @State private var selectedPhotoIndex: Int = 0
    @State private var showPhotoGrid: Bool = false
    @State private var pickedPathPhotos: [PathPhoto] = []
    @State private var showAssociationAlert = false
    @State private var associatedCount = 0
    @State private var pendingPhotos: [PathPhoto] = []

    // MARK: - View Components
    private func mapView(for currentPath: RecordedPath) -> some View {
        MapWithPolylines(
            region: region,
            locations: currentPath.locations,
            pathSegments: currentPath.segments,
            photos: currentPath.photos,
            onPhotoTapped: { tappedPhoto in
                handlePhotoTap(tappedPhoto)
            }
        )
        .id(currentPath.photos.count)
    }

    private func bottomInfoSheet(for currentPath: RecordedPath) -> some View {
        VStack(spacing: 0) {
            Spacer()
            pathInfoContent(for: currentPath)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(.ultraThinMaterial)
                        .shadow(radius: 8)
                )
                .padding(.horizontal, 12)
                .padding(.bottom, 20)
        }
    }

    private func pathInfoContent(for currentPath: RecordedPath) -> some View {
        VStack(alignment: .center, spacing: 8) {
            // Title line
            Text(currentPath.name)
                .font(.headline)
                .padding(.horizontal, 16)
                .padding(.top, 16)

            // Metrics line
            pathMetricsRow(for: currentPath)
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
        }
        .frame(maxWidth: nil, alignment: .center)
    }

    private func pathMetricsRow(for currentPath: RecordedPath) -> some View {
        HStack(spacing: 12) {
            // Distance
            metricItem(
                icon: "figure.walk",
                color: .green,
                text: settings.formatDistance(currentPath.totalDistance)
            )


            // Total time
            metricItem(
                icon: "clock",
                color: .orange,
                text: formatTime(currentPath.totalDuration)
            )


            // Pace
            metricItem(
                icon: "timer",
                color: .purple,
                text: computePace(
                    distanceMeters: currentPath.totalDistance,
                    elapsedSeconds: currentPath.totalDuration,
                    unit: settings.distanceUnit.rawValue
                )
            )
        }
    }

    private func metricItem(icon: String, color: Color, text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .foregroundColor(color)
                .font(.caption)
            Text(text)
                .font(.subheadline)
        }
    }

    // MARK: - Helper Methods
    private func handlePhotoTap(_ tappedPhoto: PathPhoto) {
        let latestPath = pathStorage.path(for: recordedPath.id) ?? recordedPath
        selectedPhotos = latestPath.photos
        if let idx = selectedPhotos?.firstIndex(where: { $0.id == tappedPhoto.id }) {
            selectedPhotoIndex = idx
        } else {
            selectedPhotoIndex = 0
        }
    }

    var body: some View {
        let currentPath = pathStorage.path(for: recordedPath.id) ?? recordedPath
        ZStack(alignment: .bottom) {
            mapView(for: currentPath)
            bottomInfoSheet(for: currentPath)
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                if !currentPath.photos.isEmpty {
                    NavigationLink(destination: PhotoGridView(photos: currentPath.photos, pathStorage: pathStorage, pathId: recordedPath.id), isActive: $showPhotoGrid) {
                        EmptyView()
                    }
                    Button(action: {
                        showPhotoGrid = true
                    }) {
                        Image(systemName: "photo.on.rectangle")
                    }
                }
                Button(action: {
                    showEditingSheet = true
                }) {
                    Image(systemName: "pencil")
                }
            }
        }
        // Hidden NavigationLink for photo pager
        .background(
            NavigationLink(
                destination: Group {
                    if let photos = selectedPhotos {
                        PhotoPagerView(
                            photos: photos,
                            selectedIndex: $selectedPhotoIndex,
                            pathStorage: pathStorage,
                            pathId: recordedPath.id
                        )
                    } else {
                        Text("No photos at this location.")
                            .padding()
                    }
                },
                isActive: Binding(
                    get: { selectedPhotos != nil },
                    set: { if !$0 { selectedPhotos = nil } }
                )
            ) {
                EmptyView()
            }
        )
        // Removed sheet for all photos; now uses navigation to PhotoGridView
        .onAppear {
            if showRenameSheetOnAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    showEditingSheet = true
                }
            }
        }
        .sheet(isPresented: $showEditingSheet) {
            PathEditingSheet(
                editedName: $editedName,
                recordedPath: recordedPath,
                pathStorage: pathStorage,
                sheetDetent: sheetDetent,
                onSetName: {
                    if var currentPath = pathStorage.path(for: recordedPath.id) {
                        currentPath.editName(editedName)
                        pathStorage.updatePath(currentPath)
                        recordedPath = currentPath
                    }
                    showEditingSheet = false
                },
                pickedPathPhotos: $pickedPathPhotos,
                pathSegments: pathSegments,
                onPhotoPickerComplete: {
                    print("Photo picker completed. Picked photos count: \(pickedPathPhotos.count)")
                    showEditingSheet = false
                    associatedCount = pickedPathPhotos.count
                    pendingPhotos = pickedPathPhotos
                    pickedPathPhotos.removeAll()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                        showAssociationAlert = true
                    }
                },
                onModifyPath: {
                    locationManager.loadPathForEditing(recordedPath, pathStorage: pathStorage)
                    showEditingSheet = false
                    dismiss()
                    onModifyPath?()
                },
                onDeletePath: {
                    pathStorage.deletePath(id: recordedPath.id)
                    showEditingSheet = false
                    dismiss()
                }
            )
            .presentationDetents([.fraction(0.25), .medium], selection: $sheetDetent)
            .onDisappear {
                // Reset editedName to match storage if not saved
                if let latest = pathStorage.path(for: recordedPath.id) {
                    editedName = latest.name
                    recordedPath = latest
                }
            }
        }
        .sheet(isPresented: Binding(get: { !showEditingSheet && showAssociationAlert && associatedCount > 0 }, set: { show in showAssociationAlert = show })) {
            PhotoAssociationConfirmationSheet(
                associatedCount: associatedCount,
                pendingPhotos: pendingPhotos,
                onAdd: {
                    if var currentPath = pathStorage.path(for: recordedPath.id) {
                        let existingFilenames = Set(currentPath.photos.map { $0.imageFilename })
                        let newPhotos = pendingPhotos.filter { !existingFilenames.contains($0.imageFilename) }
                        currentPath.photos.append(contentsOf: newPhotos)
                        pathStorage.updatePath(currentPath)
                        recordedPath = currentPath
                    }
                    pendingPhotos.removeAll()
                    showAssociationAlert = false
                },
                onCancel: {
                    pendingPhotos.removeAll()
                    showAssociationAlert = false
                }
            )
        }
        .alert("Selected photos were not captured during path recording.", isPresented: Binding(get: { !showEditingSheet && showAssociationAlert && associatedCount == 0 }, set: { show in showAssociationAlert = show })) {
            Button("OK", role: .cancel) {
                pendingPhotos.removeAll()
            }
        }
    }

    // Helper function for formatting time
    private func formatTime(_ timeInterval: TimeInterval) -> String {
        let hours = Int(timeInterval) / 3600
        let minutes = Int(timeInterval) / 60 % 60
        let seconds = Int(timeInterval) % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }
}
