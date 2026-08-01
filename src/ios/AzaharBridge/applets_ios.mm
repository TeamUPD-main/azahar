// Copyright Citra Emulator Project / Azahar Emulator Project
// Licensed under GPLv2 or any later version
// Refer to the license.txt file included.

#include <condition_variable>
#include <cstdlib>
#include <cstring>
#include <mutex>
#include <string>
#include <vector>

#include <AVFoundation/AVFoundation.h>

#include "common/logging/log.h"
#include "common/string_util.h"
#include "core/core.h"
#include "core/frontend/applets/default_applets.h"
#include "ios/AzaharBridge/applets_ios.h"
#include "ios/AzaharBridge/azahar_ios.h"
#include "fmt/format.h"

namespace {

// Software keyboard pending request
std::mutex swkbd_mutex;
std::condition_variable swkbd_cv;
bool swkbd_ready = false;  // True when the keyboard UI is shown
bool swkbd_done = false;   // True when the user has submitted or cancelled
std::string swkbd_text;
u8 swkbd_button = 0;

// Mii selector pending request
std::mutex mii_mutex;
std::condition_variable mii_cv;
bool mii_done = false;
bool mii_cancelled = false;
int mii_selected_index = -1;
std::vector<Mii::MiiData> mii_list;

} // Anonymous namespace

// ---------------------------------------------------------------------------
// Software keyboard
// ---------------------------------------------------------------------------

namespace SoftwareKeyboard {

void IOSKeyboard::Execute(const Frontend::KeyboardConfig& config) {
    SoftwareKeyboard::Execute(config);

    std::unique_lock<std::mutex> lock(swkbd_mutex);
    swkbd_ready = true;
    swkbd_done = false;
    swkbd_text.clear();
    swkbd_button = 0;

    // Notify Swift that the keyboard should appear
    if (on_swkbd_request) {
        on_swkbd_request();
    }

    // Block until the user submits or cancels
    swkbd_cv.wait(lock, [] { return swkbd_done; });
    swkbd_ready = false;

    Frontend::KeyboardData data;
    data.text = swkbd_text;
    data.button = swkbd_button;
    Finalize(data.text, data.button);
}

void IOSKeyboard::ShowError(const std::string& error) {
    if (on_alert) {
        bool unused = false;
        on_alert("Keyboard Error", error.c_str(), false, &unused);
    }
}

} // namespace SoftwareKeyboard

// ---------------------------------------------------------------------------
// Mii selector
// ---------------------------------------------------------------------------

namespace MiiSelector {

void IOSMiiSelector::Setup(const Frontend::MiiSelectorConfig& config) {
    Frontend::MiiSelector::Setup(config);

    mii_list = Frontend::LoadMiis();

    std::unique_lock<std::mutex> lock(mii_mutex);
    mii_done = false;
    mii_cancelled = false;
    mii_selected_index = -1;

    // Notify Swift to show the Mii list
    if (on_mii_request) {
        on_mii_request();
    }

    // Block until the user selects or cancels
    mii_cv.wait(lock, [] { return mii_done; });

    if (mii_cancelled) {
        Frontend::MiiSelector::Finalize(1, Mii::MiiData{});
        return;
    }

    // Index 0 = Standard Mii, index 1..N = user Miis
    if (mii_selected_index == 0) {
        Frontend::MiiSelector::Finalize(
            0, HLE::Applets::MiiSelector::GetStandardMiiResult().selected_mii_data);
    } else if (mii_selected_index >= 1 &&
               static_cast<std::size_t>(mii_selected_index - 1) < mii_list.size()) {
        Frontend::MiiSelector::Finalize(0, mii_list.at(mii_selected_index - 1));
    } else {
        Frontend::MiiSelector::Finalize(0, Mii::MiiData{});
    }
}

} // namespace MiiSelector

// ---------------------------------------------------------------------------
// C API — called from Swift via the bridging header
// ---------------------------------------------------------------------------

/// Serializes the current keyboard config as a lightweight JSON object so the
/// SwiftUI keyboard can honor max length, hint text, button labels, etc.
char* az_swkbd_get_config(void) {
    std::string json = "{}";
    auto& system = Core::System::GetInstance();
    auto* keyboard =
        static_cast<SoftwareKeyboard::IOSKeyboard*>(system.GetSoftwareKeyboard().get());
    if (keyboard) {
        const auto& config = keyboard->GetKeyboardConfig();
        json = fmt::format(
            "{{\"max_text_length\":{},\"max_digits\":{},\"multiline_mode\":{},\"hint_text\":\""
            "{}\",\"button_count\":{}}}",
            config.max_text_length, config.max_digits,
            config.multiline_mode ? "true" : "false", config.hint_text, config.button_text.size());
    }
    char* buf = static_cast<char*>(calloc(json.size() + 1, 1));
    memcpy(buf, json.c_str(), json.size());
    return buf;
}

static SoftwareKeyboard::IOSKeyboard* GetActiveKeyboard() {
    return static_cast<SoftwareKeyboard::IOSKeyboard*>(
        Core::System::GetInstance().GetSoftwareKeyboard().get());
}

bool az_swkbd_submit(const char* text, int button) {
    if (!text) return false;
    std::lock_guard<std::mutex> lock(swkbd_mutex);
    if (!swkbd_ready || swkbd_done) return false;

    // Validate the input against the keyboard filters
    auto* keyboard = GetActiveKeyboard();
    if (keyboard) {
        auto error = keyboard->ValidateInput(text);
        if (error != Frontend::ValidationError::None) {
            return false;
        }
        error = keyboard->ValidateFilters(text);
        if (error != Frontend::ValidationError::None) {
            return false;
        }
    }

    swkbd_text = text;
    swkbd_button = static_cast<u8>(button);
    swkbd_done = true;
    swkbd_cv.notify_all();
    return true;
}

void az_swkbd_cancel(void) {
    std::lock_guard<std::mutex> lock(swkbd_mutex);
    if (!swkbd_ready || swkbd_done) return;
    swkbd_text.clear();
    swkbd_button = 0;
    swkbd_done = true;
    swkbd_cv.notify_all();
}

bool az_mii_select(int index) {
    std::lock_guard<std::mutex> lock(mii_mutex);
    if (mii_done) return false;
    mii_selected_index = index;
    mii_done = true;
    mii_cv.notify_all();
    return true;
}

void az_mii_cancel(void) {
    std::lock_guard<std::mutex> lock(mii_mutex);
    if (mii_done) return;
    mii_cancelled = true;
    mii_done = true;
    mii_cv.notify_all();
}

// ---------------------------------------------------------------------------
// Microphone permission
// ---------------------------------------------------------------------------

bool CheckMicPermission() {
    if (@available(iOS 17.0, *)) {
        switch ([AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeAudio]) {
        case AVAuthorizationStatusAuthorized:
            return true;
        case AVAuthorizationStatusNotDetermined: {
            dispatch_semaphore_t sem = dispatch_semaphore_create(0);
            __block bool granted = false;
            [AVCaptureDevice requestAccessForMediaType:AVMediaTypeAudio
                                 completionHandler:^(BOOL ok) {
                                   granted = ok;
                                   dispatch_semaphore_signal(sem);
                                 }];
            dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER);
            return granted;
        }
        default:
            return false;
        }
    }
    // For older iOS, just return true (AudioSession handles permission)
    return true;
}
