// Copyright Citra Emulator Project / Azahar Emulator Project
// Licensed under GPLv2 or any later version
// Refer to the license.txt file included.

#pragma once

#include <functional>
#include <vector>

#include <rc_client.h>

#include "client_observer.h"

namespace RetroAchievements {

    class Client {
    public:
        explicit Client();
        ~Client();

        void RegisterObserver(ClientObserver& observer);

        void AttemptLogin(const char* username, const char* password);
        void AttemptLoginWithToken(const char* username, const char* token);
        void LogOut();

        void LoadGame(const char* file_path);
        void UnloadGame();
        void Reset();
        void DoFrame();

        using ImageCallback = std::function<void(std::vector<uint8_t>&& image_data)>;
        void FetchImage(const char* url, ImageCallback callback) const;

        const rc_client_user_t* GetUser() const;
        const rc_client_game_t* GetGame() const;

        // Achievement list
        rc_client_achievement_list_t* CreateAchievementList(int category, int grouping);
        void DestroyAchievementList(rc_client_achievement_list_t* list);

        // Leaderboards
        rc_client_leaderboard_list_t* CreateLeaderboardList(int grouping);
        void DestroyLeaderboardList(rc_client_leaderboard_list_t* list);

        // Save state support
        int SerializeProgress(uint8_t* buffer, uint32_t buffer_size);
        int DeserializeProgress(const uint8_t* buffer);
        bool CanPauseHardcore();

        // Hardcore mode
        void SetHardcoreEnabled(bool enabled);
        bool IsHardcoreEnabled() const;

        void OnLoginCallback(int result, const char* error_message);
        void OnLoadGameCallback(int result, const char* error_message);
        void OnEvent(const rc_client_event_t* event);

    private:
        rc_client_t* m_rc_client;
        const rc_client_user_t* m_user = nullptr;

        std::vector<ClientObserver*> m_observers;
    };

} // namespace RetroAchievements
