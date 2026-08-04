# iOS Metal Surface Initialization Analysis

## Problem
Black screen on iOS when launching 3DS games - Metal rendering surface not properly initialized.

## Root Cause
`az_emu_surface_set()` was being called before the MetalView had valid frame dimensions (calling it with `.zero` bounds).

## Reference Implementations

### Folium (Cytrus - 3DS Emulator)
**File**: `ref/Folium/Folium/Controllers/Emulation/CytrusController.swift:302-346`

**Approach**:
- Waits for `viewWillLayoutSubviews()` to ensure proper frame dimensions
- Adds additional 1/3 second delay via `DispatchQueue.main.asyncAfter`
- Explicitly extracts `CAMetalLayer` from `MTKView`
- Passes frame dimensions (height, width) to C++ core
- Sets BOTH screens (top and bottom) BEFORE starting emulation

```swift
override func viewWillLayoutSubviews() {
    super.viewWillLayoutSubviews()
    DispatchQueue.main.asyncAfter(deadline: .now() + (1 / 3)) {
        Task {
            guard let top: CAMetalLayer = primaryRenderingView.layer as? CAMetalLayer,
                  let bottom: CAMetalLayer = secondaryRenderingView.layer as? CAMetalLayer else {
                return
            }
            
            if await cytrusGame.cytrusSystem.running {
                return  // Don't re-initialize if already running
            }
            
            // Set Metal layers with dimensions BEFORE starting
            await cytrusGame.cytrusSystem.set(layer: top,
                                              height: top.frame.size.height,
                                              width: top.frame.size.width,
                                              secondary: false)
            
            await cytrusGame.cytrusSystem.set(layer: bottom,
                                              height: bottom.frame.size.height,
                                              width: bottom.frame.size.width,
                                              secondary: true)
            
            await cytrusGame.cytrusSystem.insertDisc(at: cytrusGame.details.url)
            await cytrusGame.cytrusSystem.start()
        }
    }
}
```

**Key insight**: The C++ bridge function `set_screens()` accepts dimensions:
```cpp
cytrus.set_screens(Unmanaged.passUnretained(layer).toOpaque(), height, width, secondary)
```

### ManicEMU (Citra Integration)
**File**: `ref/ManicEMU/ManicEmu/ManicEmu/Sources/Tools/Cores/ThreeDS.swift:282-350`

**Approach**:
- Uses `Citra.framework` with direct Metal layer allocation
- Passes `MTKView`, `metalViewFrame`, `topRect`, and `bottomRect` to `start()` method
- **Critical timing**: Delays emulation start by 1 second after Metal layer allocation
- Delays control enabling by 3.25 seconds after start

**Code snippet (lines 338-350)**:
```swift
self.metalView = metalView
let metalLayer = metalView.layer as! CAMetalLayer
citraCore.allocateMetalLayer(for: metalLayer, with: metalViewFrame.size, isSecondary: false)

// Delay 1 second before booting emulation
DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
    Thread.setThreadPriority(1.0)
    Thread.detachNewThread {
        self.citraCore.insertCartridgeAndBoot(with: gameURL, advancedMode: advancedMode, jitSupport: LibretroCore.jitAvailable())
    }
}

// Delay 3.25 seconds before enabling controls
DispatchQueue.main.asyncAfter(delay: 3.25) {
    self.citraCore.orientationChange(with: UIDevice.currentOrientation, using: metalView)
    self.enableControl = true
}
```

**Key insights**: 
- `allocateMetalLayer(for:with:isSecondary:)` takes `metalViewFrame.size` (CGSize) explicitly
- Separate method for Metal layer allocation vs emulation boot
- Significant delays ensure Metal surface is fully ready before rendering starts

## Azahar's Fix Applied

**Changed**: `src/ios/AzaharApp/Views/MetalView.swift`

### Before (Broken)
```swift
func makeUIView(context: Context) -> MetalViewUIView {
    let view = MetalViewUIView(viewModel: viewModel)
    
    // Called immediately - view still has .zero bounds!
    DispatchQueue.main.async {
        view.startPresenting()  // az_emu_surface_set() with invalid dimensions
    }
    
    return view
}
```

### After (Fixed)
```swift
override func layoutSubviews() {
    super.layoutSubviews()
    metalLayer.frame = bounds
    metalLayer.drawableSize = bounds.size
    
    // Only initialize once we have valid dimensions
    if !isSurfaceSet && bounds.size.width > 0 && bounds.size.height > 0 {
        AppLogger.info("[MetalView] layoutSubviews with valid bounds: \(bounds) - calling startPresenting()")
        startPresenting()  // Now called with proper frame size
    } else if isSurfaceSet {
        // Update existing surface on subsequent layouts
        az_emu_surface_set(Unmanaged.passUnretained(metalLayer).toOpaque(), scale)
        // ... orientation updates
    }
}
```

## Key Differences Between Implementations

### Azahar vs Folium
1. **Timing**: We use `layoutSubviews()` vs Folium's `viewWillLayoutSubviews()` + 0.33s delay
2. **Dimensions**: Our `az_emu_surface_set()` takes layer pointer + scale, Folium passes height/width explicitly
3. **Screen count**: Single unified MetalView vs separate top/bottom screens

### Azahar vs ManicEMU
1. **API design**: ManicEMU has separate `allocateMetalLayer()` before `insertCartridgeAndBoot()`, we combine in `az_emu_surface_set()`
2. **Timing**: ManicEMU delays boot by 1s after Metal allocation, delays controls by 3.25s total
3. **Frame size**: ManicEMU passes `metalViewFrame.size` explicitly to allocation method

### Common Pattern (Both References)
- ✅ **Wait for valid frame dimensions** before initializing Metal surface
- ✅ **Add delays** between Metal setup and emulation start (Folium: 0.33s, ManicEMU: 1.0s)
- ✅ **Pass explicit dimensions** to C++ core (both use `CGSize` or height/width parameters)

## Potential Issues with Current Fix

Based on reference implementations, our current fix may still have issues:

1. **Missing explicit dimensions**: Both Folium and ManicEMU pass frame size (width/height or CGSize) to their C++ bridge, we only pass scale
2. **Missing delay**: Both references add delays (0.33s-1.0s) between Metal allocation and emulation start, we start immediately
3. **Drawable size timing**: We set `metalLayer.drawableSize = bounds.size` in `layoutSubviews()` but may need to set it in `setupLayer()` first

## Recommended Next Steps

1. **Test current fix first** - May work if C++ core can infer dimensions from layer itself
2. **If black screen persists**, apply these fixes in order:
   - Add delay: `DispatchQueue.main.asyncAfter(deadline: .now() + 0.5)` before calling `az_emu_surface_set()`
   - Pass explicit dimensions: Modify `az_emu_surface_set()` signature to accept `CGSize` or width/height
   - Separate allocation from boot: Split into `az_emu_surface_allocate()` + delay + `az_emu_start_game()`

## Status
✅ Fix applied - awaiting device testing
⏳ Current approach: Initialize in `layoutSubviews()` when bounds become valid
🔍 Fallback: Add dimensions parameter to C++ bridge if needed
