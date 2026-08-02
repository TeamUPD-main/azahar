// Copyright Citra Emulator Project / Azahar Emulator Project
// Licensed under GPLv2 or any later version
// Refer to the license.txt file included.

import SwiftUI

/// System files management (equivalent to Android's SystemFilesFragment).
/// Allows users to manage NAND titles, system archives, and unique data.
struct SystemFilesView: View {
    @EnvironmentObject var appState: AppState
    @State private var isLinked = false
    @State private var systemTitlesAvailable = false
    @State private var isLoading = false
    @State private var showingAlert = false
    @State private var alertMessage = ""

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
        .alert("System Status", isPresented: $showingAlert) {
            Button("OK") {}
        } message: {
            Text(alertMessage)
        }
        .onAppear {
            refreshStatus()
        }
    }

    private func refreshStatus() {
        isLinked = az_is_full_console_linked()
        systemTitlesAvailable = az_are_system_titles_available()
    }

    private func az_are_system_titles_available() -> Bool {
        var installed = [Bool](repeating: false, count: 2)
        az_get_are_system_titles_installed(&installed)
        return installed[0] || installed[1]
    }
}

/// Types of system archives.
enum SystemArchiveType: String, CaseIterable, Identifiable {
    case sharedFont = "Shared Font"
    case touchScreenCalibration = "Touch Screen Calibration"
    case circlePadCalibration = "Circle Pad Calibration"

    var id: String { rawValue }
    var displayName: String { rawValue }
    var icon: String {
        switch self {
        case .sharedFont: return "textformat.abc"
        case .touchScreenCalibration: return "hand.tap"
        case .circlePadCalibration: return "arrow.up.and.down.and.arrow.left.and.right"
        }
    }
}
