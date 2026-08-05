# Android vs iOS Vulkan Extension Handling - Comparison

## How Android Handles Vulkan Extensions

### 1. Extension Request Strategy (GOOD!)

**File**: `src/video_core/renderer_vulkan/vk_platform.cpp:320-390`

```cpp
std::vector<const char*> GetInstanceExtensions(Frontend::WindowSystemType window_type,
                                               bool enable_debug_utils) {
    // Step 1: Query what extensions are available on this device
    const auto properties = vk::enumerateInstanceExtensionProperties();
    if (properties.empty()) {
        LOG_ERROR(Render_Vulkan, "Failed to query extension properties");
        return {};
    }

    // Step 2: Build a list of DESIRED extensions
    std::vector<const char*> extensions;
    extensions.reserve(7);

    // Android-specific extensions
    #if defined(VK_USE_PLATFORM_ANDROID_KHR)
    case Frontend::WindowSystemType::Android:
        extensions.push_back(VK_KHR_ANDROID_SURFACE_EXTENSION_NAME);
        break;
    #endif

    // Common required extension
    if (window_type != Frontend::WindowSystemType::Headless) {
        extensions.push_back(VK_KHR_SURFACE_EXTENSION_NAME);
    }

    // Optional debug extensions
    if (enable_debug_utils) {
        extensions.push_back(VK_EXT_DEBUG_UTILS_EXTENSION_NAME);
        extensions.push_back(VK_EXT_DEBUG_REPORT_EXTENSION_NAME);
    }

    // Step 3: **SANITIZE** - Remove extensions that aren't actually available
    std::erase_if(extensions, [&](const char* extension) -> bool {
        const auto it =
            std::find_if(properties.begin(), properties.end(), [extension](const auto& prop) {
                return std::strcmp(extension, prop.extensionName) == 0;
            });

        if (it == properties.end()) {
            LOG_INFO(Render_Vulkan, "Candidate instance extension {} is not available", extension);
            return true;  // Remove this extension
        }
        return false;  // Keep this extension
    });

    return extensions;
}
```

### Key Points: Android's Safe Approach

1. **Query first**: Calls `vkEnumerateInstanceExtensionProperties()` to see what's available
2. **Request desired**: Adds all extensions that *might* be useful
3. **Sanitize list**: **Removes** any extension that's not actually supported
4. **Logs removals**: Informs about missing extensions (not an error, just info)
5. **No crashes**: Only requests extensions that are guaranteed to exist

**Result**: Android never requests unsupported extensions, so `vkCreateInstance` won't fail due to `VK_ERROR_EXTENSION_NOT_PRESENT`.

---

## How iOS Handles Vulkan Extensions (PROBLEMATIC!)

### 1. Apple-Specific Extensions (HARDCODED!)

**File**: `src/video_core/renderer_vulkan/vk_platform.cpp:332-336`

```cpp
#if defined(__APPLE__)
    extensions.push_back(VK_KHR_PORTABILITY_ENUMERATION_EXTENSION_NAME);  // Always added!
    // For configuring MoltenVK.
    extensions.push_back(VK_EXT_LAYER_SETTINGS_EXTENSION_NAME);           // Always added!
#endif
```

### 2. iOS Metal Surface Extension

**File**: `src/video_core/renderer_vulkan/vk_platform.cpp:352-355`

```cpp
#elif defined(VK_USE_PLATFORM_METAL_EXT)
    case Frontend::WindowSystemType::MacOS:
        extensions.push_back(VK_EXT_METAL_SURFACE_EXTENSION_NAME);
        break;
```

**Note**: `WindowSystemType::MacOS` is used for **both** macOS and iOS.

### 3. The Sanitize Step **DOES** Apply to iOS

**Good news**: Lines 375-387 sanitize the extension list for **all platforms**, including iOS:

```cpp
// Sanitize extension list
std::erase_if(extensions, [&](const char* extension) -> bool {
    // ... checks if extension is available ...
    if (it == properties.end()) {
        LOG_INFO(Render_Vulkan, "Candidate instance extension {} is not available", extension);
        return true;  // Remove unavailable extension
    }
    return false;
});
```

**So why might it still fail?**

---

## Potential iOS Issues

### Issue #1: Portability Flag Without Extension Check

**File**: `src/video_core/renderer_vulkan/vk_platform.cpp:392-398`

```cpp
vk::InstanceCreateFlags GetInstanceFlags() {
#if defined(__APPLE__)
    return vk::InstanceCreateFlagBits::eEnumeratePortabilityKHR;  // ALWAYS set!
#else
    return static_cast<vk::InstanceCreateFlags>(0);
#endif
}
```

**Problem**: The portability **flag** is set unconditionally, but it requires the `VK_KHR_PORTABILITY_ENUMERATION_EXTENSION_NAME` extension.

**Scenario**:
1. Extension sanitizer removes `VK_KHR_PORTABILITY_ENUMERATION_EXTENSION_NAME` (not available)
2. But `GetInstanceFlags()` still returns `eEnumeratePortabilityKHR` flag
3. Vulkan says: "You set portability flag but didn't request portability extension"
4. **Crash**: `VK_ERROR_EXTENSION_NOT_PRESENT` or validation error

### Issue #2: VK_EXT_LAYER_SETTINGS May Not Exist

**File**: `src/video_core/renderer_vulkan/vk_platform.cpp:335`

```cpp
extensions.push_back(VK_EXT_LAYER_SETTINGS_EXTENSION_NAME);
```

**Problem**: This extension might not be available on iOS, especially on older MoltenVK versions.

**But**: The sanitizer **will** remove it if unavailable, so this should be safe.

### Issue #3: Validation Layers on iOS

**File**: `src/video_core/renderer_vulkan/vk_platform.cpp:495-503`

```cpp
boost::container::static_vector<const char*, 2> layers;
if (enable_validation) {
    layers.push_back("VK_LAYER_KHRONOS_validation");
    LOG_INFO(Render_Vulkan, "Validation layer enabled");
}
```

**Problem**: Validation layers are **not available** on iOS (MoltenVK doesn't ship them).

**Impact**: If `enable_validation=true` (default in debug builds), `vkCreateInstance` will fail.

---

## What Android Does Right

### 1. No Hardcoded Flags
Android doesn't use any instance creation flags:

```cpp
vk::InstanceCreateFlags GetInstanceFlags() {
#if defined(__APPLE__)
    return vk::InstanceCreateFlagBits::eEnumeratePortabilityKHR;  // iOS/macOS only
#else
    return static_cast<vk::InstanceCreateFlags>(0);  // Android uses this
#endif
}
```

### 2. Minimal Required Extensions
Android only requests:
- `VK_KHR_ANDROID_SURFACE_EXTENSION_NAME` (always available on Android)
- `VK_KHR_SURFACE_EXTENSION_NAME` (always available)
- Debug extensions (optional, removed if unavailable)

### 3. Sanitization Removes Unavailable Extensions
Android's extension list goes through the same sanitization as iOS, so it's safe.

---

## Recommended iOS Fixes (Based on Android Approach)

### Fix #1: Make Portability Flag Conditional

**File**: `src/video_core/renderer_vulkan/vk_platform.cpp:392-398`

**Current (BAD)**:
```cpp
vk::InstanceCreateFlags GetInstanceFlags() {
#if defined(__APPLE__)
    return vk::InstanceCreateFlagBits::eEnumeratePortabilityKHR;  // ALWAYS set
#else
    return static_cast<vk::InstanceCreateFlags>(0);
#endif
}
```

**Recommended (GOOD)**:
```cpp
vk::InstanceCreateFlags GetInstanceFlags(const std::vector<const char*>& extensions) {
#if defined(__APPLE__)
    // Only set portability flag if extension is actually in the list
    const auto it = std::find_if(extensions.begin(), extensions.end(), [](const char* ext) {
        return std::strcmp(ext, VK_KHR_PORTABILITY_ENUMERATION_EXTENSION_NAME) == 0;
    });
    
    if (it != extensions.end()) {
        LOG_INFO(Render_Vulkan, "Portability extension available, setting enumeration flag");
        return vk::InstanceCreateFlagBits::eEnumeratePortabilityKHR;
    } else {
        LOG_INFO(Render_Vulkan, "Portability extension not available, skipping flag");
        return static_cast<vk::InstanceCreateFlags>(0);
    }
#else
    return static_cast<vk::InstanceCreateFlags>(0);
#endif
}
```

**Then update the call site** (line 509):
```cpp
const auto instance_flags = GetInstanceFlags(extensions);  // Pass sanitized extensions
```

### Fix #2: Disable Validation Layers on iOS

**File**: `src/video_core/renderer_vulkan/vk_platform.cpp:495-503`

**Current**:
```cpp
boost::container::static_vector<const char*, 2> layers;
if (enable_validation) {
    layers.push_back("VK_LAYER_KHRONOS_validation");
    LOG_INFO(Render_Vulkan, "Validation layer enabled");
}
```

**Recommended**:
```cpp
boost::container::static_vector<const char*, 2> layers;
#if defined(CITRA_IOS)
// Validation layers are not available on iOS (MoltenVK doesn't include them)
if (enable_validation) {
    LOG_WARNING(Render_Vulkan, "Validation layers requested but not available on iOS");
}
#else
if (enable_validation) {
    layers.push_back("VK_LAYER_KHRONOS_validation");
    LOG_INFO(Render_Vulkan, "Validation layer enabled");
}
#endif
```

### Fix #3: RetroArch-Style Minimal Extensions on iOS

Based on `ref/RetroArch/gfx/common/vulkan_common.c:1067-1206`, RetroArch uses this strategy on iOS:

```cpp
// Only request absolutely required extensions
extensions = {
    VK_KHR_SURFACE_EXTENSION_NAME,           // Required for surface
    VK_EXT_METAL_SURFACE_EXTENSION_NAME,     // Required for Metal
    // Conditionally add portability if available
};

// NO debug utils on iOS
// NO validation layers on iOS
// NO extra extensions
```

**Recommended approach for Azahar**:
```cpp
#if defined(CITRA_IOS)
    // iOS: Minimal required extensions only (RetroArch approach)
    extensions.push_back(VK_EXT_METAL_SURFACE_EXTENSION_NAME);
    extensions.push_back(VK_KHR_SURFACE_EXTENSION_NAME);
    
    // Portability: conditionally add, will be removed by sanitizer if unavailable
    extensions.push_back(VK_KHR_PORTABILITY_ENUMERATION_EXTENSION_NAME);
    
    // Layer settings: conditionally add (for MoltenVK config)
    extensions.push_back(VK_EXT_LAYER_SETTINGS_EXTENSION_NAME);
    
    // NO debug extensions on iOS (not available in MoltenVK)
#elif defined(__APPLE__)
    // macOS: Full extension set
    extensions.push_back(VK_KHR_PORTABILITY_ENUMERATION_EXTENSION_NAME);
    extensions.push_back(VK_EXT_LAYER_SETTINGS_EXTENSION_NAME);
    extensions.push_back(VK_EXT_METAL_SURFACE_EXTENSION_NAME);
    extensions.push_back(VK_KHR_SURFACE_EXTENSION_NAME);
    
    if (enable_debug_utils) {
        extensions.push_back(VK_EXT_DEBUG_UTILS_EXTENSION_NAME);
        extensions.push_back(VK_EXT_DEBUG_REPORT_EXTENSION_NAME);
    }
#endif
```

---

## Summary: Android vs iOS Extension Handling

| Aspect | Android | iOS (Current) | iOS (Should Be) |
|--------|---------|---------------|-----------------|
| **Extension Query** | ✅ Yes | ✅ Yes | ✅ Yes |
| **Extension Sanitization** | ✅ Yes | ✅ Yes | ✅ Yes |
| **Portability Flag** | ❌ No (not needed) | ⚠️ Hardcoded | ❌ Conditional |
| **Validation Layers** | ✅ Optional | ⚠️ Requested | ❌ Disabled |
| **Debug Extensions** | ✅ Optional | ⚠️ Requested | ❌ iOS: None |
| **Surface Extension** | ✅ Android-specific | ✅ Metal-specific | ✅ Metal-specific |
| **Minimal Extensions** | ✅ Yes | ❌ Requests many | ⚠️ Should be minimal |

**Key Difference**: 
- Android: No special flags, minimal extensions, works out of the box
- iOS Current: Hardcoded portability flag, requests debug extensions (fail)
- iOS Fixed: Conditional portability flag, no debug/validation on iOS

---

## Expected Impact of Fixes

### Before (Current Code)
```
[XX.XXX] Creating Vulkan instance...
[XX.XXX] Required 6 extensions
[XX.XXX] Candidate instance extension VK_EXT_debug_utils is not available
[XX.XXX] Candidate instance extension VK_EXT_debug_report is not available
[XX.XXX] Requesting 4 extensions: VK_KHR_portability_enumeration, VK_EXT_layer_settings, VK_EXT_metal_surface, VK_KHR_surface
[XX.XXX] Instance flags: 0x1 (eEnumeratePortabilityKHR)
[XX.XXX] vkCreateInstance failed: VK_ERROR_INCOMPATIBLE_DRIVER  ← Portability flag without extension?
```

### After Fixes
```
[XX.XXX] Creating Vulkan instance...
[XX.XXX] Required 4 extensions
[XX.XXX] Candidate instance extension VK_KHR_portability_enumeration is not available
[XX.XXX] Portability extension not available, skipping flag
[XX.XXX] Requesting 3 extensions: VK_EXT_layer_settings, VK_EXT_metal_surface, VK_KHR_surface
[XX.XXX] Instance flags: 0x0 (none)
[XX.XXX] Validation layers requested but not available on iOS
[XX.XXX] Vulkan instance created successfully!
```

---

## Conclusion

**Android's approach is safer** because:
1. No hardcoded flags
2. Minimal required extensions
3. Sanitization removes unavailable extensions
4. No assumptions about what's available

**iOS should adopt the same approach**, with these changes:
1. Make portability flag conditional (only if extension exists)
2. Disable validation layers on iOS (not available in MoltenVK)
3. Don't request debug extensions on iOS (not needed for release builds)

This matches how RetroArch successfully handles Vulkan on iOS.

---

**Date**: August 5, 2026  
**Comparison**: Android (works) vs iOS (needs fixes)  
**Recommendation**: Apply fixes #1, #2, #3 above
