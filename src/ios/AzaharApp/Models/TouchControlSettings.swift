// Copyright Citra Emulator Project / Azahar Emulator Project
// Licensed under GPLv2 or any later version
// Refer to the license.txt file included.

import Foundation
import UIKit

/// Touch control layout settings (matches Android InputOverlay logic)
struct TouchControlSettings: Codable {
    // Button scales (0.0 - 2.0, default based on Android)
    var faceButtonScale: CGFloat = 0.5      // A/B/X/Y (50% of screen min dimension)
    var dpadScale: CGFloat = 0.5            // D-Pad
    var triggerScale: CGFloat = 0.7         // L/R/ZL/ZR (70%)
    var joystickScale: CGFloat = 0.7        // Circle Pad / C-Stick (70%)
    var centerButtonScale: CGFloat = 0.4    // Start/Select/Home
    
    // Button positions (0.0 - 1.0 as fraction of screen)
    // Landscape layout
    var landscapePositions: [String: CGPoint] = [:]
    
    // Portrait layout
    var portraitPositions: [String: CGPoint] = [:]
    
    // Button opacity (0.0 - 1.0)
    var buttonOpacity: CGFloat = 0.7
    
    // Edit mode enabled
    var isEditModeEnabled: Bool = false
    
    static let shared = TouchControlSettings()
    
    private static let userDefaultsKey = "TouchControlSettings"
    
    static func load() -> TouchControlSettings {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey),
              let settings = try? JSONDecoder().decode(TouchControlSettings.self, from: data) else {
            return TouchControlSettings()
        }
        return settings
    }
    
    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.userDefaultsKey)
        }
    }
    
    func resetToDefaults() {
        let settings = TouchControlSettings()
        settings.save()
    }
    
    /// Calculate button size based on Android algorithm
    /// Android: min(screenWidth, screenHeight) * scale
    func buttonSize(for type: ButtonType, screenSize: CGSize) -> CGFloat {
        let minDimension = min(screenSize.width, screenSize.height)
        let scale: CGFloat
        
        switch type {
        case .faceButton:
            scale = faceButtonScale
        case .dpad:
            scale = dpadScale
        case .trigger:
            scale = triggerScale
        case .joystick:
            scale = joystickScale
        case .centerButton:
            scale = centerButtonScale
        }
        
        return minDimension * scale
    }
    
    enum ButtonType {
        case faceButton  // A, B, X, Y
        case dpad
        case trigger     // L, R, ZL, ZR
        case joystick    // Circle Pad, C-Stick
        case centerButton // Start, Select, Home
    }
}
