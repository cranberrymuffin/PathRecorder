import UIKit
import Foundation
import CoreLocation

struct RecordedPath: Identifiable, Codable, Hashable {
    let id: UUID
    let startTime: Date // Keep start time for naming and reference
    let totalDuration: TimeInterval // Total time in seconds
    let totalDistance: Double
    let locations: [GPSLocation]
    var photos: [PathPhoto]
    var name: String
    
    init(startTime: Date, totalDuration: TimeInterval, totalDistance: Double, locations: [GPSLocation], photos: [PathPhoto] = [], name: String? = nil) {
        self.id = UUID()
        self.startTime = startTime
        self.totalDuration = totalDuration
        self.totalDistance = totalDistance
        self.locations = locations
        self.photos = photos
        if let name = name {
            self.name = name
        } else {
            self.name = "Path \(DateFormatter.localizedString(from: startTime, dateStyle: .short, timeStyle: .short))"
        }
    }

    static func == (lhs: RecordedPath, rhs: RecordedPath) -> Bool {
        return lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    mutating func editName(_ newName: String) {
        self.name = newName
    }
    
}

struct GPSLocation: Identifiable, Codable, Equatable {
    let id: UUID
    let latitude: Double
    let longitude: Double
    let timestamp: Date
    let segmentId: UUID // Track which recording segment this belongs to
    
    init(latitude: Double, longitude: Double, timestamp: Date, segmentId: UUID = UUID()) {
        self.id = UUID()
        self.latitude = latitude
        self.longitude = longitude
        self.timestamp = timestamp
        self.segmentId = segmentId
    }
    
    static func == (lhs: GPSLocation, rhs: GPSLocation) -> Bool {
        return lhs.id == rhs.id
    }
}

class PathStorage: ObservableObject {
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
