# Swift Package Dependencies

<details>
<summary>Relevant source files</summary>

The following files were used as context for generating this wiki page:

- [StikDebug.xcodeproj/project.pbxproj](StikDebug.xcodeproj/project.pbxproj)
- [StikDebug.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved](StikDebug.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved)

</details>



This page documents the Swift Package Manager (SPM) dependencies used in StikDebug: which packages are declared, which products are consumed, how they are resolved, and where they are used in the source. This page is limited to external SPM packages. For information about the native static library (`libidevice_ffi.a`) and the C FFI layer, see [Native Bridging and FFI Layer](). For the overall build target structure, see [Project Configuration]().

---

## Overview

StikDebug declares a single remote SPM package reference. That one package exposes two products that are both linked into the main application target. A transitive dependency is also pinned in the resolved file.

**Package dependency overview diagram:**

```mermaid
graph TD
  ["StikDebug (main target)"] -- "packageProductDependencies" --> ["Product: CodeEditorView"]
  ["StikDebug (main target)"] -- "packageProductDependencies" --> ["Product: LanguageSupport"]
  
  subgraph "XCRemoteSwiftPackageReference"
    ["CodeEditorView Package"]
  end

  ["Product: CodeEditorView"] -- "from package" --> ["CodeEditorView Package"]
  ["Product: LanguageSupport"] -- "from package" --> ["CodeEditorView Package"]
  
  ["CodeEditorView Package"] -- "depends on" --> ["Transitive Dep: Rearrange"]

  ["ScriptEditorView.swift"] -- "import CodeEditorView" --> ["Product: CodeEditorView"]
  ["ScriptEditorView.swift"] -- "import LanguageSupport" --> ["Product: LanguageSupport"]
```

Sources: [StikDebug.xcodeproj/project.pbxproj:160-163](), [StikDebug.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved:1-24](), [StikJIT/JSSupport/ScriptEditorView.swift:1-11]()

---

## Declared Package Reference

There is exactly one `XCRemoteSwiftPackageReference` in the project:

| Field | Value |
|---|---|
| Repository URL | `https://github.com/mchakravarty/CodeEditorView` |
| Requirement kind | `upToNextMajorVersion` |
| Minimum version | `0.15.4` |

This package is identified in the project file and linked to the `StikDebug` native target.

Sources: [StikDebug.xcodeproj/project.pbxproj:160-163](), [StikDebug.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved:7-11]()

---

## Resolved Pins

The resolved versions are pinned in `Package.resolved` (format version 3):

| Identity | Kind | Repository | Pinned Version | Revision |
|---|---|---|---|---|
| `codeeditorview` | `remoteSourceControl` | `github.com/mchakravarty/CodeEditorView` | `0.15.4` | `aba6c189bb2f6fd9d7b8e9f5739aeb3c8c7e3254` |
| `rearrange` | `remoteSourceControl` | `github.com/ChimeHQ/Rearrange.git` | `1.8.1` | `5ff7f3363f7a08f77e0d761e38e6add31c2136e1` |

`Rearrange` is not declared directly by StikDebug. It appears solely because `CodeEditorView` depends on it. StikDebug source code does not import `Rearrange` directly.

Sources: [StikDebug.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved:1-24]()

---

## Product Dependencies and Build Phases

The `CodeEditorView` package exposes two products that are each registered as `XCSwiftPackageProductDependency` entries and linked in the main target's `PBXFrameworksBuildPhase`.

**Product-to-build-phase mapping:**

```mermaid
graph LR
  subgraph "XCSwiftPackageProductDependency"
    ["CodeEditorView"]
    ["LanguageSupport"]
  end

  subgraph "PBXFrameworksBuildPhase (StikDebug)"
    ["CodeEditorView in Frameworks"]
    ["LanguageSupport in Frameworks"]
  end

  ["CodeEditorView"] --> ["CodeEditorView in Frameworks"]
  ["LanguageSupport"] --> ["LanguageSupport in Frameworks"]
```

Both products resolve to the same upstream `XCRemoteSwiftPackageReference`.

The `StikDebugTests` and `StikDebugUITests` targets have empty `packageProductDependencies` arrays; neither test target imports these packages.

Sources: [StikDebug.xcodeproj/project.pbxproj:10-11](), [StikDebug.xcodeproj/project.pbxproj:83-92](), [StikDebug.xcodeproj/project.pbxproj:160-163](), [StikDebug.xcodeproj/project.pbxproj:185-186]()

---

## Usage in Source Code

The only file that imports these packages is `ScriptEditorView.swift`.

**Code Entity Mapping: ScriptEditorView Integration**

```mermaid
graph TD
  ["ScriptEditorView (ScriptEditorView.swift)"] -- "uses" --> ["CodeEditor (struct)"]
  ["ScriptEditorView (ScriptEditorView.swift)"] -- "uses" --> ["CodeEditor.Position (struct)"]
  ["ScriptEditorView (ScriptEditorView.swift)"] -- "uses" --> ["TextLocated<Message> (type)"]
  ["ScriptEditorView (ScriptEditorView.swift)"] -- "uses" --> ["Theme (Theme.defaultDark/Light)"]
  ["ScriptEditorView (ScriptEditorView.swift)"] -- "sets" --> [".codeEditorTheme (EnvironmentKey)"]
  ["ScriptEditorView (ScriptEditorView.swift)"] -- "imports" --> ["LanguageSupport (Language enum)"]
  ["CodeEditor (struct)"] -- "language: param" --> [".none (Language value)"]
```

### Key API surface consumed

| Symbol | Product | Role in `ScriptEditorView` |
|---|---|---|
| `CodeEditor` | `CodeEditorView` | Main SwiftUI view for text editing |
| `CodeEditor.Position` | `CodeEditorView` | Tracks cursor/scroll position as `@State` |
| `TextLocated<Message>` | `CodeEditorView` | `Set` of inline editor messages/diagnostics as `@State` |
| `Theme` | `CodeEditorView` | Editor color theme; `Theme.defaultDark` / `Theme.defaultLight` selected by `colorScheme` |
| `.codeEditorTheme` | `CodeEditorView` | SwiftUI `EnvironmentKey` used to inject the active `Theme` |
| `Language` / `.none` | `LanguageSupport` | Syntax language passed to `CodeEditor`; `.none` means no syntax highlighting |

`ScriptEditorView` is reached from `ScriptListView` via a `NavigationLink` when a script row is tapped in non-picker mode. For a description of the full script management flow, see [Script Management]().

Sources: [StikJIT/JSSupport/ScriptEditorView.swift:1-11](), [StikJIT/JSSupport/ScriptListView.swift:187-198]()

---

## Dependency Graph Summary

```mermaid
graph TD
  ["StikDebug.app (target: StikDebug)"] -- "links: CodeEditorView product" --> ["CodeEditorView package v0.15.4"]
  ["StikDebug.app (target: StikDebug)"] -- "links: LanguageSupport product" --> ["CodeEditorView package v0.15.4"]
  ["CodeEditorView package v0.15.4"] -- "depends on" --> ["Rearrange package v1.8.1"]

  ["StikJIT/JSSupport/ScriptEditorView.swift"] -- "import CodeEditorView" --> ["CodeEditorView package v0.15.4"]
  ["StikJIT/JSSupport/ScriptEditorView.swift"] -- "import LanguageSupport" --> ["CodeEditorView package v0.15.4"]
```

Sources: [StikDebug.xcodeproj/project.pbxproj:160-163](), [StikDebug.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved:1-24](), [StikJIT/JSSupport/ScriptEditorView.swift:1-11]()