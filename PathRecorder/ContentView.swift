//
//  ContentView.swift
//  PathRecorder
//
//  Created by Brad Dettmer on 6/1/25.
//

import SwiftUI
import SwiftData
import CoreLocation
import Shared // Import the module if needed
import StoreKit

struct ContentView: View {
    private let rateAlertKey = "PathRecorder.HasShownRateAlert"
    // Computed property for sort order label
    var sortOrderLabel: String {
        switch selectedSortField {
        case .date:
            return sortAscending ? "Least recent" : "Most recent"
        case .time:
            return sortAscending ? "Shortest first" : "Longest first"
        case .distance:
            return sortAscending ? "Shortest first" : "Longest first"
        case .pace:
            return sortAscending ? "Fastest first" : "Slowest first"
        }
    }
    @StateObject private var locationManager = LocationManager()
    @StateObject private var pathStorage = PathStorage()
    @StateObject private var settings = Settings()
    @State private var showRecordingSheet = false
    @State private var selectedPathForRename: RecordedPath? = nil
    @State private var navigationPath = NavigationPath()
    @State private var showRenameSheet = false
    @State private var showLocationAlert = false
    @State private var showSettingsSheet = false

    enum SortField: String, CaseIterable, Identifiable {
        case date = "Date"
        case pace = "Pace"
        case time = "Time"
        case distance = "Distance"
        var id: String { rawValue }
    }
    @State private var selectedSortField: SortField = .date
    @State private var sortAscending: Bool = false

    var body: some View {
        NavigationStack(path: $navigationPath) {
            VStack(spacing: 10) {
                Text("No history yet — start recording to track your journeys.")
                    .font(.headline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, maxHeight: pathStorage.recordedPaths.isEmpty ? .infinity : 0, alignment: .center)
                    .opacity(pathStorage.recordedPaths.isEmpty ? 1 : 0)

                if pathStorage.recordedPaths.count > 1 {
                    HStack {
                        Menu {
                            Picker("Sort by", selection: $selectedSortField) {
                                ForEach(SortField.allCases) { field in
                                    Text(field.rawValue).tag(field)
                                }
                            }
                        } label: {
                            Text("Sort by \(selectedSortField.rawValue)")
                        }
                        .font(.subheadline)
                        Spacer()
                        Button(action: {
                            sortAscending.toggle()
                        }) {
                            Text(sortOrderLabel)
                        }
                        .font(.subheadline)
                    }
                    .padding(.horizontal)
                }

                List {
                    ForEach(sortedPaths) { path in
                        RecordedPathRow(
                            path: path,
                            onEdit: {
                                showRecordingSheet = true
                                locationManager.loadPathForEditing(path, pathStorage: pathStorage)
                            },
                            onDelete: {
                                pathStorage.deletePath(id: path.id)
                            },
                            formatTime: formatTime,
                            onSelect: {
                                navigationPath.append(path)
                            },
                            settings: settings
                        )
                        .environmentObject(locationManager)
                    }
                }
                .listStyle(.plain)

                Button(action: {
                    if locationManager.authorizationStatus == .authorizedAlways || locationManager.authorizationStatus == .authorizedWhenInUse {
                        locationManager.startRecording()
                        showRecordingSheet = true
                    } else {
                        showLocationAlert = true
                    }
                }) {
                    Text("Start Recording")
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.green)
                        .cornerRadius(10)
                }
                .padding(.horizontal)
                .alert("Location Access Needed", isPresented: $showLocationAlert) {
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                    Button("Cancel", role: .cancel) { }
                } message: {
                    Text("To record your path, please allow location access in Settings.")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding()
            .onAppear {
                locationManager.requestPermission()
                // Automatically show recording view if in-progress recording exists
                if locationManager.isRecording && locationManager.isPaused {
                    showRecordingSheet = true
                }
                // Show StoreKit review prompt if more than 3 recordings and not shown before
                let hasShownRateAlert = UserDefaults.standard.bool(forKey: rateAlertKey)
                if pathStorage.recordedPaths.count >= 3 && !hasShownRateAlert {
                    if let windowScene = UIApplication.shared.connectedScenes.first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene {
                        AppStore.requestReview(in: windowScene)
                    }
                    UserDefaults.standard.set(true, forKey: rateAlertKey)
                }
            }
            .onReceive(locationManager.$pathToNavigateTo) { path in
                if let path = path {
                    selectedPathForRename = path
                    navigationPath.append(path)
                    showRenameSheet = locationManager.editingPathName == nil
                }
            }
            .fullScreenCover(isPresented: Binding(
                get: { showRecordingSheet },
                set: { newValue in
                    if !newValue {
                        showRecordingSheet = false
                    }
                })
            ) {
                RecordingView(
                    locationManager: locationManager,
                    pathStorage: pathStorage,
                    settings: settings,
                    onStop: {
                        showRecordingSheet = false
                    }
                )
            }
            .navigationTitle("Recorded Paths")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        showSettingsSheet = true
                    }) {
                        Image(systemName: "gear")
                    }
                }
            }
            .sheet(isPresented: $showSettingsSheet) {
                SettingsView(settings: settings)
            }
            .navigationDestination(for: RecordedPath.self) { path in
                PathMapView(
                    recordedPath: path, 
                    locationManager: locationManager, 
                    pathStorage: pathStorage, 
                    settings: settings,
                    showRenameSheetOnAppear: showRenameSheet,
                    onModifyPath: {
                        showRecordingSheet = true
                    }
                )
                .onAppear {
                    showRenameSheet = false
                }
            }
        }
    }

    // Computed property for sorted paths
    var sortedPaths: [RecordedPath] {
        let paths = pathStorage.recordedPaths
        switch selectedSortField {
        case .date:
            return paths.sorted { sortAscending ? $0.startTime < $1.startTime : $0.startTime > $1.startTime }
        case .pace:
            // Lower pace = faster, so ascending = fastest first
            return paths.sorted {
                let pace0 = computePaceValue(distanceMeters: $0.totalDistance, elapsedSeconds: $0.totalDuration)
                let pace1 = computePaceValue(distanceMeters: $1.totalDistance, elapsedSeconds: $1.totalDuration)
                return sortAscending ? pace0 < pace1 : pace0 > pace1
            }
        case .time:
            return paths.sorted { sortAscending ? $0.totalDuration < $1.totalDuration : $0.totalDuration > $1.totalDuration }
        case .distance:
            return paths.sorted { sortAscending ? $0.totalDistance < $1.totalDistance : $0.totalDistance > $1.totalDistance }
        }
    }

    // Helper to get pace as seconds per meter (or per km/mi, but for sorting, use SI)
    func computePaceValue(distanceMeters: Double, elapsedSeconds: Double) -> Double {
        guard distanceMeters > 0 else { return Double.greatestFiniteMagnitude }
        return elapsedSeconds / distanceMeters
    }

    private func formatTime(_ timeInterval: TimeInterval) -> String {
        let hours = Int(timeInterval) / 3600
        let minutes = Int(timeInterval) / 60 % 60
        let seconds = Int(timeInterval) % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }
}

struct RecordedPathRow: View {
    let path: RecordedPath
    let onEdit: () -> Void
    let onDelete: () -> Void
    let formatTime: (TimeInterval) -> String
    let onSelect: () -> Void
    let settings: Settings
    @EnvironmentObject private var locationManager: LocationManager
    @State private var showLocationAlert = false

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 5) {
                Text(path.name)
                    .font(.headline)
                HStack(spacing: 6) {
                    Image(systemName: "calendar")
                        .foregroundColor(.red)
                        .font(.subheadline)
                    Text(DateFormatter.localizedString(from: path.startTime, dateStyle: .medium, timeStyle: .short))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                HStack(spacing: 12) {
                    HStack(spacing: 6) {
                        Image(systemName: "figure.walk")
                            .foregroundColor(.green)
                            .font(.subheadline)
                        Text(settings.formatDistance(path.totalDistance))
                    }
                    HStack(spacing: 6) {
                        Image(systemName: "alarm")
                            .foregroundColor(.orange)
                            .font(.subheadline)
                        Text(formatTime(path.totalDuration))
                    }
                    HStack(spacing: 6) {
                        Image(systemName: "timer")
                            .foregroundColor(.blue)
                            .font(.subheadline)
                        Text(computePace(distanceMeters: path.totalDistance, elapsedSeconds: path.totalDuration, unit: settings.distanceUnit.rawValue))
                    }
                }
                .font(.subheadline)
                .foregroundColor(.secondary)
            }
            .padding(.vertical, 5)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
            .tint(.purple)
            Button(action: {
                if locationManager.authorizationStatus == .authorizedAlways || locationManager.authorizationStatus == .authorizedWhenInUse {
                    onEdit()
                } else {
                    showLocationAlert = true
                }
            }) {
                Label("Resume", systemImage: "pencil")
            }
            .tint(.blue)
        }
        .alert("Location Access Needed", isPresented: $showLocationAlert) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("To record your path, please allow location access in Settings.")
        }
    }
}
