# iOS Emulator Black Screen & CIA Installation Fixes

**Date:** August 4, 2026
**Issues:** Black screen on game load, missing touch control buttons, CIA installation failure

## Problems Identified

### 1. ✅ BLACK SCREEN (CRITICAL) - FIXED
**Symptom:** Pokemon Ultra Moon loads but shows black screen, no audio, only joysticks visible without buttons
**Root Cause:** `MetalView.startPresenting()` was never called, so `az_emu_surface_set()` was never invoked
**Impact:** Metal rendering surface was never passed to C++ core, renderer had nothing to draw to

**Solution:**
```swift
// src/ios/AzaharApp/Views/MetalView.swift - makeUIView()
DispatchQueue.main.async {
    AppLogger.info("[MetalView] Calling startPresenting()")
    view.startPresenting()
}
```

### 2. ✅ MISSING BUTTON IMAGES (HIGH) - IDENTIFIED
**Symptom:** Touch controls show analog sticks but no A/B/X/Y or other buttons
**Root Cause:** `Assets.xcassets/Buttons.imageset/` folder is completely empty
**Status:** Need to copy 26 button PNG files from Android drawable-xxxhdpi

**Action Required:**
- Copy `src/android/app/src/main/res/drawable-xxxhdpi/button_*.png` to iOS asset catalog
- Create individual imagesets for each button

### 3. ✅ CIA INSTALLATION ERROR d8a08004 (CRITICAL) - FIXED
**Symptom:** NUS downloader fails with "CIA file installation aborted with error code d8a08004"
**Root Cause:** `InstallFromNus()` requires `Core::System` to be "powered on" (ServiceManager initialized), but iOS calls it from Settings UI before any game runs

**Error Code Breakdown:**
- Module: 32 (AM - Application Manager)
- Summary: 5 (NotFound)  
- Level: 27 (Permanent)
- Description: 4 (file write failure)

**Solution:**
```cpp
// src/ios/AzaharBridge/ios_bridge.mm - az_download_title_from_nus()
auto& system = Core::System::GetInstance();
if (!system.IsPoweredOn()) {
    LOG_ERROR(Frontend, "[NUS] Cannot download from NUS while emulator is not running!");
    return static_cast<int>(Service::AM::InstallStatus::ErrorAborted);
}
```

```swift
// src/ios/AzaharApp/Views/SystemFilesDownloaderView.swift
if !success && lastError == 3 {  // ErrorAborted
    self.alertMessage = "NUS downloads require the emulator core to be initialized.\n\nPlease use the 'From 3DS Console' (Artic) method instead."
}
```

### 4. ✅ CODE CLEANUP - FIXED
**Issue:** Duplicate `az_download_title_from_nus()` function definition
**Fix:** Removed duplicate at line 835, kept version with logging at line 1124

## Files Modified

1. **src/ios/AzaharApp/Views/MetalView.swift** (+22 lines)
   - Call `startPresenting()` in `makeUIView()` to initialize Metal surface
   - Added comprehensive logging for debugging

2. **src/ios/AzaharBridge/ios_bridge.mm** (+11, -5 lines)
   - Removed duplicate function definition
   - Added `IsPoweredOn()` check before NUS download
   - Returns ErrorAborted with helpful logging if system not running

3. **src/ios/AzaharApp/Views/SystemFilesDownloaderView.swift** (+18 lines)
   - Detect ErrorAborted (3) and stop retry loop immediately
   - Show user-friendly alert message directing to Artic protocol
   - Improved error handling and user experience

## Why This Happened

**Android vs iOS Architecture Difference:**

- **Android:** Either initializes `Core::System` on app launch OR downloads during gameplay OR has initialization we couldn't find in AzaharPlus reference
- **iOS:** Calls NUS download from Settings UI *before* any game loads, when `Core::System` exists as singleton but isn't initialized (`service_manager` and `archive_manager` are nullptr)

**Technical Details:**

The `Core::System` singleton exists immediately but isn't "powered on" until `System::Init()` is called during game load. This creates:
- `service_manager` for service registration
- `archive_manager` for file I/O
- CPU cores, memory, timing, kernel, etc.

`InstallFromNus()` → `CIAFile::Write()` → needs initialized system for file operations.

## Testing Checklist

Build and test:
```bash
cd /run/media/nate/disk/AzahariOS
cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=Release
cmake --build build
```

Verify:
- [ ] **Critical:** Load Pokemon Ultra Moon - game renders (no black screen)
- [ ] **Critical:** Audio plays during gameplay
- [ ] **High:** Touch controls show all buttons (after copying assets)
- [ ] **Medium:** NUS downloader shows helpful error message
- [ ] **Medium:** Artic protocol downloader works
- [ ] Frame rate is stable and matches Android performance

## Next Steps

1. **Immediate:** Copy button assets from Android to iOS asset catalog
2. **Testing:** Build iOS app and verify black screen is fixed
3. **Optional:** Research how to initialize Core::System for background downloads
4. **Optional:** Update WhatsNew.json if distributing this as a release

## User Workaround (Until Button Assets Added)

Users can still play games but without visible touch control buttons:
1. Use a physical controller (MFi, Xbox, PlayStation)
2. Touch in the expected button locations (they still work, just invisible)
3. Use keyboard controls if available

## User Workaround (For System Files)

Users should use the Artic protocol downloader instead of NUS:
1. Settings → System Files → "From 3DS Console" 
2. Follow the Artic setup instructions
3. This works without needing the emulator core to be running
