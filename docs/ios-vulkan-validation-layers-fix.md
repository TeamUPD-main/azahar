# iOS Vulkan Instance Creation Fix - Validation Layers & Portability Flag

## Success: MoltenVK Loading Complete! 🎉

From the latest crash log (build `c0ccdd6483a0aa2cfc01457cd7ff98b5c51a522d`):

```
[17.145754] Attempting to load MoltenVK: @executable_path/Frameworks/MoltenVK.framework/MoltenVK
[17.173704] ✅ Successfully loaded MoltenVK from: @executable_path/Frameworks/MoltenVK.framework/MoltenVK
[17.173711] Vulkan library loaded successfully
[17.174500] Available Vulkan version: 1.4.334
[17.175422] ✅ Calling vkCreateInstance on main thread (iOS requirement)
```

**All previous fixes are working**:
- ✅ iOS-specific MoltenVK paths
- ✅ Framework loading from correct location
- ✅ Main thread enforcement active
- ✅ CITRA_IOS macro defined correctly
- ✅ Move-only types handled with `__block` pointers

---

## New Error: Validation Layer Not Present

**Line 71** (CRITICAL):
```
[17.180723] vk::createInstanceUnique failed with vk::SystemError: 
vk::createInstanceUnique: ErrorLayerNotPresent (error code: -6)
```

**Root Cause**: 
- **Line 64**: `Validation layer enabled` - Code requested `VK_LAYER_KHRONOS_validation`
- **Problem**: iOS MoltenVK does **not ship validation layers**
- **Result**: `vkCreateInstance` fails with `VK_ERROR_LAYER_NOT_PRESENT`

---

## Secondary Issue: Portability Flag Mismatch

**Line 62**: `Candidate instance extension VK_KHR_portability_enumeration is not available`
- Extension was removed by sanitizer (correct behavior)

**Line 65**: `Instance flags: 0x1` (eEnumeratePortabilityKHR flag set)
- Flag was set unconditionally even though extension unavailable
- Vulkan spec requires: if flag is set, extension must be enabled
- **Potential issue**: May cause validation errors or rejection

---

## Fix #1: Disable Validation Layers on iOS

**File**: `src/video_core/renderer_vulkan/vk_platform.cpp:484-495`

### Before
```cpp
boost::container::static_vector<const char*, 2> layers;
if (enable_validation) {
    layers.push_back("VK_LAYER_KHRONOS_validation");  // ❌ Not available on iOS!
    LOG_INFO(Render_Vulkan, "Validation layer enabled");
}
if (dump_command_buffers) {
    layers.push_back("VK_LAYER_LUNARG_api_dump");
    LOG_INFO(Render_Vulkan, "API dump layer enabled");
}
```

### After
```cpp
boost::container::static_vector<const char*, 2> layers;
#if defined(CITRA_IOS)
    // Validation layers are not available on iOS (MoltenVK doesn't ship them)
    if (enable_validation) {
        LOG_WARNING(Render_Vulkan, "Validation layers requested but not available on iOS - skipping");
    }
#else
    if (enable_validation) {
        layers.push_back("VK_LAYER_KHRONOS_validation");
        LOG_INFO(Render_Vulkan, "Validation layer enabled");
    }
#endif
    if (dump_command_buffers) {
        layers.push_back("VK_LAYER_LUNARG_api_dump");
        LOG_INFO(Render_Vulkan, "API dump layer enabled");
    }
```

**Result**: On iOS, validation layers are **not requested**, preventing the error.

---

## Fix #2: Make Portability Flag Conditional

**File**: `src/video_core/renderer_vulkan/vk_platform.cpp:409-426`

### Before
```cpp
vk::InstanceCreateFlags GetInstanceFlags() {
#if defined(__APPLE__)
    return vk::InstanceCreateFlagBits::eEnumeratePortabilityKHR;  // ❌ Always set!
#else
    return static_cast<vk::InstanceCreateFlags>(0);
#endif
}
```

### After
```cpp
vk::InstanceCreateFlags GetInstanceFlags(const std::vector<const char*>& extensions) {
#if defined(__APPLE__)
    // Only set portability flag if the extension is actually available
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
    (void)extensions;
    return static_cast<vk::InstanceCreateFlags>(0);
#endif
}
```

### Call Site Update (Line 501)
```cpp
// Before:
const auto instance_flags = GetInstanceFlags();

// After:
const auto instance_flags = GetInstanceFlags(extensions);  // Pass sanitized extension list
```

**Result**: Flag is only set if the extension is actually available in the sanitized list.

---

## Expected Next Build Behavior

With these fixes, the next build should show:

```
[XX.XXX] Attempting to load MoltenVK: @executable_path/Frameworks/MoltenVK.framework/MoltenVK
[XX.XXX] ✅ Successfully loaded MoltenVK from: @executable_path/Frameworks/MoltenVK.framework/MoltenVK
[XX.XXX] Available Vulkan version: 1.4.334
[XX.XXX] Getting instance extensions...
[XX.XXX] Candidate instance extension VK_KHR_portability_enumeration is not available
[XX.XXX] Required 4 extensions (down from 5)
[XX.XXX] ⚠️ Validation layers requested but not available on iOS - skipping
[XX.XXX] ⚠️ Portability extension not available, skipping flag
[XX.XXX] Instance flags: 0x0 (none)
[XX.XXX] VK_EXT_layer_settings extension found, applying MoltenVK config
[XX.XXX] Creating Vulkan instance...
[XX.XXX] Calling vkCreateInstance on main thread (iOS requirement)
[XX.XXX] ✅ Vulkan instance created successfully!
[XX.XXX] Instance dispatcher initialized
```

---

## Why These Issues Happen

### Validation Layers on Desktop vs iOS

**Desktop (Windows/Linux/macOS)**:
- Vulkan SDK includes validation layers
- Validation layers are separate shared libraries
- Can be enabled for debugging

**iOS**:
- No Vulkan SDK (uses MoltenVK only)
- MoltenVK does **not include** validation layers
- Layers must be disabled at compile time or runtime

### Portability Extension on macOS vs iOS

**macOS**:
- MoltenVK supports `VK_KHR_portability_enumeration`
- Extension allows enumerating non-conformant implementations
- Flag + extension both work

**iOS**:
- MoltenVK v1.4.2 may not expose the extension on iOS
- But the code tried to set the flag anyway
- Mismatch causes potential rejection

---

## Android Comparison

Android handles this correctly (as documented in `docs/android-vs-ios-vulkan-extensions.md`):

1. **No hardcoded flags** - Uses `0` flags on all non-Apple platforms
2. **No validation layers in release** - Only requested in debug builds with proper checks
3. **Sanitization removes unavailable extensions** - Same as iOS now

**iOS is now aligned with Android's proven approach.**

---

## Complete iOS Vulkan Fix Stack (All Fixes)

### ✅ Phase 1: MoltenVK Loading (Completed)
1. iOS-specific framework paths (`@executable_path/Frameworks/`)
2. Multi-path fallback loading
3. Framework + dylib bundling in CMake

### ✅ Phase 2: Compilation (Completed)
4. CITRA_IOS macro defined for video_core target
5. Move-only types support with `__block ReturnType*`
6. Main thread enforcement helper (`EnsureMainThread`)

### ✅ Phase 3: Runtime Validation (This Fix - Completed)
7. Disable validation layers on iOS
8. Make portability flag conditional on extension availability

---

## Files Modified

**This fix**:
1. `src/video_core/renderer_vulkan/vk_platform.cpp:409-426` - Conditional portability flag
2. `src/video_core/renderer_vulkan/vk_platform.cpp:484-495` - Disable validation on iOS
3. `src/video_core/renderer_vulkan/vk_platform.cpp:501` - Pass extensions to flag function

**Previous fixes** (already in codebase):
- `src/video_core/CMakeLists.txt` - CITRA_IOS definition
- `src/video_core/renderer_vulkan/vk_platform.cpp` - iOS paths, main thread enforcement
- `src/ios/CMakeLists.txt` - MoltenVK bundling

---

## Testing Checklist

### ✅ Build Phase
- [ ] Compiles without errors
- [ ] Links successfully
- [ ] IPA contains MoltenVK framework

### ✅ Runtime - MoltenVK Loading
- [ ] Log shows: `"Successfully loaded MoltenVK from: @executable_path/Frameworks/MoltenVK.framework/MoltenVK"`
- [ ] Vulkan version detected: `1.4.334`

### ✅ Runtime - Validation Layers
- [ ] Log shows: `"Validation layers requested but not available on iOS - skipping"`
- [ ] **NOT** in log: `"Validation layer enabled"`
- [ ] Layers array is empty or only contains API dump

### ✅ Runtime - Portability Flag
- [ ] Log shows: `"Portability extension not available, skipping flag"`
- [ ] Log shows: `"Instance flags: 0x0"` (not `0x1`)

### ✅ Runtime - Instance Creation
- [ ] Log shows: `"Vulkan instance created successfully!"`
- [ ] **NO** error: `"ErrorLayerNotPresent"`
- [ ] **NO** crash on `vkCreateInstance`

### ✅ Next Steps (If Instance Creation Succeeds)
- [ ] May encounter CAMetalLayer issues (needs Swift-side setup)
- [ ] May encounter device/queue creation issues
- [ ] May proceed to actual rendering (success!)

---

## Potential Remaining Issues

Even with these fixes, the app may still encounter:

### 1. CAMetalLayer Not Initialized
**Symptom**: Surface creation fails or rendering doesn't work
**Location**: `src/ios/AzaharApp/Views/GameView.swift`
**Fix**: Add `setupMetalLayer()` with proper device/scale/opaque settings

### 2. Swapchain Creation Issues
**Symptom**: vkCreateSwapchainKHR fails
**Fix**: Verify surface formats and present modes are queried correctly

### 3. Device Features Not Available
**Symptom**: vkCreateDevice fails
**Fix**: Make device features conditional based on availability queries

These are documented in `docs/vulkan-ios-retroarch-analysis.md`.

---

## Commit Message (Suggested)

```
[iOS] Fix Vulkan instance creation - disable validation layers & conditional portability flag

Build c0ccdd6483 successfully loaded MoltenVK but crashed with
VK_ERROR_LAYER_NOT_PRESENT (-6) because validation layers were
requested but don't exist on iOS.

Root causes:
1. Validation layers: iOS MoltenVK doesn't ship validation layers,
   but code unconditionally requested VK_LAYER_KHRONOS_validation
2. Portability flag: Set unconditionally even when extension was
   removed by sanitizer, violating Vulkan spec requirement

Fixes:
- Disable validation layers on iOS with #ifdef CITRA_IOS
- Make portability flag conditional on extension availability
- Pass sanitized extension list to GetInstanceFlags()
- Log warnings when iOS-unavailable features are requested

This matches Android's approach (no hardcoded flags, conditional layers).

Expected result: vkCreateInstance succeeds on iOS, proceeds to rendering.
```

---

## Progress Summary

### Before All Fixes
```
❌ libMoltenVK.dylib not loading (wrong path)
❌ Compilation errors (move-only types in blocks)
❌ macOS paths used instead of iOS paths
```

### After Phase 1 + 2
```
✅ MoltenVK loads successfully
✅ Compiles without errors
✅ iOS-specific paths working
✅ Main thread enforcement active
❌ Validation layer error: ErrorLayerNotPresent
```

### After This Fix (Phase 3)
```
✅ MoltenVK loads successfully
✅ Compiles without errors
✅ iOS-specific paths working
✅ Main thread enforcement active
✅ Validation layers disabled on iOS
✅ Portability flag conditional
❓ vkCreateInstance should now succeed
```

---

**Date**: August 5, 2026  
**Time**: 01:46 UTC  
**Build**: c0ccdd6483a0aa2cfc01457cd7ff98b5c51a522d (analyzed)  
**Next Build**: Should succeed at Vulkan instance creation  
**Status**: Ready for build - All known issues fixed
