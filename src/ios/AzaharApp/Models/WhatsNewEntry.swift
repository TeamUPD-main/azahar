// Copyright Citra Emulator Project / Azahar Emulator Project
// Licensed under GPLv2 or any later version
// Refer to the license.txt file included.

import Foundation

/// Model for What's New changelog entries
struct WhatsNewEntry: Codable {
    let version: String
    let releaseDate: String
    let sections: [ChangelogSection]
    let compatibility: CompatibilityInfo?
    let notes: [String]?
    
    struct ChangelogSection: Codable {
        let title: String
        let items: [String]
    }
    
    struct CompatibilityInfo: Codable {
        let minimumIOSVersion: String
        let recommendedIOSVersion: String
        let requiresStikDebug: Bool
        let requiresLocalDevVPN: Bool
    }
}

/// Manager for loading and tracking What's New changelog
class WhatsNewManager {
    static let shared = WhatsNewManager()
    
    private init() {}
    
    /// Load What's New entry from bundled JSON
    func loadWhatsNew() -> WhatsNewEntry? {
        guard let url = Bundle.main.url(forResource: "WhatsNew", withExtension: "json") else {
            print("[WhatsNew] WhatsNew.json not found in bundle")
            return nil
        }
        
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            let entry = try decoder.decode(WhatsNewEntry.self, from: data)
            return entry
        } catch {
            print("[WhatsNew] Failed to decode WhatsNew.json: \(error)")
            return nil
        }
    }
    
    /// Check if What's New should be shown for current version
    func shouldShowWhatsNew() -> Bool {
        guard let entry = loadWhatsNew() else { return false }
        
        // Get current app version
        guard let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String else {
            return false
        }
        
        // Get last seen version from UserDefaults
        let lastSeenVersion = UserDefaults.standard.string(forKey: "lastSeenWhatsNewVersion")
        
        // Show if we haven't seen this version yet
        return lastSeenVersion != entry.version
    }
    
    /// Mark What's New as seen for current version
    func markWhatsNewAsSeen() {
        guard let entry = loadWhatsNew() else { return }
        UserDefaults.standard.set(entry.version, forKey: "lastSeenWhatsNewVersion")
        print("[WhatsNew] Marked version \(entry.version) as seen")
    }
    
    /// Reset What's New tracking (for testing)
    func resetWhatsNewTracking() {
        UserDefaults.standard.removeObject(forKey: "lastSeenWhatsNewVersion")
        print("[WhatsNew] Reset What's New tracking")
    }
}
