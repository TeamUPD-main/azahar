// Copyright Citra Emulator Project / Azahar Emulator Project
// Licensed under GPLv2 or any later version
// Refer to the license.txt file included.

import SwiftUI

struct Achievement: Identifiable {
    let id: UInt32
    let title: String
    let description: String
    let badgeUrl: String
    let points: UInt32
    let unlocked: Bool
    let hardcore: Bool
    let progressIndicator: String
    let progressPercent: Float
}

struct AchievementListView: View {
    @State private var achievements: [Achievement] = []
    @State private var isLoading = true
    @State private var game: AzaharBridge.GameInfo?
    
    var body: some View {
        VStack {
            if isLoading {
                ProgressView("Loading achievements...")
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
                                Text("\(game.numUnlocked) / \(game.numAchievements) unlocked")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    
                    Section("Achievements") {
                        ForEach(achievements) { achievement in
                            AchievementRow(achievement: achievement)
                        }
                    }
                }
            } else {
                ContentUnavailableView(
                    "No Game Loaded",
                    systemImage: "gamecontroller",
                    description: Text("Start a game to view achievements")
                )
            }
        }
        .navigationTitle("Achievements")
        .onAppear {
            loadAchievements()
        }
    }
    
    func loadAchievements() {
        guard let gameInfo = AzaharBridge.getRAGame() else {
            isLoading = false
            return
        }
        
        game = gameInfo
        
        // Get achievement count
        let count = az_ra_get_achievements(nil, 0)
        guard count > 0 else {
            isLoading = false
            return
        }
        
        // Allocate buffer and fetch achievements
        var buffer = [az_ra_achievement_t](repeating: az_ra_achievement_t(), count: Int(count))
        let fetched = az_ra_get_achievements(&buffer, Int32(count))
        
        achievements = (0..<Int(fetched)).map { i in
            let ach = buffer[i]
            return Achievement(
                id: ach.id,
                title: String(cString: ach.title),
                description: String(cString: ach.description),
                badgeUrl: String(cString: ach.badge_url),
                points: ach.points,
                unlocked: ach.unlocked,
                hardcore: ach.hardcore,
                progressIndicator: String(cString: ach.progress_indicator),
                progressPercent: ach.progress_percent
            )
        }
        
        isLoading = false
    }
}

struct AchievementRow: View {
    let achievement: Achievement
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            AsyncImage(url: URL(string: achievement.badgeUrl)) { image in
                image.resizable().scaledToFit()
            } placeholder: {
                ProgressView()
            }
            .frame(width: 48, height: 48)
            .cornerRadius(8)
            .opacity(achievement.unlocked ? 1.0 : 0.5)
            
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(achievement.title)
                        .font(.headline)
                    
                    Spacer()
                    
                    HStack(spacing: 4) {
                        Image(systemName: achievement.hardcore ? "star.fill" : "star")
                            .foregroundColor(.yellow)
                        Text("\(achievement.points)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                
                Text(achievement.description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                if achievement.unlocked {
                    Label("Unlocked", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundColor(.green)
                } else if achievement.progressPercent > 0 {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(achievement.progressIndicator)
                            .font(.caption)
                            .foregroundColor(.blue)
                        
                        ProgressView(value: Double(achievement.progressPercent), total: 100)
                            .tint(.blue)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    NavigationStack {
        AchievementListView()
    }
}
