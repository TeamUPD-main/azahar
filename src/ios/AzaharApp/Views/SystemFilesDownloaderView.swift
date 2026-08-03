// Copyright Citra Emulator Project / Azahar Emulator Project
// Licensed under GPLv2 or any later version
// Refer to the license.txt file included.

import SwiftUI
import Foundation

/// System Files Downloader - downloads and installs required 3DS system files from NUS
struct SystemFilesDownloaderView: View {
    @Environment(\.dismiss) private var dismiss
    
    @State private var isDownloading = false
    @State private var downloadProgress: Double = 0
    @State private var currentFile = ""
    @State private var statusMessage = "Ready to download system files"
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var downloadComplete = false
    @State private var selectedRegion = 1  // Default to USA
    @State private var totalTitles = 0
    @State private var downloadedTitles = 0
    
    private var systemFilesAvailable: Bool {
        var status = [false, false]
        az_get_are_system_titles_installed(&status)
        return status[0] && status[1]  // Both Old3DS and New3DS
    }
    
    private let regions = [
        (0, "Japan"),
        (1, "USA"),
        (2, "Europe"),
        (3, "Australia"),
        (4, "China"),
        (5, "Korea"),
        (6, "Taiwan")
    ]
    
    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: downloadComplete ? "checkmark.circle.fill" : "arrow.down.circle")
                                .font(.title)
                                .foregroundStyle(downloadComplete ? .green : .blue)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text(statusTitle)
                                    .font(.headline)
                                
                                Text(statusMessage)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        
                        if isDownloading {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Downloading: \(currentFile)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                
                                ProgressView(value: downloadProgress, total: Double(totalTitles))
                                    .progressViewStyle(.linear)
                                
                                Text("\(downloadedTitles) / \(totalTitles) titles installed")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.vertical, 8)
                } header: {
                    Text("Status")
                }
                
                Section {
                    FileStatusRow(
                        name: "AES Keys",
                        detail: "Required for decrypting game data",
                        installed: az_are_keys_available()
                    )
                    FileStatusRow(
                        name: "Old 3DS System Titles",
                        detail: "Base system firmware",
                        installed: {
                            var status = [false, false]
                            az_get_are_system_titles_installed(&status)
                            return status[0]
                        }()
                    )
                    FileStatusRow(
                        name: "New 3DS System Titles",
                        detail: "Enhanced system firmware",
                        installed: {
                            var status = [false, false]
                            az_get_are_system_titles_installed(&status)
                            return status[1]
                        }()
                    )
                } header: {
                    Text("System Files")
                }
                
                if !az_are_keys_available() {
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("⚠️ AES Keys Missing")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                            
                            Text("AES keys are required to download and decrypt system files. Please place your aes_keys.txt file in the Documents/azahar/sysdata/ folder.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } header: {
                        Text("Requirements")
                    }
                }
                
                if !systemFilesAvailable && az_are_keys_available() {
                    Section {
                        Picker("Region", selection: $selectedRegion) {
                            ForEach(regions, id: \.0) { region in
                                Text(region.1).tag(region.0)
                            }
                        }
                        .pickerStyle(.menu)
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("This will download and install 3DS system titles from Nintendo's servers. The download includes:")
                                .font(.caption)
                            
                            Text("• Old 3DS system titles (Home Menu, system apps)")
                                .font(.caption2)
                            Text("• New 3DS system titles (enhanced firmware)")
                                .font(.caption2)
                            
                            Text("\nDownload size: ~150-200 MB")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    } header: {
                        Text("Download Options")
                    }
                    
                    Section {
                        if isDownloading {
                            Button(role: .destructive) {
                                cancelDownload()
                            } label: {
                                Label("Cancel Download", systemImage: "xmark.circle")
                            }
                        }
                    }
                }
            }
            .navigationTitle("System Files Setup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if !isDownloading {
                        Button("Close") { dismiss() }
                    }
                }
                
                ToolbarItem(placement: .primaryAction) {
                    if downloadComplete {
                        Button("Done") { dismiss() }
                            .fontWeight(.semibold)
                    } else if !isDownloading && !systemFilesAvailable && az_are_keys_available() {
                        Button("Download") { startDownload() }
                            .fontWeight(.semibold)
                    }
                }
            }
            .alert("Download Error", isPresented: $showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage)
            }
        }
        .interactiveDismissDisabled(isDownloading)
    }
    
    private var statusTitle: String {
        if downloadComplete {
            return "Download Complete"
        }
        if isDownloading {
            return "Downloading System Files"
        }
        if systemFilesAvailable {
            return "System Files Ready"
        }
        if !az_are_keys_available() {
            return "AES Keys Required"
        }
        return "System Files Required"
    }
    
    private func startDownload() {
        isDownloading = true
        downloadProgress = 0
        downloadedTitles = 0
        statusMessage = "Preparing download..."
        
        Task {
            do {
                // Get all system title IDs (Old3DS + New3DS = 6)
                let maxTitles = 200
                var titleIds = [Int64](repeating: 0, count: maxTitles)
                let count = Int(az_get_system_title_ids(6, Int32(selectedRegion), &titleIds, Int32(maxTitles)))
                
                guard count > 0 else {
                    throw SystemFilesError.noTitles
                }
                
                let titles = Array(titleIds.prefix(count))
                totalTitles = titles.count
                
                await MainActor.run {
                    statusMessage = "Downloading \(totalTitles) system titles..."
                }
                
                // Download titles with retry logic
                let retryCount = 3
                for (index, titleId) in titles.enumerated() {
                    await MainActor.run {
                        currentFile = String(format: "Title %016llX (%d/%d)", titleId, index + 1, totalTitles)
                    }
                    
                    var success = false
                    for attempt in 1...retryCount {
                        let result = az_download_title_from_nus(titleId)
                        
                        if result == 0 {  // InstallStatus::Success
                            success = true
                            break
                        } else if attempt < retryCount {
                            // Retry after delay
                            try await Task.sleep(nanoseconds: 3_000_000_000)  // 3 seconds
                        } else {
                            // Failed after all retries
                            throw SystemFilesError.downloadFailed(titleId, Int(result))
                        }
                    }
                    
                    if success {
                        await MainActor.run {
                            downloadedTitles += 1
                            downloadProgress = Double(downloadedTitles)
                        }
                    }
                }
                
                await MainActor.run {
                    downloadProgress = Double(totalTitles)
                    downloadComplete = true
                    statusMessage = "All system files downloaded successfully"
                    isDownloading = false
                }
                
            } catch {
                await MainActor.run {
                    isDownloading = false
                    errorMessage = error.localizedDescription
                    showError = true
                    statusMessage = "Download failed"
                }
            }
        }
    }
    
    private func cancelDownload() {
        isDownloading = false
        statusMessage = "Download cancelled"
    }
}

struct FileStatusRow: View {
    let name: String
    let detail: String
    let installed: Bool
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.subheadline)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            if installed {
                Label("Installed", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
            } else {
                Label("Missing", systemImage: "xmark.circle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding(.vertical, 2)
    }
}

enum SystemFilesError: LocalizedError {
    case noTitles
    case downloadFailed(Int64, Int)
    
    var errorDescription: String? {
        switch self {
        case .noTitles:
            return "No system titles found for the selected region"
        case .downloadFailed(let titleId, let status):
            let statusMsg: String
            switch status {
            case 1: statusMsg = "Failed to open file"
            case 2: statusMsg = "File not found on server"
            case 3: statusMsg = "Download aborted"
            case 4: statusMsg = "Invalid title data"
            case 5: statusMsg = "Encrypted content (keys missing)"
            default: statusMsg = "Unknown error"
            }
            return String(format: "Failed to download title %016llX: %@", titleId, statusMsg)
        }
    }
}

#Preview {
    SystemFilesDownloaderView()
}
