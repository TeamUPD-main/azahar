// Copyright Citra Emulator Project / Azahar Emulator Project
// Licensed under GPLv2 or any later version
// Refer to the license.txt file included.

import UIKit
import SwiftUI

/// App delegate for external display handling. This app is SwiftUI-driven; the
/// delegate provides the ExternalSceneDelegate for UIKit scene management.
final class AppDelegate: NSObject, UIApplicationDelegate {
    // No need to override application(_:configurationForConnecting:options:)
    // Let SwiftUI handle the default configuration
}

/// Handles the UIWindowScene that UIKit creates for a connected external
/// display. Mirrors the ManicEMU approach: a dedicated scene shows the
/// emulated screen(s) fullscreen while the main scene keeps running.
final class ExternalSceneDelegate: NSObject, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene else { return }

        // Only handle scenes that belong to an external display.
        guard windowScene.screen != UIScreen.main else { return }

        let manager = ExternalDisplayManager.shared

        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = UIHostingController(
            rootView: ExternalDisplayView(displayManager: manager)
        )
        window.isHidden = false

        self.window = window
        manager.externalWindow = window
        manager.externalScreen = windowScene.screen

        if !manager.isExternalDisplayConnected {
            manager.isExternalDisplayConnected = true
            manager.handleExternalDisplayConnected(windowScene.screen)
        } else {
            manager.applyDisplayMode()
        }
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        guard window?.windowScene === scene else { return }
        let manager = ExternalDisplayManager.shared
        window?.isHidden = true
        window = nil
        manager.externalWindow = nil
        manager.externalScreen = nil
        manager.isExternalDisplayConnected = false
        az_emu_secondary_surface_destroy()
        NotificationCenter.default.post(
            name: Notification.Name("ExternalDisplayModeChanged"),
            object: nil
        )
    }
}
