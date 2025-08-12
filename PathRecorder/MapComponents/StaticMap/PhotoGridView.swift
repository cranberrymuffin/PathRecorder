import SwiftUI

struct PhotoGridView: View {
    let photos: [PathPhoto]
    let columns = [
        GridItem(.flexible()),
        GridItem(.flexible()),
        GridItem(.flexible())
    ]
    
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(photos) { photo in
                    if let image = photo.uiImage {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: gridItemSize, height: gridItemSize)
                            .clipped()
                            .cornerRadius(8)
                    }
                }
            }
            .padding(8)
        }
        .navigationTitle("All Photos")
        .navigationBarTitleDisplayMode(.inline)
        // No custom toolbar; use default back button only
    }
    
    private var gridItemSize: CGFloat {
        let screenWidth = UIScreen.main.bounds.width
        return (screenWidth - 32) / 3 // 3 columns, 8pt spacing, 8pt padding
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
