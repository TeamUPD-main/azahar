# JIT Enablement Engine

<details>
<summary>Relevant source files</summary>

The following files were used as context for generating this wiki page:

- [StikJIT/Utilities/JITEnableContext.swift](StikJIT/Utilities/JITEnableContext.swift)
- [StikJIT/Views/HomeView.swift](StikJIT/Views/HomeView.swift)
- [StikJIT/Views/SettingsView.swift](StikJIT/Views/SettingsView.swift)

</details>



The JIT Enablement Engine is the core system responsible for enabling Just-In-Time compilation on target iOS applications. This engine orchestrates the entire debug attachment process, manages script selection for advanced JIT configurations, handles both bundle-ID-based and PID-based debugging, and provides URL scheme integration for external automation.

This document focuses on the decision logic, execution flow, and callback mechanisms within the JIT enablement process. For device connection establishment, see [Heartbeat and Connection Management](). For JavaScript execution internals, see [JavaScript Execution Environment](). For DDI mounting operations, see [Developer Disk Image Management]().

---

## Architecture Overview

The JIT Enablement Engine operates as a multi-layer system with decision points for script selection, TXM capability detection, and execution path routing.

### Code Entity Mapping: UI to Native Bridge

The following diagram bridges the high-level UI triggers to the low-level native FFI calls used for JIT enablement.

```mermaid
graph TB
    subgraph "Swift UI Layer"
        HomeView["HomeView"]
        URLScheme["onOpenURL Handler"]
        Settings["SettingsView"]
    end
    
    subgraph "Swift Logic Layer"
        StartJIT["startJITInBackground(bundleID:pid:scriptData:scriptName:triggeredByURLScheme:)"]
        PrefScript["ScriptStore.preferredScript(for:)"]
        GetCallback["getJsCallback(scriptData:name:)"]
        TXMCheck["ProcessInfo.hasTXM"]
    end
    
    subgraph "Swift Bridge (JITEnableContext.swift)"
        Context["JITEnableContext (shared)"]
        DebugBundle["debugApp(withBundleID:logger:jsCallback:)"]
        DebugPID["debugApp(withPID:logger:jsCallback:)"]
        LaunchOnly["launchAppWithoutDebug(bundleID:logger:)"]
    end
    
    subgraph "C FFI Layer (idevice.h)"
        FFIDebugApp["debug_app"]
        FFIDebugPID["debug_app_pid"]
        FFILaunch["launch_app_via_proxy"]
    end
    
    HomeView --> StartJIT
    URLScheme --> StartJIT
    Settings -- "txmOverride" --> TXMCheck
    
    StartJIT --> PrefScript
    StartJIT --> TXMCheck
    StartJIT --> GetCallback
    
    StartJIT --> Context
    Context --> DebugBundle
    Context --> DebugPID
    Context --> LaunchOnly
    
    DebugBundle --> FFIDebugApp
    DebugPID --> FFIDebugPID
    LaunchOnly --> FFILaunch
```

**Sources:** [StikJIT/Views/HomeView.swift:93-97](), [StikJIT/Views/HomeView.swift:120-177](), [StikJIT/Utilities/JITEnableContext.swift:184-240](), [StikJIT/Views/SettingsView.swift:128-136]()

---

## JIT Enablement Flow

The complete flow from user action to JIT enablement follows a decision tree based on script availability, TXM capability, and execution context.

```mermaid
sequenceDiagram
    participant User
    participant HomeView
    participant ScriptStore as "ScriptStore"
    participant Context as "JITEnableContext"
    participant FFI as "idevice (C FFI)"
    participant JSModel as "RunJSViewModel"

    User->>HomeView: Select app or trigger URL (stikjit://enable-jit)
    HomeView->>HomeView: startJITInBackground(...)
    
    Note over HomeView, ScriptStore: Logic determines if script is needed
    HomeView->>ScriptStore: preferredScript(for: bundleID)
    ScriptStore-->>HomeView: (scriptData, scriptName)
    
    alt Has Script & TXM Enabled
        HomeView->>HomeView: getJsCallback(scriptData, name)
        HomeView->>Context: debugApp(withBundleID:..., jsCallback:)
    else No Script or No TXM
        HomeView->>Context: debugApp(withBundleID:..., jsCallback: nil)
    end
    
    Context->>FFI: debug_app(adapter, handshake, bundle_id, logger, callback)
    
    opt If callback provided (DebugAppCallback)
        FFI->>HomeView: Invoke DebugAppCallback closure
        HomeView->>JSModel: init(pid, debugProxy, remoteServer, semaphore)
        HomeView->>JSModel: runScript(data: scriptData, name: name)
    end
    
    FFI-->>HomeView: Return Success/Failure
    
    alt Success & autoQuitAfterEnablingJIT == true
        HomeView->>HomeView: exit(0)
    end
```

**Sources:** [StikJIT/Views/HomeView.swift:141-145](), [StikJIT/Views/HomeView.swift:273-333](), [StikJIT/Utilities/JITEnableContext.swift:13-13](), [StikJIT/Utilities/JITEnableContext.swift:184-240]()

---

## Script Selection System

The script selection system implements a priority-based fallback mechanism to determine which JavaScript should execute during JIT enablement. The selection occurs in `HomeView` before calling into `JITEnableContext`.

### Selection Priority

| Priority | Method | Description | Condition |
|----------|--------|-------------|-----------|
| 1 | `assignedScript(for:)` | User-assigned script via `BundleScriptMap` | Script file exists in documents/scripts |
| 2 | `autoScript(for:)` | Auto-detected script for known apps | `ProcessInfo.hasTXM == true` AND app matches known list |
| 3 | None | Direct JIT enablement without script | Fallback when no script available |

**Sources:** [StikJIT/Views/HomeView.swift:224-252](), [StikJIT/Views/HomeView.swift:192-211](), [StikJIT/Views/HomeView.swift:213-222]()

### Auto-Script Mapping

The `autoScriptResource(for:)` function maps known application names to bundled scripts:

| App Name | Script Resource | Script File |
|----------|----------------|-------------|
| maciOS | maciOS | maciOS.js |
| Amethyst, MeloNX, XeniOS, MeloCafe | universal | universal.js |
| Geode | Geode | Geode.js |
| Manic EMU | manic | manic.js |
| UTM, DolphiniOS, Flycast | UTM-Dolphin | UTM-Dolphin.js |

**Sources:** [StikJIT/Views/HomeView.swift:213-222]()

---

## TXM Detection and Override

The TXM (Trusted Execution Monitor) detection determines whether advanced script-based JIT enablement is available. This capability is required for executing JavaScript callbacks during debug attachment.

### Detection Logic

The `ProcessInfo.hasTXM` computed property implements a two-stage check:

1.  **User Override**: Checks `UserDefaults.Keys.txmOverride` (Settings -> "Always Run Scripts"). [StikJIT/Views/HomeView.swift:348-350]()
2.  **Filesystem Probing**: Searches `/System/Volumes/Preboot` or `/private/preboot` for `Ap,TrustedExecutionMonitor.img4` firmware files. [StikJIT/Views/HomeView.swift:352-369]()

### Code Entity: TXM Detection Flow

```mermaid
graph LR
    Start["ProcessInfo.hasTXM"]
    CheckOverride{"UserDefaults<br/>txmOverride"}
    ReturnTrue["Return true"]
    DetectLocal["detectLocalTXM()"]
    CheckPreboot{"/System/Volumes/Preboot<br/>exists?"}
    CheckTXMFile1["Check<br/>*/boot/usr/standalone/firmware/FUD/<br/>Ap,TrustedExecutionMonitor.img4"]
    CheckTXMFile2["Check<br/>/private/preboot/*/usr/standalone/firmware/FUD/<br/>Ap,TrustedExecutionMonitor.img4"]
    
    Start --> CheckOverride
    CheckOverride -->|true| ReturnTrue
    CheckOverride -->|false| DetectLocal
    DetectLocal --> CheckPreboot
    CheckPreboot -->|true| CheckTXMFile1
    CheckPreboot -->|false| CheckTXMFile2
    CheckTXMFile1 --> ReturnTrue
    CheckTXMFile2 --> ReturnTrue
```

**Sources:** [StikJIT/Views/HomeView.swift:347-369](), [StikJIT/Views/SettingsView.swift:15-15]()

---

## Debug Entry Points

The `JITEnableContext` singleton provides three distinct entry points for JIT operations, replacing the legacy Objective-C implementation with Swift-native wrappers.

### Entry Point Signatures

*   **Bundle-ID Debugging**: `func debugApp(withBundleID bundleID: String, logger: LogFunc?, jsCallback: DebugAppCallback?) throws` [StikJIT/Utilities/JITEnableContext.swift:184-240]()
*   **PID Debugging**: `func debugApp(withPID pid: Int32, logger: LogFunc?, jsCallback: DebugAppCallback?) throws` [StikJIT/Utilities/JITEnableContext.swift:242-298]()
*   **Launch Only**: `func launchAppWithoutDebug(_ bundleID: String, logger: LogFunc?) throws` [StikJIT/Utilities/JITEnableContext.swift:300-344]()

### Implementation Detail

These methods wrap the C FFI functions from the `idevice` xcframework. For example, `debugApp(withBundleID:...)` calls `debug_app`, passing the `adapter` and `handshake` handles managed by the singleton. [StikJIT/Utilities/JITEnableContext.swift:222-228]()

---

## JavaScript Callback Mechanism

When TXM is available and a script is selected, the JIT engine creates a callback closure that bridges the native debug session to JavaScript execution.

### DebugAppCallback Type

The `DebugAppCallback` is defined as a closure receiving raw pointers to the debug proxy and remote server handles:

```swift
typealias DebugAppCallback = (
    _ pid: Int32, 
    _ debugProxy: OpaquePointer?, 
    _ remoteServer: OpaquePointer?, 
    _ semaphore: DispatchSemaphore
) -> Void
```
[StikJIT/Utilities/JITEnableContext.swift:13-13]()

### Lifecycle in startJITInBackground

1.  **Creation**: `getJsCallback` creates the closure. [StikJIT/Views/HomeView.swift:254-271]()
2.  **UI Notification**: Inside the closure, a `RunJSViewModel` is initialized and a notification `.intentJSScriptReady` is posted to trigger the Script View UI. [StikJIT/Views/HomeView.swift:260-265]()
3.  **Execution**: The script is executed in a global background queue using `model.runScript(data: scriptData, name: name)`. [StikJIT/Views/HomeView.swift:266-269]()

---

## URL Scheme Integration

The JIT engine supports automation via `onOpenURL` in `HomeView`.

### Supported Commands

| Command | Parameters | Action |
|---------|------------|--------|
| `enable-jit` | `bundle-id`, `pid`, `script-data`, `script-name` | Triggers `startJITInBackground`. If `script-data` is missing, it attempts to resolve via `ScriptStore.preferredScript`. [StikJIT/Views/HomeView.swift:124-150]() |
| `kill-process` | `pid` | Calls `JITEnableContext.shared.killProcess(withPID:)`. [StikJIT/Views/HomeView.swift:151-168]() |
| `launch-app` | `bundle-id` | Calls `JITEnableContext.shared.launchAppWithoutDebug`. [StikJIT/Views/HomeView.swift:169-175]() |

### Auto-Quit Behavior

If `@AppStorage("autoQuitAfterEnablingJIT")` is enabled, the application will call `exit(0)` immediately after a successful JIT enablement triggered by any method. [StikJIT/Views/HomeView.swift:77-77](), [StikJIT/Views/HomeView.swift:322-324]()

**Sources:** [StikJIT/Views/HomeView.swift:120-177](), [StikJIT/Views/HomeView.swift:322-324]()