import SwiftUI
import MapKit
import Foundation

class PhotoAnnotation: NSObject, MKAnnotation {
    let photos: [PathPhoto]
    var coordinate: CLLocationCoordinate2D
    init(photos: [PathPhoto], coordinate: CLLocationCoordinate2D) {
        self.photos = photos
        self.coordinate = coordinate
    }
}

private struct ClusterKey: Hashable {
    let x: Int
    let y: Int
}

struct MapWithPolylines: UIViewRepresentable {
    var region: MKCoordinateRegion
    let locations: [GPSLocation]
    let pathSegments: [PathSegment]
    let photos: [PathPhoto]
    let onPhotoTapped: ([PathPhoto], PathPhoto) -> Void

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.setRegion(region, animated: false)
        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        mapView.removeOverlays(mapView.overlays)
        mapView.removeAnnotations(mapView.annotations)
        for (index, segment) in pathSegments.enumerated() {
            if segment.coordinates.count >= 2 {
                let polyline = segment.mkPolyline
                polyline.title = "segment_\(index)"
                mapView.addOverlay(polyline)
            }
            // Add GPS point annotations for segment start/end
            if let startCoord = segment.coordinates.first,
               let endCoord = segment.coordinates.last {
                let startAnnotation = MKPointAnnotation()
                startAnnotation.coordinate = startCoord
                mapView.addAnnotation(startAnnotation)

                let endAnnotation = MKPointAnnotation()
                endAnnotation.coordinate = endCoord
                mapView.addAnnotation(endAnnotation)
            }
        }

        updatePhotoAnnotations(on: mapView)
    }

    private func updatePhotoAnnotations(on mapView: MKMapView) {
        let threshold: CGFloat = 52.0
        var photoGroups: [[PathPhoto]] = []
        var groupCoordinates: [[CLLocationCoordinate2D]] = []
        var groupScreenPoints: [CGPoint] = []

        for photo in photos {
            guard let coordinate = coordinate(for: photo, in: locations) else { continue }
            let screenPoint = mapView.convert(coordinate, toPointTo: mapView)
            if let matchingIndex = groupScreenPoints.firstIndex(where: { existingPoint in
                abs(existingPoint.x - screenPoint.x) < threshold &&
                abs(existingPoint.y - screenPoint.y) < threshold
            }) {
                photoGroups[matchingIndex].append(photo)
                groupCoordinates[matchingIndex].append(coordinate)
            } else {
                photoGroups.append([photo])
                groupCoordinates.append([coordinate])
                groupScreenPoints.append(screenPoint)
            }
        }

        let existingPhotoAnnotations = mapView.annotations.compactMap { $0 as? PhotoAnnotation }
        mapView.removeAnnotations(existingPhotoAnnotations)

        for (index, groupedPhotos) in photoGroups.enumerated() {
            let coordinates = groupCoordinates[index]
            guard !coordinates.isEmpty else { continue }
            let sortedPhotos = groupedPhotos.sorted { $0.timestamp < $1.timestamp }
            let centerCoordinate = averageCoordinate(from: coordinates)
            let annotation = PhotoAnnotation(photos: sortedPhotos, coordinate: centerCoordinate)
            mapView.addAnnotation(annotation)
        }
    }

    private func averageCoordinate(from coordinates: [CLLocationCoordinate2D]) -> CLLocationCoordinate2D {
        let total = coordinates.reduce((lat: 0.0, lon: 0.0)) { acc, coord in
            (acc.lat + coord.latitude, acc.lon + coord.longitude)
        }
        return CLLocationCoordinate2D(
            latitude: total.lat / Double(coordinates.count),
            longitude: total.lon / Double(coordinates.count)
        )
    }

    private func coordinate(for photo: PathPhoto, in locations: [GPSLocation]) -> CLLocationCoordinate2D? {
        guard let location = locations.first(where: { $0.id == photo.locationId }) else { return nil }
        return CLLocationCoordinate2D(latitude: location.latitude, longitude: location.longitude)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self, onPhotoTapped: onPhotoTapped)
    }

    class Coordinator: NSObject, MKMapViewDelegate {
        var parent: MapWithPolylines
        let onPhotoTapped: ([PathPhoto], PathPhoto) -> Void
        init(_ parent: MapWithPolylines, onPhotoTapped: @escaping ([PathPhoto], PathPhoto) -> Void) {
            self.parent = parent
            self.onPhotoTapped = onPhotoTapped
        }
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            return MapRenderingHelpers.polylineRenderer(for: overlay)
        }
        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if let photoAnnotation = annotation as? PhotoAnnotation {
                let identifier = "PhotoAnnotation"
                var annotationView = mapView.dequeueReusableAnnotationView(withIdentifier: identifier)
                if annotationView == nil {
                    annotationView = MKAnnotationView(annotation: annotation, reuseIdentifier: identifier)
                } else {
                    annotationView?.annotation = annotation
                }
                // Use helper for annotation marker image with preview
                let preview = photoAnnotation.photos.first?.image
                annotationView?.image = MapRenderingHelpers.photoAnnotationImage(preview: preview)
                annotationView?.canShowCallout = false
                annotationView?.centerOffset = CGPoint(x: 0, y: 0)
                annotationView?.isUserInteractionEnabled = true
                // Ensure photo annotation is always on top
                annotationView?.layer.zPosition = 1
                return annotationView
            } else {
                let identifier = "GPSPoint"
                var annotationView = mapView.dequeueReusableAnnotationView(withIdentifier: identifier)
                if annotationView == nil {
                    annotationView = MKAnnotationView(annotation: annotation, reuseIdentifier: identifier)
                } else {
                    annotationView?.annotation = annotation
                }
                annotationView?.image = MapRenderingHelpers.cachedBlueDotImage()
                annotationView?.centerOffset = CGPoint(x: 0, y: 0)
                annotationView?.isUserInteractionEnabled = false // Don't block touches
                annotationView?.layer.zPosition = 0
                return annotationView
            }
        }
        func mapView(_ mapView: MKMapView, didSelect annotationView: MKAnnotationView) {
            if let photoAnnotation = annotationView.annotation as? PhotoAnnotation {
                print("Photo annotation tapped at coordinate: \(photoAnnotation.coordinate.latitude), \(photoAnnotation.coordinate.longitude)")
                let sortedPhotos = photoAnnotation.photos.sorted { $0.timestamp < $1.timestamp }
                guard let firstPhoto = sortedPhotos.first else { return }
                onPhotoTapped(sortedPhotos, firstPhoto)
            }
        }

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            parent.updatePhotoAnnotations(on: mapView)
        }
    }
}
