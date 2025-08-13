import SwiftUI
import Photos

struct PhotoPagerView: View {
    @Environment(\.dismiss) private var dismiss
    let photos: [PathPhoto] // Replace with your actual model type
    @Binding var selectedIndex: Int
    @State private var showShareSheet = false
    @State private var imageToShare: ShareImage?
    @State private var showDeleteAlert = false
    @State private var showPhotoLibraryAlert = false
    @ObservedObject var pathStorage: PathStorage
    let pathId: UUID

    var body: some View {
        Group {
            if photos.isEmpty {
                Text("No photos at this location.")
                    .padding()
            } else {
                ZStack(alignment: .topLeading) {
                    VStack(spacing: 0) {
                        TabView(selection: $selectedIndex) {
                            ForEach(Array(photos.enumerated()), id: \.element.id) { idx, photo in
                                VStack {
                                    if let image = photo.image {
                                        Text(DateFormatter.localizedString(from: photo.timestamp, dateStyle: .medium, timeStyle: .short))
                                            .font(.subheadline)
                                        // Display GPS coordinate in readable format
                                        Text(String(format: "Lat: %.5f, Lon: %.5f", photo.coordinate.latitude, photo.coordinate.longitude))
                                            .font(.caption)
                                        Image(uiImage: image)
                                            .resizable()
                                            .scaledToFit()
                                            .frame(maxWidth: 400, maxHeight: 400)
                                            .cornerRadius(16)
                                            .padding()
                                            .contextMenu {
                                                Button(action: {
                                                    let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(photo.imageFilename)
                                                    
                                                    // Ensure the temp file exists and has content, create it if not
                                                    if !FileManager.default.fileExists(atPath: fileURL.path) {
                                                        if let data = image.jpegData(compressionQuality: 0.9) {
                                                            try? data.write(to: fileURL)
                                                        }
                                                    }
                                                    
                                                    imageToShare = ShareImage(image: image, fileURL: fileURL)
                                                    showShareSheet = true
                                                }) {
                                                    Label("Share", systemImage: "square.and.arrow.up")
                                                }
                                                
                                                Button(action: {
                                                    saveImageToPhotos(image)
                                                }) {
                                                    Label("Save to Photos", systemImage: "square.and.arrow.down")
                                                }
                                                
                                                Button(action: {
                                                    UIPasteboard.general.image = image
                                                }) {
                                                    Label("Copy", systemImage: "doc.on.doc")
                                                }
                                            }
                                    } else {
                                        Text("Photo unavailable")
                                    }
                                }
                                .frame(maxHeight: .infinity)
                                .tag(idx)
                            }
                        }
                        .tabViewStyle(PageTabViewStyle(indexDisplayMode: .automatic))
                        .frame(maxHeight: .infinity)
                    }
                    .frame(maxHeight: .infinity)
                    .padding()
                    
                    // Delete button in top left corner
                    Button(action: {
                        showDeleteAlert = true
                    }) {
                        Image(systemName: "trash")
                            .font(.title2)
                            .foregroundColor(.red)
                            .padding(12)
                            .background(Color.white.opacity(0.8))
                            .clipShape(Circle())
                            .shadow(radius: 4)
                    }
                    .padding()
                }
            }
        }
        .alert("Delete Photo", isPresented: $showDeleteAlert) {
            Button("Delete", role: .destructive) {
                if selectedIndex < photos.count {
                    let photoToDelete = photos[selectedIndex]
                    deletePhoto(photoToDelete)
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Are you sure you want to delete this photo? This action cannot be undone.")
        }
        .sheet(item: $imageToShare) { shareImage in
            ShareSheet(activityItems: [shareImage.fileURL])
        }
        .onChange(of: imageToShare) { oldValue, newValue in
            // When share sheet is dismissed, clean up temp file
            if oldValue != nil && newValue == nil {
                if let fileURL = oldValue?.fileURL {
                    try? FileManager.default.removeItem(at: fileURL)
                }
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
    
    private func deletePhoto(_ photo: PathPhoto) {
        // Get the current path from storage
        if var currentPath = pathStorage.path(for: pathId) {
            // Remove photo from the path
            currentPath.deletePhoto(photo)
            
            // Update the stored path
            pathStorage.updatePath(currentPath)
            
            // Close the photo pager sheet
            dismiss()
        }
    }
    
    private func saveImageToPhotos(_ image: UIImage) {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        switch status {
        case .authorized:
            UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
        case .notDetermined:
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { newStatus in
                DispatchQueue.main.async {
                    if newStatus == .authorized {
                        UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
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

    // UIKit share sheet wrapper
    struct ShareSheet: UIViewControllerRepresentable {
        var activityItems: [Any]
        var applicationActivities: [UIActivity]? = nil

        func makeUIViewController(context: Context) -> UIActivityViewController {
            UIActivityViewController(activityItems: activityItems, applicationActivities: applicationActivities)
        }

        func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
    }
}

// Wrapper for sharing images in .sheet(item:)
struct ShareImage: Identifiable, Equatable {
    let id = UUID()
    let image: UIImage
    let fileURL: URL

    static func == (lhs: ShareImage, rhs: ShareImage) -> Bool {
        lhs.id == rhs.id && lhs.fileURL == rhs.fileURL
    }
}

