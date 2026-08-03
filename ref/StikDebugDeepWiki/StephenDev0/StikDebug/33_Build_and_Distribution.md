# Build and Distribution

<details>
<summary>Relevant source files</summary>

The following files were used as context for generating this wiki page:

- [.github/ISSUE_TEMPLATE/bug_report.yml](.github/ISSUE_TEMPLATE/bug_report.yml)
- [.github/ISSUE_TEMPLATE/feature_request.yml](.github/ISSUE_TEMPLATE/feature_request.yml)
- [.github/pull_request_template.md](.github/pull_request_template.md)
- [.github/workflows/build_ipa.yml](.github/workflows/build_ipa.yml)
- [StikDebug.xcodeproj/project.pbxproj](StikDebug.xcodeproj/project.pbxproj)
- [StikDebug.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved](StikDebug.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved)

</details>



This page provides a high-level overview of the StikDebug build system, project structure, and automated distribution pipelines. StikDebug utilizes a modern Xcode configuration combined with GitHub Actions to provide continuous delivery of unsigned IPAs suitable for sideloading and JIT enablement on iOS 17.4+.

---

## Project Configuration

The StikDebug codebase is organized into a single Xcode project with multiple targets catering to the main application, system extensions, and testing suites.

*   **Targets:** The project defines the primary `StikDebug` application target (internally named `StikJIT`), the `StikDebugTests` unit test bundle, and the `StikDebugUITests` UI test bundle. [StikDebug.xcodeproj/project.pbxproj:143-167](), [StikDebug.xcodeproj/project.pbxproj:168-190](), [StikDebug.xcodeproj/project.pbxproj:47-49]()
*   **Build Settings:** The project targets iOS 17.4+ and utilizes Swift 5 for its mixed-language core, integrating the `idevice` xcframework via custom search paths. [.github/workflows/build_ipa.yml:43-43]()
*   **Entitlements:** Security and capability definitions are managed via `StikJIT.entitlements`, which includes the necessary keys for JIT enablement and app group communication (`group.com.stik.sj`).
*   **Localization:** The application supports English (`en`), Spanish (`es`), and Italian (`it`) for a localized user experience.

For details on targets, build settings, and localization, see [Project Configuration](#6.1).

---

## Swift Package Dependencies

StikDebug leverages the Swift Package Manager (SPM) to integrate external libraries, primarily focusing on the script editor's UI and text manipulation capabilities.

| Package | Role | Source |
| :--- | :--- | :--- |
| `CodeEditorView` | Provides the core code editor UI component for script editing. | [StikDebug.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved:5-12]() |
| `LanguageSupport` | Adds syntax highlighting and language-specific features to the editor. | [StikDebug.xcodeproj/project.pbxproj:162-162]() |
| `Rearrange` | Manages text range transformations and efficient updates in the editor. | [StikDebug.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved:14-21]() |

For details on package roles and version pinning, see [Swift Package Dependencies](#6.2).

---

## CI/CD Pipeline

The project uses GitHub Actions to automate the build and release process, ensuring that the latest code is always available as a functional artifact for testing and distribution.

*   **Build Workflow (`build_ipa.yml`):** Automatically triggers on pushes to `main` and `semi-rewrite` branches. It uses Xcode 26.0.1 on `macos-latest` to generate a `StikDebug.xcarchive`. [.github/workflows/build_ipa.yml:1-35]()
*   **Unsigned Packaging:** Because the app is intended for sideloading via tools like SideStore, the CI pipeline explicitly disables code signing (`CODE_SIGNING_ALLOWED=NO`, `CODE_SIGNING_REQUIRED=NO`) and manually packages the `.app` into a `.ipa` via a `Payload/` directory. [.github/workflows/build_ipa.yml:39-51]()
*   **Artifact Retention:** Generated IPAs are stored as workflow artifacts for 90 days. [.github/workflows/build_ipa.yml:55-59]()

For details on the automation scripts and environment configuration, see [CI/CD Pipeline](#6.3).

---

## Distribution and Updates

StikDebug is distributed through community-driven methods compatible with AltStore and SideStore repositories.

*   **Repository Metadata:** The `updatesource.yml` workflow automates the synchronization of `repo.json` whenever a new release is published.
*   **Update Script:** A Python script (`update_json.py`) handles the extraction of release metadata (version, size, download URL) to update the app record in the repository.
*   **Nightly Builds:** Rolling releases are tagged as `Nightly` to provide users with the most recent features and bug fixes directly from the `main` branch. [.github/workflows/build_ipa.yml:68-73]()
*   **Version Extraction:** The CI pipeline automatically extracts the `MARKETING_VERSION` from the project file to label releases. [.github/workflows/build_ipa.yml:61-66]()

For details on the `repo.json` format, `StikJIT.json` app records, and update automation, see [Distribution and Updates](#6.4).

---

## Build System Mapping

The following diagrams bridge the high-level build concepts to the specific entities found in the project configuration and CI scripts.

### Build Pipeline Entity Map
Title: "Build Pipeline Entity Map"
```mermaid
graph LR
    subgraph "Xcode_Project_Space"
        [PBX_StikDebug.xcodeproj]
        [T_StikDebug]
        [T_StikDebugTests]
        [DEP_Package.resolved]
    end

    subgraph "CI_CD_Space"
        [W_build_ipa.yml]
        [W_updatesource.yml]
        [PY_update_json.py]
    end

    subgraph "Distribution_Space"
        [IPA_StikDebug.ipa]
        [REPO_repo.json]
        [TAG_Nightly]
    end

    [PBX_StikDebug.xcodeproj] --> [T_StikDebug]
    [PBX_StikDebug.xcodeproj] --> [T_StikDebugTests]
    [DEP_Package.resolved] --> [T_StikDebug]
    
    [W_build_ipa.yml] -- "xcodebuild_archive" --> [T_StikDebug]
    [W_build_ipa.yml] -- "zip_Payload" --> [IPA_StikDebug.ipa]
    [W_build_ipa.yml] -- "gh-release" --> [TAG_Nightly]
    
    [W_updatesource.yml] -- "executes" --> [PY_update_json.py]
    [PY_update_json.py] -- "updates" --> [REPO_repo.json]
    [IPA_StikDebug.ipa] -- "metadata_in" --> [REPO_repo.json]
```
Sources: [StikDebug.xcodeproj/project.pbxproj:143-167](), [.github/workflows/build_ipa.yml:29-51]()

### Target and Dependency Association
Title: "Target and Dependency Association"
```mermaid
graph TD
    subgraph "Application_Targets"
        [MAIN_StikDebug]
        [TEST_StikDebugTests]
    end

    subgraph "SPM_Dependencies"
        [CEV_CodeEditorView]
        [LS_LanguageSupport]
        [RE_Rearrange]
    end

    subgraph "Frameworks"
        [WK_WidgetKit.framework]
        [SI_SwiftUI.framework]
    end

    [MAIN_StikDebug] --> [CEV_CodeEditorView]
    [MAIN_StikDebug] --> [LS_LanguageSupport]
    [CEV_CodeEditorView] --> [RE_Rearrange]
    
    [MAIN_StikDebug] --> [WK_WidgetKit.framework]
    [MAIN_StikDebug] --> [SI_SwiftUI.framework]
    [TEST_StikDebugTests] --> [MAIN_StikDebug]
```
Sources: [StikDebug.xcodeproj/project.pbxproj:160-163](), [StikDebug.xcodeproj/project.pbxproj:45-46](), [StikDebug.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved:3-21]()

---

**Sources:**
- [StikDebug.xcodeproj/project.pbxproj:1-205]()
- [.github/workflows/build_ipa.yml:1-81]()
- [StikDebug.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved:1-24]()