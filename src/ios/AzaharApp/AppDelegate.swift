// Copyright Citra Emulator Project / Azahar Emulator Project
// Licensed under GPLv2 or any later version
// Refer to the license.txt file included.

import UIKit
import SwiftUI

/// App delegate for scene configuration. This app is SwiftUI-driven; the
/// delegate only intercepts scene connections so that external displays
/// (AirPlay/HDMI/USB-C) get their own window scene delegate.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        // External displays get their own scene delegate so we can render
        // the 3DS screen(s) fullscreen on them.
        // Check if the screen is not the main screen to identify external display
        if let windowScene = connectingSceneSession.scene as? UIWindowScene,
           windowScene.screen != UIScreen.main {
            let configuration = UISceneConfiguration(
                name: "External Display Configuration",
                sessionRole: connectingSceneSession.role
            )
            configuration.delegateClass = ExternalSceneDelegate.self
            return configuration
        }

        // Return the existing configuration for the main scene
        return connectingSceneSession.configuration
    }
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
