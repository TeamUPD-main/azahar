// Copyright Citra Emulator Project / Azahar Emulator Project
// Licensed under GPLv2 or any later version
// Refer to the license.txt file included.

import SwiftUI

struct JITSettingsView: View {
    @StateObject private var jitContext = JITEnableContext.shared
    
    @AppStorage("autoEnableJIT") private var autoEnableJIT = false
    
    @State private var showError = false
    @State private var errorMessage = ""
    
    var body: some View {
        List {
            // StikDebug Integration
            Section {
                Button {
                    jitContext.openStikDebug()
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
                    jitContext.openStikDebugDownload()
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
                Text("JIT Enablement")
            } footer: {
                Text("After installing StikDebug and LocalDevVPN, use StikDebug to enable JIT for Azahar.")
            }
            
            // Auto-enable setting
            Section {
                Toggle("Auto-enable JIT on Launch", isOn: $autoEnableJIT)
                
                Text("Automatically trigger StikDebug when Azahar starts")
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
                    Text(jitContext.getIOSVersion())
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
                    Text("\(jitContext.getCurrentPID())")
                        .foregroundStyle(.secondary)
                }
                
                HStack {
                    Text("Bundle ID")
                    Spacer()
                    Text(jitContext.getCurrentBundleID())
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
        .onAppear {
            if let error = jitContext.lastError {
                errorMessage = error
                showError = true
                jitContext.lastError = nil
            }
        }
    }
}
