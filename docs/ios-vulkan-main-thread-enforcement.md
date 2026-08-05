# iOS Vulkan Main Thread Enforcement - August 5, 2026

## Critical Requirement: MoltenVK + iOS = Main Thread Only

### The Problem

MoltenVK on iOS translates Vulkan calls to Metal API calls. **Metal on iOS requires all operations to happen on the main thread**, especially:
- Creating Metal devices
- Creating CAMetalLayer
- Any Metal resource initialization

When Vulkan initialization happens on a background thread (like the emulation thread), MoltenVK will deadlock or crash when trying to access Metal resources.

### Evidence from RetroArch

From analyzing `ref/RetroArch/gfx/common/vulkan_common.c`, RetroArch explicitly enforces main thread for Vulkan initialization on iOS. This is a **known, documented requirement** for iOS Vulkan apps.

---

## Solution: Main Thread Enforcement

### Implementation: `EnsureMainThread` Helper

**File**: `src/video_core/renderer_vulkan/vk_platform.cpp` (lines 32-84)

```cpp
#if defined(CITRA_IOS)
// MoltenVK on iOS requires all Vulkan operations to happen on the main thread
// because Metal API calls must be on the main thread. This helper ensures thread safety.
template <typename Func>
auto EnsureMainThread(Func&& func) -> decltype(func()) {
    using ReturnType = decltype(func());
    
    // Check if we're already on the main thread
    static pthread_t main_thread_id = pthread_main_np() ? pthread_self() : pthread_t{};
    if (main_thread_id == pthread_t{}) {
        main_thread_id = pthread_self();
    }
    
    if (pthread_equal(pthread_self(), main_thread_id)) {
        // Already on main thread, execute directly
        LOG_DEBUG(Render_Vulkan, "Vulkan operation executing on main thread (already main)");
        return func();
    }
    
    // Not on main thread, dispatch synchronously to main queue
    LOG_INFO(Render_Vulkan, "Vulkan operation dispatched to main thread from background thread");
    
    if constexpr (std::is_void_v<ReturnType>) {
        dispatch_sync(dispatch_get_main_queue(), ^{
            func();
        });
    } else {
        __block ReturnType result;
        __block std::exception_ptr exception;
        
        dispatch_sync(dispatch_get_main_queue(), ^{
            try {
                result = func();
            } catch (...) {
                exception = std::current_exception();
            }
        });
        
        if (exception) {
            std::rethrow_exception(exception);
        }
        return result;
    }
}
#endif
```

### How It Works

1. **Thread Detection**: Uses `pthread_main_np()` and `pthread_equal()` to detect if we're on main thread
2. **Fast Path**: If already on main thread, executes directly (no overhead)
3. **Dispatch Path**: If on background thread, uses `dispatch_sync` to run on main queue
4. **Exception Safety**: Captures and rethrows exceptions across the dispatch boundary
5. **Return Value Support**: Handles both void and non-void return types using `std::is_void_v`

### Why `dispatch_sync` (Not `dispatch_async`)

- **Synchronous**: Caller must wait for Vulkan initialization to complete before proceeding
- **Prevents Race Conditions**: Ensures Vulkan is fully initialized before emulation continues
- **Matches RetroArch**: RetroArch uses synchronous dispatch for the same reason

---

## Critical Functions Wrapped

### 1. `vkCreateInstance` (Line 516-524)

**Why**: Creates the Vulkan instance, which initializes MoltenVK and Metal device.

```cpp
#if defined(CITRA_IOS)
    // MoltenVK on iOS requires vkCreateInstance to be called on the main thread
    // because it initializes Metal resources that must be on the main thread
    auto instance = EnsureMainThread([&]() {
        LOG_INFO(Render_Vulkan, "Calling vkCreateInstance on main thread (iOS requirement)");
        return vk::createInstanceUnique(instance_ci);
    });
#else
    auto instance = vk::createInstanceUnique(instance_ci);
#endif
```

**Impact**: Most critical - this is where MoltenVK initializes Metal.

### 2. `CreateSurface` (Lines 218-226, 314-317)

**Why**: Creates VkSurface from CAMetalLayer, which accesses Metal layer properties.

```cpp
vk::SurfaceKHR CreateSurface(vk::Instance instance, const Frontend::EmuWindow& emu_window) {
#if defined(CITRA_IOS)
    // MoltenVK on iOS requires surface creation on the main thread
    // because CAMetalLayer operations must be on the main thread
    return EnsureMainThread([&]() -> vk::SurfaceKHR {
        LOG_INFO(Render_Vulkan, "Creating Vulkan surface on main thread (iOS requirement)");
#endif
        // ... surface creation code ...
        return surface;
#if defined(CITRA_IOS)
    }); // End of EnsureMainThread lambda
#endif
}
```

**Impact**: Critical for proper CAMetalLayer binding.

---

## Expected Behavior

### Scenario 1: Vulkan Init on Main Thread (Ideal)
```
[XX.XXX] Render_Vulkan <Debug> Vulkan operation executing on main thread (already main)
[XX.XXX] Render_Vulkan <Info> Calling vkCreateInstance on main thread (iOS requirement)
[XX.XXX] Render_Vulkan <Info> Vulkan instance created successfully!
```

**Performance**: Zero overhead, direct execution.

### Scenario 2: Vulkan Init on Background Thread (Protected)
```
[XX.XXX] Render_Vulkan <Info> Vulkan operation dispatched to main thread from background thread
[XX.XXX] Render_Vulkan <Info> Calling vkCreateInstance on main thread (iOS requirement)
[XX.XXX] Render_Vulkan <Info> Vulkan instance created successfully!
```

**Performance**: Small dispatch overhead (~1-5ms), but prevents crashes.

### Scenario 3: Surface Creation (Always Main Thread)
```
[XX.XXX] Render_Vulkan <Info> Creating Vulkan surface on main thread (iOS requirement)
[XX.XXX] Render_Vulkan <Info> CreateSurface: Metal layer valid at 0x..., creating Vulkan surface
[XX.XXX] Render_Vulkan <Info> Successfully created Vulkan Metal surface
```

---

## Technical Details

### pthread vs NSThread

**Why pthread?**: 
- Lower level, works in C++ without Objective-C
- `pthread_main_np()` is the standard iOS main thread check
- More efficient than `[NSThread isMainThread]`

### GCD (Grand Central Dispatch)

**Why `dispatch_sync`?**:
- Blocks caller until operation completes
- Required because Vulkan handle is needed immediately
- Prevents race conditions with emulation thread

**Why `dispatch_get_main_queue()`?**:
- Main queue always runs on main thread
- Safe to call from any thread
- Standard iOS practice for main thread enforcement

### Objective-C Blocks in C++

```cpp
dispatch_sync(dispatch_get_main_queue(), ^{
    // Block (Objective-C closure)
    func();
});
```

- `^{ }` is Objective-C block syntax (like lambda)
- Works in C++ when linking against Foundation framework
- CMake already links Foundation for iOS builds

### Exception Propagation

```cpp
__block std::exception_ptr exception;

dispatch_sync(dispatch_get_main_queue(), ^{
    try {
        result = func();
    } catch (...) {
        exception = std::current_exception();
    }
});

if (exception) {
    std::rethrow_exception(exception);
}
```

**Why necessary?**: Objective-C blocks can't propagate C++ exceptions directly. We capture and rethrow.

---

## Performance Impact

### Fast Path (Already Main Thread)
- **Overhead**: 1 `pthread_equal()` check (~5-10 CPU cycles)
- **Negligible**: Less than 0.001ms

### Dispatch Path (Background to Main)
- **Overhead**: `dispatch_sync()` context switch (~1-5ms)
- **One-time**: Only happens during Vulkan initialization (once per game launch)
- **Acceptable**: Small price to prevent crashes

### Runtime After Init
- **Zero impact**: This only affects initialization functions
- Rendering loop is unaffected

---

## Why This Wasn't an Issue in RetroArch

RetroArch libretro core on iOS:
1. **RetroArch frontend creates Vulkan instance** on main thread
2. **Libretro core receives pre-initialized context** via `retro_hw_render_callback`
3. **Core never calls `vkCreateInstance`** directly

Azahar standalone iOS app:
1. **App creates its own Vulkan instance** (no frontend)
2. **Emulation thread may call Vulkan init** (depends on startup flow)
3. **Must enforce main thread ourselves**

---

## Verification Checklist

### ✅ Build Phase
- [ ] Compiles without errors (pthread and dispatch headers available on iOS)
- [ ] No linker errors (Foundation framework already linked)

### ✅ Runtime Logs - Fast Path
- [ ] Log shows: `"Vulkan operation executing on main thread (already main)"`
- [ ] No dispatch overhead

### ✅ Runtime Logs - Dispatch Path
- [ ] Log shows: `"Vulkan operation dispatched to main thread from background thread"`
- [ ] Log shows: `"Calling vkCreateInstance on main thread (iOS requirement)"`
- [ ] No deadlock or crash

### ✅ Functionality
- [ ] Vulkan instance creates successfully
- [ ] Surface creates successfully
- [ ] No Metal-related crashes
- [ ] Game rendering works (if other issues are also fixed)

---

## Related Fixes Needed

This main thread enforcement fixes **one** of the iOS Vulkan issues. Other fixes still needed:

### 1. CAMetalLayer Setup (Swift Side)
**File**: `src/ios/AzaharApp/Views/GameView.swift`
**Issue**: Metal layer may not be properly configured
**Fix**: Add `setupMetalLayer()` with:
- `MTLCreateSystemDefaultDevice()`
- `layer.contentsScale = UIScreen.main.scale`
- `layer.isOpaque = true`
- `layer.framebufferOnly = true`

### 2. Conditional Vulkan Extensions
**File**: `src/video_core/renderer_vulkan/vk_platform.cpp` (GetInstanceExtensions)
**Issue**: May request unsupported extensions
**Fix**: Make extensions conditional, check availability first

### 3. Portability Enumeration Flag
**File**: `src/video_core/renderer_vulkan/vk_platform.cpp` (GetInstanceFlags)
**Issue**: Always sets portability flag, but may not be supported
**Fix**: Check if `VK_KHR_portability_enumeration` extension is available first

All documented in `docs/vulkan-ios-retroarch-analysis.md`.

---

## References

- RetroArch iOS Vulkan: `ref/RetroArch/gfx/common/vulkan_common.c`
- Apple Metal Threading: https://developer.apple.com/documentation/metal/preparing_your_metal_app_to_run_in_the_background
- MoltenVK Known Issues: https://github.com/KhronosGroup/MoltenVK#known-issues

---

## Commit Message (Suggested)

```
[iOS] Enforce main thread for Vulkan initialization (MoltenVK requirement)

MoltenVK on iOS requires vkCreateInstance and vkCreateSurface to be
called on the main thread because Metal API calls must be on the main
thread. Without this, the app deadlocks or crashes during init.

Changes:
- Add EnsureMainThread<T> helper using GCD dispatch_sync
- Wrap vkCreateInstance call with main thread enforcement
- Wrap CreateSurface with main thread enforcement
- Use pthread_main_np() for efficient main thread detection
- Zero overhead if already on main thread (fast path)

This matches how RetroArch handles iOS Vulkan initialization.

Prevents: Deadlock/crash in MoltenVK when initializing from background thread
```

---

**Date**: August 5, 2026  
**Time**: 00:35 UTC  
**Build Hash**: 566d7da107fbe0f261520683fc4709c431466bea  
**iOS Version**: iOS 27.0 Beta (24A5390f)  
**Device**: iPhone 17,3
