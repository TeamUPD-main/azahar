# iOS Implementation - Remaining Critical Issues

## Status Summary (2026-08-04)

### ✅ Completed
- **Black screen timing fix**: Added 0.5s delay after Metal surface initialization (ManicEMU approach)
- **Crypto initialization**: `az_init_crypto()` calls `HW::AES::InitKeys()` on app launch
- **Button assets**: 26 PNG files (13 buttons × 2 states) copied from Android
- **NUS download infrastructure**: Type fixes (`uint64_t`), proper Swift conversion

### ❌ Still Broken

#### 1. Black Screen (High Priority)
**Symptom**: "Metal surface started successfully, CADisplayLink started, ready to render frames" but nothing appears on screen (both Vulkan and OpenGL)

**Applied Fix**: Added 0.5s delay before starting CADisplayLink (similar to ManicEMU's 1s delay)

**If still broken, try**:
- Increase delay to 1.0s (ManicEMU's conservative timing)
- Pass explicit frame dimensions to `az_emu_surface_set()` (add CGSize parameter)
- Verify emulation actually starts (check if `az_is_running()` returns true)
- Add logging in C++ renderer to confirm Metal layer is valid

**Reference**: ManicEMU delays 1s between Metal allocation and boot, 3.25s before enabling controls

---

#### 2. CIA Installation Fails with Status 3 (High Priority)
**Symptom**: Status 3 = `InstallStatus::ErrorAborted`

**Root Cause**: `CIAFile::Write()` is failing and returning an error result

**Investigation needed**:
1. Check if NAND directories exist and are writable
2. Verify `GetTitlePath()` returns valid path
3. Check if `CIAFile` constructor succeeds
4. Add logging to `am.cpp:1055` to see exact error code from Write()
5. Compare AzaharPlus vs current `CIAFile` implementation

**Key difference from AzaharPlus**:
- AzaharPlus uses `IOFileBase` (abstract file interface)
- Current code uses `IOFile` directly
- May need `file_derived.h` include and crypto file handling

---

#### 3. Button Sizing Incorrect (High Priority)
**Symptom**: Touch control buttons not sized correctly on iOS

**Android Implementation**:
- Uses `intrinsicWidth/Height` from drawable (lines 65-66 in `InputOverlayDrawableButton.kt`)
- Scales buttons based on screen density via `getBitmap()` function (line 1009)
- Default scale calculated from `min(displayWidth, displayHeight)` and user preferences
- Positions stored as fractions of screen size (e.g., `930/1000 * maxX` for Button A)

**iOS needs**:
1. Read button images and get intrinsic size
2. Calculate scale factor based on screen size and density
3. Apply scale to button frames
4. Store positions as percentages of screen bounds

**Reference files**:
- `src/android/.../InputOverlay.kt`: lines 1009-1050 (getBitmap, resizeBitmap)
- `src/android/.../InputOverlayDrawableButton.kt`: lines 55-66 (width/height from bitmap)
- `src/android/app/src/main/res/values/integers.xml`: button positions as fractions (/1000)

---

#### 4. Missing Touch Control Editing (High Priority)
**Symptom**: Can't move or resize buttons like Android version

**Android Implementation**:
- `isInEditMode` flag enables drag-to-move (InputOverlay.kt:47,100)
- `onConfigureTouch()` handles drag gestures (InputOverlayDrawableButton.kt:152-176)
- Saves positions to SharedPreferences after editing
- Scale adjustment per button type

**iOS needs**:
1. Edit mode toggle in pause menu
2. Drag gesture recognizers on buttons
3. Pinch gesture for resizing
4. Persist button positions/scales to UserDefaults
5. Reset to defaults option

---

#### 5. Missing Android-Style Pause Menu (Medium Priority)
**Android pause menu options** (from EmulationActivity):
- Resume
- Save State
- Load State
- Settings
- Swap Screens
- Cheats
- Amiibo
- Motion Controls
- Reset
- Exit

**Current iOS menu**: Basic (just resume/exit?)

**iOS needs**: Full-featured SwiftUI sheet matching Android functionality

---

## Implementation Priority

### Phase 1: Critical Fixes (Must Work)
1. **Black screen debugging** - Add C++ logging to verify renderer receives frames
2. **CIA installation** - Fix write failure, add error logging
3. **Button sizing** - Implement Android's scale calculation

### Phase 2: Feature Parity
4. **Touch control editing** - Drag/resize like Android
5. **Pause menu** - Full options like Android

---

## Code References

### Android Button Sizing Logic
```kotlin
// InputOverlay.kt:1039-1047
private fun resizeBitmap(context: Context, bitmap: Bitmap, scale: Float): Bitmap {
    val windowMetrics = (context as Activity).windowManager.currentWindowMetrics
    val bounds = windowMetrics.bounds
    val minDimension = min(bounds.width(), bounds.height())
    
    return Bitmap.createScaledBitmap(
        bitmap,
        (minDimension * scale).toInt(),
        (minDimension * scale).toInt(),
        true
    )
}

// InputOverlay.kt:1096-1105 - Scale per button type
var scale: Float = when (buttonId) {
    NativeLibrary.ButtonType.BUTTON_A, ... -> preferences.getInt("controlScale", 50) / 100f
    NativeLibrary.ButtonType.TRIGGER_L, ... -> preferences.getInt("controlScaleTriggers", 70) / 100f
    NativeLibrary.ButtonType.DPAD_UP -> preferences.getInt("controlScaleDpad", 50) / 100f
    NativeLibrary.ButtonType.STICK_LEFT, ... -> preferences.getInt("controlScaleJoystick", 70) / 100f
    else -> 0.50f
}
```

### Android Button Positioning
```kotlin
// InputOverlay.kt:702-704 - Position as fraction of screen
.putFloat(
    NativeLibrary.ButtonType.BUTTON_A.toString() + "-Y",
    resources.getInteger(R.integer.N3DS_BUTTON_A_Y).toFloat() / 1000 * maxY
)
```

### ManicEMU Timing Pattern
```swift
// ThreeDS.swift:338-350
citraCore.allocateMetalLayer(for: metalLayer, with: metalViewFrame.size, isSecondary: false)

DispatchQueue.main.asyncAfter(deadline: .now() + 1) {  // 1 second delay
    Thread.detachNewThread {
        self.citraCore.insertCartridgeAndBoot(...)
    }
}

DispatchQueue.main.asyncAfter(delay: 3.25) {  // 3.25 seconds total
    self.enableControl = true
}
```

---

## Next Steps

1. **Test black screen fix** - Build and run with 0.5s delay
2. **If still black** - Increase to 1.0s, add C++ renderer logging
3. **CIA debug** - Add logging to see exact Write() error code
4. **Button sizing** - Port Android's `getBitmap()`/`resizeBitmap()` logic to Swift
5. **Control editing** - Implement drag gestures with position persistence

All reference code is available in `src/android/` and `ref/ManicEMU/`.
