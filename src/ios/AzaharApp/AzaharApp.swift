// Copyright Citra Emulator Project / Azahar Emulator Project
// Licensed under GPLv2 or any later version
// Refer to the license.txt file included.

import SwiftUI

@main
struct AzaharApp: App {
    @StateObject private var appState = AppState()
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("autoEnableJIT") private var autoEnableJIT = false
    @AppStorage("useStikDebug") private var useStikDebug = true

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
                .onAppear {
                    appState.initialize()
                    
                    // Auto-enable JIT on first launch if configured
                    if autoEnableJIT {
                        Task {
                            await appState.enableJITIfNeeded()
                        }
                    }
                }
                .onChange(of: scenePhase) { oldPhase, newPhase in
                    handleScenePhaseChange(oldPhase: oldPhase, newPhase: newPhase)
                }
        }
    }
    
    private func handleScenePhaseChange(oldPhase: ScenePhase, newPhase: ScenePhase) {
        switch newPhase {
        case .active:
            // App became active (foreground)
            print("[Lifecycle] App active")
            
            // Re-enable JIT if configured and coming from background
            if autoEnableJIT && oldPhase == .background {
                Task {
                    await appState.enableJITIfNeeded()
                }
            }
            
        case .inactive:
            // App becoming inactive (e.g., during transition)
            print("[Lifecycle] App inactive")
            
        case .background:
            // App went to background
            print("[Lifecycle] App background")
            
        @unknown default:
            break
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
    
    private var jitEnableAttempted = false

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

        // Create ROMs directory in Documents
        let romsPath = (documentsPath as NSString).appendingPathComponent("ROMs")
        try? FileManager.default.createDirectory(
            atPath: romsPath,
            withIntermediateDirectories: true
        )

        scanGames()
    }
    
    /// Enable JIT if not already attempted
    func enableJITIfNeeded() async {
        guard !jitEnableAttempted else { return }
        jitEnableAttempted = true
        
        // Check if using StikDebug method
        let useStikDebug = UserDefaults.standard.bool(forKey: "useStikDebug")
        
        if useStikDebug {
            // Try to trigger StikDebug via URL scheme
            if let url = URL(string: "stikdebug://enable-jit?bundle-id=org.azahar_emu.Azahar") {
                await MainActor.run {
                    UIApplication.shared.open(url) { success in
                        if success {
                            print("[JIT] Triggered StikDebug for JIT enablement")
                        } else {
                            print("[JIT] StikDebug not available - please install it")
                        }
                    }
                }
            }
        } else {
            // Use built-in JIT enablement (experimental)
            let context = JITEnableContext.shared
            
            // Only attempt if connected
            guard context.isConnected && context.isDDIMounted else {
                print("[JIT] Not connected or DDI not mounted - skipping auto-enable")
                return
            }
            
            do {
                try context.enableJITForSelf { message in
                    print("[JIT] \(message)")
                }
                print("[JIT] Successfully enabled JIT for Azahar")
            } catch {
                print("[JIT] Failed to enable JIT: \(error)")
            }
        }
    }

    func scanGames() {
        games = GameScanner.scan(userDirectory: NSSearchPathForDirectoriesInDomains(
            .documentDirectory, .userDomainMask, true
        ).first ?? "")
    }

    func importROM(from sourceURL: URL) {
        guard sourceURL.startAccessingSecurityScopedResource() else {
            print("Failed to access security scoped resource")
            return
        }
        defer { sourceURL.stopAccessingSecurityScopedResource() }

        let documentsPath = NSSearchPathForDirectoriesInDomains(
            .documentDirectory, .userDomainMask, true
        ).first ?? ""
        let romsPath = (documentsPath as NSString).appendingPathComponent("ROMs")
        let destinationURL = URL(fileURLWithPath: romsPath)
            .appendingPathComponent(sourceURL.lastPathComponent)

        do {
            // Create ROMs directory if it doesn't exist
            try FileManager.default.createDirectory(
                at: URL(fileURLWithPath: romsPath),
                withIntermediateDirectories: true
            )
            
            // Copy the ROM file
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }
            try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
            print("Imported ROM: \(destinationURL.lastPathComponent)")
        } catch {
            print("Failed to import ROM: \(error)")
        }
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
