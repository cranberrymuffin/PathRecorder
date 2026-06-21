import XCTest
@testable import PathRecorder

final class DataMigrationTests: XCTestCase {
    private var userDefaults: UserDefaults!
    private let suiteName = "DataMigrationTestsSuite"

    override func setUp() {
        super.setUp()
        userDefaults = UserDefaults(suiteName: suiteName)
        userDefaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        userDefaults.removePersistentDomain(forName: suiteName)
        userDefaults = nil
        super.tearDown()
    }

    func testMigrationConvertsOldRecordedPathToSegmentedFormat() throws {
        // Try to load an external fixture file inside the tests folder named "fixture.json".
        let cwd = FileManager.default.currentDirectoryPath
        let fixturePath = cwd + "/PathRecorder/PathRecorderTests/fixture.json"
        var oldPathsToEncode: [RecordedPathOldTest]

        if let data = FileManager.default.contents(atPath: fixturePath), !data.isEmpty {
            // If fixture exists, try decoding it as the old model (ISO-8601 timestamps)
            let fixtureDecoder = JSONDecoder()
            fixtureDecoder.dateDecodingStrategy = .iso8601
            oldPathsToEncode = try fixtureDecoder.decode([RecordedPathOldTest].self, from: data)
        } else {
            // Fallback: construct an inline legacy path as before
            let pathPhotos = [PathPhoto(timestamp: Date(), image: UIImage(), imageFilename: "pathPhoto.jpg")]
            let segmentPhoto = PathPhoto(timestamp: Date(), image: UIImage(), imageFilename: "segmentPhoto.jpg")

            let segmentId = UUID()
            let startTime = Date()
            let location1 = GPSLocationOldTest(
                id: UUID(),
                latitude: 37.7749,
                longitude: -122.4194,
                timestamp: startTime,
                segmentId: nil,
                photos: [segmentPhoto]
            )
            let location2 = GPSLocationOldTest(
                id: UUID(),
                latitude: 37.7750,
                longitude: -122.4195,
                timestamp: startTime.addingTimeInterval(60),
                segmentId: nil,
                photos: nil
            )
            let location3 = GPSLocationOldTest(
                id: UUID(),
                latitude: 37.7760,
                longitude: -122.4200,
                timestamp: startTime.addingTimeInterval(120),
                segmentId: segmentId,
                photos: nil
            )

            let oldPath = RecordedPathOldTest(
                id: UUID(),
                startTime: startTime,
                totalDuration: 120,
                totalDistance: 100,
                locations: [location1, location2, location3],
                photos: pathPhotos,
                name: "My Legacy Path"
            )

            oldPathsToEncode = [oldPath]
        }

        let encoder = JSONEncoder()
        userDefaults.set(try encoder.encode(oldPathsToEncode), forKey: "RecordedPaths")

        let migration = DataMigration(userDefaults: userDefaults)
        migration.runMigrations()

        XCTAssertTrue(userDefaults.bool(forKey: "DataMigrationV1Completed"))

        let migratedData = userDefaults.data(forKey: "RecordedPaths")
        XCTAssertNotNil(migratedData, "Migrated data should be written back to user defaults")

        let decoder = JSONDecoder()
        let migratedPaths = try decoder.decode([RecordedPath].self, from: migratedData!)

        XCTAssertEqual(migratedPaths.count, oldPathsToEncode.count)
        let migratedPath = migratedPaths[0]
        XCTAssertEqual(migratedPath.name, oldPathsToEncode[0].name)
        XCTAssertGreaterThanOrEqual(migratedPath.photos.count, 1)
        XCTAssertGreaterThanOrEqual(migratedPath.segments.count, 1)

        // Basic consistency checks
        let allTimestamps = migratedPath.locations.map { $0.timestamp }
        let originalTimestamps = oldPathsToEncode[0].locations.map { $0.timestamp }
        XCTAssertEqual(allTimestamps, originalTimestamps)
    }

    func testMigrationPreservesCoordinatesForLegacyLocationPhotos() throws {
        let locationPhoto = PathPhoto(timestamp: Date(), image: UIImage(), imageFilename: "segmentPhoto.jpg")
        let photoLatitude = 37.7749
        let photoLongitude = -122.4194

        let location = GPSLocationOldTest(
            id: UUID(),
            latitude: photoLatitude,
            longitude: photoLongitude,
            timestamp: Date(),
            segmentId: nil,
            photos: [locationPhoto]
        )

        let oldPath = RecordedPathOldTest(
            id: UUID(),
            startTime: Date(),
            totalDuration: 60,
            totalDistance: 10,
            locations: [location],
            photos: nil,
            name: "Legacy Photo Path"
        )

        let encoder = JSONEncoder()
        userDefaults.set(try encoder.encode([oldPath]), forKey: "RecordedPaths")

        let migration = DataMigration(userDefaults: userDefaults)
        migration.runMigrations()

        let migratedData = userDefaults.data(forKey: "RecordedPaths")
        XCTAssertNotNil(migratedData)

        let decoder = JSONDecoder()
        let migratedPaths = try decoder.decode([RecordedPath].self, from: migratedData!)
        let migratedPhoto = migratedPaths[0].photos.first(where: { $0.imageFilename == "segmentPhoto.jpg" })

        XCTAssertNotNil(migratedPhoto, "The location photo should still exist after migration")
        XCTAssertEqual(migratedPhoto?.locationId, location.id)
    }

}

private struct RecordedPathOldTest: Codable {
    let id: UUID
    let startTime: Date?
    let totalDuration: TimeInterval?
    let totalDistance: Double?
    let locations: [GPSLocationOldTest]
    let photos: [PathPhoto]?
    let name: String
}

private struct GPSLocationOldTest: Codable {
    let id: UUID
    let latitude: Double
    let longitude: Double
    let timestamp: Date
    let segmentId: UUID?
    let photos: [PathPhoto]?
}
