// Copyright Citra Emulator Project / Azahar Emulator Project
// Licensed under GPLv2 or any later version
// Refer to the license.txt file included.

import SwiftUI

struct JITSettingsView: View {
    @StateObject private var jitContext = JITEnableContext.shared
    
    @AppStorage("autoEnableJIT") private var autoEnableJIT = false  // Default: disabled
    
    @State private var showError = false
    @State private var errorMessage = ""
    
    var body: some View {
        List {
            // JIT Status Section
            Section {
                HStack(spacing: 12) {
                    Circle()
                        .fill(jitContext.isJITEnabled ? Color.green : Color.red)
                        .frame(width: 10, height: 10)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(jitContext.isJITEnabled ? "JIT Enabled" : "JIT Not Enabled")
                            .font(.headline)
                            .foregroundStyle(jitContext.isJITEnabled ? .green : .red)
                        
                        if !jitContext.isJITEnabled {
                            Text("Tap 'Open StikDebug' below to enable JIT")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("Your emulator is running with JIT compilation")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
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
                Text("Status")
            }
            
            // StikDebug Integration
            Section {
                Button {
                    jitContext.enableJITViaStikDebug()
                } label: {
                    HStack {
                        Image(systemName: "app.badge.checkmark")
                            .foregroundStyle(.blue)
                            .font(.title3)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Open StikDebug")
                                .font(.headline)
                                .foregroundStyle(.primary)
                            Text("Enable JIT compilation")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        
                        Spacer()
                        
                        Image(systemName: "arrow.up.right.square")
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
                .disabled(jitContext.isJITEnabled)
                
                Button {
                    jitContext.openStikDebugDownload()
                } label: {
                    HStack {
                        Image(systemName: "arrow.down.circle.fill")
                            .foregroundStyle(.green)
                            .font(.title3)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Get StikDebug")
                                .font(.headline)
                                .foregroundStyle(.primary)
                            Text("Download from GitHub")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        
                        Spacer()
                        
                        Image(systemName: "arrow.up.right.square")
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            } header: {
                Text("JIT Enablement")
            } footer: {
                Text("StikDebug is a companion app that enables JIT compilation for sideloaded apps. Install both StikDebug and LocalDevVPN, then use StikDebug to enable JIT for Azahar.")
            }
            
            // Auto-enable setting
            Section {
                Toggle(isOn: $autoEnableJIT) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Auto-enable JIT on Launch")
                            .font(.headline)
                        Text("Automatically trigger StikDebug when Azahar starts")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                
                if !autoEnableJIT {
                    HStack(spacing: 8) {
                        Image(systemName: "info.circle.fill")
                            .foregroundStyle(.orange)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Running Without JIT")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                            Text("Azahar will use the software interpreter, which is significantly slower. You can manually enable JIT anytime using the button above.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                    .background(Color.orange.opacity(0.1))
                    .cornerRadius(8)
                }
            } header: {
                Text("Automation")
            } footer: {
                if autoEnableJIT {
                    Text("Azahar will automatically open StikDebug once when the app launches. StikDebug will close and reopen Azahar with JIT enabled. This only happens once per app launch.")
                } else {
                    Text("Auto-enable is OFF. Azahar will run in software interpreter mode (slow). Enable this toggle for optimal performance, or manually enable JIT using the button above when needed.")
                }
            }
            
            // System Info
            Section {
                LabeledContent("iOS Version") {
                    Text(jitContext.getIOSVersion())
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
                
                LabeledContent("Process ID") {
                    Text("\(jitContext.getCurrentPID())")
                        .foregroundStyle(.secondary)
                        .font(.system(.body, design: .monospaced))
                }
                
                LabeledContent("Bundle ID") {
                    Text(jitContext.getCurrentBundleID())
                        .foregroundStyle(.secondary)
                        .font(.caption)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            } header: {
                Text("System Information")
            } footer: {
                if !jitContext.hasTXM {
                    Text("⚠️ Your device has limited JIT capabilities. iOS 26+ with A13/A14/M1+ chips support advanced TXM features for better JIT performance.")
                        .font(.caption)
                }
            }
            
            // About JIT Section
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Just-In-Time (JIT) compilation significantly improves emulation performance by translating guest code to native ARM64 code on the fly.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    Text("JIT is required for smooth gameplay in most 3DS games. Without JIT, you may experience severe slowdowns and stuttering.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("About JIT")
            }
        }
        .navigationTitle("JIT Settings")
        .alert("JIT Notice", isPresented: $showError) {
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
