// Copyright Citra Emulator Project / Azahar Emulator Project
// Licensed under GPLv2 or any later version
// Refer to the license.txt file included.

import UIKit
import SwiftUI
import QuartzCore

/// Manages external displays (AirPlay, HDMI, USB-C) for dual-screen 3DS emulation
class ExternalDisplayManager: ObservableObject {
    static let shared = ExternalDisplayManager()
    
    @Published var isExternalDisplayConnected = false
    @Published var externalScreen: UIScreen?
    @Published var externalWindow: UIWindow?
    @Published var displayMode: ExternalDisplayMode = .topScreenExternal
    
    private var screenNotificationObserver: NSObjectProtocol?
    
    enum ExternalDisplayMode: Int, CaseIterable {
        case topScreenExternal = 0      // Top screen on external, bottom on iPhone
        case bottomScreenExternal = 1   // Bottom screen on external, top on iPhone
        case mirrorBothScreens = 2      // Both screens mirrored on external and iPhone
        case externalFullscreen = 3     // Full dual-screen on external only
        
        var displayName: String {
            switch self {
            case .topScreenExternal:
                return "Top Screen on TV/Monitor"
            case .bottomScreenExternal:
                return "Bottom Screen on TV/Monitor"
            case .mirrorBothScreens:
                return "Mirror Both Screens"
            case .externalFullscreen:
                return "Full Display on TV/Monitor"
            }
        }
        
        var description: String {
            switch self {
            case .topScreenExternal:
                return "3DS top screen on external display, bottom screen on iPhone with touch controls"
            case .bottomScreenExternal:
                return "3DS bottom screen on external display, top screen on iPhone"
            case .mirrorBothScreens:
                return "Both screens shown on external and iPhone"
            case .externalFullscreen:
                return "Both screens on external display only, iPhone shows controls"
            }
        }
    }
    
    private init() {
        setupScreenNotifications()
        checkForExternalDisplay()
    }
    
    private func setupScreenNotifications() {
        // Monitor for external display connection/disconnection
        NotificationCenter.default.addObserver(
            forName: UIScreen.didConnectNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let screen = notification.object as? UIScreen else { return }
            self?.handleExternalDisplayConnected(screen)
        }
        
        NotificationCenter.default.addObserver(
            forName: UIScreen.didDisconnectNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleExternalDisplayDisconnected()
        }
    }
    
    private func checkForExternalDisplay() {
        // Check if there's already an external screen connected
        if UIScreen.screens.count > 1 {
            handleExternalDisplayConnected(UIScreen.screens[1])
        }
    }
    
    private func handleExternalDisplayConnected(_ screen: UIScreen) {
        print("External display connected: \(screen.bounds)")
        
        externalScreen = screen
        isExternalDisplayConnected = true
        
        // Set preferred display mode for best quality
        if let mode = screen.availableModes.max(by: { $0.size.width < $1.size.width }) {
            screen.currentMode = mode
        }
        
        // Load saved display mode preference
        let savedMode = UserDefaults.standard.integer(forKey: "external_display_mode")
        if let mode = ExternalDisplayMode(rawValue: savedMode) {
            displayMode = mode
        }
        
        // Apply the layout based on display mode
        applyDisplayMode()
    }
    
    private func handleExternalDisplayDisconnected() {
        print("External display disconnected")
        
        // Clean up external window
        externalWindow?.isHidden = true
        externalWindow = nil
        externalScreen = nil
        isExternalDisplayConnected = false
        
        // Destroy secondary surface
        az_emu_secondary_surface_destroy()
    }
    
    func setDisplayMode(_ mode: ExternalDisplayMode) {
        displayMode = mode
        UserDefaults.standard.set(mode.rawValue, forKey: "external_display_mode")
        
        if isExternalDisplayConnected {
            applyDisplayMode()
        }
    }
    
    private func applyDisplayMode() {
        guard let screen = externalScreen else { return }
        
        // Update the bridge setting for secondary display layout
        // 0 = separate windows (top on external)
        // 1 = bottom on external
        // 2 = both screens on external
        switch displayMode {
        case .topScreenExternal:
            az_setting_set_int("Layout", "secondary_display_layout", 0)
        case .bottomScreenExternal:
            az_setting_set_int("Layout", "secondary_display_layout", 1)
        case .mirrorBothScreens, .externalFullscreen:
            az_setting_set_int("Layout", "secondary_display_layout", 2)
        }
        
        // Create or update external window if needed
        setupExternalWindow(on: screen)
    }
    
    private func setupExternalWindow(on screen: UIScreen) {
        // Remove old window if exists
        externalWindow?.isHidden = true
        externalWindow = nil
        
        // Create new window for external display
        let window = UIWindow(frame: screen.bounds)
        window.screen = screen
        
        // Create a hosting controller with MetalView for external display
        let hostingController = UIHostingController(
            rootView: ExternalDisplayView(displayManager: self)
        )
        
        window.rootViewController = hostingController
        window.isHidden = false
        
        externalWindow = window
        
        print("External window setup complete: \(screen.bounds)")
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}

/// View shown on the external display (AirPlay/HDMI)
struct ExternalDisplayView: View {
    @ObservedObject var displayManager: ExternalDisplayManager
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            ExternalMetalView()
                .ignoresSafeArea()
            
            // Optional: Show display mode indicator briefly
            VStack {
                Spacer()
                Text(displayManager.displayMode.displayName)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.5))
                    .padding(8)
                    .background(.black.opacity(0.3))
                    .clipShape(Capsule())
                    .padding(.bottom, 20)
            }
        }
    }
}

/// Metal view for external display rendering
struct ExternalMetalView: UIViewRepresentable {
    func makeUIView(context: Context) -> ExternalMetalUIView {
        ExternalMetalUIView()
    }
    
    func updateUIView(_ uiView: ExternalMetalUIView, context: Context) {
        // Update if needed
    }
}

/// UIKit view for external display's Metal layer
final class ExternalMetalUIView: UIView {
    private var displayLink: CADisplayLink?
    private var isSurfaceSet = false
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupLayer()
        startPresenting()
    }
    
    required init?(coder: NSCoder) {
        fatalError()
    }
    
    override class var layerClass: AnyClass {
        CAMetalLayer.self
    }
    
    private var metalLayer: CAMetalLayer {
        layer as! CAMetalLayer
    }
    
    private func setupLayer() {
        metalLayer.device = MTLCreateSystemDefaultDevice()
        metalLayer.pixelFormat = .bgra8Unorm
        metalLayer.framebufferOnly = true
        
        // Use external screen's scale
        if let screen = window?.screen {
            metalLayer.contentsScale = screen.scale
        } else {
            metalLayer.contentsScale = UIScreen.main.scale
        }
        
        metalLayer.drawableSize = bounds.size
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        metalLayer.frame = bounds
        
        if let screen = window?.screen {
            metalLayer.contentsScale = screen.scale
        }
        
        metalLayer.drawableSize = bounds.size
        
        if isSurfaceSet {
            let scale = Float(metalLayer.contentsScale)
            az_emu_secondary_surface_set(
                Unmanaged.passUnretained(metalLayer).toOpaque(),
                scale
            )
        }
    }
    
    func startPresenting() {
        guard !isSurfaceSet else { return }
        
        let scale = Float(metalLayer.contentsScale)
        az_emu_secondary_surface_set(
            Unmanaged.passUnretained(metalLayer).toOpaque(),
            scale
        )
        isSurfaceSet = true
        
        print("External Metal surface set with scale: \(scale)")
    }
    
    func stopPresenting() {
        isSurfaceSet = false
        az_emu_secondary_surface_destroy()
    }
    
    deinit {
        stopPresenting()
    }
}
