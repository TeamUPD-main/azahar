// Copyright Citra Emulator Project / Azahar Emulator Project
// Licensed under GPLv2 or any later version
// Refer to the license.txt file included.

#include <cmath>
#include <mutex>

#include <CoreMotion/CoreMotion.h>

#include "common/assert.h"
#include "common/logging/log.h"
#include "common/vector_math.h"
#include "ios/AzaharBridge/motion_ios.h"

namespace InputManager {

namespace {
using Common::Vec3;
}

class IOSMotion final : public Input::MotionDevice {
public:
    explicit IOSMotion(std::chrono::microseconds update_period)
        : update_period(update_period) {
        motion_manager = [[CMMotionManager alloc] init];
        if (motion_manager == nil) {
            LOG_ERROR(Input, "Could not create CMMotionManager");
            return;
        }
        if (motion_manager.accelerometerUpdateInterval == 0) {
            motion_manager.accelerometerUpdateInterval =
                static_cast<NSTimeInterval>(update_period.count()) / 1000000.0;
            motion_manager.gyroUpdateInterval =
                static_cast<NSTimeInterval>(update_period.count()) / 1000000.0;
        }
    }

    ~IOSMotion() {
        DisableSensors();
        motion_manager = nil;
    }

    static Vec3<float> TransformAxes(Vec3<float> in) {
        // 3DS   Y+            Phone     Z+
        // on    |             laying    |
        // table |             in        |
        //       |_______ X-   portrait  |_______ X+
        //      /              mode     /
        //     /                       /
        //    Z-                      Y-
        Vec3<float> out;
        out.y = in.z;
        // rotations are 90 degrees counter-clockwise from portrait
        switch (screen_rotation.load()) {
        case 0:
            out.x = -in.x;
            out.z = in.y;
            break;
        case 1:
            out.x = in.y;
            out.z = in.x;
            break;
        case 2:
            out.x = in.x;
            out.z = -in.y;
            break;
        case 3:
            out.x = -in.y;
            out.z = -in.x;
            break;
        default:
            UNREACHABLE();
        }
        return out;
    }

    void Update() const {
        if (!sensors_enabled) {
            return;
        }
        CMAccelerometerData* accel = motion_manager.accelerometerData;
        if (accel != nil) {
            // convert from m/(s^2) to g and invert
            const CMAcceleration a = accel.acceleration;
            acceleration = TransformAxes(Vec3<float>(a.x, a.y, a.z)) / -9.81f;
        }
        CMGyroData* gyro = motion_manager.gyroData;
        if (gyro != nil) {
            // convert from rad/s to deg/s
            const CMRotationRate r = gyro.rotationRate;
            rotation = TransformAxes(Vec3<float>(r.x, r.y, r.z)) * 180.0f / static_cast<float>(M_PI);
        }
    }

    std::tuple<Vec3<float>, Vec3<float>> GetStatus() const override {
        Update();
        return {acceleration, rotation};
    }

    void EnableSensors() {
        if (motion_manager == nil) {
            return;
        }
        std::lock_guard<std::mutex> guard(sensor_mutex);
        if (sensors_enabled) {
            return;
        }
        LOG_TRACE(Input, "Enabling motion sensors..");
        if (motion_manager.isAccelerometerAvailable) {
            [motion_manager startAccelerometerUpdates];
        }
        if (motion_manager.isGyroAvailable) {
            [motion_manager startGyroUpdates];
        }
        sensors_enabled = true;
    }

    void DisableSensors() {
        if (motion_manager == nil) {
            return;
        }
        std::lock_guard<std::mutex> guard(sensor_mutex);
        if (!sensors_enabled) {
            return;
        }
        LOG_TRACE(Input, "Disabling motion sensors..");
        [motion_manager stopAccelerometerUpdates];
        [motion_manager stopGyroUpdates];
        sensors_enabled = false;
    }

private:
    CMMotionManager* motion_manager = nil;
    std::chrono::microseconds update_period;
    mutable bool sensors_enabled = false;
    mutable std::mutex sensor_mutex;
    mutable std::atomic<Vec3<float>> acceleration{};
    mutable std::atomic<Vec3<float>> rotation{};
};

std::unique_ptr<Input::MotionDevice> IOSMotionFactory::Create(const Common::ParamPackage& params) {
    std::chrono::milliseconds update_period{params.Get("update_period", 4)};
    std::unique_ptr<IOSMotion> motion = std::make_unique<IOSMotion>(update_period);
    motion_device = motion.get();
    return std::move(motion);
}

void IOSMotionFactory::EnableSensors() {
    if (motion_device) {
        motion_device->EnableSensors();
    }
}

void IOSMotionFactory::DisableSensors() {
    if (motion_device) {
        motion_device->DisableSensors();
    }
}

} // namespace InputManager
