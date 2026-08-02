#!/usr/bin/env python3
"""
Wrapper for swiftc to filter/transform incompatible C++ linker flags.
Swift doesn't understand -pthread or -Wl, style flags.
"""
import sys
import subprocess

def transform_args(args):
    """Transform C++ linker flags to Swift-compatible format."""
    result = []
    for arg in args:
        # Skip pthread flags
        if arg in ('-pthread', '-lpthread'):
            continue
        # Transform -Wl, flags to -Xlinker format
        elif arg.startswith('-Wl,'):
            # Remove -Wl, prefix and split by comma
            wl_content = arg[4:]  # Skip '-Wl,'
            parts = wl_content.split(',')
            for part in parts:
                if part:
                    result.extend(['-Xlinker', part])
        else:
            result.append(arg)
    return result

if __name__ == '__main__':
    # Transform arguments
    swiftc_args = transform_args(sys.argv[1:])
    
    # Call actual swiftc
    sys.exit(subprocess.call(['/usr/bin/swiftc'] + swiftc_args))
