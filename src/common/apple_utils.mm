// Copyright Citra Emulator Project / Azahar Emulator Project
// Licensed under GPLv2 or any later version
// Refer to the license.txt file included.

#import <Foundation/Foundation.h>

#if TARGET_OS_OSX
#import <AppKit/AppKit.h>
#import <CoreGraphics/CoreGraphics.h>
#else
#import <UIKit/UIKit.h>
#endif

namespace AppleUtils {

float GetRefreshRate() {
#if TARGET_OS_OSX
    NSScreen* screen = [NSScreen mainScreen];
    if (screen) {
        NSDictionary* screenInfo = [screen deviceDescription];
        CGDirectDisplayID displayID =
            (CGDirectDisplayID)[screenInfo[@"NSScreenNumber"] unsignedIntValue];
        CGDisplayModeRef displayMode = CGDisplayCopyDisplayMode(displayID);
        if (displayMode) {
            CGFloat refreshRate = CGDisplayModeGetRefreshRate(displayMode);
            CFRelease(displayMode);
            return refreshRate;
        }
    }
    return 60;
#else
    // iOS: use UIScreen.maximumFramesPerSecond (available since iOS 10.3)
    UIScreen* screen = [UIScreen mainScreen];
    if (screen) {
        return static_cast<float>(screen.maximumFramesPerSecond);
    }
    return 60;
#endif
}

int IsLowPowerModeEnabled() {
    return (int)[NSProcessInfo processInfo].lowPowerModeEnabled;
}

int IsRunningFromTerminal() {
    return 0;
}

} // namespace AppleUtils
