import Foundation
import CoreLocation
import ActivityKit

// Import the PathRecorderAttributes from the Shared folder
import struct Shared.PathRecorderAttributes

class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var capturedPhotos: [PathPhoto] = []
    func addPhoto(_ photo: PathPhoto) {
        capturedPhotos.append(photo)
        saveRecordingState()
    }

    /// Snapshots the current GPS position into the recorded path and returns its id.
    /// Call this at the moment a photo is captured so the photo has a precise location pin.
    func recordPhotoLocation() -> UUID? {
        guard let current = currentLocation else { return nil }
        let gpsLocation = GPSLocation(
            latitude: current.coordinate.latitude,
            longitude: current.coordinate.longitude,
            timestamp: current.timestamp,
            segmentId: currentSegmentId
        )
        locations.append(gpsLocation)
        saveRecordingState()
        return gpsLocation.id
    }
    private let locationManager = CLLocationManager()
    @Published var locations: [GPSLocation] = []
    @Published var isRecording = false
    @Published var isPaused = false
    @Published var totalDistance: Double = 0
    @Published var startTime: Date?
    @Published var elapsedTime: TimeInterval = 0
    @Published var currentLocation: CLLocation?
    @Published var currentActivity: Activity<PathRecorderAttributes>?
    @Published var editingPathId: UUID? = nil
    @Published var editingPathName: String? = nil
    @Published var pathToNavigateTo: RecordedPath? = nil // Track path to navigate to after recording
    
    // Properties for improved distance calculation
    private var lastProcessedTime: Date?
    private var lastProcessedLocation: CLLocation?
    private var recentLocations: [CLLocation] = [] // For moving average calculation
    private let minAccuracy: CLLocationAccuracy = 20.0 // Accuracy threshold in meters
    private let minDistance: Double = 2.0 // Minimum distance in meters
    private let minTimeInterval: TimeInterval = 2.0 // Minimum seconds between location updates
    private let maxLocationsForAverage: Int = 3 // Number of locations to use for moving average
    
    // Track recording segments for proper line drawing
    private var currentSegmentId: UUID = UUID()
    
    private var activityUpdateTimer: Timer?
    private var lastTimerUpdate: Date?
    
    // MARK: - Persistence Keys
    private let recordingStateKey = "PathRecorder.RecordingState"

    struct RecordingState: Codable {
        let locations: [GPSLocation]
        let totalDistance: Double
        let elapsedTime: TimeInterval
        let startTime: Date?
        let isPaused: Bool
        let editingPathId: UUID?
        let editingPathName: String?
        let photos: [PathPhoto]
    }

    // MARK: - Persistence Methods
    private func saveRecordingState() {
        let state = RecordingState(
            locations: self.locations,
            totalDistance: self.totalDistance,
            elapsedTime: self.elapsedTime,
            startTime: self.startTime,
            isPaused: self.isPaused,
            editingPathId: self.editingPathId,
            editingPathName: self.editingPathName,
            photos: self.capturedPhotos
        )
        if let data = try? JSONEncoder().encode(state) {
            UserDefaults.standard.set(data, forKey: recordingStateKey)
        }
    }

    // Appends the current location as the final GPSLocation for the segment
    private func markSegment() {
        if let finalLocation = self.currentLocation {
            let gpsLocation = GPSLocation(
                latitude: finalLocation.coordinate.latitude,
                longitude: finalLocation.coordinate.longitude,
                timestamp: finalLocation.timestamp,
                segmentId: self.currentSegmentId
            )
            self.locations.append(gpsLocation)
        }
    }

    private func loadRecordingStateIfNeeded() {
        guard let data = UserDefaults.standard.data(forKey: recordingStateKey),
              let state = try? JSONDecoder().decode(RecordingState.self, from: data),
              !state.locations.isEmpty else { return }
        self.locations = state.locations
        self.totalDistance = state.totalDistance
        self.elapsedTime = state.elapsedTime
        self.startTime = state.startTime
        self.isPaused = true // Always restore to paused state
        self.isRecording = true
        self.currentSegmentId = UUID()
        self.editingPathId = state.editingPathId // Restore editingPathId
        self.editingPathName = state.editingPathName // Restore editingPathName
        self.capturedPhotos = state.photos
        // Clear current location to prevent showing stale location annotation
        self.currentLocation = nil
        print("Restored in-progress recording from disk")
        // Don't start location updates immediately - wait for user to resume
        // locationManager.startUpdatingLocation()
        self.startLiveActivity()
    }

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        // End any orphaned activities and restore the first available one
        Task {
            self.endLiveActivity()
            // Wait briefly for cleanup
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1s
            if let existingActivity = Activity<PathRecorderAttributes>.activities.first {
                await MainActor.run {
                    self.currentActivity = existingActivity
                }
                print("Restored existing Live Activity with ID: \(existingActivity.id)")
            }
        }
        loadRecordingStateIfNeeded()
    }
    
    func requestPermission() {
        locationManager.requestAlwaysAuthorization()
    }

    func startRecording() {
        locations.removeAll()
        totalDistance = 0
        startTime = Date()
        elapsedTime = 0
        lastProcessedLocation = nil
        currentSegmentId = UUID() // Start a new segment
        isRecording = true
        isPaused = false
        self.editingPathId = nil
        self.editingPathName = nil
        locationManager.startUpdatingLocation()
        self.markSegment() // Ensure segment starts with a coordinate
        startLiveActivity()
        // Start a timer to update elapsed time and Live Activity every second
        startActivityTimer()
    }
    
    func stopRecording(pathStorage: PathStorage) {        // Save the current path before stopping if pathStorage is provided
        // Ensure UI updates happen on main thread
        DispatchQueue.main.async {
            self.markSegment()
            self.isRecording = false
            self.isPaused = false
            self.locationManager.stopUpdatingLocation()
            // Stop and invalidate the timer
            self.stopActivityTimer()
            self.endLiveActivity()
            self.saveCurrentPath(to: pathStorage)
            UserDefaults.standard.removeObject(forKey: self.recordingStateKey) // Clear saved state
        }
    }
    
    func pauseRecording() {
        guard isRecording && !isPaused else { return }
        DispatchQueue.main.async {
            self.markSegment()
            self.isPaused = true
            self.locationManager.stopUpdatingLocation()
            // Stop the timer when pausing
            self.stopActivityTimer()
            // Update Live Activity to show paused state
            self.updateLiveActivity()
            self.saveRecordingState() // Save when paused
        }
    }
    
    func resumeRecording() {
        guard isRecording && isPaused else { return }
        
        DispatchQueue.main.async {
            self.isPaused = false
            // Reset only the smoothing data, keep the recorded path
            self.lastProcessedTime = nil
            self.lastProcessedLocation = nil
            self.recentLocations.removeAll()
            // Start a new segment when resuming; assign the segment ID before location updates begin
            self.currentSegmentId = UUID()
            self.locationManager.startUpdatingLocation()
            // Do not duplicate the last paused location in the new segment.
            // Subsequent location updates will belong to this new segment.
            // Recreate the timer when resuming
            self.startActivityTimer()
            // Update Live Activity to show resumed state
            self.updateLiveActivity()
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        
        // Ensure updates happen on the main thread
        DispatchQueue.main.async {
            self.currentLocation = location

            if !self.isRecording || self.isPaused { return }
        
            // Filter location by accuracy
            if location.horizontalAccuracy > self.minAccuracy {
                print("Skipping location due to poor accuracy: \(location.horizontalAccuracy)m")
                return
            }

            // Time-based filtering
            if let lastTime = self.lastProcessedTime,
               location.timestamp.timeIntervalSince(lastTime) < self.minTimeInterval {
                print("Skipping location - too soon after last update")
                return
            }
            
            // Update the last processed time
            self.lastProcessedTime = location.timestamp
            
            // Add to recent locations for moving average (limited to maxLocationsForAverage)
            self.recentLocations.append(location)
            if self.recentLocations.count > self.maxLocationsForAverage {
                self.recentLocations.removeFirst()
            }
            
            let avgLocation = self.calculateAverageLocation(self.recentLocations)
        
            // Create the GPS location from the averaged coordinates
            let gpsLocation = GPSLocation(
                latitude: avgLocation.coordinate.latitude,
                longitude: avgLocation.coordinate.longitude,
                timestamp: location.timestamp,
                segmentId: self.currentSegmentId
            )
            self.locations.append(gpsLocation)

            // Compare with previous location (if exists)
            if self.lastProcessedLocation != nil {
                // Calculate distance to previous location
                let distance = avgLocation.distance(from: self.lastProcessedLocation!)
                
                // Only record if we've moved at least minDistance
                if distance >= self.minDistance {
                    self.totalDistance += distance
                    print("Distance added: \(distance)m, Total: \(self.totalDistance)m")
                } else {
                    print("Skipping - distance too small: \(distance)m")
                }
            }
            // This is the first location, just add it
            self.lastProcessedLocation = avgLocation
            print("Location recorded")
            
            self.saveRecordingState() // Save after each update
            self.updateLiveActivity()
        }
    }
    
    // Helper method to calculate the average location from a set of locations
    private func calculateAverageLocation(_ locations: [CLLocation]) -> CLLocation {
        guard !locations.isEmpty else { return CLLocation() }
        
        // Calculate average latitude and longitude
        var totalLat: Double = 0
        var totalLong: Double = 0
        
        for location in locations {
            totalLat += location.coordinate.latitude
            totalLong += location.coordinate.longitude
        }
        
        let avgLat = totalLat / Double(locations.count)
        let avgLong = totalLong / Double(locations.count)
        
        return CLLocation(latitude: avgLat, longitude: avgLong)
    }
    
    // MARK: - Live Activity Methods
    private func startLiveActivity() {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            print("Live Activities not available or not enabled")
            return
        }
        // End any existing activity first to avoid duplicates
        endLiveActivity()
        // Add a small delay to ensure cleanup is complete
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            // Assign first available activity if any
            if let existingActivity = Activity<PathRecorderAttributes>.activities.first {
                self.currentActivity = existingActivity
                print("Live Activity already exists, not creating a new one.")
                return
            }
            let unit = UserDefaults.standard.string(forKey: "distanceUnit") ?? "km"
            let initialState = PathRecorderAttributes.ContentState(
                latitude: self.currentLocation?.coordinate.latitude ?? 0,
                longitude: self.currentLocation?.coordinate.longitude ?? 0,
                distance: self.totalDistance,
                elapsedTime: self.elapsedTime,
                isPaused: self.isPaused,
                distanceUnit: unit
            )
            let attributes = PathRecorderAttributes()
            do {
                let content = ActivityContent(state: initialState, staleDate: nil)
                self.currentActivity = try Activity.request(
                    attributes: attributes,
                    content: content,
                    pushType: nil
                )
                print("Live Activity started successfully with ID: \(self.currentActivity?.id ?? "unknown")")
            } catch {
                print("Error starting live activity: \(error.localizedDescription)")
                if let error = error as NSError? {
                    print("Error domain: \(error.domain), code: \(error.code)")
                    print("Error userInfo: \(error.userInfo)")
                }
            }
        }
    }
    
    private func updateLiveActivity() {
        Task {
            guard let activity = currentActivity else { 
                print("No active Live Activity to update")
                return 
            }

            // Capture values from main thread
            let (currentElapsedTime, isPausedState, unit) = await MainActor.run {
                let unit = UserDefaults.standard.string(forKey: "distanceUnit") ?? "km"
                return (self.elapsedTime, self.isPaused, unit)
            }

            let updatedState = PathRecorderAttributes.ContentState(
                latitude: currentLocation?.coordinate.latitude ?? 0,
                longitude: currentLocation?.coordinate.longitude ?? 0,
                distance: self.totalDistance,
                elapsedTime: currentElapsedTime,
                isPaused: isPausedState,
                distanceUnit: unit
            )

            let content = ActivityContent(state: updatedState, staleDate: nil)
            await activity.update(content)
            print("Live Activity updated successfully")
        }
    }
    
    private func endLiveActivity() {
        Task {
            guard let activity = currentActivity else { 
                print("No active Live Activity to end")
                return 
            }
            
            print("Ending Live Activity with ID: \(activity.id)")
            
            // Capture current values on the main thread
            let (lat, long, dist, time) = await MainActor.run {
                return (
                    self.currentLocation?.coordinate.latitude ?? 0,
                    self.currentLocation?.coordinate.longitude ?? 0,
                    self.totalDistance,
                    self.elapsedTime
                )
            }
            
            let finalState = PathRecorderAttributes.ContentState(
                latitude: lat,
                longitude: long,
                distance: dist,
                elapsedTime: time,
                isPaused: false
            )
            
            let finalContent = ActivityContent(state: finalState, staleDate: nil)
            await activity.end(finalContent, dismissalPolicy: .immediate)
            print("Live Activity ended successfully")
            
            // Update this property on the main thread
            await MainActor.run {
                self.currentActivity = nil
            }
        }
    }
    
    // MARK: - Timer Management
    private func startActivityTimer() {
        lastTimerUpdate = Date()
        activityUpdateTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            DispatchQueue.main.async {
                let now = Date()
                if let lastUpdate = self.lastTimerUpdate {
                    // Add the actual time interval since last update
                    let actualInterval = now.timeIntervalSince(lastUpdate)
                    self.elapsedTime += actualInterval
                }
                self.lastTimerUpdate = now
                self.updateLiveActivity()
            }
        }
    }
    
    private func stopActivityTimer() {
        activityUpdateTimer?.invalidate()
        activityUpdateTimer = nil
        lastTimerUpdate = nil
    }

    func loadPathForEditing(_ path: RecordedPath, pathStorage: PathStorage) {
        guard !isRecording else {
            print("Cannot load path for editing while recording is active")
            return
        }

        // Flatten segments back to locations for editing
        self.locations = path.segments.flatMap { $0.locations }
        self.totalDistance = path.totalDistance
        self.elapsedTime = path.totalDuration
        self.startTime = path.startTime
        self.editingPathName = path.name

        // Set up recording state for editing
        self.isRecording = true
        self.isPaused = true // Start in paused state as requested
        self.editingPathId = path.id
        
        // Restore all photos associated with the selected path
        self.capturedPhotos = path.photos
        
        // Clear current location to prevent showing stale location annotation
        self.currentLocation = nil
        // Set up for continuing the path
        self.currentSegmentId = UUID() // New segment for continuation
        
        // Start Live Activity immediately with the correct initial values
        self.startLiveActivity()
        
        // Automatically resume when editing the path
        self.resumeRecording()
        
        print("Loaded existing path for editing - Distance: \(totalDistance)m, Duration: \(elapsedTime)s")
    }
    
    func saveCurrentPath(to pathStorage: PathStorage) {
        guard let startTime = startTime else { return }

        if (editingPathId != nil) {
            // If editing, delete the old path immediately after loading for editing
            pathStorage.deletePath(id: editingPathId!)
        }

        // Group locations by segmentId to create PathSegments
        let groupedBySegment = Dictionary(grouping: locations) { $0.segmentId }
        let segments = groupedBySegment
            .sorted { segments1, segments2 in
                (segments1.value.first?.timestamp ?? Date()) < (segments2.value.first?.timestamp ?? Date())
            }
            .map { _, groupedLocations in
                let sortedLocations = groupedLocations.sorted { $0.timestamp < $1.timestamp }
                return PathSegment(locations: sortedLocations)
            }

        // Create new path with segments and preserve captured photos
        let recordedPath = RecordedPath(segments: segments, name: editingPathName, photos: capturedPhotos)
        pathStorage.savePath(recordedPath)
        capturedPhotos.removeAll()

        // Always navigate to the path, but only show rename sheet if name is nil
        DispatchQueue.main.async {
            self.pathToNavigateTo = recordedPath
        }
    }
    
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedAlways:
            print("location authorized always")
            // Enable background location updates when authorized
            locationManager.allowsBackgroundLocationUpdates = true
            locationManager.showsBackgroundLocationIndicator = true
        case .authorizedWhenInUse:
            print("location authorized when in use")
            // Background updates not available, disable them
            locationManager.allowsBackgroundLocationUpdates = false
            locationManager.showsBackgroundLocationIndicator = false
        case .denied:
            print("location denied")
            locationManager.allowsBackgroundLocationUpdates = false
            locationManager.showsBackgroundLocationIndicator = false
        case .restricted:
            print("location restricted")
            locationManager.allowsBackgroundLocationUpdates = false
            locationManager.showsBackgroundLocationIndicator = false
        case .notDetermined:
            print("location not determined")
        @unknown default:
            print("location unknown status")
        }
    }
    
    var lastRecordedLocation: CLLocation? {
        locations.last.map { CLLocation(latitude: $0.latitude, longitude: $0.longitude) }
    }
    
    var authorizationStatus: CLAuthorizationStatus {
        return locationManager.authorizationStatus
    }
}
