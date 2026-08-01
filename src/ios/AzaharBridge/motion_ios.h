// Copyright Citra Emulator Project / Azahar Emulator Project
// Licensed under GPLv2 or any later version
// Refer to the license.txt file included.

#pragma once

#include <atomic>

#include "core/frontend/input.h"

namespace InputManager {

// Screen rotation (0..3) used to transform device sensor axes into 3DS axes.
// Updated by the Swift frontend when the device rotates.
inline std::atomic<int> screen_rotation{0};

class IOSMotion;

/// Motion factory backed by CoreMotion (accelerometer + gyroscope).
class IOSMotionFactory final : public Input::Factory<Input::MotionDevice> {
public:
    /// Creates a motion device that reads data from the device sensors.
    std::unique_ptr<Input::MotionDevice> Create(const Common::ParamPackage& params) override;

    void EnableSensors();
    void DisableSensors();

private:
    IOSMotion* motion_device = nullptr;
};

} // namespace InputManager
