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
    let timestamp: Date
    let imageFilename: String
    let locationId: UUID

    init(timestamp: Date, image: UIImage, imageFilename: String, locationId: UUID) {
        self.id = UUID()
        self.timestamp = timestamp
        self.imageFilename = imageFilename
        self.locationId = locationId
        if let data = image.jpegData(compressionQuality: 0.9) {
            let url = PathPhoto.imagesDirectory.appendingPathComponent(imageFilename)
            try? data.write(to: url)
        }
    }

    init(id: UUID, timestamp: Date, imageFilename: String, locationId: UUID) {
        self.id = id
        self.timestamp = timestamp
        self.imageFilename = imageFilename
        self.locationId = locationId
    }

    var image: UIImage? {
        let url = PathPhoto.imagesDirectory.appendingPathComponent(imageFilename)
        return UIImage(contentsOfFile: url.path)
    }

    static func == (lhs: PathPhoto, rhs: PathPhoto) -> Bool {
        return lhs.id == rhs.id &&
            lhs.timestamp == rhs.timestamp &&
            lhs.imageFilename == rhs.imageFilename &&
            lhs.locationId == rhs.locationId
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(timestamp)
        hasher.combine(imageFilename)
        hasher.combine(locationId)
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
