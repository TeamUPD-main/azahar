// Copyright Citra Emulator Project / Azahar Emulator Project
// Licensed under GPLv2 or any later version
// Refer to the license.txt file included.

// iOS bridge implementing the az_* C API. This file is the direct equivalent
// of src/android/app/src/main/jni/native.cpp (the Android JNI layer).
// It wires the C++ core through a platform-agnostic ObjC++ layer that Swift
// calls via the bridging header (azahar_ios.h).

#include <algorithm>
#include <atomic>
#include <condition_variable>
#include <cstring>
#include <mutex>
#include <string>

#include <QuartzCore/QuartzCore.h>

#include "common/arch.h"
#include "common/aarch64/cpu_detect.h"
#include "common/common_paths.h"
#include "common/file_util.h"
#include "common/logging/backend.h"
#include "common/logging/log.h"
#include "common/microprofile.h"
#include "common/play_time_manager.h"
#include "common/scm_rev.h"
#include "common/scope_exit.h"
#include "common/settings.h"
#include "common/string_util.h"
#include "core/core.h"
#include "core/frontend/applets/default_applets.h"
#include "core/frontend/camera/factory.h"
#include "core/hle/service/am/am.h"
#include "core/hle/service/cfg/cfg.h"
#include "core/hle/service/fs/archive.h"
#include "core/hle/service/nfc/nfc.h"
#include "core/hw/aes/key.h"
#include "core/hw/unique_data.h"
#include "core/loader/loader.h"
#include "core/savestate.h"
#include "core/system_titles.h"
#include "core/zip_pass.h"
#include "ios/AzaharBridge/EmuWindowIOS.h"
#include "ios/AzaharBridge/config_ios.h"
#include "ios/AzaharBridge/input_manager_ios.h"
#include "ios/AzaharBridge/logging_ios.h"
#include "ios/AzaharBridge/camera_ios.h"
#include "ios/AzaharBridge/applets_ios.h"
#include "ios/AzaharBridge/azahar_ios.h"
#include "network/announce_multiplayer_session.h"
#include "video_core/gpu.h"
#include "video_core/renderer_base.h"
#include "input_common/main.h"
#include "input_common/udp/client.h"

// ---------------------------------------------------------------------------
// Internal state (file scope, single-TU only)
// ---------------------------------------------------------------------------
std::unique_ptr<EmuWindowIOS> window;
std::unique_ptr<EmuWindowIOS> secondary_window;
std::unique_ptr<PlayTime::PlayTimeManager> play_time_manager;
int64_t ptm_current_title_id = std::numeric_limits<int64_t>::max();

std::atomic<bool> stop_run{true};
std::atomic<bool> pause_emulation{false};
std::atomic<bool> is_portrait{false};

std::mutex paused_mutex;
std::mutex running_mutex;
std::condition_variable running_cv;

std::atomic<int> last_result{AZ_CORE_ERROR_UNKNOWN};

// Pending surface layers (set before RunCitra creates the window)
CAMetalLayer* pending_primary_layer = nullptr;
float pending_primary_scale = 1.0f;
CAMetalLayer* pending_secondary_layer = nullptr;
float pending_secondary_scale = 1.0f;

std::string inserted_cartridge;
std::string pending_rom_path;

// Forward declarations
static void RunCitra(const std::string& filepath);
static void TryShutdown();

// Callbacks from the Swift frontend.
// translation units (applets, etc.) can trigger them.
az_on_alert_fn on_alert = nullptr;
az_on_core_error_fn on_core_error = nullptr;
az_on_exit_emulation_fn on_exit_emulation = nullptr;
az_on_disk_cache_progress_fn on_disk_cache_progress = nullptr;
az_on_netplay_message_fn on_netplay_message = nullptr;
az_on_netplay_clear_chat_fn on_netplay_clear_chat = nullptr;
az_on_compress_progress_fn on_compress_progress = nullptr;
az_on_swkbd_request_fn on_swkbd_request = nullptr;
az_on_mii_request_fn on_mii_request = nullptr;

/// C++ helper to call the Swift alert callback (synchronous, waits for result)
bool ShowAlert(const char* title, const char* message, bool yes_no) {
    bool result = false;
    if (on_alert) {
        on_alert(title, message, yes_no, &result);
    }
    return result;
}

/// C++ helper to call the Swift core-error callback
bool HandleCoreError(int error, const std::string& details) {
    bool can_continue = false;
    if (on_core_error) {
        on_core_error(error, details.c_str(), &can_continue);
    }
    return can_continue;
}

void NotifyExit(int result_code) {
    last_result.store(result_code);
    if (on_exit_emulation) {
        on_exit_emulation(result_code);
    }
}

/// Helper to read the user-configured graphics API and create the appropriate EmuWindow
std::unique_ptr<EmuWindowIOS> CreateEmuWindow(CAMetalLayer* layer, bool is_secondary) {
    auto emu_window = std::make_unique<EmuWindowIOS>(layer, is_secondary);
    return emu_window;
}

// ---------------------------------------------------------------------------
// Public C API implementation (az_*)
// ---------------------------------------------------------------------------

void az_set_user_directory(const char* directory) {
    FileUtil::SetCurrentDir(directory ? std::string(directory) : "");
}

void az_create_config_file(void) {
    Config config;
}

void az_create_log_file(void) {
    AzaharLogging::Init();
}

void az_reload_settings(void) {
    Config config;
    if (Core::System::GetInstance().IsPoweredOn()) {
        Core::System::GetInstance().ApplySettings();
    }
}

void az_log_device_info(void) {
    LOG_INFO(Frontend, "Azahar iOS build: {} {}", Common::g_scm_rev, Common::g_scm_branch);
    LOG_INFO(Frontend, "CPU: {}", Common::GetCPUCaps().cpu_string);
}

void az_set_portrait_mode(bool portrait) {
    is_portrait.store(portrait, std::memory_order_relaxed);
    SetIOSPortraitMode(portrait);
}

// Callback setters
void az_set_on_alert(az_on_alert_fn fn) { on_alert = fn; }
void az_set_on_core_error(az_on_core_error_fn fn) { on_core_error = fn; }
void az_set_on_exit_emulation(az_on_exit_emulation_fn fn) { on_exit_emulation = fn; }
void az_set_on_disk_cache_progress(az_on_disk_cache_progress_fn fn) { on_disk_cache_progress = fn; }
void az_set_on_netplay_message(az_on_netplay_message_fn fn) { on_netplay_message = fn; }
void az_set_on_netplay_clear_chat(az_on_netplay_clear_chat_fn fn) { on_netplay_clear_chat = fn; }
void az_set_on_compress_progress(az_on_compress_progress_fn fn) { on_compress_progress = fn; }
void az_set_on_swkbd_request(az_on_swkbd_request_fn fn) { on_swkbd_request = fn; }
void az_set_on_mii_request(az_on_mii_request_fn fn) { on_mii_request = fn; }

// ---------------------------------------------------------------------------
// Emulation control
// ---------------------------------------------------------------------------

static void RunCitra(const std::string& filepath) {
    std::scoped_lock lock(running_mutex);

    Core::System& system = Core::System::GetInstance();

    if (!inserted_cartridge.empty()) {
        system.InsertCartridge(inserted_cartridge);
    }

    // Create windows — Vulkan path (iOS always uses Vulkan via MoltenVK)
    window = CreateEmuWindow(pending_primary_layer, false);
    secondary_window = CreateEmuWindow(pending_secondary_layer, true);

    if (!window) {
        LOG_CRITICAL(Frontend, "Failed to create EmuWindowIOS");
        last_result.store(AZ_CORE_ERROR_UNKNOWN);
        return;
    }

    // Load config
    Config config;

    FileUtil::SetCurrentRomPath(filepath);
    auto loader = Loader::GetLoader(filepath);
    if (!loader) {
        LOG_CRITICAL(Frontend, "Failed to load ROM: {}", filepath);
        last_result.store(AZ_CORE_ERROR_GET_LOADER);
        return;
    }

    // Read program ID
    u64 title_id = 0;
    loader->ReadProgramId(title_id);
    system.RegisterAppLoaderEarly(loader);

    // Apply settings
    system.ApplySettings();

    // Register applets
    Frontend::RegisterDefaultApplets(system);

    // Register iOS camera factory and applets
    Camera::RegisterFactory("ios", std::make_unique<Camera::IOS::Factory>());
    system.RegisterMiiSelector(std::make_shared<MiiSelector::IOSMiiSelector>());
    system.RegisterSoftwareKeyboard(std::make_shared<SoftwareKeyboard::IOSKeyboard>());
    system.RegisterMicPermissionCheck(&CheckMicPermission);

    // Register input
    InputManager::Init();

    stop_run = false;
    pause_emulation = false;

    system.GPU().ApplyPerProgramSettings(title_id);

    SCOPE_EXIT({ TryShutdown(); });

    system.RunLoop();

    // If we reach here the loop exited normally or with an error
}

static void TryShutdown() {
    if (window) {
        window->DoneCurrent();
    }
    if (secondary_window) {
        secondary_window->DoneCurrent();
    }

    Core::System& system = Core::System::GetInstance();
    system.Shutdown();
    system.EjectCartridge();

    if (window) {
        window.reset();
    }
    if (secondary_window) {
        secondary_window.reset();
    }

    InputManager::Shutdown();
    MicroProfileShutdown();
}

int az_get_last_result(void) {
    return last_result.load();
}

void az_run(const char* path) {
    if (!path) return;
    pending_rom_path = path;
    last_result.store(AZ_CORE_ERROR_UNKNOWN);
    RunCitra(pending_rom_path);
}

void az_pause_emulation(void) {
    pause_emulation = true;
    if (InputManager::IOSMotionHandler()) {
        InputManager::IOSMotionHandler()->DisableSensors();
    }
}

void az_unpause_emulation(void) {
    pause_emulation = false;
    running_cv.notify_all();
    if (InputManager::IOSMotionHandler()) {
        InputManager::IOSMotionHandler()->EnableSensors();
    }
}

void az_stop_emulation(void) {
    stop_run = true;
    pause_emulation = false;
    running_cv.notify_all();
}

bool az_is_running(void) {
    return !stop_run.load();
}

bool az_is_paused(void) {
    return pause_emulation.load();
}

int64_t az_get_running_title_id(void) {
    auto& system = Core::System::GetInstance();
    if (!system.IsPoweredOn()) return 0;
    u64 program_id = 0;
    system.GetAppLoader().ReadProgramId(program_id);
    return static_cast<int64_t>(program_id);
}

// ---------------------------------------------------------------------------
// Surface
// ---------------------------------------------------------------------------

void az_emu_surface_set(void* metal_layer, float scale) {
    auto* layer = (__bridge CAMetalLayer*)metal_layer;
    pending_primary_layer = layer;
    pending_primary_scale = scale;

    if (window) {
        if (window->OnSurfaceChanged(layer)) {
            if (Core::System::GetInstance().IsPoweredOn()) {
                Core::System::GetInstance().GPU().Renderer().NotifySurfaceChanged(false);
            }
        }
    }
}

void az_emu_surface_destroy(void) {
    pending_primary_layer = nullptr;
    if (window) {
        window->OnSurfaceChanged(nullptr);
    }
}

void az_emu_secondary_surface_set(void* metal_layer, float scale) {
    auto* layer = (__bridge CAMetalLayer*)metal_layer;
    pending_secondary_layer = layer;
    pending_secondary_scale = scale;

    if (secondary_window) {
        if (secondary_window->OnSurfaceChanged(layer)) {
            if (Core::System::GetInstance().IsPoweredOn()) {
                Core::System::GetInstance().GPU().Renderer().NotifySurfaceChanged(true);
            }
        }
    }
}

void az_emu_secondary_surface_destroy(void) {
    pending_secondary_layer = nullptr;
    if (secondary_window) {
        secondary_window->OnSurfaceChanged(nullptr);
    }
}

void az_present_frame(void) {
    // Presentation is driven entirely by the renderer's own present thread via
    // the TextureMailbox; nothing to do from the frontend display link.
}

void az_update_framebuffer(bool is_portrait) {
    if (!Core::System::GetInstance().IsPoweredOn()) return;
    Core::System::GetInstance().GPU().Renderer().UpdateCurrentFramebufferLayout(is_portrait);
}

void az_swap_screens(bool swap, int rotation) {
    Settings::values.swap_screen.SetValue(swap);
    InputManager::screen_rotation.store(rotation);
}

// ---------------------------------------------------------------------------
// Input
// ---------------------------------------------------------------------------

bool az_button_event(int button, bool pressed) {
    if (!InputManager::ButtonHandler()) return false;
    return pressed ? InputManager::ButtonHandler()->PressKey(button)
                  : InputManager::ButtonHandler()->ReleaseKey(button);
}

bool az_analog_event(int analog, float x, float y) {
    if (!InputManager::AnalogHandler()) return false;
    // Clamp to unit circle and invert Y (core expects this)
    x = std::clamp(x, -1.0f, 1.0f);
    y = -std::clamp(y, -1.0f, 1.0f);
    float mag = std::sqrt(x * x + y * y);
    if (mag > 1.0f) { x /= mag; y /= mag; }
    return InputManager::AnalogHandler()->MoveJoystick(analog, x, y);
}

bool az_axis_event(int axis, float value) {
    if (!InputManager::ButtonHandler()) return false;
    return InputManager::ButtonHandler()->AnalogButtonEvent(axis, value);
}

bool az_touch_event(float x, float y, bool pressed) {
    if (!window) return false;
    return window->OnTouchEvent(static_cast<int>(x), static_cast<int>(y), pressed);
}

void az_touch_moved(float x, float y) {
    if (!window) return;
    window->OnTouchMoved(static_cast<int>(x), static_cast<int>(y));
}

bool az_secondary_touch_event(float x, float y, bool pressed) {
    if (!secondary_window) return false;
    return secondary_window->OnTouchEvent(static_cast<int>(x), static_cast<int>(y), pressed);
}

void az_secondary_touch_moved(float x, float y) {
    if (!secondary_window) return;
    secondary_window->OnTouchMoved(static_cast<int>(x), static_cast<int>(y));
}

void az_release_all_keys(void) {
    if (InputManager::ButtonHandler()) {
        InputManager::ButtonHandler()->ReleaseAllKeys();
    }
}

// ---------------------------------------------------------------------------
// Settings
// ---------------------------------------------------------------------------

static std::string GetConfigPath() {
    return FileUtil::GetUserPath(FileUtil::UserPath::ConfigDir) + "config.ini";
}

static std::map<std::string, std::map<std::string, std::string>> LoadIniAsMap() {
    std::map<std::string, std::map<std::string, std::string>> sections;
    std::string current_section;
    std::string content;
    FileUtil::ReadFileToString(true, GetConfigPath(), content);
    std::istringstream stream(content);
    std::string line;
    while (std::getline(stream, line)) {
        if (line.empty() || line[0] == '#' || line[0] == ';') continue;
        if (line.front() == '[' && line.back() == ']') {
            current_section = line.substr(1, line.size() - 2);
            continue;
        }
        auto eq = line.find('=');
        if (eq != std::string::npos) {
            std::string key = line.substr(0, eq);
            std::string value = line.substr(eq + 1);
            // Trim whitespace
            auto trim = [](std::string& s) {
                s.erase(0, s.find_first_not_of(" \t\r\n"));
                s.erase(s.find_last_not_of(" \t\r\n") + 1);
            };
            trim(key);
            trim(value);
            sections[current_section][key] = value;
        }
    }
    return sections;
}

static void WriteIniFromMap(const std::map<std::string, std::map<std::string, std::string>>& sections) {
    std::ostringstream out;
    for (const auto& [section, keys] : sections) {
        out << "[" << section << "]\n";
        for (const auto& [key, value] : keys) {
            out << key << " = " << value << "\n";
        }
        out << "\n";
    }
    FileUtil::CreateFullPath(GetConfigPath());
    FileUtil::WriteStringToFile(true, GetConfigPath(), out.str());
}

char* az_setting_get_string(const char* group, const char* key, const char* default_value) {
    if (!group || !key) {
        return strdup(default_value ? default_value : "");
    }
    auto sections = LoadIniAsMap();
    auto sit = sections.find(group);
    if (sit != sections.end()) {
        auto kit = sit->second.find(key);
        if (kit != sit->second.end()) {
            return strdup(kit->second.c_str());
        }
    }
    return strdup(default_value ? default_value : "");
}

bool az_setting_get_bool(const char* group, const char* key, bool default_value) {
    char* val = az_setting_get_string(group, key, default_value ? "1" : "0");
    bool result = (val[0] == '1');
    free(val);
    return result;
}

long az_setting_get_int(const char* group, const char* key, long default_value) {
    char* val = az_setting_get_string(group, key, "");
    long result = default_value;
    try { result = std::stol(val); } catch (...) {}
    free(val);
    return result;
}

double az_setting_get_float(const char* group, const char* key, double default_value) {
    char* val = az_setting_get_string(group, key, "");
    double result = default_value;
    try { result = std::stod(val); } catch (...) {}
    free(val);
    return result;
}

static void SetSettingRaw(const char* group, const char* key, const char* value) {
    if (!group || !key || !value) return;
    auto sections = LoadIniAsMap();
    sections[group][key] = value;
    WriteIniFromMap(sections);
}

void az_setting_set_string(const char* group, const char* key, const char* value) {
    SetSettingRaw(group, key, value);
    az_reload_settings();
}

void az_setting_set_bool(const char* group, const char* key, bool value) {
    az_setting_set_string(group, key, value ? "1" : "0");
}

void az_setting_set_int(const char* group, const char* key, long value) {
    az_setting_set_string(group, key, std::to_string(value).c_str());
}

void az_setting_set_float(const char* group, const char* key, double value) {
    az_setting_set_string(group, key, std::to_string(value).c_str());
}

void az_set_temporary_frame_limit(double speed) {
    Settings::temporary_frame_limit = speed;
    Settings::is_temporary_frame_limit = true;
}

void az_disable_temporary_frame_limit(void) {
    Settings::is_temporary_frame_limit = false;
}

// ---------------------------------------------------------------------------
// Games / titles
// ---------------------------------------------------------------------------

int64_t az_get_title_id(const char* path) {
    if (!path) return 0;
    auto loader = Loader::GetLoader(path);
    if (!loader) return 0;
    u64 title_id = 0;
    loader->ReadProgramId(title_id);
    return static_cast<int64_t>(title_id);
}

bool az_get_is_system_title(const char* path) {
    if (!path) return false;
    int64_t id = az_get_title_id(path);
    return (static_cast<u64>(id) >> 32) == 0x00040010;
}

bool az_are_keys_available(void) {
    HW::AES::InitKeys();
    return HW::AES::IsKeyXAvailable(HW::AES::KeySlotID::NCCHSecure1) &&
           HW::AES::IsKeyXAvailable(HW::AES::KeySlotID::NCCHSecure2);
}

int az_get_installed_game_paths(az_game_path* out, int max_count) {
    if (!out || max_count <= 0) return 0;
    int count = 0;

    // Scan SDMC titles
    std::string sdmc_base = FileUtil::GetUserPath(FileUtil::UserPath::SDMCDir) +
        "/Nintendo 3DS/00000000000000000000000000000000/00000000000000000000000000000000/title/00040000";
    FileUtil::ForeachDirectoryEntry(
        nullptr, sdmc_base,
        [&](u64* /*num_entries_out*/, const std::string& dir, const std::string& virtual_name) {
            if (count >= max_count) return false;
            std::string tmd_path =
                dir + "/" + virtual_name + "/content/00000000.app";
            if (FileUtil::Exists(tmd_path)) {
                auto loader = Loader::GetLoader(tmd_path);
                if (loader) {
                    out[count].path = strdup(tmd_path.c_str());
                    out[count].media_type = AZ_MEDIA_TYPE_SDMC;
                    count++;
                }
            }
            return true;
        });

    return count;
}

bool az_uninstall_title(int64_t title_id, int media_type) {
    return Service::AM::UninstallProgram(
               static_cast<Service::FS::MediaType>(media_type),
               static_cast<u64>(title_id))
        .IsSuccess();
}

bool az_native_file_exists(const char* path) {
    return path && FileUtil::Exists(path);
}

const char* az_get_home_menu_path(int region) {
    std::string path = Core::GetHomeMenuNcchPath(region);
    static thread_local std::string cached;
    cached = path;
    return cached.c_str();
}

int az_get_system_title_ids(int system_type, int region, int64_t* out, int max_count) {
    if (!out || max_count <= 0) return 0;
    auto ids = Core::GetSystemTitleIds(
        static_cast<Core::SystemTitleSet>(system_type), region);
    int count = 0;
    for (auto id : ids) {
        if (count >= max_count) break;
        out[count++] = static_cast<int64_t>(id);
    }
    return count;
}

void az_get_are_system_titles_installed(bool* out) {
    if (!out) return;
    auto [old_3ds, new_3ds] = Core::AreSystemTitlesInstalled();
    out[0] = old_3ds;
    out[1] = new_3ds;
}

void az_uninstall_system_files(bool old3ds) {
    Core::UninstallSystemFiles(old3ds ? Core::SystemTitleSet::Old3ds : Core::SystemTitleSet::New3ds);
}

bool az_is_full_console_linked(void) {
    return HW::UniqueData::IsFullConsoleLinked();
}

void az_unlink_console(void) {
    HW::UniqueData::UnlinkConsole();
}

// ---------------------------------------------------------------------------
// Save states / perf / play time
// ---------------------------------------------------------------------------

int az_get_savestate_info(az_savestate_info* out, int max_count) {
    if (!out || max_count <= 0) return 0;
    auto& system = Core::System::GetInstance();
    if (!system.IsPoweredOn()) return 0;
    u64 title_id = 0;
    auto& loader = system.GetAppLoader();
    loader.ReadProgramId(title_id);
    if (title_id == 0) return 0;

    auto states = Core::ListSaveStates(title_id, system.Movie().GetCurrentMovieID());
    int count = 0;
    for (const auto& state : states) {
        if (count >= max_count) break;
        out[count].slot = state.slot;
        out[count].timestamp_ms = state.time * 1000;
        count++;
    }
    return count;
}

void az_save_state(int slot) {
    Core::System::GetInstance().SendSignal(Core::System::Signal::Save, slot);
}

void az_load_state(int slot) {
    Core::System::GetInstance().SendSignal(Core::System::Signal::Load, slot);
}

void az_get_perf_stats(double* out) {
    if (!out) return;
    auto& system = Core::System::GetInstance();
    auto stats = system.GetAndResetPerfStats();
    out[0] = stats.system_fps;
    out[1] = stats.game_fps;
    out[2] = stats.emulation_speed;
    out[3] = stats.time_vblank_interval;
    out[4] = stats.time_hle_svc;
    out[5] = stats.time_hle_ipc;
    out[6] = stats.time_gpu;
    out[7] = stats.time_swap;
    out[8] = stats.time_remaining;
}

void az_play_time_init(void) {
    play_time_manager = std::make_unique<PlayTime::PlayTimeManager>();
}

void az_play_time_start(int64_t title_id) {
    ptm_current_title_id = title_id;
    if (play_time_manager) {
        play_time_manager->SetProgramId(static_cast<u64>(title_id));
        play_time_manager->Start();
    }
}

void az_play_time_stop(void) {
    if (play_time_manager) play_time_manager->Stop();
}

int64_t az_play_time_get(int64_t title_id) {
    if (!play_time_manager) return 0;
    return static_cast<int64_t>(play_time_manager->GetPlayTime(static_cast<u64>(title_id)));
}

int64_t az_play_time_get_current_title(void) {
    return ptm_current_title_id;
}

// ---------------------------------------------------------------------------
// Amiibo
// ---------------------------------------------------------------------------

bool az_load_amiibo(const char* path) {
    if (!path) return false;
    auto& system = Core::System::GetInstance();
    auto nfc = system.ServiceManager().GetService<Service::NFC::Module::Interface>("nfc:u");
    if (nfc) {
        return nfc->LoadAmiibo(path);
    }
    return false;
}

void az_remove_amiibo(void) {
    auto& system = Core::System::GetInstance();
    auto nfc = system.ServiceManager().GetService<Service::NFC::Module::Interface>("nfc:u");
    if (nfc) nfc->RemoveAmiibo();
}

// ---------------------------------------------------------------------------
// Software keyboard / Mii selector — implemented in applets_ios.mm
// (az_swkbd_submit, az_swkbd_cancel, az_mii_select, az_mii_cancel).
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// Netplay — stubs (wire through multiplayer.cpp when needed)
// ---------------------------------------------------------------------------

void az_netplay_init(void) {}
void az_netplay_shutdown(void) {}
int az_netplay_get_public_rooms(az_room_entry*, int) { return 0; }
int az_netplay_create_room(const char*, int, const char*, const char*, int64_t, const char*, const char*, int) { return AZ_NETPLAY_UNKNOWN_ERROR; }
int az_netplay_join_room(const char*, int, const char*, const char*) { return AZ_NETPLAY_UNKNOWN_ERROR; }
int az_netplay_get_room_info(az_room_entry*) { return 0; }
bool az_netplay_is_joined(void) { return false; }
bool az_netplay_is_hosted_room(void) { return false; }
void az_netplay_send_message(const char*) {}
void az_netplay_kick_user(const char*) {}
void az_netplay_leave_room(void) {}
bool az_netplay_is_moderator(void) { return false; }
int az_netplay_get_ban_list(char**, int) { return 0; }
void az_netplay_ban_user(const char*) {}
void az_netplay_unban_user(const char*) {}

// ---------------------------------------------------------------------------
// Cheats — stubs
// ---------------------------------------------------------------------------

int az_cheats_load(const char*, az_cheat_entry*, int) { return 0; }
bool az_cheats_set_enabled(int64_t, bool) { return false; }
bool az_cheats_apply(void) { return false; }

// ---------------------------------------------------------------------------
// ROM/CIA compression
// ---------------------------------------------------------------------------

int az_compress_file(const char*, const char*) { return AZ_COMPRESS_UNSUPPORTED; }
int az_decompress_file(const char*, const char*) { return AZ_DECOMPRESS_UNSUPPORTED; }
char* az_get_recommended_extension(const char*, bool) { return strdup(""); }

// ---------------------------------------------------------------------------
// ZipPass (StreetPass export/import)
// ---------------------------------------------------------------------------

int az_zippass_export(const char* path) {
    if (!path) return -1;
    return Core::exportZipPass(std::string(path));
}

int az_zippass_import(const char* path) {
    if (!path) return -1;
    return Core::importZipPass(std::string(path));
}

int az_zippass_import_queued(void) {
    return Core::importQueuedZipPass();
}

int az_zippass_clear_config(void) {
    return Core::clearStreetPassConfig();
}

// ---------------------------------------------------------------------------
// System Files
// ---------------------------------------------------------------------------

int az_install_cia(const char* path) {
    if (!path) return static_cast<int>(Service::AM::InstallStatus::ErrorFailedToOpenFile);
    
    auto& system = Core::System::GetInstance();
    Service::AM::InstallStatus status = Service::AM::InstallCIA(
        std::string(path),
        [](std::size_t current, std::size_t total) {
            // Progress callback - could expose this to Swift if needed
        }
    );
    
    return static_cast<int>(status);
}

bool az_system_files_available(void) {
    return HW::AES::IsKeyXAvailable(HW::AES::KeySlotID::NCCHSecure1) &&
           HW::AES::IsKeyXAvailable(HW::AES::KeySlotID::NCCHSecure2);
}

bool az_system_files_region_available(int region) {
    if (region < 0 || region > 6) return false;
    
    // Check if the home menu for this region exists
    const std::string home_menu_path = Core::GetHomeMenuNcchPath(region);
    return FileUtil::Exists(home_menu_path);
}

// ---------------------------------------------------------------------------
// RetroAchievements
// ---------------------------------------------------------------------------

static az_ra_event_callback ra_event_callback = nullptr;
static az_ra_user_t ra_cached_user;
static az_ra_game_t ra_cached_game;
static std::string ra_cached_username;
static std::string ra_cached_display_name;
static std::string ra_cached_token;
static std::string ra_cached_avatar_url;
static std::string ra_cached_game_title;
static std::string ra_cached_game_badge_url;

class IOSClientObserver : public RetroAchievements::ClientObserver {
public:
    void OnLoginSucceeded(const rc_client_user_t* user) override {
        if (user) {
            ra_cached_username = user->username ? user->username : "";
            ra_cached_display_name = user->display_name ? user->display_name : "";
            ra_cached_token = user->token ? user->token : "";
            ra_cached_avatar_url = user->avatar_url ? user->avatar_url : "";
            
            ra_cached_user.username = ra_cached_username.c_str();
            ra_cached_user.display_name = ra_cached_display_name.c_str();
            ra_cached_user.score = user->score;
            ra_cached_user.score_softcore = user->score_softcore;
            ra_cached_user.token = ra_cached_token.c_str();
            ra_cached_user.avatar_url = ra_cached_avatar_url.c_str();
        }
    }

    void OnLoginFailed(int result, const char* error_message) override {
        LOG_ERROR(Frontend, "RetroAchievements login failed: {}", error_message);
    }

    void OnLoadGameSucceeded(const rc_client_game_t* game) override {
        if (game) {
            ra_cached_game_title = game->title ? game->title : "";
            ra_cached_game_badge_url = game->badge_url ? game->badge_url : "";
            
            ra_cached_game.id = game->id;
            ra_cached_game.title = ra_cached_game_title.c_str();
            ra_cached_game.badge_url = ra_cached_game_badge_url.c_str();
            ra_cached_game.num_achievements = game->num_achievements;
            ra_cached_game.num_unlocked = game->num_unlocked_achievements;
        }
    }

    void OnLoadGameFailed(int result, const char* error_message) override {
        LOG_ERROR(Frontend, "RetroAchievements load game failed: {}", error_message);
    }

    void OnEvent(const rc_client_event_t* event) override {
        if (!ra_event_callback || !event) return;

        const char* title = "";
        const char* description = "";
        const char* badge_url = "";

        switch (event->type) {
            case RC_CLIENT_EVENT_ACHIEVEMENT_TRIGGERED:
                if (event->achievement) {
                    title = event->achievement->title ? event->achievement->title : "";
                    description = event->achievement->description ? event->achievement->description : "";
                    badge_url = event->achievement->badge_url ? event->achievement->badge_url : "";
                }
                break;
            case RC_CLIENT_EVENT_LEADERBOARD_STARTED:
            case RC_CLIENT_EVENT_LEADERBOARD_FAILED:
            case RC_CLIENT_EVENT_LEADERBOARD_SUBMITTED:
            case RC_CLIENT_EVENT_LEADERBOARD_TRACKER_UPDATE:
            case RC_CLIENT_EVENT_LEADERBOARD_TRACKER_SHOW:
            case RC_CLIENT_EVENT_LEADERBOARD_TRACKER_HIDE:
                if (event->leaderboard) {
                    title = event->leaderboard->title ? event->leaderboard->title : "";
                    description = event->leaderboard->description ? event->leaderboard->description : "";
                }
                break;
            default:
                break;
        }

        ra_event_callback(event->type, title, description, badge_url);
    }
};

static std::unique_ptr<IOSClientObserver> ios_ra_observer;

void az_ra_set_event_callback(az_ra_event_callback callback) {
    ra_event_callback = callback;
}

void az_ra_login(const char* username, const char* password) {
    if (!username || !password) return;
    
    auto& system = Core::System::GetInstance();
    auto& client = system.RetroAchievementsClient();
    
    if (!ios_ra_observer) {
        ios_ra_observer = std::make_unique<IOSClientObserver>();
        client.RegisterObserver(*ios_ra_observer);
    }
    
    client.AttemptLogin(username, password);
}

void az_ra_login_with_token(const char* username, const char* token) {
    if (!username || !token) return;
    
    auto& system = Core::System::GetInstance();
    auto& client = system.RetroAchievementsClient();
    
    if (!ios_ra_observer) {
        ios_ra_observer = std::make_unique<IOSClientObserver>();
        client.RegisterObserver(*ios_ra_observer);
    }
    
    client.AttemptLoginWithToken(username, token);
}

void az_ra_logout(void) {
    auto& system = Core::System::GetInstance();
    auto& client = system.RetroAchievementsClient();
    client.LogOut();
    
    // Clear cached data
    ra_cached_username.clear();
    ra_cached_display_name.clear();
    ra_cached_token.clear();
    ra_cached_avatar_url.clear();
}

bool az_ra_is_logged_in(void) {
    auto& system = Core::System::GetInstance();
    auto& client = system.RetroAchievementsClient();
    return client.GetUser() != nullptr;
}

const az_ra_user_t* az_ra_get_user(void) {
    auto& system = Core::System::GetInstance();
    auto& client = system.RetroAchievementsClient();
    const rc_client_user_t* user = client.GetUser();
    
    if (!user) return nullptr;
    
    // Update cached user data
    ra_cached_username = user->username ? user->username : "";
    ra_cached_display_name = user->display_name ? user->display_name : "";
    ra_cached_token = user->token ? user->token : "";
    ra_cached_avatar_url = user->avatar_url ? user->avatar_url : "";
    
    ra_cached_user.username = ra_cached_username.c_str();
    ra_cached_user.display_name = ra_cached_display_name.c_str();
    ra_cached_user.score = user->score;
    ra_cached_user.score_softcore = user->score_softcore;
    ra_cached_user.token = ra_cached_token.c_str();
    ra_cached_user.avatar_url = ra_cached_avatar_url.c_str();
    
    return &ra_cached_user;
}

const az_ra_game_t* az_ra_get_game(void) {
    // TODO: Implement when game loading is integrated
    return nullptr;
}

int az_ra_get_achievements(az_ra_achievement_t* out, int max_count) {
    // TODO: Implement achievement list retrieval
    return 0;
}

void az_ra_set_enabled(bool enabled) {
    Settings::values.retroachievements_enabled = enabled;
}

bool az_ra_is_enabled(void) {
    return Settings::values.retroachievements_enabled.GetValue();
}

// ---------------------------------------------------------------------------
// Misc
// ---------------------------------------------------------------------------

void az_free_string(char* str) { free(str); }

const char* az_get_version_string(void) {
    static thread_local std::string ver = Common::g_scm_rev;
    return ver.c_str();
}
