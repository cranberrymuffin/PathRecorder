import MapKit

/// Represents a segment of a path, used for drawing polylines.
struct PathSegment: Identifiable {
    let id: UUID
    let coordinates: [CLLocationCoordinate2D]
    var polyline: MKPolyline {
        MKPolyline(coordinates: coordinates, count: coordinates.count)
    }
} 