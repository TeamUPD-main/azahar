// Copyright Citra Emulator Project / Azahar Emulator Project
// Licensed under GPLv2 or any later version
// Refer to the license.txt file included.

import SwiftUI

/// Main game list screen (equivalent to Android's GamesFragment).
struct GameListView: View {
    @EnvironmentObject var appState: AppState
    @State private var searchText = ""

    var filteredGames: [Game] {
        if searchText.isEmpty { return appState.games }
        return appState.games.filter {
            $0.title.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        List {
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
        }
        .navigationTitle("Games")
        .searchable(text: $searchText, prompt: "Search games...")
        .overlay {
            if appState.games.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "gamecontroller")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    Text("No games found")
                        .foregroundStyle(.secondary)
                    Text("Tap + to add ROMs to the Documents/ROMs folder")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
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
