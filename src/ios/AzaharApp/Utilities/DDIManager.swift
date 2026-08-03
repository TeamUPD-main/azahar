// Copyright Citra Emulator Project / Azahar Emulator Project
// Licensed under GPLv2 or any later version
// Refer to the license.txt file included.

import Foundation

/// Manages downloading and mounting Developer Disk Images (DDI) for iOS debugging
@MainActor
class DDIManager: ObservableObject {
    static let shared = DDIManager()
    
    @Published var downloadProgress: Double = 0.0
    @Published var isDownloading = false
    @Published var isReady = false
    @Published var statusMessage = ""
    
    private let fileManager = FileManager.default
    private var documentsDirectory: URL {
        fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
    
    private var ddiDirectory: URL {
        documentsDirectory.appendingPathComponent("DDI", isDirectory: true)
    }
    
    // DDI file URLs for current iOS version
    private var imageURL: URL {
        ddiDirectory.appendingPathComponent("Image.dmg")
    }
    
    private var signatureURL: URL {
        ddiDirectory.appendingPathComponent("Image.dmg.signature")
    }
    
    private var trustcacheURL: URL {
        ddiDirectory.appendingPathComponent("Image.dmg.trustcache")
    }
    
    private var manifestURL: URL {
        ddiDirectory.appendingPathComponent("BuildManifest.plist")
    }
    
    private init() {
        createDDIDirectoryIfNeeded()
        checkIfReady()
    }
    
    private func createDDIDirectoryIfNeeded() {
        if !fileManager.fileExists(atPath: ddiDirectory.path) {
            try? fileManager.createDirectory(at: ddiDirectory, withIntermediateDirectories: true)
        }
    }
    
    /// Check if all required DDI files are present
    func checkIfReady() {
        let requiredFiles = [imageURL, trustcacheURL]
        isReady = requiredFiles.allSatisfy { fileManager.fileExists(atPath: $0.path) }
        
        if isReady {
            statusMessage = "DDI files ready"
        } else {
            statusMessage = "DDI files not found"
        }
    }
    
    /// Download DDI files for the current iOS version
    func downloadDDIFiles() async throws {
        guard !isDownloading else { return }
        
        isDownloading = true
        downloadProgress = 0.0
        statusMessage = "Detecting iOS version..."
        
        defer {
            isDownloading = false
        }
        
        // Get iOS version
        let osVersion = ProcessInfo.processInfo.operatingSystemVersion
        let versionString = "\(osVersion.majorVersion).\(osVersion.minorVersion)"
        
        statusMessage = "Downloading DDI for iOS \(versionString)..."
        
        // Base URL for DDI downloads
        // TODO: Replace with actual DDI mirror URL
        let baseURL = "https://github.com/mspvirajpatel/Xcode_Developer_Disk_Images/releases/download/\(versionString)"
        
        let filesToDownload: [(url: String, destination: URL)] = [
            ("\(baseURL)/Image.dmg", imageURL),
            ("\(baseURL)/Image.dmg.signature", signatureURL),
            ("\(baseURL)/Image.dmg.trustcache", trustcacheURL),
            ("\(baseURL)/BuildManifest.plist", manifestURL)
        ]
        
        let totalFiles = Double(filesToDownload.count)
        
        for (index, item) in filesToDownload.enumerated() {
            // Skip if file already exists
            if fileManager.fileExists(atPath: item.destination.path) {
                downloadProgress = Double(index + 1) / totalFiles
                continue
            }
            
            statusMessage = "Downloading \(item.destination.lastPathComponent)..."
            
            do {
                try await downloadFile(from: item.url, to: item.destination)
            } catch {
                // Signature and manifest are optional
                if item.destination == signatureURL || item.destination == manifestURL {
                    print("[DDI] Optional file download failed: \(error)")
                    continue
                }
                throw error
            }
            
            downloadProgress = Double(index + 1) / totalFiles
        }
        
        checkIfReady()
        
        if isReady {
            statusMessage = "DDI download complete"
        } else {
            throw DDIError.downloadFailed("Required files missing after download")
        }
    }
    
    private func downloadFile(from urlString: String, to destination: URL) async throws {
        guard let url = URL(string: urlString) else {
            throw DDIError.invalidURL(urlString)
        }
        
        let (tempURL, response) = try await URLSession.shared.download(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw DDIError.downloadFailed("HTTP error: \((response as? HTTPURLResponse)?.statusCode ?? -1)")
        }
        
        // Move downloaded file to destination
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        
        try fileManager.moveItem(at: tempURL, to: destination)
        print("[DDI] Downloaded: \(destination.lastPathComponent)")
    }
    
    /// Mount the DDI using JITEnableContext
    func mountDDI() async throws {
        guard isReady else {
            throw DDIError.filesNotReady
        }
        
        statusMessage = "Mounting DDI..."
        
        let context = JITEnableContext.shared
        
        guard context.isConnected else {
            throw DDIError.notConnected
        }
        
        try context.mountDDI(
            imagePath: imageURL.path,
            signaturePath: signatureURL.path,
            trustcachePath: trustcacheURL.path
        ) { message in
            Task { @MainActor in
                self.statusMessage = message
            }
        }
        
        statusMessage = "DDI mounted successfully"
    }
    
    /// Clean up downloaded DDI files
    func cleanupDDIFiles() throws {
        if fileManager.fileExists(atPath: ddiDirectory.path) {
            try fileManager.removeItem(at: ddiDirectory)
            createDDIDirectoryIfNeeded()
            checkIfReady()
            statusMessage = "DDI files cleaned up"
        }
    }
    
    /// Get total size of DDI files
    func getDDISize() -> String {
        guard isReady else { return "N/A" }
        
        let files = [imageURL, signatureURL, trustcacheURL, manifestURL]
        var totalSize: Int64 = 0
        
        for file in files {
            if let attrs = try? fileManager.attributesOfItem(atPath: file.path),
               let size = attrs[.size] as? Int64 {
                totalSize += size
            }
        }
        
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: totalSize)
    }
}

// MARK: - Error Types

enum DDIError: LocalizedError {
    case invalidURL(String)
    case downloadFailed(String)
    case filesNotReady
    case notConnected
    
    var errorDescription: String? {
        switch self {
        case .invalidURL(let url):
            return "Invalid URL: \(url)"
        case .downloadFailed(let msg):
            return "Download failed: \(msg)"
        case .filesNotReady:
            return "DDI files not ready. Please download first."
        case .notConnected:
            return "Not connected to device services"
        }
    }
}
