// Copyright Citra Emulator Project / Azahar Emulator Project
// Licensed under GPLv2 or any later version
// Refer to the license.txt file included.

import SwiftUI

/// Log viewer for debugging game loading and runtime issues
struct LogViewerView: View {
    @State private var logContent = ""
    @State private var isLoading = true
    @State private var autoRefresh = false
    @State private var searchText = ""
    
    private let timer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()
    
    var body: some View {
        VStack(spacing: 0) {
            // Search bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search logs...", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color(.systemBackground))
            
            Divider()
            
            // Log content
            ScrollView {
                if isLoading {
                    ProgressView("Loading logs...")
                        .padding()
                } else if logContent.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "doc.text")
                            .font(.system(size: 48))
                            .foregroundStyle(.secondary)
                        Text("No logs available")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                        Text("Logs will appear here when you run games or perform operations")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                } else {
                    Text(filteredContent)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                }
            }
        }
        .navigationTitle("Logs")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        refreshLogs()
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    
                    Toggle(isOn: $autoRefresh) {
                        Label("Auto Refresh", systemImage: "arrow.triangle.2.circlepath")
                    }
                    
                    Divider()
                    
                    Button {
                        clearLogs()
                    } label: {
                        Label("Clear Logs", systemImage: "trash")
                    }
                    
                    Button {
                        shareLogs()
                    } label: {
                        Label("Share Logs", systemImage: "square.and.arrow.up")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .onAppear {
            refreshLogs()
        }
        .onReceive(timer) { _ in
            if autoRefresh {
                refreshLogs()
            }
        }
    }
    
    private var filteredContent: String {
        guard !searchText.isEmpty else { return logContent }
        return logContent.components(separatedBy: "\n")
            .filter { $0.localizedCaseInsensitiveContains(searchText) }
            .joined(separator: "\n")
    }
    
    private func refreshLogs() {
        isLoading = true
        
        DispatchQueue.global(qos: .userInitiated).async {
            // Get log file path from Documents directory
            let docsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            let logPath = docsDir?.appendingPathComponent("log/citra_log.txt").path ?? ""
            
            var content = ""
            if FileManager.default.fileExists(atPath: logPath) {
                do {
                    content = try String(contentsOfFile: logPath, encoding: .utf8)
                    // Get last 10000 lines to avoid memory issues
                    let lines = content.components(separatedBy: "\n")
                    if lines.count > 10000 {
                        content = lines.suffix(10000).joined(separator: "\n")
                    }
                } catch {
                    content = "Error reading log file: \(error.localizedDescription)"
                }
            } else {
                content = "Log file not found at: \(logPath)\n\nLogs will be created when you run a game."
            }
            
            DispatchQueue.main.async {
                self.logContent = content
                self.isLoading = false
            }
        }
    }
    
    private func clearLogs() {
        let docsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        let logPath = docsDir?.appendingPathComponent("log/citra_log.txt").path ?? ""
        
        do {
            try "".write(toFile: logPath, atomically: true, encoding: .utf8)
            logContent = ""
        } catch {
            print("Failed to clear logs: \(error)")
        }
    }
    
    private func shareLogs() {
        let docsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        guard let logURL = docsDir?.appendingPathComponent("log/citra_log.txt") else { return }
        
        let activityVC = UIActivityViewController(activityItems: [logURL], applicationActivities: nil)
        
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootVC = windowScene.windows.first?.rootViewController {
            rootVC.present(activityVC, animated: true)
        }
    }
}

#Preview {
    NavigationStack {
        LogViewerView()
    }
}
