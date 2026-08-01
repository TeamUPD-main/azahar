// Copyright Citra Emulator Project / Azahar Emulator Project
// Licensed under GPLv2 or any later version
// Refer to the license.txt file included.

import SwiftUI

/// About / Licenses screen (equivalent to Android's LicensesFragment).
struct AboutView: View {
    @State private var showingLicenseDetail = false

    var body: some View {
        List {
            Section("App") {
                HStack {
                    Text("Version")
                    Spacer()
                    Text(String(cString: az_get_version_string()))
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("Build")
                    Spacer()
                    Text("iOS")
                        .foregroundStyle(.secondary)
                }
            }

            Section("License") {
                NavigationLink("GNU General Public License v2.0") {
                    ScrollView {
                        Text(licenseText)
                            .font(.caption)
                            .padding()
                    }
                    .navigationTitle("GPLv2")
                }
            }

            Section("Credits") {
                Link("Azahar Emulator Project", destination: URL(string: "https://azahar-emu.org")!)
                Link("Citra (original project)", destination: URL(string: "https://github.com/citra-emu/citra")!)
                Link("GitHub Repository", destination: URL(string: "https://github.com/azahar-emu/azahar")!)
                Link("Discord Server", destination: URL(string: "https://discord.gg/4ZjMpAp3M6")!)
            }

            Section("Third-Party Libraries") {
                ForEach(thirdPartyLibs, id: \.name) { lib in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(lib.name).font(.headline)
                            Text(lib.url)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(lib.license)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("About")
    }

    private struct ThirdPartyLib: Identifiable {
        let id = UUID()
        let name: String
        let url: String
        let license: String
    }

    private let thirdPartyLibs: [ThirdPartyLib] = [
        ThirdPartyLib(name: "Boost", url: "https://www.boost.org", license: "BSL-1.0"),
        ThirdPartyLib(name: "dynarmic", url: "https://github.com/merryhime/dynarmic", license: "MIT"),
        ThirdPartyLib(name: "fmtlib", url: "https://github.com/fmtlib/fmt", license: "MIT"),
        ThirdPartyLib(name: "inih", url: "https://github.com/benhoyt/inih", license: "BSD-3-Clause"),
        ThirdPartyLib(name: "Cubeb", url: "https://github.com/mozilla/cubeb", license: "ISC"),
        ThirdPartyLib(name: "OpenAL Soft", url: "https://github.com/AudioSDK/OpenAL-SW", license: "LGPL-2.1"),
        ThirdPartyLib(name: "MoltenVK", url: "https://github.com/KhronosGroup/MoltenVK", license: "Apache-2.0"),
        ThirdPartyLib(name: "libyuv", url: "https://chromium.googlesource.com/libyuv/libyuv", license: "BSD-3-Clause"),
        ThirdPartyLib(name: "Catch2", url: "https://github.com/catchorg/Catch2", license: "BSL-1.0"),
    ]

    private let licenseText = """
    Copyright (C) 2024 Azahar Emulator Project

    This program is free software: you can redistribute it and/or modify it under \
    the terms of the GNU General Public License as published by the Free Software \
    Foundation, either version 2 of the License, or (at your option) any later version.

    This program is distributed in the hope that it will be useful, but WITHOUT ANY \
    WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A \
    PARTICULAR PURPOSE. See the GNU General Public License for more details.

    You should have received a copy of the GNU General Public License along with \
    this program. If not, see <https://www.gnu.org/licenses/>.
    """
}
