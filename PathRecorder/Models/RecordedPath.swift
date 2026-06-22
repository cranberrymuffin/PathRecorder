import UIKit
import Foundation
import CoreLocation

struct RecordedPath: Identifiable, Codable, Hashable {
    let id: UUID
    var segments: [PathSegment]
    var name: String
    var photos: [PathPhoto]
    
    init(segments: [PathSegment], name: String? = nil, photos: [PathPhoto] = []) {
        self.id = UUID()
        self.segments = segments
        self.photos = photos
        if let name = name {
            self.name = name
        } else {
            let startTime = segments.first?.startTime ?? Date()
            self.name = "Path \(DateFormatter.localizedString(from: startTime, dateStyle: .short, timeStyle: .short))"
        }
    }

    init(id: UUID, segments: [PathSegment], name: String, photos: [PathPhoto] = []) {
        self.id = id
        self.segments = segments
        self.name = name
        self.photos = photos
    }
    
    /// Start time of the first segment
    var startTime: Date {
        segments.first?.startTime ?? Date()
    }
    
    /// Total duration across all segments
    var totalDuration: TimeInterval {
        segments.reduce(0) { $0 + $1.duration }
    }
    
    /// Total distance traveled across all segments
    var totalDistance: Double {
        segments.reduce(0) { total, segment in
            var distance = total
            for i in 0..<(segment.locations.count - 1) {
                let loc1 = CLLocationCoordinate2D(latitude: segment.locations[i].latitude, 
                                                   longitude: segment.locations[i].longitude)
                let loc2 = CLLocationCoordinate2D(latitude: segment.locations[i + 1].latitude, 
                                                   longitude: segment.locations[i + 1].longitude)
                let c1 = CLLocation(latitude: loc1.latitude, longitude: loc1.longitude)
                let c2 = CLLocation(latitude: loc2.latitude, longitude: loc2.longitude)
                distance += c1.distance(from: c2)
            }
            return distance
        }
    }
    
    /// All GPS locations from all segments (for backward compatibility with display code)
    var locations: [GPSLocation] {
        segments.flatMap { $0.locations }
    }
    
    mutating func editName(_ newName: String) {
        self.name = newName
    }
    
    mutating func addSegment(_ segment: PathSegment) {
        segments.append(segment)
    }

    static func == (lhs: RecordedPath, rhs: RecordedPath) -> Bool {
        return lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

struct GPSLocation: Identifiable, Codable, Equatable {
    let id: UUID
    let latitude: Double
    let longitude: Double
    let timestamp: Date
    let segmentId: UUID  // Tracks which segment this location belongs to
    
    init(latitude: Double, longitude: Double, timestamp: Date, segmentId: UUID) {
        self.id = UUID()
        self.latitude = latitude
        self.longitude = longitude
        self.timestamp = timestamp
        self.segmentId = segmentId
    }

    init(id: UUID, latitude: Double, longitude: Double, timestamp: Date, segmentId: UUID) {
        self.id = id
        self.latitude = latitude
        self.longitude = longitude
        self.timestamp = timestamp
        self.segmentId = segmentId
    }
    
    static func == (lhs: GPSLocation, rhs: GPSLocation) -> Bool {
        return lhs.id == rhs.id
    }
}

