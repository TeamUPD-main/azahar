// Copyright Citra Emulator Project / Azahar Emulator Project
// Licensed under GPLv2 or any later version
// Refer to the license.txt file included.

import SwiftUI

struct JITSettingsView: View {
    @StateObject private var jitContext = JITEnableContext.shared
    @StateObject private var ddiManager = DDIManager.shared
    
    @AppStorage("autoEnableJIT") private var autoEnableJIT = false
    @AppStorage("useStikDebug") private var useStikDebug = true
    @AppStorage("pairingFilePath") private var pairingFilePath = ""
    
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var isEnabling = false
    
    var body: some View {
        List {
            // Method Selection
            Section {
                Picker("JIT Method", selection: $useStikDebug) {
                    Text("StikDebug (Recommended)").tag(true)
                    Text("Built-in (Experimental)").tag(false)
                }
                
                Text(useStikDebug ? 
                    "Uses StikDebug companion app for reliable JIT enablement" :
                    "Experimental built-in JIT enablement (requires setup)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("JIT Enablement Method")
            }
            
            if useStikDebug {
                stikDebugSection
            } else {
                builtInJITSection
            }
            
            // Auto-enable setting
            Section {
                Toggle("Auto-enable JIT on Launch", isOn: $autoEnableJIT)
                
                Text("Automatically enable JIT when Azahar starts")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Automation")
            }
            
            // System Info
            Section {
                HStack {
                    Text("iOS Version")
                    Spacer()
                    Text(getIOSVersion())
                        .foregroundStyle(.secondary)
                }
                
                HStack {
                    Text("TXM Support")
                    Spacer()
                    if jitContext.hasTXM {
                        Label("Available", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Label("Not Available", systemImage: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }
                
                HStack {
                    Text("Current PID")
                    Spacer()
                    Text("\(get_current_pid())")
                        .foregroundStyle(.secondary)
                }
                
                HStack {
                    Text("Bundle ID")
                    Spacer()
                    Text(String(cString: get_current_bundle_id()))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("System Information")
            } footer: {
                if !jitContext.hasTXM {
                    Text("⚠️ iOS 27 with A13/A14/M1 chips requires TXM support for advanced JIT features. Your device may have limited JIT capabilities.")
                        .font(.caption)
                }
            }
        }
        .navigationTitle("JIT Settings")
        .alert("JIT Error", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
    }
    
    // MARK: - StikDebug Section
    
    private var stikDebugSection: some View {
        Section {
            Button {
                openStikDebug()
            } label: {
                HStack {
                    Image(systemName: "app.badge")
                        .foregroundStyle(.blue)
                    VStack(alignment: .leading) {
                        Text("Open StikDebug")
                        Text("Enable JIT using StikDebug app")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            Button {
                openStikDebugInstall()
            } label: {
                HStack {
                    Image(systemName: "arrow.down.circle")
                        .foregroundStyle(.green)
                    VStack(alignment: .leading) {
                        Text("Get StikDebug")
                        Text("Download from GitHub")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            Text("StikDebug is a companion app that enables JIT compilation for sideloaded apps. It works on iOS 17.4+ and supports advanced features on iOS 26+ with TXM.")
                .font(.caption)
                .foregroundStyle(.secondary)
        } header: {
            Text("StikDebug Integration")
        } footer: {
            Text("After installing StikDebug and LocalDevVPN, use StikDebug to enable JIT for Azahar.")
        }
    }
    
    // MARK: - Built-in JIT Section
    
    private var builtInJITSection: some View {
        Group {
            // Connection Status
            Section {
                HStack {
                    Text("Connection")
                    Spacer()
                    if jitContext.isConnected {
                        Label("Connected", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Label("Disconnected", systemImage: "xmark.circle.fill")
                            .foregroundStyle(.red)
                    }
                }
                
                if !pairingFilePath.isEmpty {
                    Text("Pairing file: \(pairingFilePath)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Button {
                    selectPairingFile()
                } label: {
                    Label("Select Pairing File", systemImage: "doc")
                }
                
                if !jitContext.isConnected && !pairingFilePath.isEmpty {
                    Button {
                        connectToDevice()
                    } label: {
                        Label("Connect", systemImage: "network")
                    }
                }
            } header: {
                Text("Device Connection")
            } footer: {
                Text("Requires a .mobiledevicepairing file and LocalDevVPN running")
            }
            
            // DDI Management
            Section {
                HStack {
                    Text("DDI Status")
                    Spacer()
                    if ddiManager.isReady {
                        Label("Ready", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Label("Not Ready", systemImage: "exclamationmark.circle.fill")
                            .foregroundStyle(.orange)
                    }
                }
                
                if ddiManager.isReady {
                    HStack {
                        Text("Size")
                        Spacer()
                        Text(ddiManager.getDDISize())
                            .foregroundStyle(.secondary)
                    }
                }
                
                if ddiManager.isDownloading {
                    VStack(alignment: .leading) {
                        Text(ddiManager.statusMessage)
                            .font(.caption)
                        ProgressView(value: ddiManager.downloadProgress)
                    }
                } else if !ddiManager.isReady {
                    Button {
                        Task {
                            await downloadDDI()
                        }
                    } label: {
                        Label("Download DDI Files", systemImage: "arrow.down.circle")
                    }
                }
                
                if ddiManager.isReady && jitContext.isConnected && !jitContext.isDDIMounted {
                    Button {
                        Task {
                            await mountDDI()
                        }
                    } label: {
                        Label("Mount DDI", systemImage: "externaldrive")
                    }
                }
                
                if ddiManager.isReady {
                    Button(role: .destructive) {
                        cleanupDDI()
                    } label: {
                        Label("Delete DDI Files", systemImage: "trash")
                    }
                }
            } header: {
                Text("Developer Disk Image")
            } footer: {
                Text("Required for iOS 17+ debugging. DDI files are downloaded automatically for your iOS version.")
            }
            
            // JIT Control
            Section {
                Button {
                    Task {
                        await enableJIT()
                    }
                } label: {
                    HStack {
                        if isEnabling {
                            ProgressView()
                                .frame(width: 20, height: 20)
                        } else {
                            Image(systemName: "bolt.fill")
                                .foregroundStyle(.yellow)
                        }
                        Text(isEnabling ? "Enabling JIT..." : "Enable JIT for Azahar")
                    }
                }
                .disabled(!jitContext.isConnected || !jitContext.isDDIMounted || isEnabling)
            } header: {
                Text("JIT Control")
            } footer: {
                Text("Enables Just-In-Time compilation for better performance. Requires connection and mounted DDI.")
            }
        }
    }
    
    // MARK: - Helper Functions
    
    private func getIOSVersion() -> String {
        let os = ProcessInfo.processInfo.operatingSystemVersion
        return "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)"
    }
    
    private func openStikDebug() {
        // Try to open StikDebug with URL scheme
        if let url = URL(string: "stikdebug://enable-jit?bundle-id=org.azahar_emu.Azahar") {
            UIApplication.shared.open(url)
        }
    }
    
    private func openStikDebugInstall() {
        // Open StikDebug GitHub releases
        if let url = URL(string: "https://github.com/BomberFish/StikDebug/releases") {
            UIApplication.shared.open(url)
        }
    }
    
    private func selectPairingFile() {
        // TODO: Implement document picker for .mobiledevicepairing file
        errorMessage = "Please place your .mobiledevicepairing file in Azahar's Documents folder"
        showError = true
    }
    
    private func connectToDevice() {
        Task {
            do {
                try jitContext.startTunnel(pairingFilePath: pairingFilePath)
            } catch {
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }
    
    private func downloadDDI() async {
        do {
            try await ddiManager.downloadDDIFiles()
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }
    
    private func mountDDI() async {
        do {
            try await ddiManager.mountDDI()
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }
    
    private func cleanupDDI() {
        do {
            try ddiManager.cleanupDDIFiles()
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }
    
    private func enableJIT() async {
        isEnabling = true
        defer { isEnabling = false }
        
        do {
            try jitContext.enableJITForSelf { message in
                print(message)
            }
            
            // Show success
            errorMessage = "JIT enabled successfully! Azahar is now running with JIT compilation."
            showError = true
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }
}
