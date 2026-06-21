import MapKit
import Foundation

/// Represents a continuous segment of a path (between pause/resume events)
struct PathSegment: Identifiable, Codable {
    let id: UUID
    let locations: [GPSLocation]
    
    init(locations: [GPSLocation]) {
        self.id = UUID()
        self.locations = locations
    }
    
    var startTime: Date {
        locations.first?.timestamp ?? Date()
    }
    
    var endTime: Date {
        locations.last?.timestamp ?? Date()
    }
    
    var duration: TimeInterval {
        endTime.timeIntervalSince(startTime)
    }
    
    var coordinates: [CLLocationCoordinate2D] {
        locations.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
    }
    
    var mkPolyline: MKPolyline {
        let coords = coordinates
        return MKPolyline(coordinates: coords, count: coords.count)
    }
}