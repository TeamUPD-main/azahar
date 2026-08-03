// Copyright Citra Emulator Project / Azahar Emulator Project
// Licensed under GPLv2 or any later version
// Refer to the license.txt file included.

import Foundation

/// Swift wrapper for Azahar C bridge functions
struct AzaharBridge {
    
    // MARK: - RetroAchievements Types
    
    struct UserInfo {
        let username: String
        let displayName: String
        let score: UInt32
        let scoreSoftcore: UInt32
        let token: String
        let avatarUrl: String
        
        init?(from ptr: UnsafePointer<az_ra_user_t>?) {
            guard let ptr = ptr else { return nil }
            let user = ptr.pointee
            self.username = String(cString: user.username!)
            self.displayName = String(cString: user.display_name!)
            self.score = user.score
            self.scoreSoftcore = user.score_softcore
            self.token = String(cString: user.token!)
            self.avatarUrl = String(cString: user.avatar_url!)
        }
    }
    
    struct GameInfo {
        let id: UInt32
        let title: String
        let badgeUrl: String
        let numAchievements: UInt32
        let numUnlocked: UInt32
        let numLeaderboards: UInt32
        
        init?(from ptr: UnsafePointer<az_ra_game_t>?) {
            guard let ptr = ptr else { return nil }
            let game = ptr.pointee
            self.id = game.id
            self.title = String(cString: game.title)
            self.badgeUrl = String(cString: game.badge_url)
            self.numAchievements = game.num_achievements
            self.numUnlocked = game.num_unlocked
            self.numLeaderboards = game.num_leaderboards
        }
    }
    
    // MARK: - RetroAchievements Functions
    
    static func raLogin(username: String, password: String) {
        az_ra_login(username, password)
    }
    
    static func raLoginWithToken(username: String, token: String) {
        az_ra_login_with_token(username, token)
    }
    
    static func raLogout() {
        az_ra_logout()
    }
    
    static func raIsLoggedIn() -> Bool {
        return az_ra_is_logged_in()
    }
    
    static func raGetUser() -> UserInfo? {
        return UserInfo(from: az_ra_get_user())
    }
    
    static func raGetGame() -> GameInfo? {
        return GameInfo(from: az_ra_get_game())
    }
    
    static func raSetEnabled(_ enabled: Bool) {
        az_ra_set_enabled(enabled)
    }
    
    static func raIsEnabled() -> Bool {
        return az_ra_is_enabled()
    }
    
    static func raSetHardcoreEnabled(_ enabled: Bool) {
        az_ra_set_hardcore_enabled(enabled)
    }
    
    static func raIsHardcoreEnabled() -> Bool {
        return az_ra_is_hardcore_enabled()
    }
    
    static func raCanPauseHardcore() -> Bool {
        return az_ra_can_pause_hardcore()
    }
    
    // MARK: - Helper Functions
    
    static func getRAUser() -> UserInfo? {
        return raGetUser()
    }
    
    static func getRAGame() -> GameInfo? {
        return raGetGame()
    }
}
