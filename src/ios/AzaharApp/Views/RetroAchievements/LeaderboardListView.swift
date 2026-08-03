// Copyright Citra Emulator Project / Azahar Emulator Project
// Licensed under GPLv2 or any later version
// Refer to the license.txt file included.

import SwiftUI

struct Leaderboard: Identifiable {
    let id: UInt32
    let title: String
    let description: String
    let numEntries: UInt32
}

struct LeaderboardListView: View {
    @State private var leaderboards: [Leaderboard] = []
    @State private var isLoading = true
    @State private var game: AzaharBridge.GameInfo?
    
    var body: some View {
        VStack {
            if isLoading {
                ProgressView("Loading leaderboards...")
            } else if let game = game {
                List {
                    Section {
                        HStack {
                            AsyncImage(url: URL(string: game.badgeUrl)) { image in
                                image.resizable().scaledToFit()
                            } placeholder: {
                                ProgressView()
                            }
                            .frame(width: 64, height: 64)
                            .cornerRadius(8)
                            
                            VStack(alignment: .leading) {
                                Text(game.title)
                                    .font(.headline)
                                Text("\(game.numLeaderboards) leaderboards")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    
                    if leaderboards.isEmpty {
                        Section {
                            ContentUnavailableView(
                                "No Leaderboards",
                                systemImage: "chart.bar",
                                description: Text("This game has no leaderboards")
                            )
                        }
                    } else {
                        Section("Leaderboards") {
                            ForEach(leaderboards) { leaderboard in
                                LeaderboardRow(leaderboard: leaderboard)
                            }
                        }
                    }
                }
            } else {
                ContentUnavailableView(
                    "No Game Loaded",
                    systemImage: "gamecontroller",
                    description: Text("Start a game to view leaderboards")
                )
            }
        }
        .navigationTitle("Leaderboards")
        .onAppear {
            loadLeaderboards()
        }
    }
    
    func loadLeaderboards() {
        guard let gameInfo = AzaharBridge.getRAGame() else {
            isLoading = false
            return
        }
        
        game = gameInfo
        
        // Get leaderboard count
        let count = az_ra_get_leaderboards(nil, 0)
        guard count > 0 else {
            isLoading = false
            return
        }
        
        // Allocate buffer and fetch leaderboards
        var buffer = [az_ra_leaderboard_t](repeating: az_ra_leaderboard_t(), count: Int(count))
        let fetched = az_ra_get_leaderboards(&buffer, Int32(count))
        
        leaderboards = (0..<Int(fetched)).map { i in
            let lb = buffer[i]
            return Leaderboard(
                id: lb.id,
                title: String(cString: lb.title),
                description: String(cString: lb.description),
                numEntries: lb.num_entries
            )
        }
        
        isLoading = false
    }
}

struct LeaderboardRow: View {
    let leaderboard: Leaderboard
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(leaderboard.title)
                .font(.headline)
            
            Text(leaderboard.description)
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            if leaderboard.numEntries > 0 {
                Label("\(leaderboard.numEntries) entries", systemImage: "person.2")
                    .font(.caption)
                    .foregroundColor(.blue)
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    NavigationStack {
        LeaderboardListView()
    }
}
