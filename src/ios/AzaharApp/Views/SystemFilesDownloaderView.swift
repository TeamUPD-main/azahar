// Copyright Citra Emulator Project / Azahar Emulator Project
// Licensed under GPLv2 or any later version
// Refer to the license.txt file included.

import SwiftUI

/// System files downloader with NUS and Artic support (like AzaharPlus Android)
struct SystemFilesDownloaderView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @AppStorage("last_artic_base_addr") private var lastArticBaseAddr = ""
    
    @State private var downloadMethod: DownloadMethod = .nus
    @State private var selectedRegion = 1 // USA
    @State private var selectedSystemType = 6 // Old3DS + New3DS
    @State private var serverAddress = ""
    @State private var setupState: [Bool]?
    @State private var isChecking = false
    @State private var isDownloading = false
    @State private var downloadProgress = 0
    @State private var totalTitles = 0
    @State private var showAlert = false
    @State private var alertTitle = ""
    @State private var alertMessage = ""
    @State private var currentDownloadTitle: UInt64 = 0
    
    private let regionNames = ["Japan", "USA", "Europe", "Australia", "China", "Korea", "Taiwan"]
    private let systemTypeNames = ["Minimal", "Old 3DS", "New 3DS", "Minimal + Old 3DS", "Minimal + New 3DS", "Old 3DS + New 3DS", "All"]
    private let systemTypeValues = [1, 2, 4, 3, 5, 6, 7]
    
    enum DownloadMethod: String, CaseIterable {
        case nus = "Nintendo Update Server"
        case artic = "From 3DS Console"
    }
    
    var body: some View {
        List {
            Section {
                Text("Azahar needs system files including Home Menu, shared fonts, and system archives.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } header: {
                Text("About System Files")
            }
            
            Section {
                Picker("Download Method", selection: $downloadMethod) {
                    ForEach(DownloadMethod.allCases, id: \.self) { method in
                        Text(method.rawValue).tag(method)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: downloadMethod) { _, newValue in
                    if newValue == .artic {
                        checkSetupStatus()
                    }
                }
            } header: {
                Text("Download Source")
            }
            
            if downloadMethod == .nus {
                nusDownloadSection
            } else {
                articDownloadSection
            }
        }
        .navigationTitle("Download System Files")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            serverAddress = lastArticBaseAddr
            print("[SystemFilesDownloader] View appeared, method=\(downloadMethod)")
        }
        .alert(alertTitle, isPresented: $showAlert) {
            Button("OK") {
                if alertTitle == "Download Complete" {
                    dismiss()
                }
            }
        } message: {
            Text(alertMessage)
        }
    }
    
    private var nusDownloadSection: some View {
        Group {
            if !az_are_keys_available() {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                            Text("AES Keys Missing")
                                .fontWeight(.semibold)
                        }
                        Text("System files cannot be downloaded without AES keys. Please import your aes_keys.txt file first.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            
            Section {
                Picker("Region", selection: $selectedRegion) {
                    ForEach(0..<regionNames.count, id: \.self) { index in
                        Text(regionNames[index]).tag(index)
                    }
                }
                
                Picker("System Type", selection: $selectedSystemType) {
                    ForEach(0..<systemTypeNames.count, id: \.self) { index in
                        Text(systemTypeNames[index]).tag(systemTypeValues[index])
                    }
                }
                
                if isDownloading {
                    VStack(spacing: 8) {
                        HStack {
                            ProgressView()
                            Text("Downloading system files...")
                                .font(.subheadline)
                        }
                        
                        if totalTitles > 0 {
                            ProgressView(value: Double(downloadProgress), total: Double(totalTitles)) {
                                Text("\(downloadProgress) / \(totalTitles) titles")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        
                        if currentDownloadTitle != 0 {
                            Text(String(format: "Title: %016llX", currentDownloadTitle))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .monospaced()
                        }
                        
                        Button("Cancel") {
                            cancelDownload()
                        }
                        .foregroundStyle(.red)
                    }
                    .padding(.vertical, 4)
                }
                
                Button {
                    startNUSDownload()
                } label: {
                    Label("Download System Files", systemImage: "arrow.down.circle.fill")
                }
                .disabled(isDownloading || !az_are_keys_available())
            } header: {
                Text("Download Options")
            }
            
            Section {
                Text("Downloads: Home Menu (all regions), Shared Font, Mii Maker, Region Manifest, Bad Word List, and other system archives.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
    
    private var articDownloadSection: some View {
        Group {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Download system files and console-unique data from your real 3DS using Artic Setup Tool.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    
                    Text("Important:")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .padding(.top, 4)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("• Install Artic Setup Tool on your 3DS")
                        Text("• Both devices must be on same Wi-Fi")
                        Text("• Do not share NAND folder after setup")
                        Text("• Don't go online with both at same time")
                        Text("• Old 3DS setup required for New 3DS")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
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
    }
    
    private func startNUSDownload() {
        print("[NUS] Starting download: region=\(selectedRegion), type=\(selectedSystemType)")
        
        // Get title IDs for the selected region and system type
        // Increased from 100 to 250 to handle all system titles (196 titles exist)
        let maxTitles = 250
        var titleIds = [Int64](repeating: 0, count: maxTitles)
        let count = az_get_system_title_ids(Int32(selectedSystemType), Int32(selectedRegion), &titleIds, Int32(maxTitles))
        
        guard count > 0 else {
            alertTitle = "Error"
            alertMessage = "No system titles found for the selected region and type."
            showAlert = true
            return
        }
        
        let titles = Array(titleIds.prefix(Int(count)))
        totalTitles = titles.count
        downloadProgress = 0
        isDownloading = true
        
        print("[NUS] Found \(totalTitles) titles to download")
        
        DispatchQueue.global(qos: .userInitiated).async {
            var successCount = 0
            var failedTitles: [Int64] = []
            
            for (index, titleId) in titles.enumerated() {
                // Check if cancelled
                if !self.isDownloading {
                    DispatchQueue.main.async {
                        self.alertTitle = "Cancelled"
                        self.alertMessage = "Download was cancelled by user."
                        self.showAlert = true
                        self.isDownloading = false
                    }
                    return
                }
                
                DispatchQueue.main.async {
                    self.currentDownloadTitle = UInt64(bitPattern: titleId)
                }
                
                print("[NUS] Downloading title \(index + 1)/\(totalTitles): \(String(format: "%016llX", titleId))")
                
                // Try downloading with retries (increased from 3 to 5 for reliability)
                var success = false
                for attempt in 0..<5 {
                    let result = az_download_title_from_nus(UInt64(bitPattern: titleId))
                    if result == 0 {
                        success = true
                        print("[NUS] Successfully downloaded title \(String(format: "%016llX", titleId))")
                        break
                    } else {
                        print("[NUS] Failed to download title \(String(format: "%016llX", titleId)), attempt \(attempt + 1)/5, error: \(result)")
                        if attempt < 4 {
                            // Exponential backoff: 1s, 2s, 4s, 8s
                            Thread.sleep(forTimeInterval: Double(1 << attempt))
                        }
                    }
                }
                
                if success {
                    successCount += 1
                } else {
                    failedTitles.append(titleId)
                    print("[NUS] Permanently failed title \(String(format: "%016llX", titleId)) after all retries")
                }
                
                DispatchQueue.main.async {
                    self.downloadProgress = index + 1
                }
            }
            
            DispatchQueue.main.async {
                self.isDownloading = false
                self.currentDownloadTitle = 0
                
                if failedTitles.isEmpty {
                    self.alertTitle = "Download Complete"
                    self.alertMessage = "Successfully downloaded and installed all \(successCount) system files."
                } else {
                    self.alertTitle = "Download Completed with Errors"
                    let failedList = failedTitles.prefix(5).map { String(format: "%016llX", $0) }.joined(separator: "\n")
                    let more = failedTitles.count > 5 ? "\n...and \(failedTitles.count - 5) more" : ""
                    self.alertMessage = "Successfully downloaded \(successCount) of \(totalTitles) titles.\n\nFailed titles (\(failedTitles.count)):\n\(failedList)\(more)\n\nNote: Some titles (like Mii Maker, Region Manifest, Bad Word List) may not be available on NUS for all regions. This is normal and won't affect most games."
                }
                self.showAlert = true
                print("[NUS] Download complete: \(successCount)/\(totalTitles) succeeded, \(failedTitles.count) failed")
            }
        }
    }
    
    private func cancelDownload() {
        print("[NUS] User cancelled download")
        isDownloading = false
    }
    
    private func checkSetupStatus() {
        print("[Artic] Checking setup status for server: \(serverAddress)")
        guard !serverAddress.isEmpty else { return }
        
        isChecking = true
        
        DispatchQueue.global(qos: .userInitiated).async {
            var state = [Bool](repeating: false, count: 2)
            state[0] = az_system_files_region_available(1) // Check USA region
            state[1] = false // TODO: Add New 3DS check
            
            DispatchQueue.main.async {
                self.setupState = state
                self.isChecking = false
                print("[Artic] Setup state: old3ds=\(state[0]), new3ds=\(state[1])")
            }
        }
    }
    
    private func startSetup(isNew3DS: Bool) {
        print("[Artic] Starting \(isNew3DS ? "New" : "Old") 3DS setup with server: \(serverAddress)")
        guard !serverAddress.isEmpty else {
            alertTitle = "Error"
            alertMessage = "Please enter a server address"
            showAlert = true
            return
        }
        
        lastArticBaseAddr = serverAddress
        
        // Uninstall existing files
        az_uninstall_system_files(isNew3DS)
        
        // Launch emulation with Artic Init URL
        let urlScheme = isNew3DS ? "articinin" : "articinio"
        let game = Game(
            path: "\(urlScheme)://\(serverAddress)",
            title: isNew3DS ? "New 3DS Setup" : "Old 3DS Setup",
            titleId: 0,
            mediaType: Int32(AZ_MEDIA_TYPE_SDMC)
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
