// Copyright Citra Emulator Project / Azahar Emulator Project
// Licensed under GPLv2 or any later version
// Refer to the license.txt file included.

#pragma once

#include <memory>
#include <string>

#include "core/frontend/input.h"
#include "ios/AzaharBridge/motion_ios.h"

namespace InputManager {

enum ButtonType {
    // 3DS Controls
    N3DS_BUTTON_A = 700,
    N3DS_BUTTON_B = 701,
    N3DS_BUTTON_X = 702,
    N3DS_BUTTON_Y = 703,
    N3DS_BUTTON_START = 704,
    N3DS_BUTTON_SELECT = 705,
    N3DS_BUTTON_HOME = 706,
    N3DS_BUTTON_ZL = 707,
    N3DS_BUTTON_ZR = 708,
    N3DS_DPAD_UP = 709,
    N3DS_DPAD_DOWN = 710,
    N3DS_DPAD_LEFT = 711,
    N3DS_DPAD_RIGHT = 712,
    N3DS_CIRCLEPAD = 713,
    N3DS_CIRCLEPAD_UP = 714,
    N3DS_CIRCLEPAD_DOWN = 715,
    N3DS_CIRCLEPAD_LEFT = 716,
    N3DS_CIRCLEPAD_RIGHT = 717,
    N3DS_STICK_C = 718,
    N3DS_STICK_C_UP = 719,
    N3DS_STICK_C_DOWN = 720,
    N3DS_STICK_C_LEFT = 771,
    N3DS_STICK_C_RIGHT = 772,
    N3DS_TRIGGER_L = 773,
    N3DS_TRIGGER_R = 774,
    N3DS_BUTTON_DEBUG = 781,
    N3DS_BUTTON_GPIO14 = 782,
};

class ButtonList;
class AnalogButtonList;
class AnalogList;

/**
 * A button device factory representing a gamepad. It receives input events and
 * forwards them to all button devices it created.
 */
class ButtonFactory final : public Input::Factory<Input::ButtonDevice> {
public:
    ButtonFactory();

    std::unique_ptr<Input::ButtonDevice> Create(const Common::ParamPackage& params) override;

    /// Sets the status of all buttons bound with the key to pressed.
    bool PressKey(int button_id);

    /// Sets the status of all buttons bound with the key to released.
    bool ReleaseKey(int button_id);

    /// Sets the status of all buttons bound to an analog axis.
    bool AnalogButtonEvent(int axis_id, float axis_val);

    void ReleaseAllKeys();

private:
    std::shared_ptr<ButtonList> button_list;
    std::shared_ptr<AnalogButtonList> analog_button_list;
};

/**
 * An analog device factory representing a gamepad. It receives input events and
 * forwards them to all analog devices it created.
 */
class AnalogFactory final : public Input::Factory<Input::AnalogDevice> {
public:
    AnalogFactory();

    std::unique_ptr<Input::AnalogDevice> Create(const Common::ParamPackage& params) override;

    /// Sets the status of all analog sticks bound with the key.
    bool MoveJoystick(int analog_id, float x, float y);

private:
    std::shared_ptr<AnalogList> analog_list;
};

/// Initializes and registers all built-in input device factories.
void Init();

/// Deregisters all built-in input device factories and shuts them down.
void Shutdown();

/// Gets the gamepad button device factory.
ButtonFactory* ButtonHandler();

/// Gets the gamepad analog device factory.
AnalogFactory* AnalogHandler();

/// Gets the iOS motion device factory.
IOSMotionFactory* IOSMotionHandler();

std::string GenerateButtonParamPackage(int type);

std::string GenerateAnalogButtonParamPackage(int axis, float axis_val);

std::string GenerateAnalogParamPackage(int type);
} // namespace InputManager
