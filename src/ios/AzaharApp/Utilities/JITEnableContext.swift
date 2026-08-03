// Copyright Citra Emulator Project / Azahar Emulator Project
// Licensed under GPLv2 or any later version
// Refer to the license.txt file included.

import Foundation

/// Type alias for logging callbacks
typealias LogFunc = (String) -> Void

/// Type alias for debug callbacks (used when TXM is available for JS execution)
typealias DebugAppCallback = (
    _ pid: Int32,
    _ debugProxy: OpaquePointer?,
    _ remoteServer: OpaquePointer?,
    _ semaphore: DispatchSemaphore
) -> Void

/// Singleton managing on-device JIT enablement via idevice FFI
@MainActor
class JITEnableContext: ObservableObject {
    static let shared = JITEnableContext()
    
    @Published var isConnected = false
    @Published var isDDIMounted = false
    @Published var lastError: String?
    
    private var adapter: idevice_adapter_t?
    private var handshake: idevice_handshake_t?
    
    private init() {
        // Check if we have TXM support
        detectTXMCapability()
    }
    
    deinit {
        if let adapter = adapter {
            stop_tunnel(adapter)
        }
    }
    
    // MARK: - Connection Management
    
    /// Start the loopback tunnel to device services
    /// - Parameter pairingFilePath: Path to .mobiledevicepairing file
    func startTunnel(pairingFilePath: String) throws {
        guard !isConnected else { return }
        
        var newAdapter: idevice_adapter_t?
        var newHandshake: idevice_handshake_t?
        
        let result = start_tunnel(pairingFilePath, &newAdapter, &newHandshake)
        
        guard result == IDEVICE_SUCCESS else {
            throw JITError.connectionFailed("Failed to start tunnel: \(result.rawValue)")
        }
        
        self.adapter = newAdapter
        self.handshake = newHandshake
        self.isConnected = true
        
        print("[JITEnableContext] Tunnel started successfully")
    }
    
    /// Stop the tunnel connection
    func disconnect() {
        if let adapter = adapter {
            stop_tunnel(adapter)
            self.adapter = nil
            self.handshake = nil
            self.isConnected = false
            print("[JITEnableContext] Tunnel stopped")
        }
    }
    
    // MARK: - DDI Management
    
    /// Mount the Developer Disk Image (required for debugging on iOS 17+)
    func mountDDI(imagePath: String, signaturePath: String, trustcachePath: String, logger: LogFunc? = nil) throws {
        guard let adapter = adapter, let handshake = handshake else {
            throw JITError.notConnected
        }
        
        // Check if already mounted
        if is_developer_image_mounted(adapter, handshake) {
            isDDIMounted = true
            logger?("[JIT] DDI already mounted")
            return
        }
        
        let logCallback: idevice_log_func? = logger != nil ? { messagePtr in
            guard let messagePtr = messagePtr else { return }
            let message = String(cString: messagePtr)
            DispatchQueue.main.async {
                logger?(message)
            }
        } : nil
        
        let result = mount_developer_image(adapter, handshake, imagePath, signaturePath, trustcachePath, logCallback)
        
        guard result == IDEVICE_SUCCESS else {
            throw JITError.mountFailed("Failed to mount DDI: \(result.rawValue)")
        }
        
        isDDIMounted = true
        logger?("[JIT] DDI mounted successfully")
    }
    
    // MARK: - JIT Enablement
    
    /// Enable JIT for a specific app by bundle ID
    func debugApp(withBundleID bundleID: String, logger: LogFunc? = nil, jsCallback: DebugAppCallback? = nil) throws {
        guard let adapter = adapter, let handshake = handshake else {
            throw JITError.notConnected
        }
        
        let logCallback: idevice_log_func? = logger != nil ? { messagePtr in
            guard let messagePtr = messagePtr else { return }
            let message = String(cString: messagePtr)
            DispatchQueue.main.async {
                logger?(message)
            }
        } : nil
        
        var debugCallback: idevice_debug_callback? = nil
        var semaphorePtr: UnsafeMutableRawPointer? = nil
        var semaphore: DispatchSemaphore? = nil
        
        if let jsCallback = jsCallback {
            semaphore = DispatchSemaphore(value: 0)
            semaphorePtr = Unmanaged.passRetained(semaphore!).toOpaque()
            
            debugCallback = { pid, debugProxy, remoteServer, semPtr in
                guard let semPtr = semPtr else { return }
                let sem = Unmanaged<DispatchSemaphore>.fromOpaque(semPtr).takeRetainedValue()
                
                DispatchQueue.main.async {
                    jsCallback(
                        pid,
                        debugProxy.map { OpaquePointer($0) },
                        remoteServer.map { OpaquePointer($0) },
                        sem
                    )
                }
            }
        }
        
        let result = debug_app(adapter, handshake, bundleID, logCallback, debugCallback)
        
        guard result == IDEVICE_SUCCESS else {
            throw JITError.debugFailed("Failed to debug app '\(bundleID)': \(result.rawValue)")
        }
        
        logger?("[JIT] Successfully enabled JIT for \(bundleID)")
        
        // Wait for callback to complete if provided
        if let sem = semaphore {
            _ = sem.wait(timeout: .now() + 10.0)
        }
    }
    
    /// Enable JIT for a specific process by PID
    func debugApp(withPID pid: Int32, logger: LogFunc? = nil, jsCallback: DebugAppCallback? = nil) throws {
        guard let adapter = adapter, let handshake = handshake else {
            throw JITError.notConnected
        }
        
        let logCallback: idevice_log_func? = logger != nil ? { messagePtr in
            guard let messagePtr = messagePtr else { return }
            let message = String(cString: messagePtr)
            DispatchQueue.main.async {
                logger?(message)
            }
        } : nil
        
        var debugCallback: idevice_debug_callback? = nil
        var semaphorePtr: UnsafeMutableRawPointer? = nil
        var semaphore: DispatchSemaphore? = nil
        
        if let jsCallback = jsCallback {
            semaphore = DispatchSemaphore(value: 0)
            semaphorePtr = Unmanaged.passRetained(semaphore!).toOpaque()
            
            debugCallback = { pid, debugProxy, remoteServer, semPtr in
                guard let semPtr = semPtr else { return }
                let sem = Unmanaged<DispatchSemaphore>.fromOpaque(semPtr).takeRetainedValue()
                
                DispatchQueue.main.async {
                    jsCallback(
                        pid,
                        debugProxy.map { OpaquePointer($0) },
                        remoteServer.map { OpaquePointer($0) },
                        sem
                    )
                }
            }
        }
        
        let result = debug_app_pid(adapter, handshake, pid, logCallback, debugCallback)
        
        guard result == IDEVICE_SUCCESS else {
            throw JITError.debugFailed("Failed to debug PID \(pid): \(result.rawValue)")
        }
        
        logger?("[JIT] Successfully enabled JIT for PID \(pid)")
        
        if let sem = semaphore {
            _ = sem.wait(timeout: .now() + 10.0)
        }
    }
    
    /// Launch an app without debugging
    func launchApp(_ bundleID: String, logger: LogFunc? = nil) throws {
        guard let adapter = adapter, let handshake = handshake else {
            throw JITError.notConnected
        }
        
        let logCallback: idevice_log_func? = logger != nil ? { messagePtr in
            guard let messagePtr = messagePtr else { return }
            let message = String(cString: messagePtr)
            DispatchQueue.main.async {
                logger?(message)
            }
        } : nil
        
        let result = launch_app_via_proxy(adapter, handshake, bundleID, logCallback)
        
        guard result == IDEVICE_SUCCESS else {
            throw JITError.launchFailed("Failed to launch '\(bundleID)': \(result.rawValue)")
        }
        
        logger?("[JIT] Launched \(bundleID)")
    }
    
    // MARK: - Self-JIT Enablement
    
    /// Enable JIT for the current Azahar process
    func enableJITForSelf(logger: LogFunc? = nil) throws {
        let pid = get_current_pid()
        let bundleID = String(cString: get_current_bundle_id())
        
        logger?("[JIT] Enabling JIT for Azahar (PID: \(pid), Bundle: \(bundleID))")
        
        try debugApp(withPID: pid, logger: logger, jsCallback: nil)
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
        
        print("[JIT] TXM not detected - advanced JIT features unavailable")
    }
}

// MARK: - Error Types

enum JITError: LocalizedError {
    case notConnected
    case connectionFailed(String)
    case mountFailed(String)
    case debugFailed(String)
    case launchFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .notConnected:
            return "Not connected to device services"
        case .connectionFailed(let msg):
            return "Connection failed: \(msg)"
        case .mountFailed(let msg):
            return "DDI mount failed: \(msg)"
        case .debugFailed(let msg):
            return "Debug attach failed: \(msg)"
        case .launchFailed(let msg):
            return "App launch failed: \(msg)"
        }
    }
}
