//
//  PathPhoto.swift
//  PathRecorder
//
//  Created by Aparna Natarajan on 7/20/25.
//
import UIKit
import Foundation
import CoreLocation

// Model for storing photos taken during a path
struct PathPhoto: Identifiable, Codable, Hashable {
    let id: UUID
    let coordinate: CLLocationCoordinate2D
    let timestamp: Date
    let imageFilename: String // Store only filename, not image data

    init(coordinate: CLLocationCoordinate2D, timestamp: Date, image: UIImage, imageFilename: String) {
        self.id = UUID()
        self.coordinate = coordinate
        self.timestamp = timestamp
        self.imageFilename = imageFilename
        // Save image to disk when creating
        if let data = image.jpegData(compressionQuality: 0.9) {
            let url = PathPhoto.imagesDirectory.appendingPathComponent(imageFilename)
            try? data.write(to: url)
        }
    }

    var image: UIImage? {
        let url = PathPhoto.imagesDirectory.appendingPathComponent(imageFilename)
        return UIImage(contentsOfFile: url.path)
    }

    enum CodingKeys: String, CodingKey {
        case id, latitude, longitude, timestamp, imageFilename
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        let latitude = try container.decode(Double.self, forKey: .latitude)
        let longitude = try container.decode(Double.self, forKey: .longitude)
        coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        imageFilename = try container.decode(String.self, forKey: .imageFilename)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(coordinate.latitude, forKey: .latitude)
        try container.encode(coordinate.longitude, forKey: .longitude)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encode(imageFilename, forKey: .imageFilename)
    }
    static func == (lhs: PathPhoto, rhs: PathPhoto) -> Bool {
        return lhs.id == rhs.id &&
            lhs.coordinate.latitude == rhs.coordinate.latitude &&
            lhs.coordinate.longitude == rhs.coordinate.longitude &&
            lhs.timestamp == rhs.timestamp &&
            lhs.imageFilename == rhs.imageFilename
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(coordinate.latitude)
        hasher.combine(coordinate.longitude)
        hasher.combine(timestamp)
        hasher.combine(imageFilename)
    }

    // Directory for storing images
    static var imagesDirectory: URL {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        let dir = paths[0].appendingPathComponent("PathPhotos")
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }
}
