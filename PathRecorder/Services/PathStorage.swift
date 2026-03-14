import Foundation
import Combine

final class PathStorage: ObservableObject {
    func path(for id: UUID) -> RecordedPath? {
        recordedPaths.first(where: { $0.id == id })
    }

    @Published var recordedPaths: [RecordedPath] = []
    private let userDefaults = UserDefaults.standard
    private let key = "RecordedPaths"

    init() {
        loadPaths()
    }

    func savePath(_ path: RecordedPath) {
        recordedPaths.append(path)
        saveToUserDefaults()
    }

    func deletePath(id: UUID) {
        recordedPaths.removeAll { $0.id == id }
        saveToUserDefaults()
    }

    func updatePath(_ path: RecordedPath) {
        if let index = recordedPaths.firstIndex(where: { $0.id == path.id }) {
            recordedPaths[index] = path
            saveToUserDefaults()
        }
    }

    func deletePhoto(from pathId: UUID, photo: PathPhoto) {
        if let index = recordedPaths.firstIndex(where: { $0.id == pathId }) {
            recordedPaths[index].photos.removeAll { $0.id == photo.id }
            // Delete image file from disk
            let url = PathPhoto.imagesDirectory.appendingPathComponent(photo.imageFilename)
            try? FileManager.default.removeItem(at: url)
            saveToUserDefaults()
        }
    }

    private func saveToUserDefaults() {
        if let encoded = try? JSONEncoder().encode(recordedPaths) {
            userDefaults.set(encoded, forKey: key)
        }
    }

    private func loadPaths() {
        if let data = userDefaults.data(forKey: key),
           let decoded = try? JSONDecoder().decode([RecordedPath].self, from: data) {
            recordedPaths = decoded
        }
    }
}
