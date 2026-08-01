# Azahar iOS app — built only when targeting iOS.
# Uses the same C++ core as the Qt/Android builds but with a native SwiftUI
# frontend. To build:
#   cmake -S . -B build-ios -G Xcode \
#       -DCMAKE_SYSTEM_NAME=iOS \
#       -DCMAKE_OSX_DEPLOYMENT_TARGET=14.0 \
#       -DCMAKE_OSX_ARCHITECTURES=arm64 \
#       -DENABLE_QT=OFF -DENABLE_LIBRETRO=OFF \
#       -DENABLE_TESTS=OFF
#   cmake --build build-ios --config Release

if(NOT IOS OR ENABLE_LIBRETRO)
    return()
endif()

# ---------------------------------------------------------------------------
# azahar_ios — the C++/ObjC++ bridge (equivalent to citra-android)
# ---------------------------------------------------------------------------

add_library(azahar_ios STATIC
    AzaharBridge/ios_bridge.mm
    AzaharBridge/EmuWindowIOS.h
    AzaharBridge/EmuWindowIOS.mm
    AzaharBridge/config_ios.h
    AzaharBridge/config_ios.cpp
    AzaharBridge/default_ini_ios.h
    AzaharBridge/input_manager_ios.h
    AzaharBridge/input_manager_ios.cpp
    AzaharBridge/motion_ios.h
    AzaharBridge/motion_ios.mm
    AzaharBridge/logging_ios.h
    AzaharBridge/logging_ios.cpp
    AzaharBridge/camera_ios.h
    AzaharBridge/camera_ios.mm
    AzaharBridge/applets_ios.h
    AzaharBridge/applets_ios.mm
)

target_include_directories(azahar_ios PUBLIC
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${CMAKE_SOURCE_DIR}/src
)

target_link_libraries(azahar_ios PRIVATE
    citra_common citra_core video_core audio_core input_common network inih
)

# ObjC++ files need ARC and the ObjC++ standard
set_target_properties(azahar_ios PROPERTIES
    OBJCXX_STANDARD 20
    CXX_STANDARD 20
    XCODE_ATTRIBUTE_CLANG_ENABLE_OBJC_ARC YES
)

# ---------------------------------------------------------------------------
# Swift sources — enumerated explicitly (no globbing, per repo convention)
# ---------------------------------------------------------------------------
set(AZAHAR_SWIFT_SOURCES
    AzaharApp/AzaharApp.swift
    AzaharApp/Models/Game.swift
    AzaharApp/ViewModels/EmulationViewModel.swift
    AzaharApp/Views/RootView.swift
    AzaharApp/Views/GameListView.swift
    AzaharApp/Views/EmulationView.swift
    AzaharApp/Views/MetalView.swift
    AzaharApp/Views/TouchControlsView.swift
    AzaharApp/Views/Settings/SettingsView.swift
    AzaharApp/Views/Applets/SoftwareKeyboardView.swift
    AzaharApp/Views/Applets/MiiSelectorView.swift
    AzaharApp/Views/NetPlayView.swift
    AzaharApp/Views/CheatsView.swift
    AzaharApp/Views/SystemFilesView.swift
    AzaharApp/Views/AboutView.swift
    AzaharApp/Utilities/GamepadManager.swift
    AzaharApp/Utilities/UpdateChecker.swift
    AzaharApp/Utilities/SMDHLoader.swift
)

# ---------------------------------------------------------------------------
# azahar_ios_app — the SwiftUI executable (macOS XIP bundle on iOS)
# ---------------------------------------------------------------------------

add_executable(azahar_ios_app MACOSX_BUNDLE
    ${AZAHAR_SWIFT_SOURCES}
)

set_target_properties(azahar_ios_app PROPERTIES
    OUTPUT_NAME "Azahar"
    MACOSX_BUNDLE TRUE
    MACOSX_BUNDLE_BUNDLE_NAME "org.azahar_emu.Azahar"
    MACOSX_BUNDLE_BUNDLE_IDENTIFIER "org.azahar_emu.Azahar"
    MACOSX_BUNDLE_BUNDLE_VERSION "1"
    MACOSX_BUNDLE_SHORT_VERSION_STRING "1.0"
    MACOSX_BUNDLE_GUI_IDENTIFIER "org.azahar_emu.Azahar"
    MACOSX_BUNDLE_INFO_PLIST "${CMAKE_CURRENT_SOURCE_DIR}/AzaharApp/Resources/Info.plist"
    MACOSX_BUNDLE_ICON_FILE "AppIcon"
    MACOSX_BUNDLE_LAUNCH_SCREEN_STORYBOARD ""
    MACOSX_BUNDLE_SCREEN_ORIENTATIONS "UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight UIInterfaceOrientationPortrait"
    XCODE_ATTRIBUTE_SWIFT_OBJC_BRIDGING_HEADER "${CMAKE_CURRENT_SOURCE_DIR}/AzaharBridge/azahar_ios.h"
    XCODE_ATTRIBUTE_ASSETCATALOG_COMPILER_APPICON_NAME "AppIcon"
    XCODE_ATTRIBUTE_INFOPLIST_KEY_CFBundleDisplayName "Azahar"
    XCODE_ATTRIBUTE_INFOPLIST_KEY_UIApplicationSceneManifest_Generation YES
    XCODE_ATTRIBUTE_INFOPLIST_KEY_UIApplicationSupportsIndirectInputEvents YES
    XCODE_ATTRIBUTE_INFOPLIST_KEY_UISupportedInterfaceOrientations "~UIInterfaceOrientationPortrait"
    XCODE_ATTRIBUTE_INFOPLIST_KEY_UILaunchScreen_Generation YES
    XCODE_ATTRIBUTE_CODE_SIGN_IDENTITY "Apple Development"
    XCODE_ATTRIBUTE_DEVELOPMENT_TEAM ""
)

target_link_libraries(azahar_ios_app PRIVATE azahar_ios)

# Embed MoltenVK in the app bundle
if(EXISTS "${CMAKE_BINARY_DIR}/externals/MoltenVK/MoltenVK/dynamic/dylib/macOS/libMoltenVK.dylib")
    add_custom_command(TARGET azahar_ios_app POST_BUILD
        COMMAND ${CMAKE_COMMAND} -E copy_if_different
            "${CMAKE_BINARY_DIR}/externals/MoltenVK/MoltenVK/dynamic/dylib/macOS/libMoltenVK.dylib"
            "$<TARGET_BUNDLE_CONTENT_DIR:azahar_ios_app>/Frameworks/libMoltenVK.dylib"
        COMMENT "Bundling MoltenVK"
    )
endif()
