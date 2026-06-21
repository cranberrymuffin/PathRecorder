import SwiftUI
import Photos
import CoreLocation

struct PhotoGridView: View {
    @State private var photos: [PathPhoto]
    @ObservedObject var pathStorage: PathStorage
    let pathId: UUID
    
    init(photos: [PathPhoto], pathStorage: PathStorage, pathId: UUID) {
        self._photos = State(initialValue: photos)
        self.pathStorage = pathStorage
        self.pathId = pathId
    }
    let columns = [
        GridItem(.flexible()),
        GridItem(.flexible()),
        GridItem(.flexible())
    ]
    
    @Environment(\.dismiss) private var dismiss
    @State private var selectedPhotoIndex: Int = 0
    @State private var showSaveAllAlert = false
    @State private var showPhotoLibraryAlert = false
    
    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(Array(photos.enumerated()), id: \.element.id) { index, photo in
                    if let image = photo.uiImage {
                        NavigationLink(
                            destination: PhotoPagerView(
                                photos: photos,
                                selectedIndex: $selectedPhotoIndex,
                                pathStorage: pathStorage,
                                pathId: pathId
                            )
                            .onDisappear {
                                // Update photos when returning from pager
                                if let updatedPath = pathStorage.path(for: pathId) {
                                    photos = updatedPath.photos
                                }
                                // Dismiss if no photos left
                                if photos.isEmpty {
                                    dismiss()
                                }
                            }
                        ) {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                                .frame(width: gridItemSize, height: gridItemSize)
                                .clipped()
                                .cornerRadius(8)
                        }
                        .simultaneousGesture(
                            TapGesture().onEnded {
                                selectedPhotoIndex = index
                            }
                        )
                    }
                }
            }
            .padding(8)
        }
        .navigationTitle("All Photos")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: {
                    showSaveAllAlert = true
                }) {
                    Image(systemName: "square.and.arrow.down.on.square")
                        .foregroundColor(.blue)
                }
            }
        }
        .alert("Save All Photos", isPresented: $showSaveAllAlert) {
            Button("Save All", role: .destructive) {
                saveAllPhotosToAlbum()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            if let path = pathStorage.path(for: pathId) {
                Text("Create an album '\(path.name)' and save all \(photos.count) photos to your photo library?")
            } else {
                Text("Save all \(photos.count) photos to your photo library?")
            }
        }
        .alert("Photo Library Access Needed", isPresented: $showPhotoLibraryAlert) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("To save photos, please allow full access to your photo library in Settings.")
        }
    }
    
    private var gridItemSize: CGFloat {
        let screenWidth = UIScreen.main.bounds.width
        return (screenWidth - 32) / 3 // 3 columns, 8pt spacing, 8pt padding
    }
    
    private func saveAllPhotosToAlbum() {
        guard let path = pathStorage.path(for: pathId) else { return }
        let albumName = path.name
        
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        switch status {
        case .authorized:
            createAlbumAndSavePhotos(albumName: albumName)
        case .notDetermined:
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { newStatus in
                DispatchQueue.main.async {
                    if newStatus == .authorized {
                        createAlbumAndSavePhotos(albumName: albumName)
                    } else {
                        showPhotoLibraryAlert = true
                    }
                }
            }
        case .denied, .restricted, .limited:
            showPhotoLibraryAlert = true
        @unknown default:
            showPhotoLibraryAlert = true
        }
    }
    
    private func createAlbumAndSavePhotos(albumName: String) {
        let uniqueAlbumName = getUniqueAlbumName(baseName: albumName)
        var albumPlaceholder: PHObjectPlaceholder?
        var assetPlaceholders: [PHObjectPlaceholder] = []
        
        // First, create album and save photos
        PHPhotoLibrary.shared().performChanges({
            // Create album with unique name
            let albumRequest = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: uniqueAlbumName)
            albumPlaceholder = albumRequest.placeholderForCreatedAssetCollection
            
            // Save all photos
            for photo in photos {
                if let image = photo.uiImage {
                    let assetRequest = PHAssetChangeRequest.creationRequestForAsset(from: image)
                    
                    // Set original creation date
                    assetRequest.creationDate = photo.timestamp
                    
                    if let assetPlaceholder = assetRequest.placeholderForCreatedAsset {
                        assetPlaceholders.append(assetPlaceholder)
                    }
                }
            }
        }) { success, error in
            if success, let albumPlaceholder = albumPlaceholder, !assetPlaceholders.isEmpty {
                // Second, add photos to the created album
                PHPhotoLibrary.shared().performChanges({
                    let fetchResult = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [albumPlaceholder.localIdentifier], options: nil)
                    if let album = fetchResult.firstObject {
                        let albumChangeRequest = PHAssetCollectionChangeRequest(for: album)
                        let assets = PHAsset.fetchAssets(withLocalIdentifiers: assetPlaceholders.map { $0.localIdentifier }, options: nil)
                        albumChangeRequest?.addAssets(assets)
                    }
                }) { success, error in
                    DispatchQueue.main.async {
                        if success {
                            print("Successfully saved \(photos.count) photos to album '\(uniqueAlbumName)'")
                        } else {
                            print("Error adding photos to album: \(error?.localizedDescription ?? "Unknown error")")
                        }
                    }
                }
            } else {
                DispatchQueue.main.async {
                    print("Error creating album or saving photos: \(error?.localizedDescription ?? "Unknown error")")
                }
            }
        }
    }
    
    private func getUniqueAlbumName(baseName: String) -> String {
        // Fetch all user albums
        let fetchOptions = PHFetchOptions()
        fetchOptions.predicate = NSPredicate(format: "estimatedAssetCount > 0 OR estimatedAssetCount = 0")
        let albums = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: fetchOptions)
        
        var existingNames = Set<String>()
        albums.enumerateObjects { album, _, _ in
            if let title = album.localizedTitle {
                existingNames.insert(title)
            }
        }
        
        // Check if base name is available
        if !existingNames.contains(baseName) {
            return baseName
        }
        
        // Find the next available number
        var counter = 1
        var candidateName = "\(baseName) \(counter)"
        
        while existingNames.contains(candidateName) {
            counter += 1
            candidateName = "\(baseName) \(counter)"
        }
        
        return candidateName
    }
}

// Helper to get UIImage from PathPhoto
extension PathPhoto {
    var uiImage: UIImage? {
        // Try to load from file if possible, otherwise use in-memory image if available
        if let image = self.image { return image }
        // Try to construct file URL from imageFilename
        let fileManager = FileManager.default
        // Look in Documents directory
        if let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first {
            let url = docs.appendingPathComponent(imageFilename)
            if fileManager.fileExists(atPath: url.path) {
                return UIImage(contentsOfFile: url.path)
            }
        }
        return nil
    }
}
