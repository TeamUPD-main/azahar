// Copyright Citra Emulator Project / Azahar Emulator Project
// Licensed under GPLv2 or any later version
// Refer to the license.txt file included.

#pragma once

#include <memory>
#include "client.h"

namespace RetroAchievements {

/// Initialize the RetroAchievements system
void Initialize();

/// Shutdown the RetroAchievements system
void Shutdown();

/// Get the global RetroAchievements client instance
Client* GetClient();

/// Called every frame during emulation to process achievement logic
void DoFrame();

/// Called when a save state is created - serializes RA progress
void OnSaveState();

/// Called when a save state is loaded - deserializes RA progress
void OnLoadState();

/// Called when a game is loaded - attempts to load achievements for the game
void OnGameLoaded(const std::string& file_path);

/// Called when a game is unloaded
void OnGameUnloaded();

/// Check if RetroAchievements is initialized and ready
bool IsInitialized();

} // namespace RetroAchievements
