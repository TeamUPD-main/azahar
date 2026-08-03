// Copyright Citra Emulator Project / Azahar Emulator Project
// Licensed under GPLv2 or any later version
// Refer to the license.txt file included.

import SwiftUI
import Foundation

/// System Files Downloader - downloads and installs required 3DS system files
struct SystemFilesDownloaderView: View {
    @Environment(\.dismiss) private var dismiss
    
    @State private var isDownloading = false
    @State private var downloadProgress: Double = 0
    @State private var currentFile = ""
    @State private var statusMessage = "Ready to check system files"
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var downloadComplete = false
    
    private var systemFilesAvailable: Bool {
        // Force re-check or consider caching mechanism if needed, 
        // but current az_system_files_available() should be sufficient.
        az_system_files_available()
    }
    
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
                                
                                ProgressView(value: downloadProgress)
                                    .progressViewStyle(.linear)
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
                        name: "Shared Fonts",
                        detail: "Built into Azahar",
                        installed: true
                    )
                    FileStatusRow(
                        name: "3DS System Titles",
                        detail: "Required for Home Menu boot",
                        installed: systemFilesAvailable
                    )
                } header: {
                    Text("System Files")
                }
                
                Section {
                    if !systemFilesAvailable {
                        Text("⚠️ 3DS system titles are missing. These are required to boot the Home Menu.")
                            .font(.caption)
                        
                        Text("You can install them from a decrypted NAND dump of your own 3DS, or use the download option below.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    if isDownloading {
                        Button(role: .destructive) {
                            cancelDownload()
                        } label: {
                            Label("Cancel", systemImage: "xmark.circle")
                        }
                    }
                } header: {
                    Text("Information")
                }
            }
            .navigationTitle("System Files Setup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if !isDownloading {
                        Button("Cancel") { dismiss() }
                    }
                }
                
                ToolbarItem(placement: .primaryAction) {
                    if downloadComplete {
                        Button("Done") { dismiss() }
                            .fontWeight(.semibold)
                    } else if !isDownloading && !systemFilesAvailable {
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
        return "System Files Required"
    }
    
    private func startDownload() {
        isDownloading = true
        downloadProgress = 0
        statusMessage = "Preparing download..."
        
        Task {
            do {
                // Download AES keys if missing
                if !az_are_keys_available() {
                    await MainActor.run {
                        currentFile = "AES Keys"
                        downloadProgress = 0.2
                        statusMessage = "Downloading AES keys..."
                    }
                    let keysURL = "https://raw.githubusercontent.com/azahar-emu/azahar-system-files/main/aes_keys.txt"
                    try await downloadFile(from: keysURL, to: "sysdata/aes_keys.txt")
                }
                
                await MainActor.run {
                    downloadProgress = 1.0
                    downloadComplete = true
                    statusMessage = "System files downloaded successfully"
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
    
    private func downloadFile(from urlString: String, to relativePath: String) async throws {
        guard let url = URL(string: urlString) else {
            throw SystemFilesError.invalidURL
        }
        
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw SystemFilesError.downloadFailed(urlString)
        }
        
        // Write to the user directory
        let userDir = NSSearchPathForDirectoriesInDomains(
            .documentDirectory, .userDomainMask, true
        ).first ?? ""
        let destPath = (userDir as NSString).appendingPathComponent(relativePath)
        
        try FileManager.default.createDirectory(
            atPath: (destPath as NSString).deletingLastPathComponent,
            withIntermediateDirectories: true
        )
        try data.write(to: URL(fileURLWithPath: destPath))
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
    case invalidURL
    case downloadFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid download URL"
        case .downloadFailed(let file):
            return "Failed to download \(file)"
        }
    }
}

#Preview {
    SystemFilesDownloaderView()
}
