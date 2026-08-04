// Copyright Citra Emulator Project / Azahar Emulator Project
// Licensed under GPLv2 or any later version
// Refer to the license.txt file included.

import Foundation
import GameController

/// Monitors game controller connection status to auto-hide on-screen controls
class ControllerManager: ObservableObject {
    static let shared = ControllerManager()
    
    @Published var isControllerConnected = false
    
    private init() {
        setupNotifications()
        checkInitialControllers()
    }
    
    private func setupNotifications() {
        NotificationCenter.default.addObserver(
            forName: .GCControllerDidConnect,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateControllerStatus()
        }
        
        NotificationCenter.default.addObserver(
            forName: .GCControllerDidDisconnect,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateControllerStatus()
        }
    }
    
    private func checkInitialControllers() {
        updateControllerStatus()
    }
    
    private func updateControllerStatus() {
        isControllerConnected = !GCController.controllers().isEmpty
        AppLogger.info("[ControllerManager] Controller connected: \(isControllerConnected)")
    }
}
