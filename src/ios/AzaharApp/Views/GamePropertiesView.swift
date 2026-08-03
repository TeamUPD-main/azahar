// Copyright Citra Emulator Project / Azahar Emulator Project
// Licensed under GPLv2 or any later version
// Refer to the license.txt file included.

import SwiftUI

/// Per-game settings and properties sheet
struct GamePropertiesView: View {
    let game: Game
    @Environment(\.dismiss) private var dismiss
    @State private var showDeleteConfirmation = false
    
    var body: some View {
        NavigationStack {
            List {
                // Game info section
                Section {
                    HStack(spacing: 16) {
                        // Icon
                        if let iconData = game.iconImage, let uiImage = UIImage(data: iconData) {
                            Image(uiImage: uiImage)
                                .resizable()
                                .interpolation(.none)
                                .frame(width: 80, height: 80)
                                .cornerRadius(12)
                        } else {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color(.systemGray5))
                                .frame(width: 80, height: 80)
                                .overlay {
                                    Image(systemName: "gamecontroller.fill")
                                        .font(.largeTitle)
                                        .foregroundStyle(.secondary)
                                }
                        }
                        
                        VStack(alignment: .leading, spacing: 6) {
                            Text(game.title)
                                .font(.headline)
                                .lineLimit(2)
                            
                            if !game.publisher.isEmpty {
                                Text(game.publisher)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            
                            Text(game.formattedTitleId)
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                                .fontDesign(.monospaced)
                        }
                    }
                    .padding(.vertical, 8)
                } header: {
                    Text("Game Information")
                }
                
                // Statistics
                Section {
                    LabeledContent("Play Time") {
                        Text(game.formattedPlayTime)
                            .foregroundStyle(.secondary)
                    }
                    
                    LabeledContent("Title ID") {
                        Text(game.formattedTitleId)
                            .font(.caption)
                            .fontDesign(.monospaced)
                            .foregroundStyle(.secondary)
                    }
                    
                    LabeledContent("File Path") {
                        Text(game.path.components(separatedBy: "/").last ?? "")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                } header: {
                    Text("Details")
                }
                
                // Per-game configuration
                Section {
                    NavigationLink {
                        PerGameSettingsView(game: game)
                    } label: {
                        Label("Game Settings", systemImage: "slider.horizontal.3")
                    }
                    
                    NavigationLink {
                        CheatManagementView(game: game)
                    } label: {
                        Label("Cheats", systemImage: "terminal")
                    }
                } header: {
                    Text("Configuration")
                }
                
                // Actions
                Section {
                    Button {
                        // Open file location
                        if let url = URL(string: "shareddocuments://\(game.path)") {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        Label("Show in Files", systemImage: "folder")
                    }
                    
                    Button(role: .destructive) {
                        showDeleteConfirmation = true
                    } label: {
                        Label("Delete Game", systemImage: "trash")
                    }
                } header: {
                    Text("Actions")
                }
            }
            .navigationTitle("Properties")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .alert("Delete Game", isPresented: $showDeleteConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) {
                    deleteGame()
                }
            } message: {
                Text("Are you sure you want to delete \(game.title)? This cannot be undone.")
            }
        }
    }
    
    private func deleteGame() {
        do {
            try FileManager.default.removeItem(atPath: game.path)
            dismiss()
        } catch {
            print("Failed to delete game: \(error)")
        }
    }
}



#Preview {
    GamePropertiesView(
        game: Game(
            path: "/path/to/game.3ds",
            title: "The Legend of Zelda: Ocarina of Time 3D",
            titleId: 0x0004000000033500,
            mediaType: 0,
            publisher: "Nintendo",
            playTimeSeconds: 3723,
            iconImage: nil
        )
    )
}
