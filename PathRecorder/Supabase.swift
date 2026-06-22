//
//  Supabase.swift
//  PathRecorder
//
//  Created by Aparna Natarajan on 3/14/26.
//


import Supabase
import SwiftUI

let supabase = SupabaseClient(
  supabaseURL: URL(string: "https://hsbnabtalqugbwspdhnq.supabase.co")!,
  supabaseKey: "sb_publishable_plix2vRBUgoocyW2QacrVA_tqPYIO-M"
)

@MainActor
final class AuthManager: ObservableObject {
  @Published var currentUser: User?
  @Published var isLoadingSession = true
  @Published var isUploadingBackup = false
  @Published var backupProgress: Double = 0.0
  @Published var backupStartTime: Date? = nil
  @Published var isRestoringFromCloud = false
  @Published var restoreProgress: Double = 0.0
  @Published var unsyncedPathIds: Set<UUID> = []
  @Published var dirtyPathIds: Set<UUID> = []
  var hasUnsyncedPaths: Bool { !unsyncedPathIds.isEmpty || !dirtyPathIds.isEmpty }

  private var authListenerTask: Task<Void, Never>?

  var isAuthenticated: Bool {
    currentUser != nil
  }

  init() {
    authListenerTask = Task {
      for await (_, session) in await supabase.auth.authStateChanges {
        self.currentUser = session?.user
        self.isLoadingSession = false
      }
    }

    Task {
      await restoreSession()
    }
  }

  deinit {
    authListenerTask?.cancel()
  }

  func restoreSession() async {
    do {
      let session = try await supabase.auth.session
      currentUser = session.user
    } catch {
      currentUser = nil
    }
    isLoadingSession = false
  }

  /// Sends an SMS OTP. Creates the user if they don't exist yet, so this
  /// doubles as both sign-in and sign-up.
  func requestOTP(phone: String) async throws {
    let normalizedPhone = normalized(phone: phone)
    guard !normalizedPhone.isEmpty else {
      throw AuthFlowError.invalidPhone
    }

    try await supabase.auth.signInWithOTP(
      phone: normalizedPhone,
      shouldCreateUser: true
    )
  }

  func verifyOTP(phone: String, token: String) async throws {
    let normalizedPhone = normalized(phone: phone)
    let normalizedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)

    guard !normalizedPhone.isEmpty else {
      throw AuthFlowError.invalidPhone
    }

    guard !normalizedToken.isEmpty else {
      throw AuthFlowError.invalidOTP
    }

    _ = try await supabase.auth.verifyOTP(
      phone: normalizedPhone,
      token: normalizedToken,
      type: .sms
    )
  }

  func signOut() async throws {
    try await supabase.auth.signOut()
    currentUser = nil
  }

  func displayPhone(for user: User?) -> String {
    user?.phone ?? "Unknown"
  }

  private func normalized(phone: String) -> String {
    phone
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .replacingOccurrences(of: " ", with: "")
  }

  // MARK: - Cloud Delete

  func deleteFromCloud(pathId: UUID, photoIds: [UUID]) async {
    guard let userId = currentUser?.id else { return }
    let storagePaths = photoIds.map { "\(userId.uuidString.lowercased())/\($0.uuidString.lowercased()).jpg" }
    if !storagePaths.isEmpty {
      try? await supabase.storage.from("path-photos").remove(paths: storagePaths)
    }
    try? await supabase.from("paths").delete().eq("id", value: pathId).execute()
  }

  // MARK: - Cloud Sync

  func syncOnLogin(pathStorage: PathStorage) async {
    guard let userId = currentUser?.id else { return }
    struct ServerPathId: Decodable { let id: UUID }
    guard let entries: [ServerPathId] = try? await supabase
      .from("paths").select("id").eq("user_id", value: userId)
      .execute().value else { return }

    let serverIds = Set(entries.map { $0.id })
    let localIds = Set(pathStorage.recordedPaths.map { $0.id })

    let toRestore = Array(serverIds.subtracting(localIds))
    if !toRestore.isEmpty {
      print("[Restore] \(toRestore.count) paths to restore from cloud")
      isRestoringFromCloud = true
      restoreProgress = 0.0
      await restorePaths(ids: toRestore, pathStorage: pathStorage)
      isRestoringFromCloud = false
      restoreProgress = 0.0
    }

    let updatedLocalIds = Set(pathStorage.recordedPaths.map { $0.id })
    await MainActor.run { unsyncedPathIds = updatedLocalIds.subtracting(serverIds) }
  }

  func refreshSyncStatus(localPaths: [RecordedPath]) async {
    guard let userId = currentUser?.id else {
      await MainActor.run { unsyncedPathIds = [] }
      return
    }
    struct ServerPathId: Decodable { let id: UUID }
    guard let entries: [ServerPathId] = try? await supabase
      .from("paths").select("id").eq("user_id", value: userId)
      .execute().value else { return }
    let serverIds = Set(entries.map { $0.id })
    let localIds = Set(localPaths.map { $0.id })
    await MainActor.run { unsyncedPathIds = localIds.subtracting(serverIds) }
  }

  private func restorePaths(ids: [UUID], pathStorage: PathStorage) async {
    let totalCount = ids.count
    var restoredCount = 0
    struct ServerPhoto: Decodable {
      let id: UUID; let timestamp: Date; let storage_path: String
    }
    struct ServerLocation: Decodable {
      let id: UUID; let latitude: Double; let longitude: Double
      let timestamp: Date; let path_photos: [ServerPhoto]
    }
    struct ServerSegment: Decodable {
      let id: UUID; let gps_locations: [ServerLocation]
    }
    struct ServerPath: Decodable {
      let id: UUID; let name: String; let path_segments: [ServerSegment]
    }

    // Batch into chunks of 30 to avoid PostgREST URL length limits
    let chunkSize = 30
    let chunks = stride(from: 0, to: ids.count, by: chunkSize).map {
      Array(ids[$0..<min($0 + chunkSize, ids.count)])
    }

    for chunk in chunks {
      let idStrings = chunk.map { $0.uuidString.lowercased() }
      let paths: [ServerPath]
      do {
        paths = try await supabase
          .from("paths")
          .select("id, name, path_segments(id, gps_locations(id, latitude, longitude, timestamp, path_photos(id, timestamp, storage_path)))")
          .in("id", values: idStrings)
          .execute().value
      } catch {
        print("[Restore] ❌ chunk fetch failed: \(error)")
        continue
      }
      print("[Restore] fetched \(paths.count) paths")

      for path in paths {
        let allLocations = path.path_segments.flatMap { $0.gps_locations }
        let allPhotos = allLocations.flatMap { $0.path_photos }

        for photo in allPhotos {
          let filename = "\(photo.id.uuidString.lowercased()).jpg"
          let url = PathPhoto.imagesDirectory.appendingPathComponent(filename)
          guard !FileManager.default.fileExists(atPath: url.path) else { continue }
          do {
            let data = try await supabase.storage
              .from("path-photos").download(path: photo.storage_path)
            try? data.write(to: url)
          } catch {
            print("[Restore]   ⚠️ photo download failed: \(error)")
          }
        }

        let segments = path.path_segments.map { seg -> PathSegment in
          let locs = seg.gps_locations
            .sorted { $0.timestamp < $1.timestamp }
            .map { GPSLocation(id: $0.id, latitude: $0.latitude, longitude: $0.longitude,
                               timestamp: $0.timestamp, segmentId: seg.id) }
          return PathSegment(id: seg.id, locations: locs)
        }.sorted { $0.startTime < $1.startTime }

        let photos = allLocations.flatMap { loc in
          loc.path_photos.map {
            PathPhoto(id: $0.id, timestamp: $0.timestamp,
                      imageFilename: "\($0.id.uuidString.lowercased()).jpg",
                      locationId: loc.id)
          }
        }

        let recordedPath = RecordedPath(id: path.id, segments: segments,
                                        name: path.name, photos: photos)
        restoredCount += 1
        let progress = Double(restoredCount) / Double(totalCount)
        print("[Restore] ✓ '\(path.name)': \(segments.count) segs, \(allLocations.count) locs, \(photos.count) photos (\(restoredCount)/\(totalCount))")
        await MainActor.run {
          pathStorage.savePath(recordedPath)
          self.restoreProgress = progress
        }
      }
    }
  }
}

enum AuthFlowError: LocalizedError {
  case invalidPhone
  case invalidOTP

  var errorDescription: String? {
    switch self {
    case .invalidPhone:
      return "Enter a valid phone number in E.164 format (example: +15551234567)."
    case .invalidOTP:
      return "Enter the OTP code sent to your phone."
    }
  }
}


