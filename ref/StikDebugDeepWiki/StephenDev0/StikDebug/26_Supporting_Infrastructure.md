# Supporting Infrastructure

<details>
<summary>Relevant source files</summary>

The following files were used as context for generating this wiki page:

- [StikJIT/Utilities/LogManager.swift](StikJIT/Utilities/LogManager.swift)
- [StikJIT/Utilities/LogManagerBridge.swift](StikJIT/Utilities/LogManagerBridge.swift)
- [StikJIT/Views/ConsoleLogsView.swift](StikJIT/Views/ConsoleLogsView.swift)

</details>



## Purpose and Scope

This document provides an overview of the auxiliary systems that support the core JIT enablement and device communication functionality. Supporting infrastructure includes logging, caching, persistence, widget integration, network diagnostics, and background services. These systems operate independently but integrate with the main application flow to provide enhanced user experience, performance optimization, and debugging capabilities.

For detailed information on specific subsystems, see:
- [Logging System](#5.1) — Centralized log management and file persistence.
- [Icon Caching System](#5.2) — Multi-tier app icon storage and retrieval.
- [Tab Configuration System](#5.3) — Tab customization and persistence.
- [Network Diagnostics](#5.4) — DNS checking and connection validation.
- [Background Keep-Alive Services](#5.5) — Audio and location background modes.
- [App Intents and Shortcuts Integration](#5.6) — Siri and Shortcuts support for JIT actions.
- [DebugWidget Extension](#5.7) — Home screen widget and shared app group data.

---

## System Architecture Overview

The supporting infrastructure consists of independent subsystems that provide orthogonal capabilities to the main application. Each subsystem manages its own state and persistence layer while exposing observable properties for UI integration.

### Infrastructure Components Diagram

```mermaid
graph TB
    subgraph "UI_Layer"
        ["ConsoleLogsView"]
        ["InstalledAppsListView"]
        ["SettingsView"]
        ["DeviceInfoView"]
    end
    
    subgraph "Logging_Infrastructure"
        ["LogManager"]
        ["LogManagerBridge"]
        ["SystemLogStream"]
    end
    
    subgraph "Diagnostics_And_Info"
        ["DeviceInfoManager"]
        ["DNSChecker"]
    end
    
    subgraph "Automation_Space"
        ["AppIntentsFramework"]
        ["EnableJITIntent"]
        ["KillProcessIntent"]
    end
    
    subgraph "Background_Services"
        ["BackgroundAudioManager"]
        ["BackgroundLocationManager"]
    end
    
    ["ConsoleLogsView"] --> ["LogManager"]
    ["ConsoleLogsView"] --> ["SystemLogStream"]
    ["LogManagerBridge"] --> ["LogManager"]
    
    ["DeviceInfoView"] --> ["DeviceInfoManager"]
    
    ["EnableJITIntent"] --> ["JITEnableContext"]
    ["KillProcessIntent"] --> ["JITEnableContext"]
    ["AppIntentsFramework"] --> ["EnableJITIntent"]
    
    ["SettingsView"] --> ["BackgroundAudioManager"]
    ["SettingsView"] --> ["BackgroundLocationManager"]
    ["SettingsView"] --> ["DNSChecker"]
```

**Sources:** [StikJIT/Views/ConsoleLogsView.swift:11-32](), [StikJIT/Utilities/LogManager.swift:10-102](), [StikJIT/Utilities/LogManagerBridge.swift:10-32]()

---

## Subsystem Overview

### 5.1 Logging System
The logging system provides centralized log collection and categorization. `LogManager` acts as a singleton that collects logs from Swift, Objective-C, and C layers, storing them in memory for UI display.

**Key Components:**
- **LogManager**: `@Published` observable singleton managing in-memory `LogEntry` objects [StikJIT/Utilities/LogManager.swift:10-13]().
- **LogManagerBridge**: Objective-C wrapper for C/Objective-C FFI integration [StikJIT/Utilities/LogManagerBridge.swift:10-32]().
- **SystemLogStream**: Real-time syslog relay streamer [StikJIT/Views/ConsoleLogsView.swift:14-14]().

Logs are categorized into four types (`info`, `error`, `debug`, `warning`) [StikJIT/Utilities/LogManager.swift:22-27]() and automatically rotate when exceeding 1000 entries [StikJIT/Utilities/LogManager.swift:57-57]().

### 5.2 Icon Caching System
A three-tier caching architecture optimizes app icon loading. Icons are fetched via `JITEnableContext.getAppIcon(withBundleId:)` and cached across memory and disk. This system ensures that the application browser remains responsive even with hundreds of installed apps. For details, see [Icon Caching System](#5.2).

### 5.3 Tab Configuration System
Manages tab visibility and ordering through sanitized identifier persistence. Tab state is stored in `UserDefaults` using comma-separated string serialization. The system distinguishes between "core" IDs that are always allowed and a broader set of selectable tabs (up to 12). For details, see [Tab Configuration System](#5.3).

### 5.4 Network Diagnostics
`DNSChecker` validates network connectivity and Apple service reachability. It performs POSIX `getaddrinfo` lookups for `gs.apple.com` and probes port 62078 (the standard lockdown port) with a 20-second timeout to diagnose connection issues. For details, see [Network Diagnostics](#5.4).

### 5.5 Background Keep-Alive Services
Two background mode managers prevent app suspension:
- **BackgroundAudioManager**: Plays silent audio using `AVAudioEngine` to maintain the process lifecycle.
- **BackgroundLocationManager**: Monitors location updates using `CLLocationManager` to ensure the app remains active.
For details, see [Background Keep-Alive Services](#5.5).

### 5.6 App Intents and Shortcuts Integration
Integrates with the iOS `AppIntents` framework to expose core functionality to Siri and the Shortcuts app.

**Key Entities and Intents:**
- **InstalledAppEntity**: Represents an app on the device.
- **RunningProcessEntity**: Represents a process currently in the process list.
- **EnableJITIntent**: Automates JIT enablement for a specific bundle ID.
- **KillProcessIntent**: Allows programmatically terminating a process.
For details, see [App Intents and Shortcuts Integration](#5.6).

### 5.7 DebugWidget Extension
A home screen widget extension that accesses shared app group data (`group.com.stik.sj`) to display favorites and recent apps. It utilizes a `TimelineProvider` to update widget states. For details, see [DebugWidget Extension](#5.7).

---

## Data Persistence Architecture

Supporting infrastructure uses three persistence mechanisms: `UserDefaults.standard`, app group storage (`group.com.stik.sj`), and the file system.

### Persistence Layer Mapping

```mermaid
graph LR
    subgraph "Standard_UserDefaults"
        ["DefaultScriptName"]
        ["loadAppIconsOnJIT"]
    end
    
    subgraph "App_Group_Container"
        ["recentApps"]
        ["favoriteApps"]
        ["pinnedSystemApps"]
    end
    
    subgraph "Documents_Directory"
        ["idevice_log.txt"]
        ["scripts_folder"]
    end
    
    ["DefaultScriptName"] -.-> |"@AppStorage"| ["ScriptListView"]
    ["recentApps"] -.-> |"Shared_Access"| ["DebugWidget"]
```

**Sources:** [StikJIT/Utilities/LogManager.swift:57-59]()

### Persistence Patterns by Subsystem

| Subsystem | Storage Type | Key/Path | Usage |
|-----------|-------------|----------|-------|
| Logging | Memory | `LogManager.logs` | Real-time console display [StikJIT/Utilities/LogManager.swift:13-13]() |
| App Icons | Disk/Cache | `group.com.stik.sj` | Shared icon storage |
| Tabs | AppStorage | `enabledTabIdentifiers` | UI configuration |

---

## Logging Architecture

The logging system bridges Swift and Objective-C components through a centralized singleton with published properties for SwiftUI observation.

### Log Flow Diagram

```mermaid
graph TB
    subgraph "Log_Sources"
        ["Swift_Caller"]
        ["ObjC_LogManagerBridge"]
    end
    
    subgraph "LogManager_Logic"
        ["addLog_Function"]
        ["redundantPrefixes_Filter"]
        ["MemoryCapping_1000"]
    end
    
    subgraph "UI_Display"
        ["ConsoleLogsView_jitLogsPane"]
    end
    
    ["Swift_Caller"] --> ["addLog_Function"]
    ["ObjC_LogManagerBridge"] --> ["addLog_Function"]
    ["addLog_Function"] --> ["redundantPrefixes_Filter"]
    ["redundantPrefixes_Filter"] --> ["MemoryCapping_1000"]
    ["MemoryCapping_1000"] --> ["ConsoleLogsView_jitLogsPane"]
```

**Sources:** [StikJIT/Utilities/LogManager.swift:49-64](), [StikJIT/Utilities/LogManagerBridge.swift:10-32](), [StikJIT/Views/ConsoleLogsView.swift:121-161]()

### Log Management Logic
- **Redundant Prefix Stripping**: `LogManager` removes common prefixes like "INFO: " or "ERR: " to keep the UI clean [StikJIT/Utilities/LogManager.swift:50-52]().
- **Memory Capping**: The system maintains a maximum of 1000 entries, purging the oldest 100 when the limit is reached to prevent memory pressure [StikJIT/Utilities/LogManager.swift:57-57]().
- **Thread Safety**: Log updates are dispatched to the main queue for UI safety [StikJIT/Utilities/LogManager.swift:54-54]().

**Sources:** [StikJIT/Utilities/LogManager.swift:37-59]()