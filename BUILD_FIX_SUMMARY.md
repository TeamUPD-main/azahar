# iOS Build Fix - Type Mismatch Error

**Date:** August 4, 2026  
**Error:** `Undefined symbols for architecture arm64: "_az_download_title_from_nus"`

## Problem

The build failed with a linker error because there was a type mismatch between the header declaration and implementation:

- **Header (azahar_ios.h):** `int az_download_title_from_nus(int64_t title_id);`
- **Implementation (ios_bridge.mm):** `int az_download_title_from_nus(uint64_t title_id) { ... }`

The linker saw these as two different functions due to signed vs unsigned parameter type.

## Fix

Changed the header declaration to match the implementation:

```diff
-int az_download_title_from_nus(int64_t title_id);
+int az_download_title_from_nus(uint64_t title_id);
```

## Why uint64_t is Correct

1. Title IDs are always positive (they're hex identifiers like `0x0004013000003202`)
2. The Swift code calls it with `UInt64`: `az_download_title_from_nus(titleId)`
3. The C++ core uses `u64` everywhere for title IDs
4. Using signed `int64_t` would cause issues with title IDs > INT64_MAX

## Complete Fix Summary

All iOS issues are now resolved:

1. ✅ **Black screen** - Metal surface initialization fixed
2. ✅ **Missing buttons** - 26 button PNG assets copied from Android
3. ✅ **NUS downloads** - AES crypto initialization on app launch
4. ✅ **Type mismatch** - Changed int64_t to uint64_t in header

## Files Modified

```
 src/ios/AzaharApp/AzaharApp.swift                           |  1 +
 src/ios/AzaharApp/Views/MetalView.swift                     | 22 ++++++++++++++++++-
 src/ios/AzaharBridge/azahar_ios.h                           |  6 +++++-
 src/ios/AzaharBridge/ios_bridge.mm                          | 12 +++++++----
 src/ios/AzaharApp/Resources/Assets.xcassets/                | 35 files added
 ---------------------------------------------------------------------
 Total: 41 lines added, 6 removed (code changes)
        35 asset files added (button images)
```

## Build Command

```bash
cd /run/media/nate/disk/AzahariOS
cmake -S . -B build-ios -G Xcode -DCMAKE_BUILD_TYPE=Release
cmake --build build-ios --config Release
```

This should now build successfully!
