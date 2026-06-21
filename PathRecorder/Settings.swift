import Foundation
import SwiftUI
import UIKit
import Supabase

enum DistanceUnit: String, CaseIterable, Codable {
    case kilometers = "km"
    case miles = "mi"

    var displayName: String {
        switch self {
        case .kilometers:
            return "Kilometers"
        case .miles:
            return "Miles"
        }
    }

    var conversionFactor: Double {
        switch self {
        case .kilometers:
            return 1.0
        case .miles:
            return 0.621371 // Convert from meters to miles
        }
    }

    var unitLabel: String {
        switch self {
        case .kilometers:
            return "km"
        case .miles:
            return "mi"
        }
    }
}

class Settings: ObservableObject {
    @Published var distanceUnit: DistanceUnit {
        didSet {
            UserDefaults.standard.set(distanceUnit.rawValue, forKey: "distanceUnit")
        }
    }

    init() {
        if let savedUnit = UserDefaults.standard.string(forKey: "distanceUnit"),
           let unit = DistanceUnit(rawValue: savedUnit) {
            self.distanceUnit = unit
        } else {
            self.distanceUnit = .kilometers
        }
    }

    func convertDistance(_ meters: Double) -> Double {
        return meters / 1000 * distanceUnit.conversionFactor
    }

    func formatDistance(_ meters: Double) -> String {
        let convertedDistance = convertDistance(meters)
        return String(format: "%.2f %@", convertedDistance, distanceUnit.unitLabel)
    }
}

struct SettingsView: View {
    @ObservedObject var settings: Settings
    @ObservedObject var pathStorage: PathStorage
    @EnvironmentObject private var authManager: AuthManager
    @Environment(\.dismiss) private var dismiss
    // Sign-out
    @State private var isSigningOut = false
    @State private var backupSuccessMessage: String? = nil
    // Inline sign-in OTP flow
    @State private var authPhone = ""
    @State private var authOTP = ""
    @State private var didRequestOTP = false
    @State private var isSendingOTP = false
    @State private var isVerifyingOTP = false
    @State private var authErrorMessage: String? = nil

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Distance Units")) {
                    Picker("Distance Unit", selection: $settings.distanceUnit) {
                        ForEach(DistanceUnit.allCases, id: \.self) { unit in
                            Text(unit.displayName).tag(unit)
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())
                }
                Section(header: Text("Account")) {
                    if authManager.isAuthenticated {
                        HStack {
                            Text("Phone")
                            Spacer()
                            Text(authManager.displayPhone(for: authManager.currentUser))
                                .foregroundColor(.secondary)
                        }
                        Button {
                            Task { await uploadBackup() }
                        } label: {
                            if authManager.isUploadingBackup {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text("Backing up... \(Int(authManager.backupProgress * 100))%")
                                            .font(.subheadline)
                                        Spacer()
                                        if let remaining = estimatedTimeRemaining {
                                            Text(remaining)
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                    ProgressView(value: authManager.backupProgress)
                                }
                            } else {
                                HStack {
                                    Image(systemName: "icloud.and.arrow.up")
                                    Text("Backup to Cloud")
                                }
                            }
                        }
                        .disabled(authManager.isUploadingBackup)

                        Button(role: .destructive) {
                            Task { await signOut() }
                        } label: {
                            if isSigningOut {
                                HStack { ProgressView(); Text("Signing out...") }
                            } else {
                                Text("Sign Out")
                            }
                        }
                        .disabled(isSigningOut || authManager.isUploadingBackup)
                    } else {
                        TextField("+15551234567", text: $authPhone)
                            .keyboardType(.phonePad)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled(true)

                        Button(isSendingOTP ? "Sending..." : "Send Code") {
                            Task { await sendOTP() }
                        }
                        .disabled(isSendingOTP || authPhone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                        if didRequestOTP {
                            TextField("6-digit code", text: $authOTP)
                                .keyboardType(.numberPad)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled(true)

                            Button(isVerifyingOTP ? "Verifying..." : "Verify Code") {
                                Task { await verifyOTP() }
                            }
                            .disabled(isVerifyingOTP || authOTP.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                            Button("Resend Code") {
                                Task { await sendOTP() }
                            }
                            .disabled(isSendingOTP)
                        }

                        Text("Enter your phone number to sign in or create an account.")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .alert("Backup Saved", isPresented: .constant(backupSuccessMessage != nil)) {
            Button("OK") { backupSuccessMessage = nil }
        } message: {
            Text(backupSuccessMessage ?? "")
        }
        .alert("Auth Error", isPresented: .constant(authErrorMessage != nil)) {
            Button("OK") {
                authErrorMessage = nil
            }
        } message: {
            Text(authErrorMessage ?? "Unknown error")
        }
    }

    private var estimatedTimeRemaining: String? {
        guard let start = authManager.backupStartTime,
              authManager.backupProgress > 0.05 else { return nil }
        let elapsed = Date().timeIntervalSince(start)
        let total = elapsed / authManager.backupProgress
        let remaining = total - elapsed
        guard remaining > 1 else { return nil }
        return "~\(Int(remaining.rounded()))s remaining"
    }

    private func uploadBackup() async {
        guard let userId = authManager.currentUser?.id else {
            authErrorMessage = "Not signed in."
            return
        }
        authManager.isUploadingBackup = true
        authManager.backupProgress = 0.0
        authManager.backupStartTime = Date()
        defer {
            authManager.isUploadingBackup = false
            authManager.backupProgress = 0.0
            authManager.backupStartTime = nil
        }
        do {
            struct PathRow: Encodable {
                let id: UUID
                let user_id: UUID
                let name: String
                let created_at: Date
            }
            struct SegmentRow: Encodable {
                let id: UUID
                let path_id: UUID
            }
            struct LocationRow: Encodable {
                let id: UUID
                let segment_id: UUID
                let latitude: Double
                let longitude: Double
                let timestamp: Date
            }
            struct PhotoRow: Encodable {
                let id: UUID
                let user_id: UUID
                let location_id: UUID
                let timestamp: Date
                let storage_path: String
            }

            var pathRows: [PathRow] = []
            var segmentRows: [SegmentRow] = []
            var locationRows: [LocationRow] = []
            var photoRows: [PhotoRow] = []

            let totalPhotos = pathStorage.recordedPaths.reduce(0) { $0 + $1.photos.count }
            var uploadedPhotos = 0
            for path in pathStorage.recordedPaths {
                pathRows.append(PathRow(
                    id: path.id,
                    user_id: userId,
                    name: path.name,
                    created_at: path.startTime
                ))

                for segment in path.segments {
                    segmentRows.append(SegmentRow(id: segment.id, path_id: path.id))
                    for location in segment.locations {
                        locationRows.append(LocationRow(
                            id: location.id,
                            segment_id: segment.id,
                            latitude: location.latitude,
                            longitude: location.longitude,
                            timestamp: location.timestamp
                        ))
                    }
                }

                for photo in path.photos {
                    let storagePath = "\(userId.uuidString.lowercased())/\(photo.id.uuidString.lowercased()).jpg"
                    guard let image = photo.image,
                          let jpegData = image.jpegData(compressionQuality: 0.9) else { continue }
                    try await supabase.storage
                        .from("path-photos")
                        .upload(storagePath, data: jpegData, options: FileOptions(contentType: "image/jpeg", upsert: true))
                    uploadedPhotos += 1
                    if totalPhotos > 0 {
                        authManager.backupProgress = Double(uploadedPhotos) / Double(totalPhotos)
                    }
                    photoRows.append(PhotoRow(
                        id: photo.id,
                        user_id: userId,
                        location_id: photo.locationId,
                        timestamp: photo.timestamp,
                        storage_path: storagePath
                    ))
                }
            }

            if !pathRows.isEmpty {
                try await supabase.from("paths").upsert(pathRows, onConflict: "id").execute()
            }
            if !segmentRows.isEmpty {
                try await supabase.from("path_segments").upsert(segmentRows, onConflict: "id").execute()
            }
            if !locationRows.isEmpty {
                try await supabase.from("gps_locations").upsert(locationRows, onConflict: "id").execute()
            }
            if !photoRows.isEmpty {
                try await supabase.from("path_photos").upsert(photoRows, onConflict: "id").execute()
            }

            backupSuccessMessage = "Your data has been backed up to the cloud."
        } catch {
            authErrorMessage = error.localizedDescription
        }
    }

    private func signOut() async {
        isSigningOut = true
        defer { isSigningOut = false }
        do {
            try await authManager.signOut()
        } catch {
            authErrorMessage = error.localizedDescription
        }
    }

    private func sendOTP() async {
        isSendingOTP = true
        authErrorMessage = nil
        defer { isSendingOTP = false }
        do {
            try await authManager.requestOTP(phone: authPhone)
            didRequestOTP = true
        } catch {
            authErrorMessage = error.localizedDescription
        }
    }

    private func verifyOTP() async {
        isVerifyingOTP = true
        authErrorMessage = nil
        defer { isVerifyingOTP = false }
        do {
            try await authManager.verifyOTP(phone: authPhone, token: authOTP)
            authOTP = ""
            didRequestOTP = false
        } catch {
            authErrorMessage = error.localizedDescription
        }
    }


}

// MARK: - Color <-> Hex helpers

extension Color {
    func toHexString() -> String {
        let uiColor = UIColor(self)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        let rgb: Int = (Int)(red*255)<<16 | (Int)(green*255)<<8 | (Int)(blue*255)<<0
        return String(format: "%06x", rgb)
    }

    static func fromHexString(_ hex: String) -> Color? {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")
        var rgb: UInt64 = 0
        guard Scanner(string: hexSanitized).scanHexInt64(&rgb) else { return nil }
        let r = Double((rgb & 0xFF0000) >> 16) / 255.0
        let g = Double((rgb & 0x00FF00) >> 8) / 255.0
        let b = Double(rgb & 0x0000FF) / 255.0
        return Color(red: r, green: g, blue: b)
    }
}
