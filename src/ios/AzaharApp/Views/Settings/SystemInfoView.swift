// Copyright Citra Emulator Project / Azahar Emulator Project
// Licensed under GPLv2 or any later version
// Refer to the license.txt file included.

import SwiftUI
import UIKit
import Security

struct SystemInfoView: View {
    @StateObject private var jitContext = JITEnableContext.shared
    
    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
    }
    
    private var buildVersion: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"
    }
    
    private var bundleIdentifier: String {
        Bundle.main.bundleIdentifier ?? "Unknown"
    }
    
    private var deviceModel: String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let modelCode = withUnsafePointer(to: &systemInfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) {
                String(validatingUTF8: $0)
            }
        }
        return modelCode ?? "Unknown"
    }
    
    private var deviceName: String {
        UIDevice.current.name
    }
    
    private var systemVersion: String {
        "\(UIDevice.current.systemName) \(UIDevice.current.systemVersion)"
    }
    
    private var totalMemory: String {
        let memory = ProcessInfo.processInfo.physicalMemory
        let gb = Double(memory) / 1_000_000_000.0
        return String(format: "%.1f GB", gb)
    }
    
    private var processorCount: Int {
        ProcessInfo.processInfo.processorCount
    }
    
    var body: some View {
        List {
            // JIT Status Section
            Section {
                HStack(spacing: 12) {
                    Circle()
                        .fill(jitContext.isJITEnabled ? Color.green : Color.red)
                        .frame(width: 10, height: 10)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(jitStatusText)
                            .font(.headline)
                            .foregroundStyle(jitContext.isJITEnabled ? .green : .red)
                        
                        Text(jitStatusDescription)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                    
                    if jitContext.isJITEnabled {
                        Image(systemName: "bolt.fill")
                            .foregroundStyle(.yellow)
                            .font(.title2)
                    }
                }
                .padding(.vertical, 4)
            } header: {
                Text("JIT Status")
            }
            
            // Entitlements Section
            Section {
                EntitlementRow(
                    name: "JIT Compilation",
                    key: "com.apple.security.cs.allow-jit",
                    icon: "bolt.circle"
                )
                
                EntitlementRow(
                    name: "Unsigned Executable Memory",
                    key: "com.apple.security.cs.allow-unsigned-executable-memory",
                    icon: "memorychip"
                )
                
                EntitlementRow(
                    name: "Debugger Attachment",
                    key: "get-task-allow",
                    icon: "ant.circle"
                )
                
                EntitlementRow(
                    name: "Increased Memory Limit",
                    key: "com.apple.developer.kernel.increased-memory-limit",
                    icon: "memorychip.fill"
                )
                
                EntitlementRow(
                    name: "Network Client",
                    key: "com.apple.security.network.client",
                    icon: "network"
                )
                
                EntitlementRow(
                    name: "Network Server",
                    key: "com.apple.security.network.server",
                    icon: "server.rack"
                )
                
                EntitlementRow(
                    name: "Disable Library Validation",
                    key: "com.apple.security.cs.disable-library-validation",
                    icon: "books.vertical"
                )
            } header: {
                Text("Entitlements")
            } footer: {
                Text("Entitlements control what system capabilities the app has access to. JIT entitlements require proper code signing or StikDebug.")
            }
            
            // Device Information Section
            Section {
                LabeledContent("Device Name") {
                    Text(deviceName)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                
                LabeledContent("Model") {
                    Text(deviceModel)
                        .foregroundStyle(.secondary)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                }
                
                LabeledContent("System Version") {
                    Text(systemVersion)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                
                LabeledContent("Memory") {
                    Text(totalMemory)
                        .foregroundStyle(.secondary)
                }
                
                LabeledContent("Processor Cores") {
                    Text("\(processorCount)")
                        .foregroundStyle(.secondary)
                }
                
                LabeledContent("TXM Support") {
                    if jitContext.hasTXM {
                        Label("Available", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Label("Not Available", systemImage: "xmark.circle")
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Device Information")
            }
            
            // App Information Section
            Section {
                LabeledContent("Version") {
                    Text("\(appVersion) (\(buildVersion))")
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                
                LabeledContent("Bundle ID") {
                    Text(bundleIdentifier)
                        .foregroundStyle(.secondary)
                        .font(.caption)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
                
                LabeledContent("Process ID") {
                    Text("\(jitContext.getCurrentPID())")
                        .foregroundStyle(.secondary)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                }
                
                LabeledContent("iOS Version") {
                    Text(jitContext.getIOSVersion())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            } header: {
                Text("App Information")
            }
        }
        .navigationTitle("System Information")
        .navigationBarTitleDisplayMode(.inline)
    }
    
    private var jitStatusText: String {
        if jitContext.isJITEnabled {
            return "JIT Enabled"
        } else if hasJITEntitlement {
            return "JIT Available (Not Active)"
        } else {
            return "JIT Not Available"
        }
    }
    
    private var jitStatusDescription: String {
        if jitContext.isJITEnabled {
            return "Running with JIT compilation for optimal performance"
        } else if hasJITEntitlement {
            return "JIT entitlement present but not yet activated"
        } else {
            return "Running in interpreter mode (use StikDebug to enable JIT)"
        }
    }
    
    private var hasJITEntitlement: Bool {
        checkEntitlement("com.apple.security.cs.allow-jit") ||
        checkEntitlement("get-task-allow") ||
        checkEntitlement("dynamic-codesigning")
    }
}

struct EntitlementRow: View {
    let name: String
    let key: String
    let icon: String
    
    @State private var isEnabled: Bool = false
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundStyle(isEnabled ? .green : .secondary)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.body)
                
                Text(key)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            
            Spacer()
            
            if isEnabled {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Image(systemName: "xmark.circle")
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear {
            isEnabled = checkEntitlement(key)
        }
    }
}

private func checkEntitlement(_ entitlement: String) -> Bool {
    guard let task = SecTaskCreateFromSelf(nil) else {
        return false
    }
    
    let value = SecTaskCopyValueForEntitlement(task, entitlement as CFString, nil)
    
    guard let value = value else {
        return false
    }
    
    if CFGetTypeID(value) == CFBooleanGetTypeID(), let boolean = value as? CFBoolean {
        return CFBooleanGetValue(boolean)
    }
    
    return true
}

struct SystemInfoView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            SystemInfoView()
        }
    }
}
