// Copyright Citra Emulator Project / Azahar Emulator Project
// Licensed under GPLv2 or any later version
// Refer to the license.txt file included.

#include <algorithm>

#include <QuartzCore/QuartzCore.h>

#include "common/logging/log.h"
#include "core/frontend/framebuffer_layout.h"
#include "core/frontend/input.h"
#include "ios/AzaharBridge/EmuWindowIOS.h"
#include "ios/AzaharBridge/input_manager_ios.h"

namespace {

// Portrait state is reported by the Swift frontend to avoid touching UIKit
// from the emulation thread.
std::atomic<bool> g_is_portrait{false};

} // Anonymous namespace

void SetIOSPortraitMode(bool is_portrait) {
    g_is_portrait.store(is_portrait, std::memory_order_relaxed);
}

bool EmuWindowIOS::OnSurfaceChanged(CAMetalLayer* layer) {
    const int temp_width = (layer == nullptr) ? 0 : static_cast<int>(layer.bounds.size.width);
    const int temp_height = (layer == nullptr) ? 0 : static_cast<int>(layer.bounds.size.height);
    
    if (render_layer == layer && temp_width == static_cast<int>(window_width) &&
        temp_height == static_cast<int>(window_height)) {
        LOG_DEBUG(Frontend, "[EmuWindowIOS] Surface unchanged ({}x{}), skipping update", 
                  window_width, window_height);
        return false;
    }
    
    LOG_INFO(Frontend, "[EmuWindowIOS] Surface changed: {}x{} → {}x{}, layer={}", 
             window_width, window_height, temp_width, temp_height, fmt::ptr(layer));
    
    window_width = static_cast<unsigned>(std::max(temp_width, 0));
    window_height = static_cast<unsigned>(std::max(temp_height, 0));
    render_layer = layer;
    window_info.type = Frontend::WindowSystemType::MacOS;
    window_info.render_surface = (__bridge void*)layer;
    
    if (layer && layer.device) {
        LOG_DEBUG(Frontend, "[EmuWindowIOS] Metal device: {}", 
                  [layer.device.name UTF8String]);
    }
    
    OnFramebufferSizeChanged();
    return true;
}

bool EmuWindowIOS::OnTouchEvent(int x, int y, bool pressed) {
    if (pressed) {
        return TouchPressed(static_cast<unsigned>(std::max(x, 0)),
                            static_cast<unsigned>(std::max(y, 0)));
    }

    TouchReleased();
    return true;
}

void EmuWindowIOS::OnTouchMoved(int x, int y) {
    TouchMoved(static_cast<unsigned>(std::max(x, 0)), static_cast<unsigned>(std::max(y, 0)));
}

void EmuWindowIOS::OnFramebufferSizeChanged() {
    const bool is_portrait_mode = g_is_portrait.load(std::memory_order_relaxed) && !is_secondary;
    LOG_DEBUG(Frontend, "[EmuWindowIOS] Updating framebuffer layout: {}x{}, portrait={}, secondary={}", 
              window_width, window_height, is_portrait_mode, is_secondary);
    UpdateCurrentFramebufferLayout(window_width, window_height, is_portrait_mode);
}

EmuWindowIOS::EmuWindowIOS(CAMetalLayer* layer, bool is_secondary)
    : EmuWindow{is_secondary}, host_layer(layer) {
    LOG_INFO(Frontend, "[EmuWindowIOS] Initializing (secondary={}, layer={})", 
             is_secondary, fmt::ptr(layer));
    if (!layer) {
        LOG_WARNING(Frontend, "[EmuWindowIOS] CAMetalLayer is null, running headless");
        return;
    }
    window_width = static_cast<unsigned>(layer.bounds.size.width);
    window_height = static_cast<unsigned>(layer.bounds.size.height);
    LOG_INFO(Frontend, "[EmuWindowIOS] Initial dimensions: {}x{}", window_width, window_height);
    OnSurfaceChanged(layer);
}

EmuWindowIOS::~EmuWindowIOS() {
    LOG_INFO(Frontend, "[EmuWindowIOS] Destroying window (secondary={})", is_secondary);
    DestroyWindowSurface();
}

void EmuWindowIOS::DestroyWindowSurface() {
    render_layer = nullptr;
    host_layer = nullptr;
    window_info.render_surface = nullptr;
}

void EmuWindowIOS::PollEvents() {
    // The Swift frontend calls OnSurfaceChanged directly when the layer changes.
    // Nothing else to poll on iOS.
}

std::unique_ptr<Frontend::GraphicsContext> EmuWindowIOS::CreateSharedContext() const {
    // The Vulkan backend manages its own shared contexts on worker threads.
    return nullptr;
}

void EmuWindowIOS::MakeCurrent() {
    // No-op for the Vulkan backend.
}

void EmuWindowIOS::DoneCurrent() {
    // No-op for the Vulkan backend.
}
