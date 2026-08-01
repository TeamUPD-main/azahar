// Copyright Citra Emulator Project / Azahar Emulator Project
// Licensed under GPLv2 or any later version
// Refer to the license.txt file included.

#pragma once

#include "core/frontend/emu_window.h"

#ifdef __OBJC__
@class CAMetalLayer;
#else
typedef struct CAMetalLayer CAMetalLayer;
#endif

/**
 * EmuWindow for iOS. The Vulkan backend renders into a CAMetalLayer handed over
 * from the SwiftUI frontend (see vk_platform.cpp: the Apple path builds a
 * vk::MetalSurfaceCreateInfoEXT from a CAMetalLayer*). Like the Android Vulkan
 * window this class creates no graphics objects itself; presentation is handled
 * by the renderer's own present thread via the TextureMailbox.
 */
class EmuWindowIOS final : public Frontend::EmuWindow {
public:
    explicit EmuWindowIOS(CAMetalLayer* layer, bool is_secondary);
    ~EmuWindowIOS() override;

    /// Returns true if the surface actually changed.
    bool OnSurfaceChanged(CAMetalLayer* layer);

    bool OnTouchEvent(int x, int y, bool pressed);
    void OnTouchMoved(int x, int y);

    /// Recomputes the framebuffer layout from the current window size.
    void OnFramebufferSizeChanged();

    /// The native CAMetalLayer currently attached (may be null).
    CAMetalLayer* GetLayer() const {
        return host_layer;
    }

    unsigned GetWidth() const {
        return window_width;
    }

    unsigned GetHeight() const {
        return window_height;
    }

    void PollEvents() override;
    std::unique_ptr<Frontend::GraphicsContext> CreateSharedContext() const override;
    void MakeCurrent() override;
    void DoneCurrent() override;

private:
    void DestroyWindowSurface();

    CAMetalLayer* render_layer = nullptr; // Pending layer (applied on PollEvents)
    CAMetalLayer* host_layer = nullptr;   // Current layer
    unsigned window_width = 0;
    unsigned window_height = 0;
};
