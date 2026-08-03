// Copyright Citra Emulator Project / Azahar Emulator Project
// Licensed under GPLv2 or any later version
// Refer to the license.txt file included.

#pragma once

#include <rc_client.h>

namespace RetroAchievements {

    class ClientObserver {
    public:
        virtual ~ClientObserver() = default;

        // Login events
        virtual void OnLoginSucceeded(const rc_client_user_t* user) {}
        virtual void OnLoginFailed(int result, const char* error_message) {}

        // Game load events
        virtual void OnLoadGameSucceeded(const rc_client_game_t* game) {}
        virtual void OnLoadGameFailed(int result, const char* error_message) {}

        // Achievement events
        virtual void OnAchievementTriggered(const rc_client_achievement_t* achievement) {}
        virtual void OnChallengeIndicatorShow(const rc_client_achievement_t* achievement) {}
        virtual void OnChallengeIndicatorHide(const rc_client_achievement_t* achievement) {}
        virtual void OnProgressIndicatorShow(const rc_client_achievement_t* achievement) {}
        virtual void OnProgressIndicatorHide(const rc_client_achievement_t* achievement) {}
        virtual void OnProgressIndicatorUpdate(const rc_client_achievement_t* achievement) {}

        // Leaderboard events
        virtual void OnLeaderboardStarted(const rc_client_leaderboard_t* leaderboard) {}
        virtual void OnLeaderboardFailed(const rc_client_leaderboard_t* leaderboard) {}
        virtual void OnLeaderboardSubmitted(const rc_client_leaderboard_t* leaderboard) {}
        virtual void OnLeaderboardTrackerShow(const rc_client_leaderboard_tracker_t* tracker) {}
        virtual void OnLeaderboardTrackerHide(const rc_client_leaderboard_tracker_t* tracker) {}
        virtual void OnLeaderboardTrackerUpdate(const rc_client_leaderboard_tracker_t* tracker) {}

        // Generic event handler (for any events not specifically handled)
        virtual void OnEvent(const rc_client_event_t* event) {}
    };

} // namespace RetroAchievements
