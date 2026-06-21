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

struct MapWithPolylines: UIViewRepresentable {
    var region: MKCoordinateRegion
    let locations: [GPSLocation]
    let pathSegments: [PathSegment]
    let photos: [PathPhoto]
    let onPhotoTapped: (PathPhoto) -> Void

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
        for photo in photos {
            guard let coord = coordinate(for: photo, in: locations) else { continue }
            mapView.addAnnotation(PhotoAnnotation(photos: [photo], coordinate: coord))
        }
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
        let onPhotoTapped: (PathPhoto) -> Void
        init(_ parent: MapWithPolylines, onPhotoTapped: @escaping (PathPhoto) -> Void) {
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
                let preview = photoAnnotation.photos.first?.image
                annotationView?.image = MapRenderingHelpers.photoAnnotationImage(preview: preview)
                annotationView?.canShowCallout = false
                annotationView?.centerOffset = CGPoint(x: 0, y: 0)
                annotationView?.isUserInteractionEnabled = true
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
                annotationView?.isUserInteractionEnabled = false
                annotationView?.layer.zPosition = 0
                return annotationView
            }
        }
        func mapView(_ mapView: MKMapView, didSelect annotationView: MKAnnotationView) {
            if let photoAnnotation = annotationView.annotation as? PhotoAnnotation,
               let firstPhoto = photoAnnotation.photos.first {
                onPhotoTapped(firstPhoto)
            }
        }
    }
}
