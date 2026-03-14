import Foundation
import SwiftUI
import UIKit

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
    @Environment(\.dismiss) private var dismiss
    @State private var exportURL: URL? = nil
    @State private var showingShare = false

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
                Section(header: Text("Export")) {
                    Button(action: {
                        if let url = pathStorage.exportJSONToTemporaryFile() {
                            exportURL = url
                            showingShare = true
                        }
                    }) {
                        HStack {
                            Image(systemName: "square.and.arrow.up")
                            Text("Export JSON")
                        }
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
        .sheet(isPresented: $showingShare) {
            if let url = exportURL {
                ActivityView(activityItems: [url])
            } else {
                EmptyView()
            }
        }
    }

    // Activity view wrapper for sharing the exported file
    struct ActivityView: UIViewControllerRepresentable {
        let activityItems: [Any]

        func makeUIViewController(context: Context) -> UIActivityViewController {
            UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
        }

        func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
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
