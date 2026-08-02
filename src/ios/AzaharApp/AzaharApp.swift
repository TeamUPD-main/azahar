// Copyright Citra Emulator Project / Azahar Emulator Project
// Licensed under GPLv2 or any later version
// Refer to the license.txt file included.

import SwiftUI

@main
struct AzaharApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
                .onAppear {
                    appState.initialize()
                }
        }
    }
}

/// Top-level observable state for the application.
@MainActor
final class AppState: ObservableObject {
    @Published var games: [Game] = []
    @Published var isEmulating = false
    @Published var currentGame: Game?
    @Published var showingSettings = false
    @Published var showingDocumentPicker = false

    func initialize() {
        let documentsPath = NSSearchPathForDirectoriesInDomains(
            .documentDirectory, .userDomainMask, true
        ).first ?? ""

        // Initialize core
        az_create_log_file()
        az_set_user_directory(documentsPath)
        az_create_config_file()
        az_log_device_info()
        az_play_time_init()

        scanGames()
    }

    func scanGames() {
        games = GameScanner.scan(userDirectory: NSSearchPathForDirectoriesInDomains(
            .documentDirectory, .userDomainMask, true
        ).first ?? "")
    }

    func launchGame(_ game: Game) {
        currentGame = game
        isEmulating = true
    }

    func stopEmulation() {
        az_stop_emulation()
        isEmulating = false
        currentGame = nil
    }
}
