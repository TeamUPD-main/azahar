# AGENTS.md

Azahar, a 3DS emulator forked from Citra (merged PabloMK7's Citra fork + Lime3DS). C++20, CMake >=3.25. Internal identifiers still say `citra` (CMake `project(citra)`, `src/citra_*` dirs) while the product is `azahar`.

## Build

- All 36 git submodules are required; CMake configure hard-fails if any is missing. This checkout currently has them uninitialized — run `git submodule update --init --recursive` before any build.
- Defaults: Release build type if unset, LTO on for non-MSVC Release, PCH on (`CITRA_USE_PRECOMPILED_HEADERS`), warnings-as-errors ON (`CITRA_WARNINGS_AS_ERRORS`). Code must compile warning-free. Qt 6.9.3 is auto-downloaded via aqt unless `USE_SYSTEM_QT` is set.
- Typical flow (matches `.ci/linux.sh`):
  ```
  cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=Release
  cmake --build build
  ```
- Binaries land in `build/bin/Release/`: `azahar` (Qt GUI, target `citra_meta`), `azahar-room` (`citra_room_standalone`), `azahar_libretro`.
- Android is a separate Gradle build under `src/android/` (`./gradlew assembleVanillaRelease` / `assembleGooglePlayRelease`); don't route it through the desktop CMake flow.
- CI build environment is the Docker image `opensauce04/azahar-build-environment:latest`; get a matching dev shell with `tools/enter-docker-dev-container.sh`.

## Tests

- Catch2 suite, one `tests` executable built from `src/tests/CMakeLists.txt`.
  ```
  ctest --test-dir build -VV -C Release      # or run build/bin/Release/tests directly
  ```
- `catch_discover_tests` registers each case, so Catch2 filters work, e.g. `tests "[core]"`.

## Formatting / style (CI-enforced)

- No tabs, no trailing whitespace in `src/` and root-level files. CMake installs a pre-commit hook (`hooks/pre-commit`) enforcing this; bypass with `git commit --no-verify`.
- clang-format-15 with `src/.clang-format`: `cmake --build build --target clang-format`, or `clang-format -i` on touched files (CI check: `.ci/clang-format.sh`).
- Every changed `.cpp/.h/.kt/.kts/.m/.mm` must start with the exact header (CI enforces via `.ci/license-header.rb`):
  ```
  // Copyright Citra Emulator Project / Azahar Emulator Project
  // Licensed under GPLv2 or any later version
  // Refer to the license.txt file included.
  ```
- Kotlin: ktlint via `tools/check-kotlin-formatting.sh` / `tools/fix-kotlin-formatting.sh`.

## Codegen / wiring gotchas

- Setting keys are defined ONLY in `CMakeModules/GenerateSettingKeys.cmake` (generates `src/common/setting_keys.h`, `setting_qkeys.h`, `jni_setting_keys.cpp`). Add keys there, not as raw strings, and mirror changes to Android `SettingKeys.kt`.
- `src/common/scm_rev.cpp` is generated at configure time (gitignored).
- Source files are listed explicitly per target in each `CMakeLists.txt` (no globbing); new files must be added there.

## Contribution rules

- Read `AI-POLICY.md` before submitting anything: AI use must be disclosed, AI may not write whole/significant contributions, and may not submit PRs or issues autonomously. Violating PRs are closed.
- Feature PRs should first be proposed as a feature-request issue, and `master` should not be repeatedly merged into feature branches.
