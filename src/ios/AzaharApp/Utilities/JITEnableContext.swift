// Copyright Citra Emulator Project / Azahar Emulator Project
// Licensed under GPLv2 or any later version
// Refer to the license.txt file included.

import Foundation

/// Singleton managing StikDebug integration for on-device JIT enablement
@MainActor
class JITEnableContext: ObservableObject {
    static let shared = JITEnableContext()
    
    @Published var lastError: String?
    
    private init() {
        // Check if we have TXM support
        detectTXMCapability()
    }
    
    // MARK: - StikDebug Integration
    
    /// Trigger StikDebug to enable JIT for Azahar
    func enableJITViaStikDebug() {
        let bundleID = String(cString: get_current_bundle_id())
        
        if let url = URL(string: "stikdebug://enable-jit?bundle-id=\(bundleID)") {
            UIApplication.shared.open(url) { success in
                if success {
                    print("[JIT] Triggered StikDebug for JIT enablement")
                } else {
                    print("[JIT] StikDebug not available - please install it")
                    Task { @MainActor in
                        self.lastError = "StikDebug not installed. Please install StikDebug from GitHub."
                    }
                }
            }
        }
    }
    
    /// Open StikDebug app
    func openStikDebug() {
        enableJITViaStikDebug()
    }
    
    /// Open StikDebug GitHub releases page
    func openStikDebugDownload() {
        if let url = URL(string: "https://github.com/BomberFish/StikDebug/releases") {
            UIApplication.shared.open(url)
        }
    }
    
    // MARK: - System Information
    
    /// Get current process ID
    func getCurrentPID() -> Int32 {
        return get_current_pid()
    }
    
    /// Get current bundle identifier
    func getCurrentBundleID() -> String {
        return String(cString: get_current_bundle_id())
    }
    
    /// Get iOS version string
    func getIOSVersion() -> String {
        let os = ProcessInfo.processInfo.operatingSystemVersion
        return "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)"
    }
    
    // MARK: - TXM Detection
    
    @Published var hasTXM = false
    
    private func detectTXMCapability() {
        // Check for TXM firmware files
        // iOS 27 with A13/A14/M1 chips requires special handling
        let prebootPaths = [
            "/System/Volumes/Preboot",
            "/private/preboot"
        ]
        
        for basePath in prebootPaths {
            let fileManager = FileManager.default
            
            guard fileManager.fileExists(atPath: basePath) else { continue }
            
            do {
                let contents = try fileManager.contentsOfDirectory(atPath: basePath)
                
                for uuid in contents {
                    // iOS 27 fix: Check for TXM in multiple locations
                    let paths = [
                        "\(basePath)/\(uuid)/boot/usr/standalone/firmware/FUD/Ap,TrustedExecutionMonitor.img4",
                        "\(basePath)/\(uuid)/usr/standalone/firmware/FUD/Ap,TrustedExecutionMonitor.img4",
                        // iOS 27 A13/A14/M1 fix: Additional TXM locations
                        "\(basePath)/\(uuid)/boot/usr/standalone/firmware/Ap,TrustedExecutionMonitor.img4",
                        "\(basePath)/\(uuid)/usr/standalone/firmware/Ap,TrustedExecutionMonitor.img4"
                    ]
                    
                    for path in paths {
                        if fileManager.fileExists(atPath: path) {
                            hasTXM = true
                            print("[JIT] TXM detected at: \(path)")
                            return
                        }
                    }
                }
            } catch {
                continue
            }
        }
        
        print("[JIT] TXM not detected - advanced JIT features may be limited")
    }
}

// MARK: - C Bridge Functions

// These are declared in azahar_ios.h and implemented in the C++ bridge
@_silgen_name("get_current_pid")
func get_current_pid() -> Int32

@_silgen_name("get_current_bundle_id")
func get_current_bundle_id() -> UnsafePointer<CChar>
