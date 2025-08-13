import SwiftUI
import Photos
import CoreLocation
import ImageIO
import UniformTypeIdentifiers

struct PhotoPagerView: View {
    @Environment(\.dismiss) private var dismiss
    @State var photos: [PathPhoto]
    @Binding var selectedIndex: Int
    @State private var showShareSheet = false
    @State private var imageToShare: ShareImage?
    @State private var showDeleteAlert = false
    @ObservedObject var pathStorage: PathStorage
    let pathId: UUID

    var body: some View {
        Group {
            if photos.isEmpty {
                Text("No photos at this location.")
                    .padding()
            } else {
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
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                Button(action: {
                    if selectedIndex < photos.count, let image = photos[selectedIndex].image {
                        let photo = photos[selectedIndex]
                        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(photo.imageFilename)
                        
                        // Ensure the temp file exists with metadata, create it if not
                        if !FileManager.default.fileExists(atPath: fileURL.path) {
                            let success = createImageFileWithMetadata(photo: photo, image: image, fileURL: fileURL)
                            if !success {
                                // Fallback to simple JPEG if metadata creation fails
                                if let data = image.jpegData(compressionQuality: 0.9) {
                                    try? data.write(to: fileURL)
                                }
                            }
                        }
                        
                        imageToShare = ShareImage(image: image, fileURL: fileURL)
                        showShareSheet = true
                    }
                }) {
                    Image(systemName: "square.and.arrow.up")
                        .foregroundColor(.blue)
                }
                
                Button(action: {
                    showDeleteAlert = true
                }) {
                    Image(systemName: "trash")
                        .foregroundColor(.blue)
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
    }
    
    private func deletePhoto(_ photo: PathPhoto) {
        // Get the current path from storage
        if var currentPath = pathStorage.path(for: pathId) {
            // Remove photo from the path
            currentPath.deletePhoto(photo)
            // Remove photo from local photos array
            photos.removeAll { $0.id == photo.id }
            // Update the stored path
            pathStorage.updatePath(currentPath)
        }
        
        // Only dismiss if no photos are left
        if photos.isEmpty {
            dismiss()
        } else {
            // Ensure selectedIndex stays within bounds
            selectedIndex = min(selectedIndex, photos.count - 1)
        }
    }
    
    private func createImageFileWithMetadata(photo: PathPhoto, image: UIImage, fileURL: URL) -> Bool {
        guard let imageData = image.jpegData(compressionQuality: 0.9) else { return false }
        
        // Create image source from the data
        guard let imageSource = CGImageSourceCreateWithData(imageData as CFData, nil) else { return false }
        
        // Create image destination
        guard let imageDestination = CGImageDestinationCreateWithURL(fileURL as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else { return false }
        
        // Create metadata dictionary
        let metadata: [String: Any] = [
            kCGImagePropertyExifDictionary as String: [
                kCGImagePropertyExifDateTimeOriginal as String: ISO8601DateFormatter().string(from: photo.timestamp),
                kCGImagePropertyExifDateTimeDigitized as String: ISO8601DateFormatter().string(from: photo.timestamp)
            ],
            kCGImagePropertyGPSDictionary as String: [
                kCGImagePropertyGPSLatitude as String: abs(photo.coordinate.latitude),
                kCGImagePropertyGPSLatitudeRef as String: photo.coordinate.latitude >= 0 ? "N" : "S",
                kCGImagePropertyGPSLongitude as String: abs(photo.coordinate.longitude),
                kCGImagePropertyGPSLongitudeRef as String: photo.coordinate.longitude >= 0 ? "E" : "W",
                kCGImagePropertyGPSTimeStamp as String: ISO8601DateFormatter().string(from: photo.timestamp)
            ]
        ]
        
        // Add image with metadata
        CGImageDestinationAddImageFromSource(imageDestination, imageSource, 0, metadata as CFDictionary)
        
        // Finalize the image destination
        return CGImageDestinationFinalize(imageDestination)
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

