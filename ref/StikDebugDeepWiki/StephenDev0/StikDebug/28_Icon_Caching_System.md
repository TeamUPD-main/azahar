# Icon Caching System

<details>
<summary>Relevant source files</summary>

The following files were used as context for generating this wiki page:

- [StikJIT/JSSupport/ScriptListView.swift](StikJIT/JSSupport/ScriptListView.swift)
- [StikJIT/Utilities/AppStoreIconFetcher.swift](StikJIT/Utilities/AppStoreIconFetcher.swift)
- [StikJIT/Views/InstalledAppsListView.swift](StikJIT/Views/InstalledAppsListView.swift)

</details>



## Purpose and Scope

The Icon Caching System implements a three-tier caching strategy for application icons displayed in the application browser. It optimizes icon loading performance through memory caching, disk persistence, and network fetching with concurrency control and intelligent prefetching. This system ensures smooth scrolling in app lists while minimizing redundant network requests and memory overhead.

For application list management and filtering logic, see [Application Browser](2.4). For the underlying application management API that retrieves app metadata, see [Application Management API](4.3).

---

## Architecture Overview

The icon caching system consists of four primary components that work together to provide efficient icon retrieval and display.

```mermaid
graph TB
    subgraph UILayer["UI Layer"]
        AppButton["AppButton<br/>@StateObject iconLoader"]
        LaunchAppRow["LaunchAppRow<br/>@StateObject iconLoader"]
        IconLoader["IconLoader<br/>@MainActor ObservableObject<br/>@Published image: UIImage?"]
    end
    
    subgraph CachingInfra["Caching Infrastructure"]
        AppIconRepository["AppIconRepository<br/>enum<br/>static memory: NSCache<br/>static diskQueue: DispatchQueue"]
        MemoryCache["memory.object(forKey:)<br/>NSCache<NSString, UIImage><br/>countLimit: 2000<br/>totalCostLimit: 64MB"]
        DiskStorage["iconURL(bundleID) -> URL?<br/>group.com.stik.sj/icons/<br/>{bundleID}.png"]
        NetworkFetch["AppStoreIconFetcher.getIcon()"]
    end
    
    subgraph ConcurrencyControl["Concurrency Control"]
        Registry["static registry<br/>IconFetchRegistry actor<br/>task(for:create:)"]
        Semaphore["static fetchSemaphore<br/>AsyncSemaphore actor<br/>permits: 4"]
    end
    
    AppButton --> IconLoader
    LaunchAppRow --> IconLoader
    IconLoader -->|"await AppIconRepository.image(for:)"| AppIconRepository
    
    AppIconRepository -->|"cachedImage(for:)"| MemoryCache
    AppIconRepository -->|"loadFromDisk(bundleID:)"| DiskStorage
    AppIconRepository -->|"fetchFromSource(bundleID:)"| NetworkFetch
    
    AppIconRepository -->|"registry.task(for:)"| Registry
    AppIconRepository -->|"fetchSemaphore.acquire()"| Semaphore
    
    Registry -->|"Task deduplication"| NetworkFetch
    Semaphore -->|"Rate limiting"| NetworkFetch
```

**Sources:** [StikJIT/Views/InstalledAppsListView.swift:887-1038](), [StikJIT/Views/InstalledAppsListView.swift:1040-1075](), [StikJIT/Views/InstalledAppsListView.swift:842-857](), [StikJIT/Views/InstalledAppsListView.swift:859-885]()

---

## Three-Tier Caching Strategy

The system employs a hierarchical caching approach with increasing latency at each tier.

### Tier 1: Memory Cache (NSCache)

The first tier uses `NSCache` for fast in-memory lookups with automatic eviction under memory pressure.

| Property | Value |
|----------|-------|
| Type | `NSCache<NSString, UIImage>` |
| Count Limit | 2000 icons |
| Total Cost Limit | 64 MB |
| Cost Calculation | `width * height * 4` bytes per pixel |

```mermaid
graph LR
    Request["image(for: bundleID)"]
    MemCheck{"Memory<br/>Cache Hit?"}
    Return["Return UIImage"]
    
    Request --> MemCheck
    MemCheck -->|"Yes"| Return
    MemCheck -->|"No"| NextTier["Check Disk Tier"]
    
    Return -.->|"Cost-based<br/>Eviction"| MemCheck
```

**Implementation:** [StikJIT/Views/InstalledAppsListView.swift:888-893]()

**Sources:** [StikJIT/Views/InstalledAppsListView.swift:888-893](), [StikJIT/Views/InstalledAppsListView.swift:900-902](), [StikJIT/Views/InstalledAppsListView.swift:1026-1030]()

### Tier 2: Disk Storage

Icons are persisted to the shared app group container at `group.com.stik.sj/icons/{bundleID}.png`.

```mermaid
graph TB
    DiskCheck{"Disk<br/>File Exists?"}
    LoadFile["Load PNG Data<br/>from Disk"]
    DecodeImage["Decode UIImage<br/>with Screen Scale"]
    PrepareDisplay["prepareForDisplay()"]
    StoreMemory["Store in<br/>Memory Cache"]
    Return["Return UIImage"]
    InvalidFile["Remove<br/>Corrupt File"]
    
    DiskCheck -->|"Yes"| LoadFile
    DiskCheck -->|"No"| NextTier["Fetch from Network"]
    LoadFile -->|"Success"| DecodeImage
    LoadFile -->|"Failure"| InvalidFile
    DecodeImage -->|"Success"| PrepareDisplay
    DecodeImage -->|"Failure"| InvalidFile
    PrepareDisplay --> StoreMemory
    StoreMemory --> Return
    InvalidFile --> NextTier
```

**Disk Operations:** All disk I/O occurs on a dedicated serial queue (`com.stik.iconcache.disk`) with QoS `.utility` to avoid blocking the main thread.

**Sources:** [StikJIT/Views/InstalledAppsListView.swift:969-990](), [StikJIT/Views/InstalledAppsListView.swift:1001-1011](), [StikJIT/Views/InstalledAppsListView.swift:1013-1024]()

### Tier 3: Network Fetch

When no cached icon exists, the system fetches from `AppStoreIconFetcher` with concurrency controls. Note that `AppStoreIconFetcher` internally uses `JITEnableContext.shared.getAppIcon(withBundleId:)` to interface with the native device management layer.

| Control Mechanism | Implementation | Limit |
|-------------------|----------------|-------|
| Rate Limiting | `AsyncSemaphore` | 4 concurrent fetches |
| Deduplication | `IconFetchRegistry` | 1 task per bundle ID |
| Priority | `Task.detached(priority:)` | `.utility` |

**Sources:** [StikJIT/Views/InstalledAppsListView.swift:939-959](), [StikJIT/Views/InstalledAppsListView.swift:961-967](), [StikJIT/Views/InstalledAppsListView.swift:896](), [StikJIT/Utilities/AppStoreIconFetcher.swift:11-31]()

---

## Core Components

### AppIconRepository

A static enum providing the primary API for icon retrieval and cache management.

```mermaid
classDiagram
    class AppIconRepository {
        <<enum>>
        +cachedImage(for: String) UIImage?
        +image(for: String) async UIImage?
        +prefetch(bundleIDs: [String]) void
        +removeFromCache(bundleIDs: [String]) void
        -fetchAndStore(bundleID: String) async UIImage?
        -loadFromDisk(bundleID: String) async UIImage?
        -store(UIImage, for: String) void
        -iconURL(for: String) URL?
        -prepareForDisplay(UIImage) UIImage
    }
    
    class NSCache {
        memory: NSCache~NSString, UIImage~
        countLimit = 2000
        totalCostLimit = 64MB
    }
    
    class DispatchQueue {
        diskQueue: DispatchQueue
        label = "com.stik.iconcache.disk"
        qos = .utility
    }
    
    class AsyncSemaphore {
        fetchSemaphore: AsyncSemaphore
        permits = 4
    }
    
    class IconFetchRegistry {
        registry: IconFetchRegistry
    }
    
    AppIconRepository --> NSCache
    AppIconRepository --> DispatchQueue
    AppIconRepository --> AsyncSemaphore
    AppIconRepository --> IconFetchRegistry
```

**Key Methods:**

- `cachedImage(for:)` - Synchronous memory-only lookup [StikJIT/Views/InstalledAppsListView.swift:900-902]()
- `image(for:)` - Async retrieval through all tiers [StikJIT/Views/InstalledAppsListView.swift:904-915]()
- `prefetch(bundleIDs:)` - Background loading for anticipated icons [StikJIT/Views/InstalledAppsListView.swift:917-924]()
- `removeFromCache(bundleIDs:)` - Eviction from both memory and disk [StikJIT/Views/InstalledAppsListView.swift:926-937]()

**Sources:** [StikJIT/Views/InstalledAppsListView.swift:887-1038]()

### IconLoader

A `@MainActor` `ObservableObject` that integrates with SwiftUI views to reactively load and display icons.

```mermaid
sequenceDiagram
    participant View as "AppButton/LaunchAppRow"
    participant Loader as "IconLoader"
    participant Repo as "AppIconRepository"
    
    View->>Loader: init(bundleID:)
    Loader->>Repo: cachedImage(for:)
    alt Already Cached
        Repo-->>Loader: UIImage
        Loader->>Loader: Set @Published image
        Note over Loader: didStart = true
    else Not Cached
        Loader->>Loader: image = nil
        Note over Loader: didStart = false
    end
    
    View->>Loader: .onAppear { beginLoading() }
    alt image == nil && !didStart
        Loader->>Repo: Task { await image(for:) }
        Repo-->>Loader: UIImage?
        Loader->>Loader: withAnimation { image = ... }
    end
```

**Properties:**
- `@Published image: UIImage?` - Observed by SwiftUI for view updates [StikJIT/Views/InstalledAppsListView.swift:1042]()
- `bundleID: String` - Identifier for the target icon [StikJIT/Views/InstalledAppsListView.swift:1044]()
- `didStart: Bool` - Prevents redundant fetch attempts [StikJIT/Views/InstalledAppsListView.swift:1045]()

**Sources:** [StikJIT/Views/InstalledAppsListView.swift:1040-1075]()

### IconFetchRegistry

An `actor` that deduplicates concurrent fetch requests for the same bundle ID.

```mermaid
stateDiagram-v2
    [*] --> NoTask: "First Request for bundleID"
    NoTask --> TaskCreated: "task(for: bundleID, create: closure)"
    TaskCreated --> TaskRunning: "Task<UIImage?, Never> executing"
    TaskRunning --> [*]: "clear(bundleID:)"
    
    TaskRunning --> TaskRunning: "Subsequent Requests<br/>Return Existing Task"
    
    note right of TaskRunning
        tasks[bundleID] stores active Task
        Multiple callers await same instance
    end note
```

**Implementation Details:**

| Property | Type | Purpose |
|----------|------|---------|
| `tasks` | `[String: Task<UIImage?, Never>]` | Stores active fetch tasks by bundle ID [StikJIT/Views/InstalledAppsListView.swift:843]() |
| `task(for:create:)` | `func` | Returns existing task or creates new one [StikJIT/Views/InstalledAppsListView.swift:845-852]() |
| `clear(bundleID:)` | `func` | Removes task entry after completion [StikJIT/Views/InstalledAppsListView.swift:854-856]() |

**Sources:** [StikJIT/Views/InstalledAppsListView.swift:842-857](), [StikJIT/Views/InstalledAppsListView.swift:940-958]()

### AsyncSemaphore

An `actor` implementing a counting semaphore to limit concurrent network fetches.

| Property/Operation | Type/Behavior |
|-------------------|---------------|
| `permits` | `Int` - Available permits count [StikJIT/Views/InstalledAppsListView.swift:860]() |
| `waiters` | `[CheckedContinuation<Void, Never>]` - Queue of suspended tasks [StikJIT/Views/InstalledAppsListView.swift:861]() |
| `acquire()` | Decrements permits; suspends via continuation if none available [StikJIT/Views/InstalledAppsListView.swift:868-877]() |
| `release()` | Resumes first waiter or increments permits [StikJIT/Views/InstalledAppsListView.swift:879-884]() |
| Initial Permits | `4` |

**Sources:** [StikJIT/Views/InstalledAppsListView.swift:859-885](), [StikJIT/Views/InstalledAppsListView.swift:896](), [StikJIT/Views/InstalledAppsListView.swift:942](), [StikJIT/Views/InstalledAppsListView.swift:953]()

---

## Prefetching Mechanism

The system implements intelligent prefetching to preload icons for apps likely to be viewed.

### Priority Order

Icons are prefetched in the following order with a default limit of 32 bundles:

```mermaid
graph LR
    Favorites["1. favoriteApps<br/>@AppStorage array"]
    Recents["2. recentApps<br/>@AppStorage array"]
    PinnedSystem["3. pinnedSystemApps<br/>@AppStorage array"]
    Debuggable["4. debuggableSortedApps<br/>viewModel.debuggableApps sorted"]
    Launch["5. sortedLaunchApps<br/>combinedLaunchApps sorted"]
    
    Favorites --> Recents
    Recents --> PinnedSystem
    PinnedSystem --> Debuggable
    Debuggable --> Launch
    
    Launch --> Limit["limit: Int = 32<br/>Default parameter"]
```

**Sources:** [StikJIT/Views/InstalledAppsListView.swift:252-278]()

### Trigger Points

Prefetching occurs automatically when:

| Event | Code Location |
|-------|---------------|
| View appears | `.onAppear { prefetchPriorityIcons() }` [StikJIT/Views/InstalledAppsListView.swift:229]() |
| Favorites change | `.onChange(of: favoriteApps)` [StikJIT/Views/InstalledAppsListView.swift:233]() |
| Recents change | `.onChange(of: recentApps)` [StikJIT/Views/InstalledAppsListView.swift:236]() |
| Loading completes | `.onChange(of: viewModel.isLoading) { _, false }` [StikJIT/Views/InstalledAppsListView.swift:239-241]() |
| Tab switches | `.onChange(of: selectedTab)` [StikJIT/Views/InstalledAppsListView.swift:243]() |
| Pinned apps change | `.onChange(of: pinnedSystemApps)` [StikJIT/Views/InstalledAppsListView.swift:246]() |

**Sources:** [StikJIT/Views/InstalledAppsListView.swift:228-247]()

---

## Integration with UI Components

### AppButton Integration

The `AppButton` view displays debuggable apps with JIT enablement functionality.

**Icon Rendering Logic:**

| Condition | Rendered Output |
|-----------|----------------|
| `loadAppIconsOnJIT == true && iconLoader.image != nil` | `Image(uiImage:)` 54×54 with `RoundedRectangle(cornerRadius: 12)` and shadow [StikJIT/Views/InstalledAppsListView.swift:650-657]() |
| Otherwise | `RoundedRectangle` gray placeholder with `Image(systemName: "app")` [StikJIT/Views/InstalledAppsListView.swift:659-668]() |

**Sources:** [StikJIT/Views/InstalledAppsListView.swift:514-733](), [StikJIT/Views/InstalledAppsListView.swift:548](), [StikJIT/Views/InstalledAppsListView.swift:630-639](), [StikJIT/Views/InstalledAppsListView.swift:647-669]()

### LaunchAppRow Integration

The `LaunchAppRow` view displays non-debuggable apps for launching without debug attachment.

**Identical Loading Pattern:**

| Step | AppButton | LaunchAppRow | Line References |
|------|-----------|--------------|-----------------|
| Init IconLoader | `StateObject(wrappedValue: IconLoader(bundleID:))` | Identical | 548, 761 |
| Check Setting | `@AppStorage("loadAppIconsOnJIT")` | Identical | 521, 742 |
| Trigger Load | `.onAppear { iconLoader.beginLoading() }` | Identical | 631-638, 801-810 |
| Render | `iconView` computed property | Identical | 647-669, 816-838 |

**Sources:** [StikJIT/Views/InstalledAppsListView.swift:737-840](), [StikJIT/Views/InstalledAppsListView.swift:761](), [StikJIT/Views/InstalledAppsListView.swift:801-810](), [StikJIT/Views/InstalledAppsListView.swift:816-838]()

---

## Configuration and Tuning

### Cache Limits

| Parameter | Location | Value | Rationale |
|-----------|----------|-------|-----------|
| Memory Count Limit | `NSCache.countLimit` | 2000 | Covers large app libraries [StikJIT/Views/InstalledAppsListView.swift:890]() |
| Memory Cost Limit | `NSCache.totalCostLimit` | 64 MB | Balances memory usage [StikJIT/Views/InstalledAppsListView.swift:891]() |
| Concurrent Fetches | `AsyncSemaphore(permits:)` | 4 | Prevents network saturation [StikJIT/Views/InstalledAppsListView.swift:896]() |
| Prefetch Limit | `prefetchPriorityIcons(limit:)` | 32 | Balances preload vs memory [StikJIT/Views/InstalledAppsListView.swift:252]() |

**Sources:** [StikJIT/Views/InstalledAppsListView.swift:890-891](), [StikJIT/Views/InstalledAppsListView.swift:896](), [StikJIT/Views/InstalledAppsListView.swift:252]()

### Disk Storage Location

Icons are stored in the shared app group container for potential widget access:

```
group.com.stik.sj/icons/{bundleID}.png
```

| Property | Value | Location |
|----------|-------|----------|
| App Group ID | `"group.com.stik.sj"` | [StikJIT/Views/InstalledAppsListView.swift:898]() |
| Subdirectory | `"icons"` | [StikJIT/Views/InstalledAppsListView.swift:1017]() |
| File Format | PNG (lossless) | [StikJIT/Views/InstalledAppsListView.swift:1023]() |

**Sources:** [StikJIT/Views/InstalledAppsListView.swift:898](), [StikJIT/Views/InstalledAppsListView.swift:1013-1024]()

---

## Image Preparation

The system uses iOS 15+ `preparingForDisplay()` to decode images on a background thread before display, preventing main thread stalls during scrolling.

**Implementation:**

```swift
// Line 1032-1037: prepareForDisplay(_:) method
private static func prepareForDisplay(_ image: UIImage) -> UIImage {
    if #available(iOS 15.0, *) {
        return image.preparingForDisplay() ?? image
    }
    return image
}
```

**Call Sites:**

| Location | Context | Purpose |
|----------|---------|---------|
| [StikJIT/Views/InstalledAppsListView.swift:946]() | `fetchAndStore(bundleID:)` | Prepare fetched image before storage |
| [StikJIT/Views/InstalledAppsListView.swift:987]() | `loadFromDisk(bundleID:)` | Prepare disk-loaded image before return |

**Sources:** [StikJIT/Views/InstalledAppsListView.swift:946](), [StikJIT/Views/InstalledAppsListView.swift:987](), [StikJIT/Views/InstalledAppsListView.swift:1032-1037]()

---

## Cache Eviction

### Automatic Eviction

`NSCache` automatically evicts entries under memory pressure based on:
- Total cost exceeding `totalCostLimit` (64 MB)
- Count exceeding `countLimit` (2000 icons)

### Manual Eviction

The `removeFromCache(bundleIDs:)` method explicitly removes icons from both memory and disk:

```mermaid
graph TB
    Call["removeFromCache(bundleIDs:)"]
    MemoryLoop["For each bundleID"]
    RemoveMem["memory.removeObject()"]
    DiskQueue["diskQueue.async"]
    RemoveDisk["FileManager.removeItem()"]
    
    Call --> MemoryLoop
    MemoryLoop --> RemoveMem
    RemoveMem --> DiskQueue
    DiskQueue --> RemoveDisk
```

**Use Case:** Called when apps are uninstalled or when clearing cache storage.

**Sources:** [StikJIT/Views/InstalledAppsListView.swift:926-937]()