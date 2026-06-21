//
//  PathRecorderApp.swift
//  PathRecorder
//
//  Created by Brad Dettmer on 6/1/25.
//


import SwiftUI
import SwiftData
import UIKit

@main
struct PathRecorderApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate: AppDelegate
    @StateObject private var authManager = AuthManager()

    init() {
        // Run data migrations on app startup
        DataMigration.shared.runMigrations()
    }

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
    }
}
