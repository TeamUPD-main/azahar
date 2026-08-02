// Copyright Citra Emulator Project / Azahar Emulator Project
// Licensed under GPLv2 or any later version
// Refer to the license.txt file included.

import SwiftUI
import UniformTypeIdentifiers

/// System files management (equivalent to Android's SystemFilesFragment).
/// Allows users to manage NAND titles, system archives, and unique data.
struct SystemFilesView: View {
    @EnvironmentObject var appState: AppState
    @State private var isLinked = false
    @State private var systemTitlesAvailable = false
    @State private var isLoading = false
    @State private var showingAlert = false
    @State private var alertMessage = ""
    @State private var showingZipPassExport = false
    @State private var showingZipPassImport = false
    @State private var showingCIAImport = false
    @State private var installProgress: Double = 0
    @State private var isInstalling = false

    var body: some View {
        List {
            Section("Console Status") {
                HStack {
                    Label("Console Linked", systemImage: "link")
                    Spacer()
                    Text(isLinked ? "Yes" : "No")
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Label("3DS System Titles", systemImage: "internaldrive")
                    Spacer()
                    Text(systemTitlesAvailable ? "Installed" : "Not found")
                        .foregroundStyle(.secondary)
                }
            }

            Section("System Files") {
                Button {
                    showingCIAImport = true
                } label: {
                    Label("Install System CIA", systemImage: "arrow.down.doc")
                }
                
                if isInstalling {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Installing...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        ProgressView(value: installProgress)
                    }
                }
                
                Text("Install 3DS system files (Home Menu, Mii Maker, etc.) from CIA files. You can obtain these from your own 3DS console.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("StreetPass (ZipPass)") {
                Button {
                    exportZipPass()
                } label: {
                    Label("Export StreetPass Data", systemImage: "square.and.arrow.up")
                }
                
                Button {
                    showingZipPassImport = true
                } label: {
                    Label("Import StreetPass Data", systemImage: "square.and.arrow.down")
                }
                
                Button(role: .destructive) {
                    clearStreetPassData()
                } label: {
                    Label("Clear StreetPass Data", systemImage: "trash")
                }
                
                Text("Export and import StreetPass Mii Plaza data to share with other devices or backup your progress.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("System Archives") {
                if isLoading {
                    ProgressView("Loading...")
                } else {
                    ForEach(SystemArchiveType.allCases) { archive in
                        HStack {
                            Label(archive.displayName, systemImage: archive.icon)
                            Spacer()
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        }
                    }
                }
            }

            Section("Actions") {
                Button {
                    let keysAvailable = az_are_keys_available()
                    alertMessage = keysAvailable
                        ? "AES keys are available."
                        : "AES keys not available. System archives may not work."
                    showingAlert = true
                } label: {
                    Label("Check AES Keys", systemImage: "key")
                }

                if isLinked {
                    Button(role: .destructive) {
                        az_unlink_console()
                        isLinked = az_is_full_console_linked()
                    } label: {
                        Label("Unlink Console", systemImage: "link.badge.xmark")
                    }
                }
            }
        }
        .navigationTitle("System Files")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            checkSystemStatus()
        }
        .alert("System Files", isPresented: $showingAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(alertMessage)
        }
        .fileImporter(
            isPresented: $showingCIAImport,
            allowedContentTypes: [UTType(filenameExtension: "cia") ?? .data],
            allowsMultipleSelection: false
        ) { result in
            handleCIAImport(result)
        }
        .fileExporter(
            isPresented: $showingZipPassExport,
            document: ZipPassDocument(),
            contentType: .zip,
            defaultFilename: "streetpass_\(Int(Date().timeIntervalSince1970)).zip"
        ) { result in
            handleZipPassExport(result)
        }
        .fileImporter(
            isPresented: $showingZipPassImport,
            allowedContentTypes: [.zip],
            allowsMultipleSelection: false
        ) { result in
            handleZipPassImport(result)
        }
    }
    
    private func checkSystemStatus() {
        isLinked = az_is_full_console_linked()
        systemTitlesAvailable = az_system_files_available()
    }
    
    private func handleCIAImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            
            guard url.startAccessingSecurityScopedResource() else {
                alertMessage = "Failed to access file"
                showingAlert = true
                return
            }
            defer { url.stopAccessingSecurityScopedResource() }
            
            isInstalling = true
            installProgress = 0
            
            DispatchQueue.global(qos: .userInitiated).async {
                let result = az_install_cia(url.path)
                
                DispatchQueue.main.async {
                    isInstalling = false
                    
                    if result == 0 {
                        alertMessage = "System file installed successfully!"
                        checkSystemStatus()
                    } else {
                        alertMessage = "Failed to install system file. Error code: \(result)"
                    }
                    showingAlert = true
                }
            }
            
        case .failure(let error):
            alertMessage = "Failed to import CIA: \(error.localizedDescription)"
            showingAlert = true
        }
    }
    
    private func exportZipPass() {
        showingZipPassExport = true
    }
    
    private func handleZipPassExport(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            guard url.startAccessingSecurityScopedResource() else {
                alertMessage = "Failed to access export location"
                showingAlert = true
                return
            }
            defer { url.stopAccessingSecurityScopedResource() }
            
            let result = az_zippass_export(url.path)
            
            if result == 0 {
                alertMessage = "StreetPass data exported successfully!"
            } else {
                alertMessage = "Failed to export StreetPass data. Error code: \(result)"
            }
            showingAlert = true
            
        case .failure(let error):
            alertMessage = "Failed to export: \(error.localizedDescription)"
            showingAlert = true
        }
    }
    
    private func handleZipPassImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            
            guard url.startAccessingSecurityScopedResource() else {
                alertMessage = "Failed to access file"
                showingAlert = true
                return
            }
            defer { url.stopAccessingSecurityScopedResource() }
            
            let result = az_zippass_import(url.path)
            
            if result == 0 {
                alertMessage = "StreetPass data imported successfully!"
            } else {
                alertMessage = "Failed to import StreetPass data. Error code: \(result)"
            }
            showingAlert = true
            
        case .failure(let error):
            alertMessage = "Failed to import: \(error.localizedDescription)"
            showingAlert = true
        }
    }
    
    private func clearStreetPassData() {
        let result = az_zippass_clear_config()
        
        if result == 0 {
            alertMessage = "StreetPass data cleared successfully!"
        } else {
            alertMessage = "Failed to clear StreetPass data. Error code: \(result)"
        }
        showingAlert = true
    }
}

/// Helper document for ZipPass export
struct ZipPassDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.zip] }
    
    init() {}
    
    init(configuration: ReadConfiguration) throws {}
    
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        // Create a temporary file for the export
        let tempDir = FileManager.default.temporaryDirectory
        let tempFile = tempDir.appendingPathComponent("streetpass_export.zip")
        
        // Export the zippass data
        let result = az_zippass_export(tempFile.path)
        guard result == 0, FileManager.default.fileExists(atPath: tempFile.path) else {
            throw CocoaError(.fileWriteUnknown)
        }
        
        return try FileWrapper(url: tempFile, options: .immediate)
    }
}

enum SystemArchiveType: String, CaseIterable, Identifiable {
    case sharedFont = "Shared Font"
    case badWordList = "Bad Word List"
    case region = "Region Manifest"
    case homeMenu = "Home Menu"
    case miiMaker = "Mii Maker"
    
    var id: String { rawValue }
    
    var displayName: String { rawValue }
    
    var icon: String {
        switch self {
        case .sharedFont: return "textformat"
        case .badWordList: return "exclamationmark.shield"
        case .region: return "globe"
        case .homeMenu: return "house"
        case .miiMaker: return "person.circle"
        }
    }
}
