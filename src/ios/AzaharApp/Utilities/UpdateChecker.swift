// Copyright Citra Emulator Project / Azahar Emulator Project
// Licensed under GPLv2 or any later version
// Refer to the license.txt file included.

import Foundation

/// Checks for new releases on GitHub.
@MainActor
final class UpdateChecker: ObservableObject {
    @Published var isChecking = false
    @Published var hasUpdate = false
    @Published var latestVersion = ""
    @Published var downloadURL: URL?

    private let repoOwner = "azahar-emu"
    private let repoName = "azahar"
    private let checkOnStart: Bool

    init() {
        checkOnStart = az_setting_get_bool("Miscellaneous", "check_for_update_on_start", true)
    }

    func checkForUpdate() async {
        guard checkOnStart, !isChecking else { return }
        isChecking = true
        defer { isChecking = false }

        let session = URLSession.shared
        let url = URL(string: "https://api.github.com/repos/\(repoOwner)/\(repoName)/releases/latest")!
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")

        do {
            let (data, _) = try await session.data(for: request)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tagName = json["tag_name"] as? String,
                  let assets = json["assets"] as? [[String: Any]]
            else { return }

            latestVersion = tagName
            let currentVersion = safeString(from: az_get_version_string())

            if tagName != currentVersion {
                hasUpdate = true
            }

            // Find the iOS-specific asset or the main macOS universal build
            for asset in assets {
                guard let name = asset["name"] as? String,
                      let browserURL = asset["browser_download_url"] as? String
                else { continue }
                if name.contains("ios") || name.contains("universal") {
                    downloadURL = URL(string: browserURL)
                    break
                }
            }
        } catch {
            // Network error — silently ignore
        }
    }
}
