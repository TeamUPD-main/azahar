#!/usr/bin/env python3
"""
Wrapper for swiftc to filter/transform incompatible C++ linker flags and to
inject the flags CMake drops for Swift link invocations (SDK path, target
triple, bridging header). Swift doesn't understand -pthread or -Wl, flags.
"""
import os
import subprocess
import sys

IOS_TARGET = 'arm64-apple-ios18.0'


def get_sdk_path():
    """Locate the iOS SDK path via xcrun (device first, then simulator)."""
    for sdk in ('iphoneos', 'iphonesimulator'):
        try:
            result = subprocess.run(
                ['xcrun', '--sdk', sdk, '--show-sdk-path'],
                capture_output=True, text=True, check=True)
            path = result.stdout.strip()
            if path:
                return path
        except (subprocess.CalledProcessError, FileNotFoundError):
            continue
    return None


def main():
    args = sys.argv[1:]
    sdk = get_sdk_path()
    script_dir = os.path.dirname(os.path.abspath(__file__))
    bridging_header = os.path.join(script_dir, 'AzaharBridge', 'azahar_ios.h')

    transformed = []
    has_sdk = False
    has_target = False
    has_bridging = False
    for arg in args:
        if arg == '-sdk':
            has_sdk = True
        elif arg == '-target':
            has_target = True
        elif arg == '-import-objc-header':
            has_bridging = True
        # Skip pthread flags (Swift doesn't need them)
        if arg in ('-pthread', '-lpthread'):
            continue
        # Transform -Wl,-framework,Foo to -Xlinker -framework -Xlinker Foo
        if arg.startswith('-Wl,'):
            parts = arg[4:].split(',')
            for part in parts:
                if part:
                    transformed.extend(['-Xlinker', part])
            continue
        transformed.append(arg)

    cmd = ['/usr/bin/swiftc']
    if sdk and not has_sdk:
        cmd.extend(['-sdk', sdk])
    if not has_target:
        cmd.extend(['-target', IOS_TARGET])
    if os.path.isfile(bridging_header) and not has_bridging:
        cmd.extend(['-import-objc-header', bridging_header])
    cmd.extend(transformed)

    sys.exit(subprocess.call(cmd))


if __name__ == '__main__':
    main()
