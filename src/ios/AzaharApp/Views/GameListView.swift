// Copyright Citra Emulator Project / Azahar Emulator Project
// Licensed under GPLv2 or any later version
// Refer to the license.txt file included.

import SwiftUI
import UniformTypeIdentifiers

/// Main game list screen (equivalent to Android's GamesFragment).
struct GameListView: View {
    @EnvironmentObject var appState: AppState
    @State private var searchText = ""
    @State private var showingCIAImport = false
    @State private var isInstallingCIA = false
    @State private var installMessage = ""
    @State private var showInstallResult = false

    var filteredGames: [Game] {
        if searchText.isEmpty { return appState.games }
        return appState.games.filter {
            $0.title.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        List {
            // Home Menu boot option
            Section {
                Button {
                    appState.launchHomeMenu()
                } label: {
                    HStack(spacing: 12) {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.blue.gradient)
                            .frame(width: 48, height: 48)
                            .overlay {
                                Image(systemName: "house.fill")
                                    .foregroundStyle(.white)
                            }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Home Menu")
                                .font(.headline)
                            Text("Boot 3DS System Menu")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        
                        Spacer()
                        
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
            } header: {
                Text("System")
            }
            
            // Games list
            Section {
                ForEach(filteredGames) { game in
                    Button {
                        appState.launchGame(game)
                    } label: {
                        GameRowView(game: game)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button("Properties") {
                            // TODO: show game properties
                        }
                    }
                }
            } header: {
                if !appState.games.isEmpty {
                    Text("Games")
                }
            }
        }
        .navigationTitle("Games")
        .searchable(text: $searchText, prompt: "Search games...")
        .overlay {
            if appState.games.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "gamecontroller")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    
                    Text("No games found")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    
                    VStack(spacing: 8) {
                        Text("To add games:")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        Text("1. Tap the + button above")
                            .font(.caption)
                        Text("2. Select ROM files (.3ds, .cci, .cia, .cxi)")
                            .font(.caption)
                        Text("3. Files will be imported to Documents/ROMs")
                            .font(.caption)
                    }
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                }
                .padding()
            }
        }
        .refreshable {
            appState.scanGames()
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        appState.showingDocumentPicker = true
                    } label: {
                        Label("Import ROM", systemImage: "arrow.down.doc")
                    }
                    Button {
                        showingCIAImport = true
                    } label: {
                        Label("Install CIA", systemImage: "shippingbox")
                    }
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $appState.showingDocumentPicker) {
            DocumentPicker(onComplete: { urls in
                for url in urls {
                    appState.importROM(from: url)
                }
                appState.scanGames()
            })
        }
        .fileImporter(
            isPresented: $showingCIAImport,
            allowedContentTypes: [UTType(filenameExtension: "cia") ?? .data],
            allowsMultipleSelection: false
        ) { result in
            handleCIAImport(result)
        }
        .alert("CIA Install", isPresented: $showInstallResult) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(installMessage)
        }
        .overlay {
            if isInstallingCIA {
                ZStack {
                    Color.black.opacity(0.4)
                        .ignoresSafeArea()
                    VStack(spacing: 12) {
                        ProgressView()
                            .scaleEffect(1.5)
                        Text("Installing CIA...")
                            .font(.headline)
                            .foregroundStyle(.white)
                        Text("This may take a moment")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.8))
                    }
                }
            }
        }
    }

    private func handleCIAImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }

            guard url.startAccessingSecurityScopedResource() else {
                installMessage = "Failed to access the selected file."
                showInstallResult = true
                return
            }
            defer { url.stopAccessingSecurityScopedResource() }

            isInstallingCIA = true
            DispatchQueue.global(qos: .userInitiated).async {
                let result = az_install_cia(url.path)
                DispatchQueue.main.async {
                    isInstallingCIA = false
                    installMessage = result == 0
                        ? "CIA installed successfully!"
                        : "Failed to install CIA. Error code: \(result)"
                    showInstallResult = true
                    appState.scanGames()
                }
            }

        case .failure(let error):
            installMessage = "Failed to import file: \(error.localizedDescription)"
            showInstallResult = true
        }
    }
}

struct GameRowView: View {
    let game: Game

    var body: some View {
        HStack(spacing: 12) {
            // Game icon placeholder
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(.systemGray5))
                .frame(width: 48, height: 48)
                .overlay {
                    Image(systemName: "gamecontroller.fill")
                        .foregroundStyle(.secondary)
                }

            VStack(alignment: .leading, spacing: 4) {
                Text(game.title)
                    .font(.headline)
                    .lineLimit(1)
                Text(game.formattedTitleId)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}
