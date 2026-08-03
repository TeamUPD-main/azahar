# On-Device JIT Implementation for AzahariOS

## Overview

AzahariOS now supports on-device JIT (Just-In-Time) compilation enablement for iOS 17.4+ devices. This implementation provides two methods:

1. **StikDebug Integration (Recommended)** - Uses the external StikDebug companion app
2. **Built-in JIT (Experimental)** - Native implementation using idevice FFI library

## What Was Implemented

### 1. idevice FFI Bridge Layer
**Files Created:**
- `src/ios/AzaharBridge/idevice.h` - C header defining idevice library API
- `src/ios/AzaharBridge/idevice.c` - Stub implementation (to be replaced with actual Rust-compiled library)

**Key Functions:**
- `start_tunnel()` / `stop_tunnel()` - Loopback tunnel management
- `mount_developer_image()` - DDI mounting for iOS 17+
- `debug_app()` / `debug_app_pid()` - JIT enablement via debug attachment
- `launch_app_via_proxy()` - App launching
- `get_device_info()` - Device metadata
- `get_current_pid()` / `get_current_bundle_id()` - Process info

### 2. JITEnableContext Swift Singleton
**File:** `src/ios/AzaharApp/Utilities/JITEnableContext.swift`

**Features:**
- Connection management to device services via loopback tunnel
- DDI mounting orchestration
- JIT enablement for apps by bundle ID or PID
- Self-JIT enablement for Azahar
- **iOS 27 TXM Detection Fix** - Enhanced detection for A13/A14/M1 chips:
  - Checks multiple firmware paths: `/System/Volumes/Preboot` and `/private/preboot`
  - Searches in both `boot/usr/standalone/firmware/FUD/` and `usr/standalone/firmware/FUD/`
  - Additional iOS 27 paths: `boot/usr/standalone/firmware/` and `usr/standalone/firmware/`
- JavaScript callback support for TXM-enabled devices (iOS 26+)

### 3. DDIManager for Developer Disk Images
**File:** `src/ios/AzaharApp/Utilities/DDIManager.swift`

**Features:**
- Automatic DDI download for current iOS version
- Downloads from GitHub mirror: `mspvirajpatel/Xcode_Developer_Disk_Images`
- Files managed: `Image.dmg`, `Image.dmg.signature`, `Image.dmg.trustcache`, `BuildManifest.plist`
- Progress tracking and status reporting
- Storage in Documents/DDI directory
- Cleanup functionality

### 4. JIT Settings UI
**File:** `src/ios/AzaharApp/Views/Settings/JITSettingsView.swift`

**Two Modes:**

#### StikDebug Mode (Recommended):
- One-tap launch to StikDebug app via URL scheme: `stikdebug://enable-jit?bundle-id=org.azahar_emu.Azahar`
- Link to download StikDebug from GitHub releases
- Simple, reliable, user-friendly

#### Built-in Mode (Experimental):
- Connection status display
- Pairing file selection
- DDI download and mounting
- Manual JIT enable button
- Diagnostic information

**Settings:**
- Auto-enable JIT on launch toggle
- Method selection (StikDebug vs Built-in)
- System information display (iOS version, TXM support, PID, Bundle ID)

### 5. App Lifecycle Integration
**File:** `src/ios/AzaharApp/AzaharApp.swift`

**Features:**
- Scene phase monitoring
- Auto-enable JIT on app launch (if configured)
- Re-enable JIT when returning from background
- StikDebug URL scheme triggering
- Fallback to built-in JIT if connected

### 6. Settings Integration
**File:** `src/ios/AzaharApp/Views/Settings/SettingsView.swift`

Added new "JIT Compilation" section with navigation to JITSettingsView.

## iOS 27 A13/A14/M1 Chip Fix

The TXM detection logic now properly handles iOS 27 devices with A13, A14, or M1 chips by checking additional firmware paths:

```swift
let paths = [
    "\(basePath)/\(uuid)/boot/usr/standalone/firmware/FUD/Ap,TrustedExecutionMonitor.img4",
    "\(basePath)/\(uuid)/usr/standalone/firmware/FUD/Ap,TrustedExecutionMonitor.img4",
    // iOS 27 A13/A14/M1 fix:
    "\(basePath)/\(uuid)/boot/usr/standalone/firmware/Ap,TrustedExecutionMonitor.img4",
    "\(basePath)/\(uuid)/usr/standalone/firmware/Ap,TrustedExecutionMonitor.img4"
]
```

**Note:** Apps requiring JIT on iOS 27 with these chips may need their own patches to work properly.

## How It Works

### StikDebug Method (Recommended)

1. User installs StikDebug and LocalDevVPN from GitHub/sideloading
2. User opens JIT Settings in Azahar
3. User taps "Open StikDebug" button
4. StikDebug enables JIT for Azahar
5. User returns to Azahar with JIT enabled

**Advantages:**
- Reliable and tested
- Works on all iOS 17.4-27.x versions
- Maintained by StikDebug developers
- Supports advanced features on iOS 26+ with TXM

### Built-in Method (Experimental)

1. User obtains `.mobiledevicepairing` file (from macOS Xcode pairing)
2. User installs LocalDevVPN on device
3. User places pairing file in Azahar Documents folder
4. User connects in JIT Settings
5. DDI auto-downloads for current iOS version
6. User mounts DDI
7. User enables JIT for Azahar

**Advantages:**
- No external app required (once set up)
- Direct control over JIT process
- Educational for developers

**Limitations:**
- Requires initial setup with computer
- Experimental/stub implementation
- Needs actual Rust idevice library integration

## Technical Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                     AzahariOS iOS App                        │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐ │
│  │ AzaharApp    │───→│ JIT Settings │───→│ StikDebug    │ │
│  │ (Lifecycle)  │    │ View         │    │ URL Scheme   │ │
│  └──────────────┘    └──────────────┘    └──────────────┘ │
│         │                    │                    │         │
│         └────────────────────┴────────────────────┘         │
│                          │                                   │
│                          ↓                                   │
│            ┌────────────────────────────┐                   │
│            │  JITEnableContext.shared   │                   │
│            │  (Swift Singleton)         │                   │
│            └────────────────────────────┘                   │
│                          │                                   │
│         ┌────────────────┼────────────────┐                │
│         ↓                ↓                ↓                 │
│  ┌──────────────┐ ┌──────────────┐ ┌──────────────┐      │
│  │ DDIManager   │ │ TXM Detection│ │ idevice FFI  │      │
│  │ (DDI files)  │ │ (iOS 27 fix) │ │ Bridge       │      │
│  └──────────────┘ └──────────────┘ └──────────────┘      │
│                                             │               │
└─────────────────────────────────────────────┼───────────────┘
                                              ↓
                    ┌────────────────────────────────────┐
                    │  idevice C FFI Library             │
                    │  (Rust compiled, currently stub)   │
                    └────────────────────────────────────┘
                                              ↓
                    ┌────────────────────────────────────┐
                    │  LocalDevVPN (Loopback Tunnel)     │
                    └────────────────────────────────────┘
                                              ↓
                    ┌────────────────────────────────────┐
                    │  iOS Device Services (lockdownd)   │
                    └────────────────────────────────────┘
```

## Requirements

### For StikDebug Method:
- iOS 17.4 - 27.x
- StikDebug app installed (from GitHub releases)
- LocalDevVPN app installed
- No computer required after initial sideloading

### For Built-in Method:
- iOS 17.4 - 27.x
- LocalDevVPN app installed
- `.mobiledevicepairing` file (obtained from macOS Xcode pairing)
- Developer Disk Image files (auto-downloaded)
- Actual idevice Rust library (currently using stub)

## User Instructions

### Using StikDebug (Simple):

1. Install StikDebug from: https://github.com/BomberFish/StikDebug/releases
2. Install LocalDevVPN from App Store or GitHub
3. Open Azahar Settings → JIT Compilation → JIT Settings
4. Ensure "StikDebug (Recommended)" is selected
5. Tap "Open StikDebug"
6. In StikDebug, enable JIT for Azahar
7. Return to Azahar - JIT is now enabled!

Optional: Enable "Auto-enable JIT on Launch" to automatically trigger StikDebug when Azahar starts.

### Using Built-in (Advanced):

1. Pair your device with Xcode on macOS to generate pairing file
2. Locate `.mobiledevicepairing` in `~/Library/Lockdown/` on your Mac
3. Transfer file to iOS device (via Files app or iTunes)
4. Install LocalDevVPN and start the tunnel
5. Open Azahar Settings → JIT Compilation → JIT Settings
6. Select "Built-in (Experimental)"
7. Select pairing file
8. Tap "Connect"
9. Tap "Download DDI Files" (wait for download)
10. Tap "Mount DDI"
11. Tap "Enable JIT for Azahar"

## Next Steps

### To Make Built-in Method Production-Ready:

1. **Replace idevice stub** - Integrate actual Rust-compiled `libidevice_ffi.a`
2. **Add document picker** - Allow users to select `.mobiledevicepairing` file via UI
3. **Implement pairing flow** - Generate pairing on-device without computer
4. **Add persistent storage** - Remember connection state across app launches
5. **Implement background refresh** - Keep JIT enabled when app is backgrounded
6. **Error handling** - Better error messages and recovery
7. **Testing** - Extensive testing across iOS versions and device types

### Optional Enhancements:

- URL scheme handler for external JIT triggers
- Siri Shortcuts integration
- Widget for quick JIT enable
- Notification when JIT needs re-enabling
- Integration with other JIT-dependent emulator features

## Files Modified/Created

### Created:
1. `src/ios/AzaharBridge/idevice.h` - idevice FFI header
2. `src/ios/AzaharBridge/idevice.c` - idevice stub implementation
3. `src/ios/AzaharApp/Utilities/JITEnableContext.swift` - JIT enablement logic
4. `src/ios/AzaharApp/Utilities/DDIManager.swift` - DDI download/mounting
5. `src/ios/AzaharApp/Views/Settings/JITSettingsView.swift` - JIT settings UI

### Modified:
1. `src/ios/AzaharBridge/azahar_ios.h` - Added idevice.h include
2. `src/ios/AzaharApp/AzaharApp.swift` - Added lifecycle integration
3. `src/ios/AzaharApp/Views/Settings/SettingsView.swift` - Added JIT section
4. `src/ios/CMakeLists.txt` - Added new source files to build

## Known Limitations

1. **Stub Implementation** - Current idevice.c is a stub; real functionality requires Rust library
2. **iOS 27 Compatibility** - Apps on iOS 27 with A13/A14/M1 need their own patches
3. **No Auto-Pairing** - Built-in method requires manual pairing file from computer
4. **No Background Persistence** - JIT must be re-enabled after app suspension (StikDebug handles this better)
5. **Experimental Status** - Built-in method is not production-ready

## Security Considerations

- Pairing files contain device trust data - users should keep them secure
- JIT enablement bypasses iOS sandboxing restrictions - only use for development/emulation
- LocalDevVPN creates a loopback tunnel - ensure it's from a trusted source
- DDI files are downloaded from third-party mirrors - verify checksums if security-critical

## Credits

- **StikDebug** by BomberFish and contributors
- **idevice** Rust library by jkcoxson
- **LocalDevVPN** for loopback tunnel functionality
- **StikDebug Documentation** for architecture reference
- **Xcode Developer Disk Images** mirror by mspvirajpatel

## License

All code follows the Azahar project license (GPLv2 or later).

---

## Summary

AzahariOS now has two paths to enable JIT on iOS:

1. **StikDebug (Recommended)**: One-tap integration with external companion app - reliable and user-friendly
2. **Built-in (Experimental)**: Native implementation for advanced users and future independence

The implementation includes full iOS 27 A13/A14/M1 TXM detection fixes and provides a solid foundation for JIT-dependent features like faster 3DS emulation.
