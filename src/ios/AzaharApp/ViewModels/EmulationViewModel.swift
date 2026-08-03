// Copyright Citra Emulator Project / Azahar Emulator Project
// Licensed under GPLv2 or any later version
// Refer to the license.txt file included.

import Foundation
import SwiftUI

/// Manages the emulation lifecycle on a background thread.
/// (Equivalent to the Android EmulationViewModel + EmulationFragment interaction.)
@MainActor
final class EmulationViewModel: ObservableObject {
    @Published var isRunning = false
    @Published var isPaused = false
    @Published var showPerfStats = false
    @Published var turboEnabled = false
    @Published var gameTitle = ""
    @Published var perfStatsText = ""
    @Published var leftStickPosition: CGPoint = .zero
    @Published var rightStickPosition: CGPoint = .zero
    @Published var isControlsVisible = true
    @Published var isLoading = false

    private let game: Game
    private var emulationThread: Task<Void, Never>?
    private var perfTimer: Timer?

    init(game: Game) {
        self.game = game
        self.gameTitle = game.title
    }

    func startEmulation() {
        guard !isRunning else { return }
        isLoading = true
        isRunning = true
        isPaused = false

        // Resolve launch path. Empty path means boot to Home Menu.
        let path: String
        if game.path.isEmpty {
            let region = Int32(az_setting_get_int("System", "region_value", 0))
            path = String(cString: az_get_home_menu_path(region))
            if path.isEmpty {
                isRunning = false
                isLoading = false
                gameTitle = "Home Menu not installed"
                return
            }
        } else {
            path = game.path
        }

        emulationThread = Task.detached(priority: .userInitiated) {
            // Wait until surface is set. 
            // In a production app, use a proper ConditionVariable or async stream.
            // For now, poll briefly.
            while !az_is_surface_set() {
                try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
            }

            // Hide loading screen after a brief delay (allows icon to display)
            try? await Task.sleep(nanoseconds: 500_000_000) // 500ms
            await MainActor.run {
                self.isLoading = false
            }

            az_run(path)

            await MainActor.run {
                self.isRunning = false
            }
        }

        // Start performance stats timer
        perfTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updatePerfStats()
            }
        }
    }

    func stop() {
        az_stop_emulation()
        emulationThread?.cancel()
        emulationThread = nil
        perfTimer?.invalidate()
        perfTimer = nil
        isRunning = false
        isLoading = false
    }

    func togglePause() {
        if isPaused {
            resume()
        } else {
            pause()
        }
    }

    func pause() {
        az_pause_emulation()
        isPaused = true
    }

    func resume() {
        az_unpause_emulation()
        isPaused = false
    }

    func saveState(slot: Int) {
        az_save_state(Int32(slot))
    }

    func loadState(slot: Int) {
        az_load_state(Int32(slot))
    }

    func cycleLayout() {
        let current = az_setting_get_int("Layout", "layout_option", 2)
        let next = (current + 1) % 6
        az_setting_set_int("Layout", "layout_option", next)
        az_update_framebuffer(UIScreen.main.bounds.height > UIScreen.main.bounds.width)
    }

    func toggleTurbo() {
        turboEnabled.toggle()
        if turboEnabled {
            az_set_temporary_frame_limit(200)
        } else {
            az_disable_temporary_frame_limit()
        }
    }

    func togglePerfStats() {
        showPerfStats.toggle()
    }

    private func updatePerfStats() {
        guard isRunning, showPerfStats else { return }
        var stats = [Double](repeating: 0, count: 9)
        az_get_perf_stats(&stats)
        perfStatsText = String(format: "%.0f fps / %.0f%%", stats[1], stats[2] * 100)
    }

    deinit {
        Task { @MainActor [weak self] in
            self?.perfTimer?.invalidate()
        }
    }
}
