import SwiftUI
import PhotosUI
import UIKit

struct PhotoLibraryPicker: View {
    @Binding var pathPhotos: [PathPhoto]
    var recordedPath: RecordedPath
    var pathSegments: [PathSegment]
    var onComplete: () -> Void
    @State private var showPicker = false
    @State private var showPhotoLibraryAlert = false
    var body: some View {
        VStack {
            Button(action: {
                let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
                switch status {
                case .authorized:
                    showPicker = true
                case .notDetermined:
                    PHPhotoLibrary.requestAuthorization(for: .readWrite) { newStatus in
                        DispatchQueue.main.async {
                            if newStatus == .authorized {
                                showPicker = true
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
            }) {
                Text("Select Photos from Library")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.purple)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                    .shadow(color: Color.blue.opacity(0.2), radius: 2, x: 0, y: 2)
                    .padding(.horizontal)
            }
        }
        .sheet(isPresented: $showPicker) {
            UIKitPhotoPicker { images, assets in
                var pending: [PathPhoto] = []
                for (image, asset) in zip(images, assets) {
                    let creationDate: Date? = asset?.creationDate
                    if let creationDate = creationDate {
                        // Find which segment contains this photo's creation date
                        for segment in pathSegments {
                            let segmentLocations = segment.locations
                            guard let first = segmentLocations.first, let last = segmentLocations.last else { continue }
                            if creationDate >= first.timestamp && creationDate <= last.timestamp {
                                var filename = "photo_\(UUID().uuidString).jpg"
                                if let asset = asset, let resource = PHAssetResource.assetResources(for: asset).first {
                                    filename = resource.originalFilename
                                }
                                guard let closestLocation = segmentLocations.min(by: {
                                    abs($0.timestamp.timeIntervalSince(creationDate)) < abs($1.timestamp.timeIntervalSince(creationDate))
                                }) else { continue }
                                let pathPhoto = PathPhoto(
                                    timestamp: creationDate,
                                    image: image,
                                    imageFilename: filename,
                                    locationId: closestLocation.id
                                )
                                pending.append(pathPhoto)
                                break
                            }
                        }
                    }
                }
                pathPhotos = pending
                onComplete()
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
            Text("To upload photos, please allow full access to your photo library in Settings.")
        }
    }

// UIKit PHPickerViewController wrapper
struct UIKitPhotoPicker: UIViewControllerRepresentable {
    var onComplete: ([UIImage], [PHAsset?]) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onComplete: onComplete)
    }

    func makeUIViewController(context: Context) -> UIViewController {
        var config = PHPickerConfiguration(photoLibrary: PHPhotoLibrary.shared())
        config.selectionLimit = 0
        config.filter = .images
        config.preferredAssetRepresentationMode = .current
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}

    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let onComplete: ([UIImage], [PHAsset?]) -> Void
        init(onComplete: @escaping ([UIImage], [PHAsset?]) -> Void) {
            self.onComplete = onComplete
        }
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            var images: [UIImage] = []
            var assets: [PHAsset?] = []
            let group = DispatchGroup()
            for result in results {
                group.enter()
                result.itemProvider.loadObject(ofClass: UIImage.self) { reading, _ in
                    let image = reading as? UIImage
                    images.append(image ?? UIImage())
                    if let assetId = result.assetIdentifier {
                        let asset = PHAsset.fetchAssets(withLocalIdentifiers: [assetId], options: nil).firstObject
                        assets.append(asset)
                    } else {
                        assets.append(nil)
                    }
                    group.leave()
                }
            }
            group.notify(queue: .main) {
                picker.dismiss(animated: true)
                // Only call onComplete if there was a selection
                if !results.isEmpty {
                    self.onComplete(images, assets)
                }
            }
        }
    }
}
}

// Helper to attach PHAsset to UIImage
extension UIImage {
    private struct AssociatedKeys {
        static var assetKey: UInt8 = 0
    }
    var asset: PHAsset? {
        get {
            objc_getAssociatedObject(self, &AssociatedKeys.assetKey) as? PHAsset
        }
        set {
            objc_setAssociatedObject(self, &AssociatedKeys.assetKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }
}
