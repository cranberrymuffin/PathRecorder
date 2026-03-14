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

