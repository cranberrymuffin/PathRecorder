import UIKit
import MapKit

protocol LiveMapViewControllerDelegate: AnyObject {
    func regionDidChange(_ region: MKCoordinateRegion, userInitiated: Bool)
    func mapTouched(at coordinate: CLLocationCoordinate2D, point: CGPoint)
}

class LiveMapViewController: UIViewController, MKMapViewDelegate {
    let mapView = MKMapView()
    weak var delegate: LiveMapViewControllerDelegate?
    private var overlays: [UUID: MKPolyline] = [:]
    private var annotations: [UUID: MKPointAnnotation] = [:]
    var isAutoCentering: Bool = true
    var isPaused: Bool = false
    private var isProgrammaticChange = false
    private var isUserInteracting = false
    private var bufferedLocations: [GPSLocation]? = nil

    override func viewDidLoad() {
        super.viewDidLoad()
        mapView.delegate = self
        mapView.frame = view.bounds
        mapView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(mapView)
        // Fallback to a default region if location is not available
        let defaultRegion = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194), // San Francisco
            span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
        )
        mapView.setRegion(defaultRegion, animated: false)
        mapView.isUserInteractionEnabled = true // Always allow user interaction
    }

    func setRegion(_ region: MKCoordinateRegion, animated: Bool) {
        // Only update region if it has changed significantly
        let current = mapView.region
        if current.isSignificantlyDifferent(from: region, threshold: 0.0005) {
            isProgrammaticChange = true
            mapView.setRegion(region, animated: animated)
        }
    }

    func setLocations(_ locations: [GPSLocation]) {
        if isUserInteracting {
            // Buffer locations while user is interacting
            bufferedLocations = locations
            return
        }
        updateMapWithLocations(locations)
    }

    func setIsAutoCentering(_ value: Bool) {
        isAutoCentering = value
        // If auto-centering is being enabled, reset user interaction state
        if value {
            isUserInteracting = false
            // Apply any buffered locations immediately
            if let buffered = bufferedLocations {
                updateMapWithLocations(buffered)
                bufferedLocations = nil
            }
        }
    }

    func setIsPaused(_ value: Bool) {
        isPaused = value
        // Update annotations visibility based on paused state
        updateAnnotationsVisibility()
    }

    private func updateMapWithLocations(_ locations: [GPSLocation]) {
        // Efficiently update overlays and annotations
        let grouped = Dictionary(grouping: locations, by: { $0.segmentId })
        let segmentIds = Set(grouped.keys)
        for (id, polyline) in overlays where !segmentIds.contains(id) {
            mapView.removeOverlay(polyline)
            overlays.removeValue(forKey: id)
        }
        let orderedSegments = grouped
            .map { (id: $0.key, locations: $0.value.sorted(by: { $0.timestamp < $1.timestamp })) }
            .sorted { $0.locations.first?.timestamp ?? .distantPast < $1.locations.first?.timestamp ?? .distantPast }

        for (index, segment) in orderedSegments.enumerated() {
            let coords = segment.locations.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
            if let polyline = overlays[segment.id] {
                mapView.removeOverlay(polyline)
            }
            if coords.count >= 2 {
                let polyline = MKPolyline(coordinates: coords, count: coords.count)
                polyline.title = "segment_\(index)"
                overlays[segment.id] = polyline
                mapView.addOverlay(polyline)
            }
        }
        // Only show annotation for the last location if not paused
        // Remove all existing annotations first
        for (_, annotation) in annotations {
            mapView.removeAnnotation(annotation)
        }
        annotations.removeAll()
        if let lastLocation = locations.last, !isPaused {
            let annotation = MKPointAnnotation()
            annotation.coordinate = CLLocationCoordinate2D(latitude: lastLocation.latitude, longitude: lastLocation.longitude)
            annotations[lastLocation.id] = annotation
            mapView.addAnnotation(annotation)
        }
    }

    private func updateAnnotationsVisibility() {
        if isPaused {
            // Hide all annotations when paused
            for (_, annotation) in annotations {
                mapView.removeAnnotation(annotation)
            }
        } else {
            // Show annotations when not paused (re-add them)
            for (_, annotation) in annotations {
                mapView.addAnnotation(annotation)
            }
        }
    }

    // MARK: - MKMapViewDelegate
    func mapView(_ mapView: MKMapView, regionWillChangeAnimated animated: Bool) {
        // Only call onUserInteraction if this is a user gesture
        if !isProgrammaticChange {
            isUserInteracting = true
            delegate?.regionDidChange(mapView.region, userInitiated: true)
        }
    }
    func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
        if isProgrammaticChange {
            isProgrammaticChange = false
            return
        }
        isUserInteracting = false
        // Apply buffered locations if any
        if let buffered = bufferedLocations {
            updateMapWithLocations(buffered)
            bufferedLocations = nil
        }
        delegate?.regionDidChange(mapView.region, userInitiated: false)
    }
    func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
        return MapRenderingHelpers.polylineRenderer(for: overlay)
    }
    func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
        let identifier = "GPSPoint"
        var annotationView = mapView.dequeueReusableAnnotationView(withIdentifier: identifier)
        if annotationView == nil {
            annotationView = MKAnnotationView(annotation: annotation, reuseIdentifier: identifier)
        } else {
            annotationView?.annotation = annotation
        }
        annotationView?.image = MapRenderingHelpers.cachedGlowingBlueDotImage()
        annotationView?.centerOffset = CGPoint(x: 0, y: 0)
        return annotationView
    }
    
    // MARK: - Touch Detection
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        
        guard let touch = touches.first else { return }
        let touchPoint = touch.location(in: mapView)
        let coordinate = mapView.convert(touchPoint, toCoordinateFrom: mapView)
        
        // Disable auto-centering when user touches the map
        if isAutoCentering {
            isAutoCentering = false
        }
        
        // Notify delegate about the touch immediately when finger touches down
        delegate?.mapTouched(at: coordinate, point: touchPoint)
    }
}
