// Copyright Citra Emulator Project / Azahar Emulator Project
// Licensed under GPLv2 or any later version
// Refer to the license.txt file included.

import SwiftUI

/// System files downloader using Artic Setup Tool
/// Downloads system files from a real 3DS console over the network
struct SystemFilesDownloaderView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @AppStorage("last_artic_base_addr") private var lastArticBaseAddr = ""
    
    @State private var serverAddress = ""
    @State private var setupState: [Bool]?
    @State private var isChecking = false
    @State private var showAlert = false
    @State private var alertMessage = ""
    
    var body: some View {
        List {
            Section {
                Text("Azahar needs console unique data and firmware files from a real console to be able to use some of its features. Such files and data can be set up with the Azahar Artic Setup Tool.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                
                Text("Notes:")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .padding(.top, 8)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("• This operation will install console unique data to Azahar")
                    Text("• Do not share your user or NAND folders after setup")
                    Text("• Do not go online with both Azahar and your 3DS at the same time")
                    Text("• Old 3DS setup is needed for New 3DS setup to work")
                    Text("• Setup both modes for best compatibility")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            } header: {
                Text("About System Files Setup")
            }
            
            Section {
                HStack {
                    Text("Server Address")
                    Spacer()
                    TextField("192.168.1.100", text: $serverAddress)
                        .multilineTextAlignment(.trailing)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                
                if isChecking {
                    HStack {
                        ProgressView()
                        Text("Checking setup status...")
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Connection")
            }
            
            if let state = setupState, !isChecking {
                Section {
                    // Old 3DS Setup
                    Button {
                        startSetup(isNew3DS: false)
                    } label: {
                        HStack {
                            VStack(alignment: .leading) {
                                Text("Old 3DS Setup")
                                    .foregroundStyle(.primary)
                                if !state[0] {
                                    Text("Setup is possible")
                                        .font(.caption)
                                        .foregroundStyle(.blue)
                                } else {
                                    Text("Setup already completed")
                                        .font(.caption)
                                        .foregroundStyle(.green)
                                }
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .disabled(state[0])
                    
                    // New 3DS Setup
                    Button {
                        startSetup(isNew3DS: true)
                    } label: {
                        HStack {
                            VStack(alignment: .leading) {
                                Text("New 3DS Setup")
                                    .foregroundStyle(.primary)
                                if !state[0] {
                                    Text("Old 3DS setup is required first")
                                        .font(.caption)
                                        .foregroundStyle(.orange)
                                } else if !state[1] {
                                    Text("Setup is possible")
                                        .font(.caption)
                                        .foregroundStyle(.blue)
                                } else {
                                    Text("Setup already completed")
                                        .font(.caption)
                                        .foregroundStyle(.green)
                                }
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .disabled(!state[0] || state[1])
                } header: {
                    Text("Setup Options")
                }
            }
        }
        .navigationTitle("Download System Files")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            serverAddress = lastArticBaseAddr
            checkSetupStatus()
        }
        .alert("System Files Setup", isPresented: $showAlert) {
            Button("OK") {}
        } message: {
            Text(alertMessage)
        }
    }
    
    private func checkSetupStatus() {
        guard !serverAddress.isEmpty else { return }
        
        isChecking = true
        
        DispatchQueue.global(qos: .userInitiated).async {
            // Check if system titles are installed
            // Index 0: Old 3DS, Index 1: New 3DS
            var state = [Bool](repeating: false, count: 2)
            state[0] = az_system_files_region_available(1) // Check USA region as proxy
            state[1] = false // TODO: Add New 3DS specific check
            
            DispatchQueue.main.async {
                self.setupState = state
                self.isChecking = false
            }
        }
    }
    
    private func startSetup(isNew3DS: Bool) {
        guard !serverAddress.isEmpty else {
            alertMessage = "Please enter a server address"
            showAlert = true
            return
        }
        
        lastArticBaseAddr = serverAddress
        
        // Uninstall existing files for this mode
        az_uninstall_system_files(isNew3DS)
        
        // Launch emulation with Artic Init URL
        let urlScheme = isNew3DS ? "articinin" : "articinio"
        let game = Game(
            title: isNew3DS ? "New 3DS Setup" : "Old 3DS Setup",
            path: "\(urlScheme)://\(serverAddress)",
            titleId: 0
        )
        
        appState.currentGame = game
        appState.isEmulating = true
        dismiss()
    }
}

#Preview {
    NavigationStack {
        SystemFilesDownloaderView()
            .environmentObject(AppState())
    }
}
