import SwiftUI
import MapKit

/// Displays a map with polylines and GPS point annotations for a recorded path.
struct PathMapView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var sheetDetent: PresentationDetent = .fraction(0.25)
    @ObservedObject var locationManager: LocationManager
    @ObservedObject var pathStorage: PathStorage
    @State private var region: MKCoordinateRegion
    @State private var pathSegments: [PathSegment] = []
    @State private var showEditingSheet = false
    @State private var editedName: String
    @State private var recordedPath: RecordedPath
    var showRenameSheetOnAppear: Bool
    var onModifyPath: (() -> Void)?

    init(recordedPath: RecordedPath, locationManager: LocationManager, pathStorage: PathStorage, showRenameSheetOnAppear: Bool = false, onModifyPath: (() -> Void)? = nil) {
        self.locationManager = locationManager
        self.pathStorage = pathStorage
        _recordedPath = State(initialValue: recordedPath)
        // Group locations by segment first
        let segments = Dictionary(grouping: recordedPath.locations, by: { $0.segmentId })
        var tempSegments: [PathSegment] = []
        for (segmentId, locations) in segments {
            let sortedLocations = locations.sorted { $0.timestamp < $1.timestamp }
            let coordinates = sortedLocations.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
            tempSegments.append(PathSegment(id: segmentId, coordinates: coordinates))
        }
        _pathSegments = State(initialValue: tempSegments)
        // Calculate the proper region to fit all coordinates
        let allCoordinates = tempSegments.flatMap { $0.coordinates }
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

    var body: some View {
        let currentPath = pathStorage.path(for: recordedPath.id) ?? recordedPath
        MapWithPolylines(
            region: region,
            locations: currentPath.locations,
            pathSegments: pathSegments,
            photos: currentPath.photos,
            onPhotoTapped: { tappedPhoto in
                // Always get the most current path data when a photo is tapped
                let latestPath = pathStorage.path(for: recordedPath.id) ?? recordedPath
                
                // Find all photos within 10 meters of the tapped coordinate
                let tappedLocation = CLLocation(latitude: tappedPhoto.coordinate.latitude, longitude: tappedPhoto.coordinate.longitude)
                let nearbyPhotos = latestPath.photos.filter {
                    let photoLocation = CLLocation(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude)
                    return tappedLocation.distance(from: photoLocation) <= 10.0 // meters
                }
                selectedPhotos = nearbyPhotos
                // Show the tapped photo first if multiple (only if it still exists)
                if let idx = nearbyPhotos.firstIndex(where: { $0.id == tappedPhoto.id }) {
                    selectedPhotoIndex = idx
                } else {
                    selectedPhotoIndex = 0
                }
            }
        )
        .id(currentPath.photos.count) // Force refresh when photo count changes
        .navigationTitle(currentPath.name)
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
}
