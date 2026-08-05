# Vulkan iOS Initialization: RetroArch vs Azahar Native App

**Date**: 2026-08-04  
**Analysis**: How RetroArch successfully initializes Vulkan on iOS and recommendations for Azahar native app

---

## Executive Summary

RetroArch successfully runs Azahar (3DS emulation) on iOS using Vulkan through MoltenVK. The native Azahar iOS app crashes at `Vulkan::CreateInstance`. This document analyzes the key differences and provides recommendations.

**Key Finding**: RetroArch uses a simpler, iOS-optimized Vulkan initialization path compared to Azahar's desktop-focused approach.

---

## RetroArch's iOS Vulkan Setup

### 1. Instance Creation (ref/RetroArch/gfx/common/vulkan_common.c:1067-1206)

**Required Extensions Only:**
```c
const char *required_extensions[3];
uint32_t required_extension_count = 0;

required_extensions[required_extension_count++] = "VK_KHR_surface";

// For iOS (VULKAN_WSI_MVK_IOS):
case VULKAN_WSI_MVK_IOS:
    required_extensions[required_extension_count++] = "VK_EXT_metal_surface";
    break;
```

**Optional Extensions (Lines 1055-1065):**
```c
static const char *vulkan_optional_instance_extensions[] = {
#ifdef __APPLE__
    VK_KHR_PORTABILITY_ENUMERATION_EXTENSION_NAME,  // "VK_KHR_portability_enumeration"
#endif
#ifdef _WIN32
    "VK_KHR_get_surface_capabilities2",
#endif
#ifdef VULKAN_HDR_SWAPCHAIN
    VULKAN_COLORSPACE_EXTENSION_NAME  // "VK_EXT_swapchain_colorspace"
#endif
};
```

**Portability Flag (Lines 1165-1175):**
```c
#ifdef __APPLE__
    /* Check if portability enumeration was enabled (needed for Vulkan loader to find MoltenVK) */
    for (i = 0; i < info.enabledExtensionCount; i++)
    {
        if (string_is_equal(instance_extensions[i], VK_KHR_PORTABILITY_ENUMERATION_EXTENSION_NAME))
        {
            info.flags |= VK_INSTANCE_CREATE_ENUMERATE_PORTABILITY_BIT_KHR;  // 0x00000001
            break;
        }
    }
#endif
```

**Instance Creation:**
```c
if ((res = vkCreateInstance(&info, NULL, &instance)) != VK_SUCCESS)
{
    RARCH_ERR("[Vulkan] Failed to create Vulkan instance (%d).\n", res);
    RARCH_ERR("[Vulkan] If VULKAN_DEBUG=1 is enabled, make sure Vulkan validation layers are installed.\n");
    for (i = 0; i < info.enabledLayerCount; i++)
        RARCH_ERR("[Vulkan] Core explicitly enables layer (%s), this might be cause of failure.\n", info.ppEnabledLayerNames[i]);
    instance = VK_NULL_HANDLE;
    goto end;
}
```

### 2. Surface Creation (ref/RetroArch/gfx/common/vulkan_common.c:1773-1791)

**iOS-Specific Surface Creation:**
```c
case VULKAN_WSI_MVK_IOS:
#if defined(HAVE_COCOA) || defined(HAVE_COCOA_METAL) || defined(HAVE_COCOATOUCH)
    {
        VkMetalSurfaceCreateInfoEXT surf_info;
        PFN_vkCreateMetalSurfaceEXT create;
        
        if (!VULKAN_SYMBOL_WRAPPER_LOAD_INSTANCE_SYMBOL(vk->context.instance, 
                                                        "vkCreateMetalSurfaceEXT", 
                                                        create))
            return false;

        surf_info.sType  = VK_STRUCTURE_TYPE_METAL_SURFACE_CREATE_INFO_EXT;
        surf_info.pNext  = NULL;
        surf_info.flags  = 0;
        surf_info.pLayer = surface;  // CAMetalLayer* passed in

        if (create(vk->context.instance, &surf_info, NULL, &vk->vk_surface) != VK_SUCCESS)
            return false;
    }
#endif
    break;
```

### 3. CAMetalLayer Setup (ref/RetroArch/ui/drivers/ui_cocoatouch.m:508-538)

**MetalLayerView Implementation:**
```objc
@implementation MetalLayerView

+ (Class)layerClass {
    return [CAMetalLayer class];  // Critical: UIKit automatically creates CAMetalLayer
}

- (instancetype)init {
    self = [super init];
    if (self)
        [self setupMetalLayer];
    return self;
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self)
        [self setupMetalLayer];
    return self;
}

- (CAMetalLayer *)metalLayer {
    return (CAMetalLayer *)self.layer;  // Safe cast because of +layerClass
}

- (void)setupMetalLayer {
    self.metalLayer.device = MTLCreateSystemDefaultDevice();
    self.metalLayer.contentsScale = cocoa_screen_get_native_scale();  // Retina support
    self.metalLayer.opaque = YES;
}

@end
```

### 4. Context Initialization Flow (ref/RetroArch/gfx/drivers_context/cocoa_vk_ctx.m)

**iOS Init (Lines 465-471):**
```objc
static void cocoa_vk_gfx_ctx_init_mainthread(void *userdata)
{
    cocoa_vk_init_args_t *args = (cocoa_vk_init_args_t*)userdata;

    [apple_platform setViewType:APPLE_VIEW_TYPE_VULKAN];  // Creates MetalLayerView
    args->ok = vulkan_context_init(&args->ctx->vk, VULKAN_WSI_MVK_IOS);
}
```

**Surface Creation (Lines 413-432):**
```objc
static void cocoa_vk_gfx_ctx_set_video_mode_mainthread(void *userdata)
{
    cocoa_vk_set_video_mode_args_t *args = (cocoa_vk_set_video_mode_args_t*)userdata;
    id g_view = apple_platform.renderView;
    cocoa_vk_ctx_data_t *cocoa_ctx = (cocoa_vk_ctx_data_t*)args->data;
    
    cocoa_ctx->width  = args->width;
    cocoa_ctx->height = args->height;

    if (!vulkan_surface_create(&cocoa_ctx->vk,
                               VULKAN_WSI_MVK_IOS,
                               NULL,
                               (BRIDGE void *)((MetalLayerView*)g_view).metalLayer,  // Pass CAMetalLayer*
                               cocoa_ctx->width,
                               cocoa_ctx->height,
                               cocoa_ctx->swap_interval))
    {
        RARCH_ERR("[Vulkan] Failed to create surface.\n");
        args->ok = false;
        return;
    }
    
    args->ok = true;
}
```

**Threading Model (Lines 84-92):**
```objc
/* MoltenVK internally marshals some CAMetalLayer work to the GCD main queue via
 * dispatch_sync when called off the main thread; with threaded video
 * the worker calling into MoltenVK while the main thread is blocked in
 * the thread wrapper's command wait would deadlock, because that wait
 * only pumps the private trampoline runloop mode, which does NOT drain
 * the GCD main queue. Running on the main thread short-circuits
 * MoltenVK's internal dispatch (it checks for the main thread and
 * calls straight through). */
```

---

## Azahar Native App Current Implementation

### 1. Instance Creation (src/video_core/renderer_vulkan/vk_platform.cpp:301-438)

**Extensions Requested:**
```cpp
std::vector<const char*> enabled_extensions;
enabled_extensions.push_back(VK_KHR_SURFACE_EXTENSION_NAME);

#if defined(__APPLE__)
    enabled_extensions.push_back(VK_EXT_METAL_SURFACE_EXTENSION_NAME);
    enabled_extensions.push_back(VK_KHR_PORTABILITY_ENUMERATION_EXTENSION_NAME);
    
    instance_info.flags = VK_INSTANCE_CREATE_ENUMERATE_PORTABILITY_BIT_KHR;
#endif
```

**Potential Issues:**
1. May request additional extensions through `available_extensions` check
2. Validation layers may be enabled in debug builds
3. More complex extension discovery logic compared to RetroArch's minimal approach

### 2. CAMetalLayer Setup (src/ios/AzaharApp/Views/GameView.swift)

**Current Implementation:**
```swift
#if VULKAN
class GameMetalView: UIView {
    override class var layerClass: AnyClass {
        return CAMetalLayer.self
    }
    
    var metalLayer: CAMetalLayer {
        return layer as! CAMetalLayer
    }
}
#endif
```

**Issue**: Missing MoltenVK-specific initialization:
- No MTLDevice assignment to layer
- No contentsScale for Retina support
- No opaque flag set

---

## Key Differences: RetroArch vs Azahar

| Aspect | RetroArch iOS | Azahar Native App | Impact |
|--------|---------------|-------------------|--------|
| **Extension Strategy** | Minimal required + optional discovery | All available extensions | iOS may not support all extensions |
| **Portability Flag** | Conditional on extension presence | Unconditional on Apple platforms | May fail if extension unavailable |
| **CAMetalLayer Init** | Full setup (device, scale, opaque) | Minimal setup | MoltenVK may not work correctly |
| **Threading** | All Vulkan ops on main thread | Not specified | iOS UIKit/GCD deadlock risk |
| **Error Handling** | Graceful fallback for extensions | Hard fails on missing extensions | No recovery path |
| **API Version** | Checks supported version vs requested | May request unsupported version | iOS supports limited Vulkan versions |

---

## Recommendations for Azahar Native App

### Priority 1: Fix CAMetalLayer Initialization

**File**: `src/ios/AzaharApp/Views/GameView.swift`

Add proper MoltenVK initialization:
```swift
#if VULKAN
class GameMetalView: UIView {
    override class var layerClass: AnyClass {
        return CAMetalLayer.self
    }
    
    var metalLayer: CAMetalLayer {
        return layer as! CAMetalLayer
    }
    
    private func setupMetalLayer() {
        guard let device = MTLCreateSystemDefaultDevice() else {
            print("Failed to create Metal device")
            return
        }
        
        metalLayer.device = device
        metalLayer.contentsScale = UIScreen.main.nativeScale  // Retina support
        metalLayer.opaque = true
        metalLayer.framebufferOnly = false  // Allow readback if needed
    }
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupMetalLayer()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupMetalLayer()
    }
}
#endif
```

### Priority 2: Simplify Extension Discovery

**File**: `src/video_core/renderer_vulkan/vk_platform.cpp`

Use RetroArch's minimal approach:
```cpp
#if defined(__APPLE__)
    // Required extensions
    std::vector<const char*> required_extensions = {
        VK_KHR_SURFACE_EXTENSION_NAME,
        VK_EXT_METAL_SURFACE_EXTENSION_NAME
    };
    
    // Optional extensions - only enable if available
    std::vector<const char*> optional_extensions = {
        VK_KHR_PORTABILITY_ENUMERATION_EXTENSION_NAME
    };
    
    // Check which optional extensions are available
    uint32_t available_count = 0;
    vkEnumerateInstanceExtensionProperties(nullptr, &available_count, nullptr);
    std::vector<VkExtensionProperties> available(available_count);
    vkEnumerateInstanceExtensionProperties(nullptr, &available_count, available.data());
    
    std::vector<const char*> enabled_extensions = required_extensions;
    bool portability_enabled = false;
    
    for (const auto& opt_ext : optional_extensions) {
        for (const auto& avail_ext : available) {
            if (strcmp(opt_ext, avail_ext.extensionName) == 0) {
                enabled_extensions.push_back(opt_ext);
                if (strcmp(opt_ext, VK_KHR_PORTABILITY_ENUMERATION_EXTENSION_NAME) == 0) {
                    portability_enabled = true;
                }
                break;
            }
        }
    }
    
    // Only set portability flag if extension is actually enabled
    if (portability_enabled) {
        instance_info.flags |= VK_INSTANCE_CREATE_ENUMERATE_PORTABILITY_BIT_KHR;
    }
#endif
```

### Priority 3: Main Thread Enforcement

**File**: `src/ios/AzaharBridge/ios_bridge.mm`

Ensure all Vulkan calls happen on main thread:
```objc
// Add dispatch_async wrapper for Vulkan initialization
- (BOOL)initializeVulkan {
    __block BOOL success = NO;
    
    if ([NSThread isMainThread]) {
        success = [self initializeVulkanInternal];
    } else {
        dispatch_sync(dispatch_get_main_queue(), ^{
            success = [self initializeVulkanInternal];
        });
    }
    
    return success;
}

- (BOOL)initializeVulkanInternal {
    // Actual Vulkan initialization here
    // Called from C++ via bridge
}
```

**C++ Bridge Call**:
```cpp
// In VideoCore initialization
bool InitializeRenderer() {
#if defined(CITRA_IOS)
    // Ensure main thread execution
    return IOSBridge::InitializeVulkan();  // Dispatches to main thread internally
#else
    return Vulkan::CreateInstance(...);
#endif
}
```

### Priority 4: Validate Instance Version

**File**: `src/video_core/renderer_vulkan/vk_platform.cpp`

Add version check like RetroArch:
```cpp
uint32_t supported_instance_version = VK_API_VERSION_1_0;
if (vkEnumerateInstanceVersion) {
    if (vkEnumerateInstanceVersion(&supported_instance_version) != VK_SUCCESS) {
        supported_instance_version = VK_API_VERSION_1_0;
    }
}

// Don't request higher than supported
uint32_t requested_version = VK_API_VERSION_1_1;  // Or whatever Azahar needs
if (supported_instance_version < requested_version) {
    LOG_WARNING(Render_Vulkan, 
                "Requested Vulkan {}.{} but only {}.{} is supported, using supported version",
                VK_VERSION_MAJOR(requested_version), VK_VERSION_MINOR(requested_version),
                VK_VERSION_MAJOR(supported_instance_version), VK_VERSION_MINOR(supported_instance_version));
    requested_version = supported_instance_version;
}

application_info.apiVersion = requested_version;
```

### Priority 5: Graceful Extension Fallback

**File**: `src/video_core/renderer_vulkan/vk_platform.cpp`

Don't abort on missing optional extensions:
```cpp
// Separate required vs optional
std::vector<const char*> required_extensions = {
    VK_KHR_SURFACE_EXTENSION_NAME,
    VK_EXT_METAL_SURFACE_EXTENSION_NAME
};

std::vector<const char*> optional_extensions = {
    VK_KHR_PORTABILITY_ENUMERATION_EXTENSION_NAME,
    // Add other optional extensions here
};

// Validate required extensions
for (const auto& req_ext : required_extensions) {
    bool found = false;
    for (const auto& avail_ext : available_extensions) {
        if (strcmp(req_ext, avail_ext.extensionName) == 0) {
            found = true;
            break;
        }
    }
    if (!found) {
        LOG_CRITICAL(Render_Vulkan, "Required extension {} not available", req_ext);
        return nullptr;  // Fatal error
    }
}

// Enable optional extensions if available (no error if missing)
for (const auto& opt_ext : optional_extensions) {
    for (const auto& avail_ext : available_extensions) {
        if (strcmp(opt_ext, avail_ext.extensionName) == 0) {
            LOG_INFO(Render_Vulkan, "Enabling optional extension: {}", opt_ext);
            enabled_extensions.push_back(opt_ext);
            break;
        }
    }
}
```

---

## Testing Recommendations

1. **Add detailed logging** at each step (already done in current code):
   - Library loading success
   - vkGetInstanceProcAddr resolution
   - Available extensions list
   - Enabled extensions list
   - Instance creation flags
   - Exact VkResult error code

2. **Test with minimal configuration first**:
   - Only required extensions (VK_KHR_surface + VK_EXT_metal_surface)
   - No validation layers
   - Vulkan 1.0 API version
   - No optional features

3. **Progressively add features**:
   - Add portability enumeration if available
   - Try Vulkan 1.1 features
   - Enable validation layers in debug

4. **Compare behavior**:
   - Check what extensions RetroArch actually enables on the device
   - Compare API version requested
   - Compare instance creation flags

---

## Additional Notes

### MoltenVK Version Differences

- RetroArch uses MoltenVK v1.4.2 (per `CMakeModules/DownloadExternals.cmake:193`)
- Azahar uses MoltenVK v1.4.2 (updated recently)
- Versions match, so not a version compatibility issue

### iOS Vulkan Limitations

iOS through MoltenVK has several limitations compared to desktop:
- Limited Vulkan 1.1+ feature support
- Metal backend constraints
- Different memory management model
- Different threading requirements (main thread affinity)

### Why LibRetro Core Works

The libretro core works because:
1. RetroArch creates and owns the Vulkan instance
2. RetroArch handles all iOS-specific quirks
3. The core just receives a pre-configured context
4. RetroArch's iOS-tested initialization path is used

From `src/citra_libretro/libretro_vk.cpp:252-259`:
```cpp
vk::UniqueInstance CreateInstance([[maybe_unused]] const Common::DynamicLibrary& library,
                                  [[maybe_unused]] Frontend::WindowSystemType window_type,
                                  [[maybe_unused]] bool enable_validation,
                                  [[maybe_unused]] bool dump_command_buffers) {
    // LibRetro manages the VkInstance - we don't create one
    LOG_WARNING(Render_Vulkan, "CreateInstance called in LibRetro mode - this should not happen");
    return nullptr;
}
```

---

## Summary

The native Azahar iOS app needs to adopt RetroArch's proven iOS Vulkan initialization strategy:

1. ✅ **Minimal extension set** - Only request what iOS MoltenVK actually supports
2. ✅ **Proper CAMetalLayer setup** - Initialize MTLDevice, contentsScale, and opaque flag
3. ✅ **Main thread execution** - All Vulkan/MoltenVK calls must be on main thread
4. ✅ **Graceful fallback** - Don't abort on optional extension availability
5. ✅ **Version validation** - Don't request unsupported Vulkan API versions

These changes should be implemented in priority order, with extensive logging to identify the exact failure point.
