# iOS Build Fix: CITRA_IOS Macro Not Defined for video_core - August 5, 2026

## Critical Bug: Wrong MoltenVK Paths Used on iOS

### The Problem

After implementing iOS-specific MoltenVK paths in `vk_platform.cpp`, the build from commit `52cf64425` still crashed with:

```
[23.497521] Attempting to load MoltenVK: libMoltenVK.dylib
[23.497702] Attempting to load MoltenVK: @executable_path/../Frameworks/MoltenVK.framework/MoltenVK  ← macOS path!
[23.497742] Attempting to load MoltenVK: @executable_path/libMoltenVK.dylib
[23.497775] Attempting to load MoltenVK: MoltenVK
[23.497910] Failed to load MoltenVK from all attempted paths
```

**Expected iOS paths** (never tried):
```
@executable_path/Frameworks/MoltenVK.framework/MoltenVK  ← iOS path (no ..)
@executable_path/Frameworks/libMoltenVK.dylib
```

### Root Cause Analysis

The code in `vk_platform.cpp` had iOS-specific paths:

```cpp
#if defined(CITRA_IOS)
    // iOS: Try framework path first (standard iOS embedding)
    std::vector<std::string> mvk_paths = {
        "@executable_path/Frameworks/MoltenVK.framework/MoltenVK",  // Correct iOS path
        "@executable_path/Frameworks/libMoltenVK.dylib",
        "MoltenVK",
        "libMoltenVK.dylib"
    };
#else
    // macOS: Try standard dylib paths
    std::vector<std::string> mvk_paths = {
        Common::DynamicLibrary::GetLibraryName("MoltenVK"),
        "@executable_path/../Frameworks/MoltenVK.framework/MoltenVK",  // macOS path
        "@executable_path/libMoltenVK.dylib",
        "MoltenVK"
    };
#endif
```

But at runtime, the **macOS paths were used** instead of iOS paths. This means `CITRA_IOS` was **not defined** during compilation.

### Investigation

**1. Where is CITRA_IOS defined?**

`src/ios/CMakeLists.txt`:
```cmake
# Line 50: Define CITRA_IOS preprocessor macro
target_compile_definitions(azahar_ios PUBLIC CITRA_IOS)

# Line 222: Ensure CITRA_IOS is available to iOS app
target_compile_definitions(azahar_ios_app PRIVATE CITRA_IOS)
```

**2. Which target compiles vk_platform.cpp?**

`src/video_core/CMakeLists.txt`:
```cmake
# Line 3: Define video_core library
add_library(video_core STATIC EXCLUDE_FROM_ALL
    # ... many files ...

# Line 186: vk_platform.cpp is part of video_core target
    $<$<NOT:$<BOOL:${ENABLE_LIBRETRO}>>:renderer_vulkan/vk_platform.cpp>
```

**3. Does video_core get CITRA_IOS?**

❌ **NO!** The `CITRA_IOS` macro was only defined for:
- `azahar_ios` (bridge library)
- `azahar_ios_app` (app target)

But **NOT** for `video_core`, which is where `vk_platform.cpp` gets compiled.

### The Disconnect

```
Target Hierarchy:
  azahar_ios_app (CITRA_IOS ✅)
    ↓ links
  azahar_ios (CITRA_IOS ✅)
    ↓ links
  video_core (CITRA_IOS ❌)  ← PROBLEM!
    ↓ contains
  vk_platform.cpp (needs CITRA_IOS)
```

When `video_core` was compiled, `CITRA_IOS` was undefined, so the preprocessor used the `#else` branch (macOS paths).

---

## The Fix

**File**: `src/video_core/CMakeLists.txt` (after line 215)

```cmake
add_dependencies(video_core host_shaders)
target_include_directories(video_core PRIVATE ${HOST_SHADERS_INCLUDE})

create_target_directory_groups(video_core)

# Define CITRA_IOS for iOS builds so vk_platform.cpp can use iOS-specific paths
if (IOS)
    target_compile_definitions(video_core PUBLIC CITRA_IOS)
endif()

target_link_libraries(video_core PUBLIC citra_common citra_core)
```

### Why This Works

1. **`IOS` is a CMake variable** set automatically by the CMake iOS toolchain
2. **`target_compile_definitions(video_core PUBLIC CITRA_IOS)`** adds `-DCITRA_IOS` to all compilation units in `video_core`
3. **`PUBLIC`** propagates the definition to targets that link to `video_core`
4. Now when `vk_platform.cpp` is compiled, `CITRA_IOS` is defined, and the iOS paths are used

---

## Verification in CI Build Logs

### Before Fix (Build 52cf64425)

**CMake Configuration** (line 2123-2124):
```
-- MoltenVK framework will be embedded in iOS app bundle
-- MoltenVK dylib fallback will also be copied
```
✅ Framework bundling works

**Xcode Compilation** (line 17538):
```bash
swiftc -module-name Azahar ... -DCITRA_IOS ...
  -Xcc -DCITRA_IOS  # Passed to C++ via -Xcc
```
✅ Swift code gets CITRA_IOS

**Problem**: Only Swift files in `azahar_ios_app` got the definition. C++ code in `video_core` did NOT.

### After Fix (Next Build)

**Expected CMake Configuration**:
```
-- MoltenVK framework will be embedded in iOS app bundle
-- MoltenVK dylib fallback will also be copied
```

**Expected C++ Compilation**:
```bash
# When compiling vk_platform.cpp (part of video_core)
clang++ ... -DCITRA_IOS ... vk_platform.cpp.o
```

**Expected Runtime Log**:
```
[XX.XXX] Attempting to load Vulkan library: libvulkan.dylib
[XX.XXX] Failed to load libvulkan.dylib, falling back to MoltenVK
[XX.XXX] Attempting to load MoltenVK: @executable_path/Frameworks/MoltenVK.framework/MoltenVK  ← iOS path!
[XX.XXX] Successfully loaded MoltenVK from: @executable_path/Frameworks/MoltenVK.framework/MoltenVK
```

---

## Why This Bug Was Subtle

### 1. Split Build System
- **CMake** handles C++ compilation (video_core)
- **Xcode** handles Swift compilation (azahar_ios_app)
- Preprocessor macros must be coordinated between both

### 2. Target Scope
- `target_compile_definitions` only affects the **specified target**
- Linking doesn't automatically propagate preprocessor definitions (unless `PUBLIC` or `INTERFACE`)
- `azahar_ios` and `azahar_ios_app` had `CITRA_IOS`, but `video_core` didn't

### 3. Silent Failure
- No compiler error if macro is undefined
- Preprocessor silently uses `#else` branch (macOS paths)
- Only detected at **runtime** when paths fail

### 4. Platform-Specific
- Only affects iOS builds
- macOS builds work fine (uses correct `#else` branch)
- Android/Windows/Linux don't use this code path

---

## Lessons Learned

### 1. Preprocessor Macro Scope
When using platform-specific `#ifdef`, ensure the macro is defined in **all relevant targets**, not just the top-level app.

**Bad**:
```cmake
# Only defines for app target
target_compile_definitions(my_app PRIVATE MY_PLATFORM)
```

**Good**:
```cmake
# Defines for all targets that need it
if (IOS)
    target_compile_definitions(core_library PUBLIC MY_PLATFORM)
    target_compile_definitions(my_app PRIVATE MY_PLATFORM)
endif()
```

### 2. Verify Compilation Commands
Check actual compiler invocations in CI logs to ensure macros are passed:
```bash
# Should see:
clang++ -DCITRA_IOS ... vk_platform.cpp.o
```

### 3. Runtime Logging for Conditionals
When code has platform-specific branches, add logging to confirm which branch is used:
```cpp
#if defined(CITRA_IOS)
    LOG_INFO(..., "Using iOS-specific paths");  // This helps debug!
#else
    LOG_INFO(..., "Using macOS-specific paths");
#endif
```

### 4. CMake Target Dependencies
Understand the linking hierarchy:
```
app (executable)
 ↓ links
bridge (library)
 ↓ links
core (library)  ← Definitions must propagate down to here!
```

---

## Related Files Modified

### This Fix (CITRA_IOS Definition)
- `src/video_core/CMakeLists.txt:217-221` - Added CITRA_IOS for video_core

### Previous Fixes (iOS-Specific Paths)
- `src/video_core/renderer_vulkan/vk_platform.cpp:28-84` - EnsureMainThread helper
- `src/video_core/renderer_vulkan/vk_platform.cpp:170-186` - iOS-specific MoltenVK paths
- `src/video_core/renderer_vulkan/vk_platform.cpp:219-224` - Main thread enforcement for CreateSurface
- `src/video_core/renderer_vulkan/vk_platform.cpp:516-524` - Main thread enforcement for CreateInstance
- `src/ios/CMakeLists.txt:243-269` - Framework + dylib bundling

### Existing Definitions
- `src/ios/CMakeLists.txt:50` - `azahar_ios` gets CITRA_IOS
- `src/ios/CMakeLists.txt:222` - `azahar_ios_app` gets CITRA_IOS

---

## Expected Outcome

With this fix, the next build should:

1. ✅ Compile `video_core` with `-DCITRA_IOS` flag
2. ✅ Use iOS-specific paths at runtime:
   - `@executable_path/Frameworks/MoltenVK.framework/MoltenVK` (first)
   - `@executable_path/Frameworks/libMoltenVK.dylib` (fallback)
3. ✅ Successfully load MoltenVK from framework
4. ✅ Proceed to Vulkan instance creation on main thread
5. ❓ May encounter new issues (CAMetalLayer, extensions) - separate fixes

---

## Testing Checklist

### ✅ Build Phase
- [ ] CMake configuration shows: `"MoltenVK framework will be embedded"`
- [ ] CMake configuration shows: `"MoltenVK dylib fallback will also be copied"`
- [ ] C++ compilation log shows: `clang++ ... -DCITRA_IOS ... vk_platform.cpp.o`

### ✅ IPA Contents
```bash
unzip -l Azahar.ipa | grep -i moltenvk
```
Should show:
```
Frameworks/MoltenVK.framework/MoltenVK
Frameworks/libMoltenVK.dylib
```

### ✅ Runtime Logs
- [ ] Log shows: `"Attempting to load MoltenVK: @executable_path/Frameworks/MoltenVK.framework/MoltenVK"` (iOS path, not `../`)
- [ ] Log shows: `"Successfully loaded MoltenVK from: @executable_path/Frameworks/MoltenVK.framework/MoltenVK"`
- [ ] Log shows: `"Vulkan operation executing on main thread"` or `"dispatched to main thread"`
- [ ] No more: `"Failed to load MoltenVK from all attempted paths"`

### ✅ App Behavior
- [ ] App doesn't crash immediately when launching game
- [ ] Vulkan library loading succeeds
- [ ] May encounter **new** issues (that's progress!)

---

## Comparison: Build Before vs After

### Build 52cf64425 (CITRA_IOS Missing)

**Runtime Log**:
```
[23.497521] Attempting to load MoltenVK: libMoltenVK.dylib
[23.497702] Attempting to load MoltenVK: @executable_path/../Frameworks/MoltenVK.framework/MoltenVK  ← WRONG
[23.497742] Attempting to load MoltenVK: @executable_path/libMoltenVK.dylib
[23.497775] Attempting to load MoltenVK: MoltenVK
[23.497910] Failed to load MoltenVK from all attempted paths
[23.497913] Vulkan library is not loaded!
```
❌ **Result**: Crash with SIGABRT, no Vulkan

### Next Build (CITRA_IOS Defined)

**Expected Runtime Log**:
```
[XX.XXX] Attempting to load Vulkan library: libvulkan.dylib
[XX.XXX] Failed to load libvulkan.dylib, falling back to MoltenVK
[XX.XXX] Attempting to load MoltenVK: @executable_path/Frameworks/MoltenVK.framework/MoltenVK  ← CORRECT!
[XX.XXX] Successfully loaded MoltenVK from: @executable_path/Frameworks/MoltenVK.framework/MoltenVK
[XX.XXX] vkGetInstanceProcAddr resolved successfully
[XX.XXX] Vulkan library version: 1.4.2
[XX.XXX] Vulkan operation dispatched to main thread from background thread
[XX.XXX] Calling vkCreateInstance on main thread (iOS requirement)
[XX.XXX] Creating Vulkan instance...
... (continues with Vulkan initialization)
```
✅ **Result**: MoltenVK loads, Vulkan initialization proceeds

---

## Commit Message (Suggested)

```
[iOS] Fix CITRA_IOS not defined for video_core target

Critical fix: vk_platform.cpp was using macOS code paths on iOS
because CITRA_IOS preprocessor macro was not defined during
video_core compilation.

Root cause: CITRA_IOS was only defined for azahar_ios and
azahar_ios_app targets, but vk_platform.cpp is compiled as part
of video_core, which didn't have the macro.

Changes:
- Add target_compile_definitions(video_core PUBLIC CITRA_IOS)
  when IOS=ON in src/video_core/CMakeLists.txt
- Now vk_platform.cpp uses iOS-specific MoltenVK paths:
  @executable_path/Frameworks/MoltenVK.framework/MoltenVK

This completes the iOS Vulkan initialization fixes:
1. iOS-specific MoltenVK paths (vk_platform.cpp)
2. Main thread enforcement (EnsureMainThread helper)
3. Framework + dylib bundling (ios/CMakeLists.txt)
4. CITRA_IOS macro definition (this fix)

Previous build (52cf64425) still crashed because macOS paths
were used. This fix ensures iOS paths are compiled in.

Fixes: MoltenVK loading failure on iOS
```

---

**Date**: August 5, 2026  
**Time**: 00:55 UTC  
**Previous Build Hash**: 52cf64425f0cc37780804563beb589618913a39d  
**iOS Version**: iOS 27.0 Beta (24A5390f)  
**Device**: iPhone 17,3  
**Status**: Fix ready, awaiting next build
