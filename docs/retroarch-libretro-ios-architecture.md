# RetroArch + Azahar/Citra LibRetro Core on iOS: Architecture Deep Dive

**Date**: 2026-08-05  
**Purpose**: Document how RetroArch successfully runs the Azahar (Citra fork) libretro core on iOS using Vulkan/MoltenVK

---

## Table of Contents

1. [Overview](#overview)
2. [LibRetro Architecture](#libretro-architecture)
3. [Vulkan Context Ownership](#vulkan-context-ownership)
4. [iOS-Specific Implementation](#ios-specific-implementation)
5. [Build System](#build-system)
6. [Runtime Flow](#runtime-flow)
7. [Key Differences vs Native App](#key-differences-vs-native-app)
8. [Why This Approach Works on iOS](#why-this-approach-works-on-ios)

---

## Overview

### What is LibRetro?

LibRetro is an API specification that allows emulator cores to be used across multiple frontend applications. The core provides emulation logic, while the frontend (RetroArch) provides:
- Window/display management
- Input handling
- Audio output
- Video rendering context (OpenGL/Vulkan)
- Save states
- UI/menu system
- Network features (achievements, netplay)

### Azahar as a LibRetro Core

Azahar builds two separate targets:
1. **Native Applications** (`azahar` desktop, `Azahar.app` iOS) - Standalone apps with full UI
2. **LibRetro Core** (`azahar_libretro.so`/`.dylib`) - Headless emulator library

The iOS libretro core is built as:
- **Desktop/Android**: `azahar_libretro.so` (shared library loaded dynamically)
- **iOS**: Statically linked into RetroArch.app (iOS doesn't allow dynamic library loading)

---

## LibRetro Architecture

### Core Responsibilities (Azahar LibRetro Core)

```
┌─────────────────────────────────────────────┐
│    Azahar LibRetro Core (libretro core)    │
├─────────────────────────────────────────────┤
│  • 3DS CPU emulation (ARM11 + ARM9)        │
│  • GPU emulation (PICA200)                  │
│  • Memory management                        │
│  • Game logic                               │
│  • Save state serialization                 │
│  • Audio/video frame generation             │
│  • Input mapping                            │
│                                             │
│  DOES NOT:                                  │
│  ✗ Create windows                          │
│  ✗ Manage Vulkan instance                  │
│  ✗ Handle surface creation                 │
│  ✗ Provide UI/menu                         │
│  ✗ Manage save files (frontend does)       │
└─────────────────────────────────────────────┘
```

### Frontend Responsibilities (RetroArch)

```
┌─────────────────────────────────────────────┐
│         RetroArch Frontend (iOS)            │
├─────────────────────────────────────────────┤
│  • UIKit window/view management             │
│  • CAMetalLayer creation & setup            │
│  • Vulkan instance creation                 │
│  • Vulkan surface creation                  │
│  • Swapchain management                     │
│  • Input device handling (touch, MFi)       │
│  • Audio output (AudioQueue/AudioUnit)      │
│  • Menu system (XMB/Ozone/RGUI)             │
│  • Save state management                    │
│  • RetroAchievements client                 │
│  • File browser                             │
│  • Core loading/management                  │
└─────────────────────────────────────────────┘
```

---

## Vulkan Context Ownership

### Critical Difference: Who Creates What?

#### Native Azahar iOS App
```
Azahar App (SwiftUI)
    └─> GameView (UIView with CAMetalLayer)
        └─> VideoCore::RendererVulkan
            └─> Vulkan::CreateInstance()  ← Creates VkInstance
                └─> VkSurface from CAMetalLayer
                    └─> VkSwapchain
                        └─> Renders to screen
```

#### RetroArch + Azahar LibRetro Core
```
RetroArch iOS App (UIKit)
    └─> MetalLayerView (UIView with CAMetalLayer)
        └─> RetroArch Vulkan Driver (vulkan_common.c)
            └─> vkCreateInstance()  ← RetroArch creates instance
                └─> VkSurface from CAMetalLayer
                    └─> VkSwapchain
                        └─> Azahar LibRetro Core
                            └─> retro_hw_render_interface_vulkan
                                └─> Uses RetroArch's VkInstance
                                └─> Gets pre-configured VkDevice
                                └─> Renders to RetroArch's swapchain
```

### LibRetro Vulkan API

The core receives a pre-initialized Vulkan context from RetroArch:

**File**: `externals/libretro/libretro_vulkan.h` (in Azahar codebase)

```c
struct retro_hw_render_interface_vulkan {
    VkInstance instance;                    // Created by RetroArch
    VkPhysicalDevice gpu;                   // Selected by RetroArch
    VkDevice device;                        // Created by RetroArch
    VkQueue queue;                          // RetroArch's graphics queue
    uint32_t queue_index;
    
    // Image to render into (from swapchain)
    VkImage image;
    VkImageView image_view;
    VkFormat image_format;
    
    // Synchronization
    VkCommandBuffer command_buffer;
    VkSemaphore semaphore;
    
    // Callbacks
    VkDevice (*get_device_proc_addr)(VkDevice device, const char *name);
    VkInstance (*get_instance_proc_addr)(VkInstance instance, const char *name);
};
```

**Key Point**: The core NEVER calls `vkCreateInstance` - it's a no-op!

---

## iOS-Specific Implementation

### RetroArch iOS Vulkan Setup

#### 1. CAMetalLayer Creation (ref/RetroArch/ui/drivers/ui_cocoatouch.m:508-538)

```objc
@implementation MetalLayerView

// Critical: Tell UIKit to use CAMetalLayer instead of CALayer
+ (Class)layerClass {
    return [CAMetalLayer class];
}

- (CAMetalLayer *)metalLayer {
    return (CAMetalLayer *)self.layer;  // Safe because of +layerClass
}

- (void)setupMetalLayer {
    // Create Metal device (required by MoltenVK)
    self.metalLayer.device = MTLCreateSystemDefaultDevice();
    
    // Retina display support
    self.metalLayer.contentsScale = cocoa_screen_get_native_scale();
    
    // Opaque for better performance
    self.metalLayer.opaque = YES;
}

@end
```

#### 2. Vulkan Instance Creation (ref/RetroArch/gfx/common/vulkan_common.c:1067-1206)

```c
VkInstance vulkan_context_create_instance_wrapper(void *opaque, const VkInstanceCreateInfo *create_info)
{
    gfx_ctx_vulkan_data_t *vk = (gfx_ctx_vulkan_data_t *)opaque;
    
    // Minimal required extensions for iOS
    const char *required_extensions[3];
    uint32_t required_extension_count = 0;
    
    required_extensions[required_extension_count++] = "VK_KHR_surface";
    
    // iOS uses Metal surface
    if (vk->wsi_type == VULKAN_WSI_MVK_IOS) {
        required_extensions[required_extension_count++] = "VK_EXT_metal_surface";
    }
    
    // Optional portability enumeration (for MoltenVK discovery via Vulkan loader)
    static const char *optional_extensions[] = {
        "VK_KHR_portability_enumeration"
    };
    
    // Check which optional extensions are available
    uint32_t available_count = 0;
    vkEnumerateInstanceExtensionProperties(NULL, &available_count, NULL);
    VkExtensionProperties *available = malloc(available_count * sizeof(VkExtensionProperties));
    vkEnumerateInstanceExtensionProperties(NULL, &available_count, available);
    
    // Enable optional extensions if supported
    bool portability_enabled = false;
    for (i = 0; i < available_count; i++) {
        if (strcmp(available[i].extensionName, "VK_KHR_portability_enumeration") == 0) {
            enabled_extensions[extension_count++] = "VK_KHR_portability_enumeration";
            portability_enabled = true;
            break;
        }
    }
    
    // Only set flag if extension is actually enabled
    if (portability_enabled) {
        instance_info.flags |= VK_INSTANCE_CREATE_ENUMERATE_PORTABILITY_BIT_KHR;
    }
    
    // Create instance (no validation layers on iOS by default)
    VkResult res = vkCreateInstance(&instance_info, NULL, &instance);
    if (res != VK_SUCCESS) {
        RARCH_ERR("[Vulkan] Failed to create instance: %d\n", res);
        return VK_NULL_HANDLE;
    }
    
    return instance;
}
```

#### 3. Surface Creation (ref/RetroArch/gfx/common/vulkan_common.c:1773-1791)

```c
bool vulkan_surface_create(gfx_ctx_vulkan_data_t *vk,
                           enum vulkan_wsi_type type,
                           void *display,
                           void *surface,  // CAMetalLayer* for iOS
                           unsigned width, unsigned height,
                           unsigned swap_interval)
{
    switch (type) {
        case VULKAN_WSI_MVK_IOS:
        {
            VkMetalSurfaceCreateInfoEXT surf_info = {
                .sType  = VK_STRUCTURE_TYPE_METAL_SURFACE_CREATE_INFO_EXT,
                .pNext  = NULL,
                .flags  = 0,
                .pLayer = surface  // CAMetalLayer* passed from MetalLayerView
            };
            
            PFN_vkCreateMetalSurfaceEXT vkCreateMetalSurfaceEXT;
            vkCreateMetalSurfaceEXT = (PFN_vkCreateMetalSurfaceEXT)
                vkGetInstanceProcAddr(vk->context.instance, "vkCreateMetalSurfaceEXT");
            
            if (vkCreateMetalSurfaceEXT(vk->context.instance, &surf_info, NULL, 
                                       &vk->vk_surface) != VK_SUCCESS)
                return false;
        }
        break;
    }
    
    // Create device and swapchain...
    return true;
}
```

#### 4. Context Initialization (ref/RetroArch/gfx/drivers_context/cocoa_vk_ctx.m:465-471)

```objc
static void cocoa_vk_gfx_ctx_init_mainthread(void *userdata)
{
    cocoa_vk_init_args_t *args = (cocoa_vk_init_args_t*)userdata;
    
    // Tell platform layer to create MetalLayerView
    [apple_platform setViewType:APPLE_VIEW_TYPE_VULKAN];
    
    // Initialize Vulkan context (iOS-specific WSI type)
    args->ok = vulkan_context_init(&args->ctx->vk, VULKAN_WSI_MVK_IOS);
}
```

### Azahar LibRetro Core's Stub Implementation

**File**: `src/citra_libretro/libretro_vk.cpp:252-260`

```cpp
vk::UniqueInstance CreateInstance([[maybe_unused]] const Common::DynamicLibrary& library,
                                  [[maybe_unused]] Frontend::WindowSystemType window_type,
                                  [[maybe_unused]] bool enable_validation,
                                  [[maybe_unused]] bool dump_command_buffers) {
    // LibRetro manages the VkInstance - we don't create one
    LOG_WARNING(Render_Vulkan, "CreateInstance called in LibRetro mode - this should not happen");
    return nullptr;  // RetroArch owns the instance
}
```

**Critical**: This function is never actually called because the core uses the pre-created context from RetroArch.

---

## Build System

### RetroArch iOS Build Configuration

RetroArch on iOS is built with:
```makefile
# From Makefile (simplified)
HAVE_COCOA_METAL = 1      # Metal support
HAVE_COCOATOUCH = 1       # iOS-specific UI
HAVE_VULKAN = 1           # Vulkan rendering
HAVE_SLANG = 1            # Slang shader support
HAVE_SPIRV_CROSS = 1      # SPIR-V to Metal translation
```

### Azahar LibRetro Core Build

**File**: `src/citra_libretro/CMakeLists.txt`

```cmake
# LibRetro core target
add_library(azahar_libretro SHARED
    libretro.cpp
    libretro_vk.cpp      # Stub Vulkan implementation
    libretro_core_impl.cpp
    # ... other sources
)

# iOS-specific: Static library (iOS doesn't support dylib loading)
if(IOS)
    set_target_properties(azahar_libretro PROPERTIES
        BUNDLE TRUE
        MACOSX_BUNDLE_INFO_PLIST ${CMAKE_CURRENT_SOURCE_DIR}/Info.plist
    )
endif()

# Link against video_core but exclude platform layer
target_link_libraries(azahar_libretro PRIVATE
    video_core
    core
    audio_core
    # NOT linking: ios_bridge, SwiftUI views
)
```

### Key Build Differences

| Component | Native iOS App | LibRetro Core |
|-----------|----------------|---------------|
| **Entry Point** | `@main AzaharApp` (SwiftUI) | `retro_init()` (C API) |
| **UI** | Full SwiftUI interface | No UI (RetroArch provides) |
| **Vulkan Instance** | Created by app | Created by RetroArch |
| **Window Management** | GameView + SwiftUI | RetroArch's MetalLayerView |
| **Input** | GameControllerInput.swift | `retro_input_poll()` |
| **Audio** | Native AudioQueue | RetroArch audio driver |
| **Save States** | CoreDataManager.swift | `retro_serialize()` API |
| **Settings UI** | SettingsView.swift | RetroArch menu |
| **File Format** | `.app` bundle | `.dylib` or static link |

---

## Runtime Flow

### Startup Sequence

```
1. User launches RetroArch iOS app
   └─> RetroArch_iOS application:didFinishLaunchingWithOptions:

2. User selects "Load Core" → "Nintendo 3DS (Azahar)"
   └─> RetroArch loads azahar_libretro core
       └─> Calls retro_init()
           └─> Azahar initializes CPU, memory, etc.
           └─> Does NOT initialize video (waiting for context)

3. User selects ROM file
   └─> RetroArch calls retro_load_game()
       └─> Azahar loads ROM into emulated memory

4. RetroArch initializes video
   └─> Creates MetalLayerView
       └─> Calls +[MetalLayerView layerClass] → returns CAMetalLayer
       └─> Calls setupMetalLayer
           └─> metalLayer.device = MTLCreateSystemDefaultDevice()
           └─> metalLayer.contentsScale = screen scale
           └─> metalLayer.opaque = YES

5. RetroArch creates Vulkan context (MAIN THREAD ONLY)
   └─> vulkan_context_init(&vk, VULKAN_WSI_MVK_IOS)
       └─> vkCreateInstance() with minimal extensions
           └─> VK_KHR_surface
           └─> VK_EXT_metal_surface
           └─> VK_KHR_portability_enumeration (if available)
       └─> vkCreateMetalSurfaceEXT(metalLayer)
       └─> Selects physical device (iPhone GPU)
       └─> vkCreateDevice()
       └─> vkCreateSwapchainKHR()

6. RetroArch passes Vulkan context to core
   └─> retro_get_hw_render_interface(RETRO_HW_RENDER_INTERFACE_VULKAN)
       └─> Returns retro_hw_render_interface_vulkan struct
           └─> instance = RetroArch's VkInstance
           └─> device = RetroArch's VkDevice
           └─> queue = RetroArch's VkQueue
           └─> image = Current swapchain image
       
7. Azahar core initializes renderer with provided context
   └─> VideoCore::RendererVulkan::Init()
       └─> Uses retro_hw_render_interface_vulkan.instance
       └─> Skips vkCreateInstance() (already done)
       └─> Creates pipelines, descriptor sets, buffers
       └─> Uses RetroArch's command buffer

8. Main loop
   └─> RetroArch calls retro_run() @ 60 FPS
       └─> Azahar emulates 1 frame (3DS CPU executes)
       └─> Azahar renders to RetroArch's command buffer
           └─> Draws PICA200 output via Vulkan
       └─> Returns to RetroArch
       └─> RetroArch submits command buffer
       └─> RetroArch presents swapchain image
       └─> Frame displayed on screen
```

### Frame Rendering Details

```cpp
// In Azahar libretro core
void retro_run() {
    // 1. Emulate 3DS for one frame
    Core::System::GetInstance().RunLoop();
    
    // 2. Get RetroArch's Vulkan interface
    auto* vulkan = static_cast<const retro_hw_render_interface_vulkan*>(
        hw_render.get_current_framebuffer()
    );
    
    // 3. Render using RetroArch's command buffer
    VkCommandBuffer cmd = vulkan->command_buffer;
    
    vkBeginCommandBuffer(cmd, &begin_info);
    
    // Transition RetroArch's swapchain image to render target
    vkCmdPipelineBarrier(cmd, ...);
    
    // Render pass with RetroArch's image as attachment
    VkRenderPassBeginInfo rp_info = {
        .renderPass = our_render_pass,
        .framebuffer = our_framebuffer_wrapping_retroarch_image,
        .renderArea = {{0, 0}, {width, height}}
    };
    
    vkCmdBeginRenderPass(cmd, &rp_info, VK_SUBPASS_CONTENTS_INLINE);
    
    // Draw 3DS screen content
    vkCmdBindPipeline(cmd, VK_PIPELINE_BIND_POINT_GRAPHICS, pipeline);
    vkCmdBindDescriptorSets(cmd, ...);
    vkCmdDraw(cmd, ...);
    
    vkCmdEndRenderPass(cmd);
    
    // Transition back to present
    vkCmdPipelineBarrier(cmd, ...);
    
    vkEndCommandBuffer(cmd);
    
    // RetroArch submits and presents
}
```

---

## Key Differences vs Native App

### 1. Vulkan Initialization

| Aspect | Native App | LibRetro Core |
|--------|------------|---------------|
| **vkCreateInstance** | App calls directly | RetroArch calls, core receives handle |
| **Extension Selection** | App decides | RetroArch decides (iOS-optimized) |
| **Validation Layers** | App can enable | RetroArch controls (usually disabled) |
| **Instance Ownership** | App owns | RetroArch owns |
| **Error Handling** | App must handle | RetroArch handles, core sees working context |

### 2. Surface & Swapchain

| Aspect | Native App | LibRetro Core |
|--------|------------|---------------|
| **CAMetalLayer** | GameView creates | MetalLayerView creates (proven iOS setup) |
| **VkSurface** | App creates from layer | RetroArch creates from layer |
| **Swapchain** | App manages | RetroArch manages |
| **Present** | App calls vkQueuePresentKHR | RetroArch presents |
| **Resize Handling** | App handles | RetroArch handles |

### 3. Threading Model

| Aspect | Native App | LibRetro Core |
|--------|------------|---------------|
| **Vulkan Calls** | May be on any thread | Guaranteed main thread (RetroArch enforces) |
| **MoltenVK Dispatch** | May deadlock with GCD | Short-circuits (on main thread) |
| **Command Recording** | App manages threads | Single-threaded (RetroArch's run loop) |

### 4. MoltenVK Configuration

| Aspect | Native App | LibRetro Core |
|--------|------------|---------------|
| **MTLDevice** | App must set on layer | RetroArch sets correctly |
| **contentsScale** | App must set (Retina) | RetroArch sets (proven working) |
| **Opaque Flag** | App must set | RetroArch sets |
| **Frame Pacing** | App implements | RetroArch handles |

---

## Why This Approach Works on iOS

### 1. **Proven CAMetalLayer Setup**

RetroArch's MetalLayerView has been tested on thousands of iOS devices:
- Correctly sets `MTLDevice` (required by MoltenVK)
- Handles Retina scaling automatically
- Proper opaque flag for performance
- Tested with iOS 11-18+

### 2. **Main Thread Execution**

RetroArch enforces all Vulkan operations on the main thread:
```objc
// All Vulkan init/teardown wrapped in main thread sync
cocoa_main_thread_sync(cocoa_vk_gfx_ctx_init_mainthread, &args);
```

This avoids MoltenVK's internal `dispatch_sync` to main queue, which would deadlock with threaded video.

### 3. **Minimal Extension Set**

RetroArch only requests extensions known to work on iOS:
- `VK_KHR_surface` (required)
- `VK_EXT_metal_surface` (required for iOS)
- `VK_KHR_portability_enumeration` (optional, fallback if unavailable)

No desktop-specific extensions requested.

### 4. **Conditional Portability Flag**

```c
// Only set flag if extension is actually available
if (portability_enabled) {
    instance_info.flags |= VK_INSTANCE_CREATE_ENUMERATE_PORTABILITY_BIT_KHR;
}
```

Prevents crash if extension is missing.

### 5. **Tested Integration**

RetroArch has shipped Azahar/Citra core on iOS for years:
- App Store approved
- Runs on physical devices (not just simulator)
- Handles iOS-specific quirks (memory pressure, backgrounding)
- Proven MoltenVK configuration

### 6. **Core Simplicity**

The libretro core doesn't need to:
- Detect iOS platform
- Handle iOS-specific Vulkan quirks
- Manage CAMetalLayer
- Deal with UIKit threading
- Handle app lifecycle

RetroArch isolates all iOS complexity from the core.

---

## Summary: What Makes LibRetro Work on iOS

```
┌────────────────────────────────────────────────────────────┐
│                  RetroArch iOS Success                      │
├────────────────────────────────────────────────────────────┤
│                                                             │
│  ✓ Proven CAMetalLayer setup (MTLDevice, scale, opaque)   │
│  ✓ Main thread enforcement (no GCD deadlocks)              │
│  ✓ Minimal Vulkan extensions (iOS-compatible only)         │
│  ✓ Conditional portability flag (fallback if missing)      │
│  ✓ Pre-initialized context (core receives working VkDevice)│
│  ✓ Years of iOS-specific testing and refinement            │
│  ✓ Core isolation from platform complexity                 │
│                                                             │
│  The core can focus on emulation, not iOS quirks.          │
└────────────────────────────────────────────────────────────┘
```

**Key Insight**: RetroArch absorbs all iOS/MoltenVK complexity, providing the core with a "just works" Vulkan context. The native app must replicate this same proven setup to succeed.

---

## Recommendations for Native App

To achieve the same success as RetroArch:

1. **Copy MetalLayerView setup exactly** - Don't reinvent, use proven pattern
2. **Enforce main thread for all Vulkan** - Wrap in `DispatchQueue.main.sync`
3. **Use RetroArch's extension list** - Minimal required + optional fallback
4. **Conditionally set portability flag** - Only if extension available
5. **Test with minimal config first** - Get basic instance creation working
6. **Add features incrementally** - Don't try everything at once

The detailed recommendations in `docs/vulkan-ios-retroarch-analysis.md` provide specific code changes to achieve this.
