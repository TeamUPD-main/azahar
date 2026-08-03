// Copyright Citra Emulator Project / Azahar Emulator Project
// Licensed under GPLv2 or any later version
// Refer to the license.txt file included.

import SwiftUI

struct RANotification: Identifiable {
    let id = UUID()
    let type: Int32
    let title: String
    let description: String
    let badgeUrl: String
    let value: String
    var isVisible: Bool = true
}

class RANotificationManager: ObservableObject {
    @Published var notifications: [RANotification] = []
    @Published var activeTrackers: [String] = []
    @Published var activeChallenges: [RANotification] = []
    @Published var activeProgress: [RANotification] = []
    
    static let shared = RANotificationManager()
    
    private init() {
        setupEventCallback()
    }
    
    func setupEventCallback() {
        az_ra_set_event_callback { eventType, title, description, badgeUrl, value in
            guard let title = title, let description = description, 
                  let badgeUrl = badgeUrl, let value = value else { return }
            
            let titleStr = String(cString: title)
            let descStr = String(cString: description)
            let badgeStr = String(cString: badgeUrl)
            let valueStr = String(cString: value)
            
            DispatchQueue.main.async {
                RANotificationManager.shared.handleEvent(
                    type: eventType,
                    title: titleStr,
                    description: descStr,
                    badgeUrl: badgeStr,
                    value: valueStr
                )
            }
        }
    }
    
    func handleEvent(type: Int32, title: String, description: String, badgeUrl: String, value: String) {
        switch type {
        case 0: // AZ_RA_EVENT_ACHIEVEMENT_TRIGGERED
            showAchievementUnlocked(title: title, description: description, badgeUrl: badgeUrl)
            
        case 1: // AZ_RA_EVENT_LEADERBOARD_STARTED
            showLeaderboardStarted(title: title)
            
        case 2: // AZ_RA_EVENT_LEADERBOARD_SUBMITTED
            showLeaderboardSubmitted(title: title)
            
        case 3: // AZ_RA_EVENT_CHALLENGE_INDICATOR_SHOW
            showChallengeIndicator(title: title, description: description, badgeUrl: badgeUrl)
            
        case 4: // AZ_RA_EVENT_CHALLENGE_INDICATOR_HIDE
            hideChallengeIndicator(title: title)
            
        case 5: // AZ_RA_EVENT_PROGRESS_INDICATOR_SHOW
            showProgressIndicator(title: title, description: description, badgeUrl: badgeUrl, value: value)
            
        case 6: // AZ_RA_EVENT_PROGRESS_INDICATOR_HIDE
            hideProgressIndicator(title: title)
            
        case 7: // AZ_RA_EVENT_PROGRESS_INDICATOR_UPDATE
            updateProgressIndicator(title: title, value: value)
            
        case 8: // AZ_RA_EVENT_LEADERBOARD_TRACKER_SHOW
            showLeaderboardTracker(title: title)
            
        case 9: // AZ_RA_EVENT_LEADERBOARD_TRACKER_HIDE
            hideLeaderboardTracker(title: title)
            
        case 10: // AZ_RA_EVENT_LEADERBOARD_TRACKER_UPDATE
            updateLeaderboardTracker(title: title)
            
        default:
            break
        }
    }
    
    func showAchievementUnlocked(title: String, description: String, badgeUrl: String) {
        let notification = RANotification(
            type: 0,
            title: title,
            description: description,
            badgeUrl: badgeUrl,
            value: ""
        )
        notifications.append(notification)
        
        // Auto-dismiss after 5 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            self.notifications.removeAll { $0.id == notification.id }
        }
    }
    
    func showLeaderboardStarted(title: String) {
        let notification = RANotification(
            type: 1,
            title: "Leaderboard Active",
            description: title,
            badgeUrl: "",
            value: ""
        )
        notifications.append(notification)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            self.notifications.removeAll { $0.id == notification.id }
        }
    }
    
    func showLeaderboardSubmitted(title: String) {
        let notification = RANotification(
            type: 2,
            title: "Score Submitted",
            description: title,
            badgeUrl: "",
            value: ""
        )
        notifications.append(notification)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            self.notifications.removeAll { $0.id == notification.id }
        }
    }
    
    func showChallengeIndicator(title: String, description: String, badgeUrl: String) {
        let challenge = RANotification(
            type: 3,
            title: title,
            description: description,
            badgeUrl: badgeUrl,
            value: ""
        )
        activeChallenges.append(challenge)
    }
    
    func hideChallengeIndicator(title: String) {
        activeChallenges.removeAll { $0.title == title }
    }
    
    func showProgressIndicator(title: String, description: String, badgeUrl: String, value: String) {
        let progress = RANotification(
            type: 5,
            title: title,
            description: description,
            badgeUrl: badgeUrl,
            value: value
        )
        activeProgress.append(progress)
    }
    
    func hideProgressIndicator(title: String) {
        activeProgress.removeAll { $0.title == title }
    }
    
    func updateProgressIndicator(title: String, value: String) {
        if let index = activeProgress.firstIndex(where: { $0.title == title }) {
            var updated = activeProgress[index]
            updated = RANotification(
                type: updated.type,
                title: updated.title,
                description: updated.description,
                badgeUrl: updated.badgeUrl,
                value: value
            )
            activeProgress[index] = updated
        }
    }
    
    func showLeaderboardTracker(title: String) {
        if !activeTrackers.contains(title) {
            activeTrackers.append(title)
        }
    }
    
    func hideLeaderboardTracker(title: String) {
        activeTrackers.removeAll { $0 == title }
    }
    
    func updateLeaderboardTracker(title: String) {
        // Already shown, just update the value (handled by the tracker itself)
    }
}

struct RANotificationView: View {
    let notification: RANotification
    
    var body: some View {
        HStack(spacing: 12) {
            if !notification.badgeUrl.isEmpty {
                AsyncImage(url: URL(string: notification.badgeUrl)) { image in
                    image.resizable().scaledToFit()
                } placeholder: {
                    ProgressView()
                }
                .frame(width: 48, height: 48)
                .cornerRadius(8)
            } else {
                Image(systemName: notification.type == 0 ? "trophy.fill" : "chart.bar.fill")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 48, height: 48)
                    .foregroundColor(.yellow)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(notification.title)
                    .font(.headline)
                    .foregroundColor(.white)
                
                if !notification.description.isEmpty {
                    Text(notification.description)
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.8))
                }
            }
            
            Spacer()
        }
        .padding()
        .background(Color.black.opacity(0.85))
        .cornerRadius(12)
        .shadow(radius: 10)
    }
}

struct RAOverlayView: View {
    @ObservedObject var manager = RANotificationManager.shared
    
    var body: some View {
        ZStack {
            // Notifications (top center)
            VStack(spacing: 8) {
                ForEach(manager.notifications) { notification in
                    RANotificationView(notification: notification)
                        .frame(maxWidth: 400)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.top, 50)
            
            // Challenge indicators (bottom left)
            VStack(alignment: .leading, spacing: 8) {
                ForEach(manager.activeChallenges) { challenge in
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text(challenge.title)
                            .font(.caption)
                            .foregroundColor(.white)
                    }
                    .padding(8)
                    .background(Color.black.opacity(0.7))
                    .cornerRadius(8)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            .padding(16)
            
            // Progress indicators (bottom center)
            VStack(spacing: 8) {
                ForEach(manager.activeProgress) { progress in
                    VStack(spacing: 4) {
                        Text(progress.title)
                            .font(.caption)
                            .foregroundColor(.white)
                        if !progress.value.isEmpty {
                            Text(progress.value)
                                .font(.caption2)
                                .foregroundColor(.blue)
                        }
                    }
                    .padding(8)
                    .background(Color.black.opacity(0.7))
                    .cornerRadius(8)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .padding(.bottom, 16)
            
            // Leaderboard trackers (top right)
            VStack(alignment: .trailing, spacing: 8) {
                ForEach(manager.activeTrackers, id: \.self) { tracker in
                    Text(tracker)
                        .font(.caption)
                        .foregroundColor(.white)
                        .padding(8)
                        .background(Color.black.opacity(0.7))
                        .cornerRadius(8)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            .padding(16)
        }
        .animation(.spring(), value: manager.notifications.count)
        .animation(.spring(), value: manager.activeChallenges.count)
        .animation(.spring(), value: manager.activeProgress.count)
        .animation(.spring(), value: manager.activeTrackers.count)
    }
}

#Preview {
    RAOverlayView()
        .background(Color.gray)
}
