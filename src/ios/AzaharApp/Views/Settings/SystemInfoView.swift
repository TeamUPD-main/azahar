import SwiftUI
import UIKit
import Security

struct SystemInfoView: View {
    @State private var isJITAvailable = false
    @State private var isDebuggerAttached = false
    @State private var hasEntitlements = false
    
    var body: some View {
        List {
            Section("JIT Status") {
                HStack {
                    Text("JIT Available")
                    Spacer()
                    Image(systemName: isJITAvailable ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(isJITAvailable ? .green : .red)
                }
                
                HStack {
                    Text("Debugger Attached")
                    Spacer()
                    Image(systemName: isDebuggerAttached ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(isDebuggerAttached ? .yellow : .green)
                }
                
                HStack {
                    Text("JIT Entitlements")
                    Spacer()
                    Image(systemName: hasEntitlements ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(hasEntitlements ? .green : .red)
                }
            }
            
            Section("Build Configuration") {
                InfoRow(label: "Target", value: "\(Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "Unknown")")
                InfoRow(label: "Bundle ID", value: Bundle.main.bundleIdentifier ?? "Unknown")
                InfoRow(label: "Version", value: "\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown")")
            }
            
            Section("Instructions") {
                Text("For JIT to work on iOS, you need:")
                    .font(.headline)
                Text("• Debugger attached (Xcode)")
                Text("• OR proper JIT entitlements")
                Text("• OR sideloaded with JIT-enabled signer")
            }
        }
        .navigationTitle("System Information")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            checkSystemStatus()
        }
    }
    
    private func checkSystemStatus() {
        // Check if debugger is attached
        isDebuggerAttached = isDebuggerPresent()
        
        // Check JIT entitlements
        hasEntitlements = checkEntitlement("dynamic-codesigning") ||
                         checkEntitlement("com.apple.security.cs.allow-jit") ||
                         checkEntitlement("com.apple.private.security.no-container")
        
        // JIT is available if debugger attached OR has entitlements
        isJITAvailable = isDebuggerAttached || hasEntitlements
    }
}

private struct InfoRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
                .font(.caption)
                .multilineTextAlignment(.trailing)
        }
    }
}

// Helper function to check if debugger is attached
private func isDebuggerPresent() -> Bool {
    var info = kinfo_proc()
    var mib = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
    var size = MemoryLayout<kinfo_proc>.stride
    
    let result = sysctl(&mib, u_int(mib.count), &info, &size, nil, 0)
    
    return result == 0 && (info.kp_proc.p_flag & P_TRACED) != 0
}

// Helper function to check entitlements using SecTask API
private func checkEntitlement(_ entitlement: String) -> Bool {
    // Use SecTaskCreateFromSelf to check our own entitlements
    guard let task = SecTaskCreateFromSelf(nil) else {
        return false
    }

    var error: Unmanaged<CFError>?
    guard let value = SecTaskCopyValueForEntitlement(task, entitlement as CFString, &error) else {
        return false
    }

    // Check if it's a boolean true value
    if CFGetTypeID(value) == CFBooleanGetTypeID(), let boolean = value as? CFBoolean {
        return CFBooleanGetValue(boolean)
    }

    // If value exists but isn't boolean, treat presence as true
    return true
}

struct SystemInfoView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack { SystemInfoView() }
    }
}
