// Copyright Citra Emulator Project / Azahar Emulator Project
// Licensed under GPLv2 or any later version
// Refer to the license.txt file included.

#pragma once

#include <string>
#include <vector>

#include "core/frontend/applets/mii_selector.h"
#include "core/frontend/applets/swkbd.h"

namespace SoftwareKeyboard {

/// iOS keyboard applet. Blocks on the emulation thread while Swift presents the
/// keyboard UI; result is delivered via az_swkbd_submit() / az_swkbd_cancel().
class IOSKeyboard final : public Frontend::SoftwareKeyboard {
public:
    ~IOSKeyboard() override = default;
    void Execute(const Frontend::KeyboardConfig& config) override;
    void ShowError(const std::string& error) override;

    const KeyboardConfig& GetKeyboardConfig() const {
        return config;
    }
};

} // namespace SoftwareKeyboard

namespace MiiSelector {

/// iOS Mii selector. Blocks while the SwiftUI list is presented.
class IOSMiiSelector final : public Frontend::MiiSelector {
public:
    ~IOSMiiSelector() override = default;
    void Setup(const Frontend::MiiSelectorConfig& config) override;
};

} // namespace MiiSelector

/// Microphone permission check. Registered with Core::System.
bool CheckMicPermission();
