# SwiftLint Integration for Azahar

## Overview
SwiftLint has been integrated into the Azahar iOS codebase to enforce consistent Swift code style and catch common issues automatically.

## What is SwiftLint?

SwiftLint is a tool to enforce Swift style and conventions, developed by Realm. It analyzes Swift code and reports style violations, common mistakes, and best practices.

## Configuration

### File: `.swiftlint.yml`
Located at the project root, this configuration file customizes SwiftLint behavior for Azahar.

### Key Settings:

**Excluded Paths:**
- `externals/` - Third-party dependencies
- `build/` - Build artifacts
- `.build/` - Swift Package Manager builds

**Included Paths:**
- `src/ios/AzaharApp/` - Only Swift iOS code

**Disabled Rules (for emulator development):**
- `line_length` - Emulator code can have long lines
- `file_length` - iOS files can be large
- `function_body_length` - Complex emulation logic
- `type_body_length` - Large view models are acceptable
- `cyclomatic_complexity` - Emulation state machines are complex
- `todo` - Don't block builds on TODOs

**Enabled Opt-In Rules:**
- `empty_count` - Use `.isEmpty` instead of `.count == 0`
- `unused_import` - Remove unused imports (enforced)
- `unused_declaration` - Catch unused variables/functions
- `first_where` - Use `.first(where:)` instead of `.filter().first`
- `contains_over_first_not_nil` - Use `.contains()` instead of `.first != nil`

**Custom Rules:**
- `copyright_header` - Enforce Azahar copyright header
- `no_print` - Use proper logging instead of `print()` statements

### Warning Threshold

**Phase 1 (Current):** `warning_threshold: 50`
- Allows up to 50 warnings without failing the build
- Warnings are reported but don't block CI
- Gives time to clean up existing code

**Phase 2 (Future):** `warning_threshold: 0`
- Zero tolerance for warnings
- All new code must be lint-clean
- Enable after cleaning up existing violations

## CI Integration

### GitHub Actions Workflow: `.github/workflows/ios27.yml`

SwiftLint runs automatically on every push and pull request:

```yaml
- name: Install SwiftLint
  run: |
    brew install swiftlint
    swiftlint version

- name: Run SwiftLint
  run: |
    cd src/ios
    swiftlint lint --reporter github-actions-logging
  continue-on-error: true  # Phase 1: Don't fail build
```

**Reporters:**
- CI uses `github-actions-logging` for inline annotations
- Local development uses `xcode` format

### CI Behavior (Phase 1):
- ✅ Runs SwiftLint on every build
- ⚠️ Reports violations as warnings
- ✅ Build continues even with lint warnings
- 📊 Violations appear in GitHub Actions logs

### CI Behavior (Phase 2 - Future):
- Remove `continue-on-error: true`
- Build fails on any lint violation
- Forces all code to be lint-clean

## Local Development

### Installation

```bash
# macOS with Homebrew
brew install swiftlint

# Verify installation
swiftlint version
```

### Running SwiftLint Locally

```bash
# From project root
cd src/ios
swiftlint lint

# Auto-fix violations (where possible)
swiftlint lint --fix

# Strict mode (treat warnings as errors)
swiftlint lint --strict

# Only check modified files
git diff --name-only | grep .swift$ | xargs swiftlint lint --path
```

### Xcode Integration

SwiftLint can be integrated as a build phase in Xcode:

1. Open Xcode project
2. Select target → Build Phases
3. Add "Run Script Phase"
4. Script:
```bash
if which swiftlint >/dev/null; then
  swiftlint
else
  echo "warning: SwiftLint not installed, download from https://github.com/realm/SwiftLint"
fi
```

## Common Violations and Fixes

### 1. Unused Imports
```swift
// ❌ Bad
import Foundation
import UIKit  // Not used

// ✅ Good
import Foundation
```

### 2. Empty Count
```swift
// ❌ Bad
if array.count == 0 { }

// ✅ Good
if array.isEmpty { }
```

### 3. Force Cast
```swift
// ❌ Bad
let view = cell as! CustomView

// ✅ Good
guard let view = cell as? CustomView else { return }
```

### 4. Force Try
```swift
// ❌ Bad
let data = try! Data(contentsOf: url)

// ✅ Good
do {
    let data = try Data(contentsOf: url)
} catch {
    print("Error: \(error)")
}
```

### 5. First Where
```swift
// ❌ Bad
let item = items.filter { $0.id == id }.first

// ✅ Good
let item = items.first(where: { $0.id == id })
```

### 6. Copyright Header
```swift
// ✅ All Swift files should start with:
// Copyright Citra Emulator Project / Azahar Emulator Project
// Licensed under GPLv2 or any later version
// Refer to the license.txt file included.
```

### 7. No Print Statements
```swift
// ❌ Bad (in production code)
print("User logged in: \(username)")

// ✅ Good
NSLog("[Auth] User logged in: \(username)")
// or use proper logging framework
```

## Disabling Rules

### For Specific Lines
```swift
// swiftlint:disable:next force_cast
let view = cell as! CustomView
```

### For File Sections
```swift
// swiftlint:disable force_cast force_try
let view = cell as! CustomView
let data = try! Data(contentsOf: url)
// swiftlint:enable force_cast force_try
```

### For Entire File
```swift
// swiftlint:disable all
// Legacy code, will be refactored later
```

## Roadmap

### Phase 1: Warnings Only (Current - Aug 2026)
- [x] Add `.swiftlint.yml` configuration
- [x] Integrate into CI with `continue-on-error: true`
- [x] Set `warning_threshold: 50`
- [ ] Fix critical violations (unused imports, force casts)
- [ ] Add Xcode build phase integration
- [ ] Document common violations

### Phase 2: Enforcement (Sep 2026)
- [ ] Reduce `warning_threshold` to 25
- [ ] Fix remaining violations
- [ ] Enable analyzer rules
- [ ] Update CI to fail on violations

### Phase 3: Strict Mode (Oct 2026)
- [ ] Set `warning_threshold: 0`
- [ ] Remove `continue-on-error: true` from CI
- [ ] Enable all recommended opt-in rules
- [ ] Add custom rules for Azahar-specific patterns

## Resources

- **SwiftLint GitHub:** https://github.com/realm/SwiftLint
- **Rule Directory:** https://realm.github.io/SwiftLint/rule-directory.html
- **Configuration Guide:** https://github.com/realm/SwiftLint#configuration

## Troubleshooting

### SwiftLint Not Found
```bash
# Install via Homebrew
brew install swiftlint

# Or download from GitHub releases
# https://github.com/realm/SwiftLint/releases
```

### Too Many Warnings
```bash
# Fix automatically where possible
swiftlint lint --fix

# Or increase warning_threshold temporarily in .swiftlint.yml
warning_threshold: 100
```

### False Positives
```bash
# Disable specific rule for that line
// swiftlint:disable:next rule_name

# Or add to disabled_rules in .swiftlint.yml
disabled_rules:
  - rule_name
```

## Maintenance

### Updating SwiftLint
```bash
# Upgrade to latest version
brew upgrade swiftlint

# Check version
swiftlint version
```

### Updating Rules
Edit `.swiftlint.yml` and adjust:
- `disabled_rules` - Rules to skip
- `opt_in_rules` - Rules to enable
- `warning_threshold` - Number of allowed warnings
- `custom_rules` - Project-specific rules

Changes take effect immediately on next run.

## Summary

SwiftLint integration provides:
- ✅ Consistent code style across all contributors
- ✅ Automatic detection of common Swift issues
- ✅ CI enforcement without blocking development
- ✅ Gradual adoption path (warnings → errors)
- ✅ Customizable rules for emulator development
- ✅ Industry-standard tooling

The current configuration is **lenient** (Phase 1) to allow gradual cleanup. Future phases will enforce stricter standards as the codebase matures.
