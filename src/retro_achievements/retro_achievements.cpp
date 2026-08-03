// Copyright Citra Emulator Project / Azahar Emulator Project
// Licensed under GPLv2 or any later version
// Refer to the license.txt file included.

#include "retro_achievements.h"
#include "common/logging/log.h"
#include <memory>
#include <vector>

namespace RetroAchievements {

static std::unique_ptr<Client> g_client;
static std::vector<uint8_t> g_progress_buffer;
static bool g_initialized = false;

void Initialize() {
    if (g_initialized) {
        LOG_WARNING(RetroAchievements, "Already initialized");
        return;
    }

    try {
        g_client = std::make_unique<Client>();
        g_initialized = true;
        LOG_INFO(RetroAchievements, "RetroAchievements system initialized");
    } catch (const std::exception& e) {
        LOG_ERROR(RetroAchievements, "Failed to initialize: {}", e.what());
        g_initialized = false;
    }
}

void Shutdown() {
    if (!g_initialized) {
        return;
    }

    if (g_client) {
        g_client->UnloadGame();
        g_client.reset();
    }
    
    g_progress_buffer.clear();
    g_initialized = false;
    LOG_INFO(RetroAchievements, "RetroAchievements system shut down");
}

Client* GetClient() {
    return g_client.get();
}

void DoFrame() {
    if (!g_initialized || !g_client) {
        return;
    }

    g_client->DoFrame();
}

void OnSaveState() {
    if (!g_initialized || !g_client) {
        return;
    }

    // Get the size needed for progress serialization
    int size = g_client->SerializeProgress(nullptr, 0);
    if (size <= 0) {
        LOG_DEBUG(RetroAchievements, "No progress to serialize");
        return;
    }

    // Allocate buffer and serialize
    g_progress_buffer.resize(size);
    int result = g_client->SerializeProgress(g_progress_buffer.data(), size);
    
    if (result > 0) {
        LOG_DEBUG(RetroAchievements, "Serialized {} bytes of RA progress", result);
    } else {
        LOG_ERROR(RetroAchievements, "Failed to serialize RA progress");
        g_progress_buffer.clear();
    }
}

void OnLoadState() {
    if (!g_initialized || !g_client) {
        return;
    }

    if (g_progress_buffer.empty()) {
        LOG_DEBUG(RetroAchievements, "No saved progress to restore");
        return;
    }

    // Deserialize the progress
    int result = g_client->DeserializeProgress(g_progress_buffer.data());
    
    if (result == RC_OK) {
        LOG_DEBUG(RetroAchievements, "Restored RA progress from save state");
    } else {
        LOG_ERROR(RetroAchievements, "Failed to deserialize RA progress: {}", result);
    }
}

void OnGameLoaded(const std::string& file_path) {
    if (!g_initialized || !g_client) {
        return;
    }

    LOG_INFO(RetroAchievements, "Loading game achievements for: {}", file_path);
    g_client->LoadGame(file_path.c_str());
}

void OnGameUnloaded() {
    if (!g_initialized || !g_client) {
        return;
    }

    LOG_INFO(RetroAchievements, "Unloading game achievements");
    g_client->UnloadGame();
    g_progress_buffer.clear();
}

bool IsInitialized() {
    return g_initialized && g_client != nullptr;
}

} // namespace RetroAchievements
