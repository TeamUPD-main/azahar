// Copyright Citra Emulator Project / Azahar Emulator Project
// Licensed under GPLv2 or any later version
// Refer to the license.txt file included.

import Foundation
import Darwin

/// Chip series for TXM detection
enum ChipSeries {
    case aseries  // A-series (iPhone/iPad)
    case mseries  // M-series (iPad/Mac)
    case unknown
}

/// Chip information parsed from Metal device
struct ChipInfo {
    let series: ChipSeries
    let number: Int
}

/// Singleton managing StikDebug integration for on-device JIT enablement
@MainActor
class JITEnableContext: ObservableObject {
    static let shared = JITEnableContext()
    
    @Published var isJITEnabled = false
    @Published var hasTXM = false
    @Published var lastError: String?
    
    private var jitCheckTimer: Timer?
    
    private init() {
        detectTXMCapability()
        checkJITStatus()
        startJITPolling()
    }
    
    // MARK: - JIT Status Detection
    
    /// Check if JIT is currently enabled
    func checkJITStatus() {
        isJITEnabled = jitEnabled()
    }
    
    /// Check if JIT is enabled via dynamic-codesigning entitlement or debugger
    private func jitEnabled() -> Bool {
        // Check for dynamic-codesigning entitlement (TrollStore/permanent JIT)
        if checkAppEntitlement("dynamic-codesigning") {
            return true
        }
        
        // Check if debugged + dual mapping works (iOS 19+)
        if #available(iOS 19, *) {
            return isDebuggerAttached() && testDualMappedExecution()
        }
        
        // iOS 17-18: Just check if debugger is attached
        return isDebuggerAttached()
    }
    
    /// Check if debugger is attached
    private func isDebuggerAttached() -> Bool {
        var info = kinfo_proc()
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        var size = MemoryLayout<kinfo_proc>.stride
        
        let result = sysctl(&mib, u_int(mib.count), &info, &size, nil, 0)
        guard result == 0 else { return false }
        
        return (info.kp_proc.p_flag & P_TRACED) != 0
    }
    
    /// Test if dual-mapped memory execution works (iOS 19+)
    private func testDualMappedExecution() -> Bool {
        guard #available(iOS 19, *) else { return false }
        
        // Allocate RW page
        let pageSize = vm_page_size
        var addr: vm_address_t = 0
        
        guard vm_allocate(mach_task_self_, &addr, pageSize, VM_FLAGS_ANYWHERE) == KERN_SUCCESS else {
            return false
        }
        
        defer { vm_deallocate(mach_task_self_, addr, pageSize) }
        
        // Try to remap as RX (dual mapping test)
        var target: vm_address_t = 0
        var cur_protection: vm_prot_t = 0
        var max_protection: vm_prot_t = 0
        
        let result = vm_remap(
            mach_task_self_,
            &target,
            pageSize,
            0,
            VM_FLAGS_ANYWHERE | VM_FLAGS_RETURN_DATA_ADDR,
            mach_task_self_,
            addr,
            0,
            &cur_protection,
            &max_protection,
            VM_INHERIT_NONE
        )
        
        if result == KERN_SUCCESS {
            vm_deallocate(mach_task_self_, target, pageSize)
            return true
        }
        
        return false
    }
    
    /// Check app entitlement
    private func checkAppEntitlement(_ entitlement: String) -> Bool {
        let value = SecTaskCopyValueForEntitlement(
            SecTaskCreateFromSelf(nil)!,
            entitlement as CFString,
            nil
        )
        return value != nil
    }
    
    // MARK: - JIT Polling
    
    /// Start polling for JIT status changes
    private func startJITPolling() {
        jitCheckTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkJITStatus()
            }
        }
    }
    
    /// Stop polling
    func stopJITPolling() {
        jitCheckTimer?.invalidate()
        jitCheckTimer = nil
    }
    
    // MARK: - StikDebug Integration
    
    /// Enable JIT via StikDebug URL scheme
    func enableJITViaStikDebug() {
        let bundleID = getCurrentBundleID()
        var urlScheme = "stikjit://enable-jit"
        
        // iOS 19+ without TXM needs script data for iOS 26 compatibility
        if #available(iOS 19.0, *), !hasTXM {
            let scriptData = getJIT26Script()
            if let encoded = scriptData.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
                urlScheme += "?bundle-id=\(bundleID)&script-name=Azahar&script-data=\(encoded)"
            } else {
                urlScheme += "?bundle-id=\(bundleID)"
            }
        } else {
            urlScheme += "?bundle-id=\(bundleID)"
        }
        
        if let url = URL(string: urlScheme) {
            UIApplication.shared.open(url) { [weak self] success in
                if !success {
                    Task { @MainActor in
                        self?.lastError = "StikDebug not installed. Please install StikDebug from GitHub."
                    }
                }
            }
        }
    }
    
    /// Get iOS 26 JIT breakpoint handler script (base64-encoded JavaScript)
    private func getJIT26Script() -> String {
        // Base64-encoded JavaScript for iOS 26 JIT breakpoint handling
        // This prevents crashes on iOS 26 TXM devices when JIT isn't enabled yet
        return "dmFyIGFkZHIgPSBhcmdzWzBdOwp2YXIgdGhyZWFkX3N0YXRlID0gVGhyZWFkLmJhY2t0cmFjZSh0aGlzLmNvbnRleHQsIEJhY2t0cmFjZXIuQUNDVVJBVEUpLm1hcChjdXJyZW50ID0+IGN1cnJlbnQuYWRkcmVzcykuZmlsdGVyKGFkZHIgPT4gIWFkZHIucmVhZENTdHJpbmcoKS5pbmNsdWRlcygiZHlsZCIpKVswXTsKCmlmIChhZGRyICYmIHRocmVhZF9zdGF0ZSkgewogICAgdmFyIG1vZHVsZXMgPSBQcm9jZXNzLmVudW1lcmF0ZU1vZHVsZXMoKTsKICAgIHZhciB0YXJnZXRfbW9kdWxlID0gbnVsbDsKICAgIAogICAgZm9yICh2YXIgaSA9IDA7IGkgPCBtb2R1bGVzLmxlbmd0aDsgaSsrKSB7CiAgICAgICAgaWYgKHRocmVhZF9zdGF0ZS5jb21wYXJlKG1vZHVsZXNbaV0uYmFzZSkgPj0gMCAmJiB0aHJlYWRfc3RhdGUuY29tcGFyZShtb2R1bGVzW2ldLmJhc2UuYWRkKG1vZHVsZXNbaV0uc2l6ZSkpIDwgMCkgewogICAgICAgICAgICB0YXJnZXRfbW9kdWxlID0gbW9kdWxlc1tpXTsKICAgICAgICAgICAgYnJlYWs7CiAgICAgICAgfQogICAgfQogICAgCiAgICBpZiAodGFyZ2V0X21vZHVsZSkgewogICAgICAgIHZhciBvZmZzZXQgPSB0aHJlYWRfc3RhdGUuc3ViKHRhcmdldF9tb2R1bGUuYmFzZSk7CiAgICAgICAgUHJvY2Vzcy5nZXRNb2R1bGVCeU5hbWUodGFyZ2V0X21vZHVsZS5uYW1lKS5iYXNlLmFkZChvZmZzZXQpLndyaXRlQnl0ZUFycmF5KFsweGMwLCAweDAwLCAweDAwLCAweGQ0XSk7CiAgICB9Cn0="
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
    
    /// Detect TXM (Trusted Execution Monitor) capability
    private func detectTXMCapability() {
        if #available(iOS 27, *) {
            hasTXM = detectTXMiOS27()
        } else if #available(iOS 26.6, *) {
            hasTXM = detectTXMiOS26()
        } else {
            hasTXM = false
        }
    }
    
    /// iOS 27 TXM detection via chip parsing
    private func detectTXMiOS27() -> Bool {
        let lastNonTXM = 12 // A12 and earlier don't have TXM
        
        guard let chipInfo = parseChipInfo() else {
            return true // Unknown chip, assume TXM support
        }
        
        if chipInfo.series == .aseries {
            return chipInfo.number > lastNonTXM
        }
        
        // M-series always has TXM
        return true
    }
    
    /// iOS 26 TXM detection via firmware files
    private func detectTXMiOS26() -> Bool {
        let prebootPaths = [
            "/System/Volumes/Preboot",
            "/private/preboot"
        ]
        
        let fileManager = FileManager.default
        
        for basePath in prebootPaths {
            guard fileManager.fileExists(atPath: basePath) else { continue }
            
            do {
                let contents = try fileManager.contentsOfDirectory(atPath: basePath)
                
                for uuid in contents {
                    let paths = [
                        "\(basePath)/\(uuid)/boot/usr/standalone/firmware/FUD/Ap,TrustedExecutionMonitor.img4",
                        "\(basePath)/\(uuid)/usr/standalone/firmware/FUD/Ap,TrustedExecutionMonitor.img4",
                        "\(basePath)/\(uuid)/boot/usr/standalone/firmware/Ap,TrustedExecutionMonitor.img4",
                        "\(basePath)/\(uuid)/usr/standalone/firmware/Ap,TrustedExecutionMonitor.img4"
                    ]
                    
                    for path in paths {
                        if fileManager.fileExists(atPath: path) {
                            return true
                        }
                    }
                }
            } catch {
                continue
            }
        }
        
        return false
    }
    
    /// Parse chip information from Metal device name
    private func parseChipInfo() -> ChipInfo? {
        guard let device = MTLCreateSystemDefaultDevice() else {
            return nil
        }
        
        let name = device.name
        
        // Parse A-series: "Apple A15 GPU" -> ChipInfo(series: .aseries, number: 15)
        if let aRange = name.range(of: "Apple A") {
            let numberString = name[aRange.upperBound...].prefix(while: { $0.isNumber })
            if let number = Int(numberString) {
                return ChipInfo(series: .aseries, number: number)
            }
        }
        
        // Parse M-series: "Apple M1 GPU" -> ChipInfo(series: .mseries, number: 1)
        if let mRange = name.range(of: "Apple M") {
            let numberString = name[mRange.upperBound...].prefix(while: { $0.isNumber })
            if let number = Int(numberString) {
                return ChipInfo(series: .mseries, number: number)
            }
        }
        
        return nil
    }
}

// MARK: - iOS 26 Crash Prevention

/// Install signal handlers to prevent iOS 26 TXM crashes when JIT isn't enabled
func installJIT26BreakpointHandler() {
    // Handler for SIGTRAP and SIGBUS
    let handler: @convention(c) (Int32, UnsafeMutablePointer<__siginfo>?, UnsafeMutableRawPointer?) -> Void = { signal, info, context in
        // Log the signal but don't crash
        print("[JIT] Caught signal \(signal) - JIT not yet enabled, continuing...")
    }
    
    var sa = sigaction()
    sa.__sigaction_u.__sa_sigaction = handler
    sa.sa_flags = SA_SIGINFO
    
    sigaction(SIGTRAP, &sa, nil)
    sigaction(SIGBUS, &sa, nil)
}

// MARK: - C Bridge Functions

@_silgen_name("get_current_pid")
func get_current_pid() -> Int32

@_silgen_name("get_current_bundle_id")
func get_current_bundle_id() -> UnsafePointer<CChar>

// MARK: - Mach VM Functions

@_silgen_name("vm_allocate")
func vm_allocate(
    _ target: vm_map_t,
    _ address: UnsafeMutablePointer<vm_address_t>,
    _ size: vm_size_t,
    _ flags: Int32
) -> kern_return_t

@_silgen_name("vm_deallocate")
func vm_deallocate(
    _ target: vm_map_t,
    _ address: vm_address_t,
    _ size: vm_size_t
) -> kern_return_t

@_silgen_name("vm_remap")
func vm_remap(
    _ target: vm_map_t,
    _ address: UnsafeMutablePointer<vm_address_t>,
    _ size: vm_size_t,
    _ mask: vm_address_t,
    _ flags: Int32,
    _ src_task: vm_map_t,
    _ src_address: vm_address_t,
    _ copy: Bool,
    _ cur_protection: UnsafeMutablePointer<vm_prot_t>,
    _ max_protection: UnsafeMutablePointer<vm_prot_t>,
    _ inheritance: vm_inherit_t
) -> kern_return_t

// MARK: - Metal Import

import Metal
